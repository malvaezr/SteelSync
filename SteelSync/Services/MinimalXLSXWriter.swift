import Foundation

/// Tiny self-contained .xlsx writer used by the pay-app Excel export.
/// Writes a stored (no-compression) ZIP — fine since the XML payload is
/// only a few KB. Avoids pulling a third-party dependency.
///
/// ## Why we hand-roll OOXML
/// An .xlsx file is just a ZIP archive containing a fixed set of XML
/// parts following the Office Open XML SpreadsheetML schema. Apple's
/// SDK has no built-in Excel writer, and pulling in CoreXLSX/libxlsxwriter
/// just to emit a couple of sheets was overkill. We write the minimum
/// set of parts Excel and Numbers will both accept.
///
/// ## ZIP layout produced by this writer
/// ```
///   [Content_Types].xml          ← MIME map (required first by some parsers)
///   _rels/.rels                  ← root relationships → xl/workbook.xml
///   xl/workbook.xml              ← sheet list
///   xl/_rels/workbook.xml.rels   ← workbook→worksheets+styles relationships
///   xl/styles.xml                ← number formats, fonts, fills, cellXfs
///   xl/worksheets/sheet1.xml     ← one file per sheet
///   xl/worksheets/sheet2.xml
///   ...
/// ```
///
/// ## Usage
/// ```
/// var book = XLSXWorkbook()
/// book.addSheet(name: "Application", rows: [[.bold("Hello"), .number(42)]])
/// book.addSheet(name: "Schedule of Values", rows: ...)
/// let url = try book.write(to: tmpURL)
/// ```
///
/// Cell values are coerced as either text or number based on the
/// `XLSXCell` case. Style ID conventions are documented on
/// `stylesXML()` below — changing that table changes the meaning of
/// every numeric `style:` argument.
struct XLSXWorkbook {

    /// Sheet payload — any 2D array of cell values plus an optional name.
    private struct SheetPayload {
        let name: String
        let rows: [[XLSXCell]]
    }

    private var sheets: [SheetPayload] = []

    mutating func addSheet(name: String, rows: [[XLSXCell]]) {
        sheets.append(SheetPayload(name: name, rows: rows))
    }

    /// Writes the workbook to `url` (overwriting if it exists). Returns
    /// the URL on success.
    func write(to url: URL) throws -> URL {
        var zip = StoredZipWriter()

        zip.add(name: "[Content_Types].xml", content: contentTypesXML())
        zip.add(name: "_rels/.rels", content: rootRelsXML())
        zip.add(name: "xl/workbook.xml", content: workbookXML())
        zip.add(name: "xl/_rels/workbook.xml.rels", content: workbookRelsXML())
        zip.add(name: "xl/styles.xml", content: stylesXML())
        for (idx, sheet) in sheets.enumerated() {
            zip.add(name: "xl/worksheets/sheet\(idx + 1).xml",
                    content: worksheetXML(for: sheet))
        }

        let data = zip.finalize()
        try data.write(to: url)
        return url
    }

    // MARK: - XML payloads

    private func contentTypesXML() -> Data {
        var s = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        s += #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
        s += #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
        s += #"<Default Extension="xml" ContentType="application/xml"/>"#
        s += #"<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>"#
        s += #"<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>"#
        for i in 0..<sheets.count {
            s += #"<Override PartName="/xl/worksheets/sheet\#(i + 1).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }
        s += "</Types>"
        return Data(s.utf8)
    }

    private func rootRelsXML() -> Data {
        let s = #"""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """#
        return Data(s.utf8)
    }

    private func workbookXML() -> Data {
        var s = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        s += #"<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">"#
        s += "<sheets>"
        for (idx, sheet) in sheets.enumerated() {
            s += #"<sheet name="\#(escapeAttr(sheet.name))" sheetId="\#(idx + 1)" r:id="rId\#(idx + 1)"/>"#
        }
        s += "</sheets></workbook>"
        return Data(s.utf8)
    }

    private func workbookRelsXML() -> Data {
        var s = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        s += #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        for (idx, _) in sheets.enumerated() {
            s += #"<Relationship Id="rId\#(idx + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#(idx + 1).xml"/>"#
        }
        s += #"<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#
        s += "</Relationships>"
        return Data(s.utf8)
    }

    /// styles.xml — the order of `<xf>` entries in `<cellXfs>` defines the
    /// integer style IDs each cell references via its `s="N"` attribute.
    /// **Do not reorder these without auditing every `XLSXCell` style arg.**
    ///
    /// Style IDs:
    /// - 0  default
    /// - 1  bold
    /// - 2  bold + yellow fill
    /// - 3  currency (default for `.number`)
    /// - 4  currency bold
    /// - 5  currency on yellow fill
    /// - 6  bold red text
    /// - 7  currency bold red text
    /// - 8  percent
    /// - 9  bold + center
    ///
    /// Custom `numFmtId`s:
    /// - 164 — currency `"$"#,##0.00;[Red]-"$"#,##0.00`
    /// - 165 — percent `0%`
    private func stylesXML() -> Data {
        let s = #"""
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <numFmts count="2">
        <numFmt numFmtId="164" formatCode="&quot;$&quot;#,##0.00;[Red]-&quot;$&quot;#,##0.00"/>
        <numFmt numFmtId="165" formatCode="0%"/>
        </numFmts>
        <fonts count="3">
        <font><sz val="10"/><name val="Calibri"/></font>
        <font><b/><sz val="10"/><name val="Calibri"/></font>
        <font><b/><sz val="10"/><color rgb="FFCC0000"/><name val="Calibri"/></font>
        </fonts>
        <fills count="3">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        <fill><patternFill patternType="solid"><fgColor rgb="FFFFFF00"/><bgColor indexed="64"/></patternFill></fill>
        </fills>
        <borders count="1"><border/></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="10">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
        <xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
        <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
        <xf numFmtId="164" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyNumberFormat="1"/>
        <xf numFmtId="164" fontId="0" fillId="2" borderId="0" xfId="0" applyFill="1" applyNumberFormat="1"/>
        <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
        <xf numFmtId="164" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyNumberFormat="1"/>
        <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
        <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment horizontal="center"/></xf>
        </cellXfs>
        <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
        <dxfs count="0"/>
        </styleSheet>
        """#
        return Data(s.utf8)
    }

    private func worksheetXML(for sheet: SheetPayload) -> Data {
        var s = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
        s += #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">"#
        s += "<sheetData>"
        for (rowIdx, row) in sheet.rows.enumerated() {
            let rowNum = rowIdx + 1
            s += #"<row r="\#(rowNum)">"#
            for (colIdx, cell) in row.enumerated() {
                let ref = columnRef(colIdx) + "\(rowNum)"
                s += cell.xml(reference: ref)
            }
            s += "</row>"
        }
        s += "</sheetData>"
        s += "</worksheet>"
        return Data(s.utf8)
    }

    // MARK: - Helpers

    /// Converts a 0-based column index to its Excel letter ref:
    /// 0→A, 1→B, … 25→Z, 26→AA, 27→AB, … 701→ZZ, 702→AAA.
    /// Bijective base-26 (no zero digit), which is why we subtract 1
    /// from the quotient before recursing.
    private func columnRef(_ idx: Int) -> String {
        var n = idx
        var s = ""
        repeat {
            let r = n % 26
            s = String(UnicodeScalar(65 + r)!) + s
            n = n / 26 - 1
        } while n >= 0
        return s
    }

    private func escapeAttr(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - Cell

enum XLSXCell {
    case empty
    case string(String, style: Int = 0)
    case number(Decimal, style: Int = 3)         // default to currency
    case percent(Double, style: Int = 8)
    case rawNumber(Double, style: Int = 0)

    static func bold(_ s: String) -> XLSXCell { .string(s, style: 1) }
    static func boldYellow(_ s: String) -> XLSXCell { .string(s, style: 2) }
    static func currency(_ d: Decimal, bold: Bool = false, yellow: Bool = false, red: Bool = false) -> XLSXCell {
        if red && bold { return .number(d, style: 7) }
        if yellow { return .number(d, style: 5) }
        if bold { return .number(d, style: 4) }
        return .number(d, style: 3)
    }
    static func boldCenter(_ s: String) -> XLSXCell { .string(s, style: 9) }
    static func boldRed(_ s: String) -> XLSXCell { .string(s, style: 6) }

    func xml(reference: String) -> String {
        switch self {
        case .empty:
            return ""
        case .string(let value, let style):
            return #"<c r="\#(reference)" s="\#(style)" t="inlineStr"><is><t xml:space="preserve">\#(escapeText(value))</t></is></c>"#
        case .number(let value, let style):
            return #"<c r="\#(reference)" s="\#(style)"><v>\#(decimalString(value))</v></c>"#
        case .percent(let value, let style):
            return #"<c r="\#(reference)" s="\#(style)"><v>\#(value)</v></c>"#
        case .rawNumber(let value, let style):
            return #"<c r="\#(reference)" s="\#(style)"><v>\#(value)</v></c>"#
        }
    }

    private func escapeText(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func decimalString(_ d: Decimal) -> String {
        var v = d
        var rounded = Decimal()
        NSDecimalRound(&rounded, &v, 4, .plain)
        return "\(rounded)"
    }
}

// MARK: - Stored ZIP writer (no compression)

/// Builds a ZIP archive in-memory using STORED (compression method 0).
/// Excel and macOS Archive Utility both happily accept stored xlsx — saves
/// us from pulling in libcompression for deflate.
///
/// The format follows APPNOTE.TXT (the PKZIP spec). Each call to `add()`
/// appends a *local file header* plus the raw payload to `output`. On
/// `finalize()` we walk the entries again to emit a matching *central
/// directory header* for each, followed by the *end-of-central-directory
/// record* (EOCD). A reader can locate every entry by reading the EOCD
/// from the tail and following the central directory's offsets.
///
/// Wire-format reference (all little-endian):
///   Local header      signature 0x04034b50 — sits just before each file
///   Central directory signature 0x02014b50 — index at end of archive
///   EOCD              signature 0x06054b50 — points back at central dir
///
/// "Version needed = 20" means PKZIP 2.0; that's the floor for the
/// STORED method we use.
private struct StoredZipWriter {
    private struct Entry {
        let name: String
        let data: Data
        let crc: UInt32
        let offset: UInt32
    }

    private var entries: [Entry] = []
    private var output = Data()

    mutating func add(name: String, content: Data) {
        let crc = CRC32.compute(content)
        let offset = UInt32(output.count)
        let nameData = Data(name.utf8)

        var header = Data()
        header.append(uint32: 0x04034b50)                // local file header signature
        header.append(uint16: 20)                         // version needed
        header.append(uint16: 0)                          // general purpose bit flag
        header.append(uint16: 0)                          // compression method (stored)
        header.append(uint16: 0)                          // mod time
        header.append(uint16: 0)                          // mod date
        header.append(uint32: crc)                        // crc32
        header.append(uint32: UInt32(content.count))      // compressed size (== uncompressed)
        header.append(uint32: UInt32(content.count))      // uncompressed size
        header.append(uint16: UInt16(nameData.count))     // filename length
        header.append(uint16: 0)                          // extra field length
        header.append(nameData)
        output.append(header)
        output.append(content)

        entries.append(Entry(name: name, data: content, crc: crc, offset: offset))
    }

    mutating func finalize() -> Data {
        let centralDirOffset = UInt32(output.count)
        var centralDirSize: UInt32 = 0

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            var cd = Data()
            cd.append(uint32: 0x02014b50)                  // central directory header signature
            cd.append(uint16: 20)                          // version made by
            cd.append(uint16: 20)                          // version needed
            cd.append(uint16: 0)                           // gp flag
            cd.append(uint16: 0)                           // method
            cd.append(uint16: 0)                           // mod time
            cd.append(uint16: 0)                           // mod date
            cd.append(uint32: entry.crc)                   // crc32
            cd.append(uint32: UInt32(entry.data.count))    // compressed
            cd.append(uint32: UInt32(entry.data.count))    // uncompressed
            cd.append(uint16: UInt16(nameData.count))      // filename length
            cd.append(uint16: 0)                           // extra field length
            cd.append(uint16: 0)                           // comment length
            cd.append(uint16: 0)                           // disk number
            cd.append(uint16: 0)                           // internal attributes
            cd.append(uint32: 0)                           // external attributes
            cd.append(uint32: entry.offset)                // local header offset
            cd.append(nameData)
            output.append(cd)
            centralDirSize += UInt32(cd.count)
        }

        var eocd = Data()
        eocd.append(uint32: 0x06054b50)
        eocd.append(uint16: 0)
        eocd.append(uint16: 0)
        eocd.append(uint16: UInt16(entries.count))
        eocd.append(uint16: UInt16(entries.count))
        eocd.append(uint32: centralDirSize)
        eocd.append(uint32: centralDirOffset)
        eocd.append(uint16: 0)
        output.append(eocd)

        return output
    }
}

// MARK: - CRC32

/// CRC-32/ISO-HDLC (same variant ZIP and PNG use).
///
/// Polynomial 0xEDB88320 is the bit-reversed form of the IEEE 802.3
/// polynomial 0x04C11DB7 — required because we shift the LSB first.
/// Initial value 0xFFFFFFFF and final XOR with 0xFFFFFFFF are the
/// standard ZIP conventions; changing either will produce checksums
/// that Excel will refuse with "file format or extension is not valid".
private enum CRC32 {
    /// 256-entry lookup table — built once at type init.
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func compute(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let idx = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = Self.table[idx] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

// MARK: - Data + little-endian helpers

private extension Data {
    mutating func append(uint16 v: UInt16) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { self.append(contentsOf: $0) }
    }
    mutating func append(uint32 v: UInt32) {
        var le = v.littleEndian
        Swift.withUnsafeBytes(of: &le) { self.append(contentsOf: $0) }
    }
}
