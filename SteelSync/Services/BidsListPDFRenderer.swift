import SwiftUI
import PDFKit

/// Selectable columns for the bids list export.
///
/// **Stable ordering matters.** The PDF renders columns in
/// `BidColumn.allCases` order — that's also the order shown in the
/// export sheet's checkboxes and the order in which `enabledColumns`
/// is filtered before being handed to the renderer. If you add a case,
/// place it where you want it to appear in the PDF, not at the bottom.
enum BidColumn: String, CaseIterable, Identifiable, Hashable {
    case priority = "Priority"
    case projectName = "Project"
    case clientName = "Client"
    case status = "Status"
    case bidAmount = "Bid Amount"
    case dueDate = "Due Date"
    case createdDate = "Created"
    case address = "Address"
    case squareFeet = "Sq Ft"
    case beams = "Beams"
    case numColumns = "Columns"
    case joists = "Joists"
    case wallPanels = "Wall Panels"
    case estimatedTons = "Est. Tons"
    case plansCount = "Plans"
    case touchpointsCount = "Touchpoints"
    case notes = "Notes"

    var id: String { rawValue }

    /// Default-on columns. Anything else stays off until the user opts in.
    var defaultEnabled: Bool {
        switch self {
        case .priority, .projectName, .clientName, .status, .bidAmount, .dueDate, .plansCount:
            return true
        default:
            return false
        }
    }

    /// Relative width weight inside a fitted row — normalized at render
    /// time against the sum of weights of *selected* columns, so the row
    /// always fills the page regardless of which columns are on. Tune
    /// these numbers if a particular column looks too cramped or too
    /// spacious in the output. Numeric/short cols get less.
    var widthWeight: CGFloat {
        switch self {
        case .priority: return 1.1
        case .projectName: return 2.4
        case .clientName: return 2.0
        case .status: return 1.2
        case .bidAmount: return 1.5
        case .dueDate, .createdDate: return 1.2
        case .address: return 2.4
        case .squareFeet, .beams, .numColumns, .joists, .wallPanels, .estimatedTons: return 0.9
        case .plansCount, .touchpointsCount: return 0.8
        case .notes: return 2.6
        }
    }
}

/// Renders a tabular PDF of bids with caller-selected columns. Letter
/// landscape, paginated by `rowsPerPage`. Returns a temp-file URL or nil
/// if the PDF context can't be opened.
@MainActor
struct BidsListPDFRenderer {
    let bids: [BidProject]
    let columns: [BidColumn]
    /// Filter labels appearing in the title block (e.g. "Pending, Working On").
    let statusLabel: String
    /// Optional explicit "Clients" line in the title block (e.g. "All clients" or "3 of 5 selected").
    let clientsLabel: String

    /// 22 rows of ~28pt each fits Letter landscape comfortably with
    /// header (~60pt) and footer (~20pt) on a 792pt-tall page. If you
    /// shrink the row font or remove the header, you can push this up;
    /// going higher with current sizes will clip the last row.
    static let rowsPerPage = 22

    func render() -> URL? {
        guard !columns.isEmpty else { return nil }

        let chunks: [[BidProject]] = bids.chunked(into: Self.rowsPerPage)
        let pageList: [(Int, [BidProject])] = chunks.isEmpty
            ? [(0, [])]  // still emit a page so the user gets a "no bids match" PDF
            : Array(chunks.enumerated())
        let totalPages = pageList.count

        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: Date())
        let filename = "Bids-Export-\(stamp).pdf"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        guard let cgContext = CGContext(
            outputURL as CFURL,
            mediaBox: nil,
            [kCGPDFContextAuthor as String: "SteelSync",
             kCGPDFContextTitle as String: filename] as CFDictionary
        ) else {
            return nil
        }

        for (idx, chunk) in pageList {
            let page = BidsListPDFPage(
                bids: chunk,
                columns: columns,
                statusLabel: statusLabel,
                clientsLabel: clientsLabel,
                pageIndex: idx,
                totalPages: totalPages,
                totalBidCount: bids.count
            )
            let renderer = ImageRenderer(content: page)
            // Letter landscape @ 96dpi: 11" × 8.5" → 1056 × 816 (we use 1008 × 792
            // to stay consistent with PayAppPDFRenderer's dpi math; close enough).
            renderer.proposedSize = .init(width: 1008, height: 792)
            renderer.scale = 2.0
            renderer.render { size, renderAction in
                var mediaBox = CGRect(origin: .zero, size: size)
                cgContext.beginPage(mediaBox: &mediaBox)
                renderAction(cgContext)
                cgContext.endPage()
            }
        }
        cgContext.closePDF()

        return outputURL
    }
}

// MARK: - Page View

private struct BidsListPDFPage: View {
    let bids: [BidProject]
    let columns: [BidColumn]
    let statusLabel: String
    let clientsLabel: String
    let pageIndex: Int
    let totalPages: Int
    let totalBidCount: Int

    private static let pageWidth: CGFloat = 1008
    private static let pageHeight: CGFloat = 792
    private static let hMargin: CGFloat = 36
    private static let vMargin: CGFloat = 32

    private var contentWidth: CGFloat { Self.pageWidth - Self.hMargin * 2 }

    /// Distributes contentWidth across selected columns by weight.
    private var columnWidths: [BidColumn: CGFloat] {
        let totalWeight = columns.reduce(0) { $0 + $1.widthWeight }
        guard totalWeight > 0 else { return [:] }
        var dict: [BidColumn: CGFloat] = [:]
        for c in columns {
            dict[c] = contentWidth * (c.widthWeight / totalWeight)
        }
        return dict
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            tableHeader
            Divider().background(Color.black.opacity(0.4))

            ForEach(Array(bids.enumerated()), id: \.offset) { idx, bid in
                row(for: bid, zebra: idx.isMultiple(of: 2))
                if idx < bids.count - 1 {
                    Divider().background(Color.gray.opacity(0.25))
                }
            }

            if bids.isEmpty {
                Text("No bids match the selected filters.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .padding(.top, 20)
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, Self.hMargin)
        .padding(.vertical, Self.vMargin)
        .frame(width: Self.pageWidth, height: Self.pageHeight, alignment: .topLeading)
        .background(Color.white)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bids — Export")
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                Text("Generated \(Date().shortDate)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                Label("Status: \(statusLabel)", systemImage: "tag")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label("Clients: \(clientsLabel)", systemImage: "person.2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label("\(totalBidCount) bid\(totalBidCount == 1 ? "" : "s")", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: Table

    private var tableHeader: some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { col in
                Text(col.rawValue.uppercased())
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundColor(.black)
                    .frame(width: columnWidths[col] ?? 0, alignment: alignment(for: col))
                    .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 4)
        .background(Color(white: 0.93))
    }

    private func row(for bid: BidProject, zebra: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(columns, id: \.self) { col in
                cell(for: col, bid: bid)
                    .frame(width: columnWidths[col] ?? 0, alignment: alignment(for: col))
                    .padding(.horizontal, 4)
            }
        }
        .padding(.vertical, 5)
        .background(zebra ? Color(white: 0.97) : Color.white)
    }

    @ViewBuilder
    private func cell(for col: BidColumn, bid: BidProject) -> some View {
        switch col {
        case .priority:
            HStack(spacing: 4) {
                Image(systemName: bid.priority.icon)
                    .foregroundColor(bid.priority.color)
                    .font(.system(size: 9))
                Text(bid.priority.rawValue)
                    .font(.system(size: 9))
            }
        case .projectName:
            Text(bid.projectName)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(2)
        case .clientName:
            Text(bid.clientName)
                .font(.system(size: 9))
                .lineLimit(2)
        case .status:
            Text(bid.status.rawValue)
                .font(.system(size: 8, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(statusColor(for: bid).opacity(0.18))
                .foregroundColor(statusColor(for: bid))
                .clipShape(RoundedRectangle(cornerRadius: 3))
        case .bidAmount:
            Text(bid.bidAmount.currencyFormatted)
                .font(.system(size: 9, weight: .medium))
        case .dueDate:
            Text(bid.bidDueDate.shortDate)
                .font(.system(size: 9))
                .foregroundColor(bid.bidDueDate < Date() && !bid.isSubmitted ? .red : .black)
        case .createdDate:
            Text(bid.createdDate.shortDate).font(.system(size: 9))
        case .address:
            Text(bid.address.isEmpty ? "—" : bid.address)
                .font(.system(size: 9))
                .lineLimit(2)
        case .squareFeet:
            Text(bid.squareFeet > 0 ? "\(bid.squareFeet)" : "—").font(.system(size: 9))
        case .beams:
            Text(bid.numberOfBeams > 0 ? "\(bid.numberOfBeams)" : "—").font(.system(size: 9))
        case .numColumns:
            Text(bid.numberOfColumns > 0 ? "\(bid.numberOfColumns)" : "—").font(.system(size: 9))
        case .joists:
            Text(bid.numberOfJoists > 0 ? "\(bid.numberOfJoists)" : "—").font(.system(size: 9))
        case .wallPanels:
            Text(bid.numberOfWallPanels > 0 ? "\(bid.numberOfWallPanels)" : "—").font(.system(size: 9))
        case .estimatedTons:
            Text(bid.estimatedTons > 0 ? String(format: "%.1f", bid.estimatedTons) : "—")
                .font(.system(size: 9))
        case .plansCount:
            HStack(spacing: 3) {
                if !bid.attachments.isEmpty {
                    Image(systemName: "paperclip").font(.system(size: 8))
                }
                Text("\(bid.attachments.count)").font(.system(size: 9))
            }
        case .touchpointsCount:
            Text("\(bid.touchpoints.count)").font(.system(size: 9))
        case .notes:
            Text(bid.notes.isEmpty ? "—" : bid.notes)
                .font(.system(size: 8))
                .lineLimit(3)
        }
    }

    private func alignment(for col: BidColumn) -> Alignment {
        switch col {
        case .bidAmount, .squareFeet, .beams, .numColumns, .joists,
             .wallPanels, .estimatedTons, .plansCount, .touchpointsCount:
            return .trailing
        case .status, .priority, .dueDate, .createdDate:
            return .center
        default:
            return .leading
        }
    }

    private func statusColor(for bid: BidProject) -> Color {
        switch bid.status {
        case .pending: return .gray
        case .workingOn: return .blue
        case .readyToSubmit: return .orange
        case .submitted: return .purple
        case .awarded: return .green
        case .lost: return .red
        }
    }

    private var footer: some View {
        HStack {
            Text("SteelSync")
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Text("Page \(pageIndex + 1) of \(totalPages)")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Helpers

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
