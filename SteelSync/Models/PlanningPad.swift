import Foundation

/// A daily planning pad entry. Stores typed notes and a reference to a PKDrawing binary file.
struct PlanningPad: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date                      // Day this plan is for (start of day)
    var textNotes: String               // Typed notes
    var recognizedText: String          // Last OCR result
    var drawingDataFileName: String?    // Binary file name for PKDrawing data
    var createdDate: Date
    var lastModifiedDate: Date

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        textNotes: String = "",
        recognizedText: String = "",
        drawingDataFileName: String? = nil,
        createdDate: Date = Date(),
        lastModifiedDate: Date = Date()
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.textNotes = textNotes
        self.recognizedText = recognizedText
        self.drawingDataFileName = drawingDataFileName
        self.createdDate = createdDate
        self.lastModifiedDate = lastModifiedDate
    }

    // MARK: - Drawing Data File Paths

    static var drawingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("SteelSync/PlanningPadDrawings", isDirectory: true)
    }

    var drawingFileURL: URL? {
        guard let name = drawingDataFileName else { return nil }
        // Sanitize: strip path traversal characters
        let safe = name.replacingOccurrences(of: "/", with: "_")
                       .replacingOccurrences(of: "..", with: "_")
        return Self.drawingsDirectory.appendingPathComponent(safe)
    }

    /// Saves PKDrawing data to disk and updates the fileName reference.
    mutating func saveDrawingData(_ data: Data) {
        let dir = Self.drawingsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileName = drawingDataFileName ?? "\(id.uuidString).drawing"
        drawingDataFileName = fileName
        let url = dir.appendingPathComponent(fileName)
        try? data.write(to: url)
    }

    /// Loads PKDrawing data from disk.
    func loadDrawingData() -> Data? {
        guard let url = drawingFileURL else { return nil }
        return try? Data(contentsOf: url)
    }
}
