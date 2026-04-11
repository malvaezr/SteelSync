import Foundation
// import llama  // Uncomment when llama.cpp XCFramework is added

/// Manages local LLM model lifecycle: download, load, inference, unload.
/// All inference runs on-device. Zero network calls after model download.
@MainActor
class LLMService: ObservableObject {
    static let shared = LLMService()

    // Model configuration
    static let modelFileName = "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
    static let modelDownloadURL = "https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
    static let maxTokens: Int32 = 512
    static let inferenceTimeout: TimeInterval = 30

    // State
    enum ModelStatus: Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case loading
        case ready
        case error(String)
        case generating
    }

    @Published var status: ModelStatus = .notDownloaded
    @Published var streamingText: String = ""

    private var downloadTask: URLSessionDownloadTask?
    private var downloadObservation: NSKeyValueObservation?

    private var inferenceTask: Task<Void, Never>?
    // llama.cpp handles — uncomment when framework is linked
    // private var model: OpaquePointer?
    // private var context: OpaquePointer?

    // MARK: - Model File Management

    static var modelsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("SteelSync/Models", isDirectory: true)
    }

    static var modelFileURL: URL {
        modelsDirectory.appendingPathComponent(modelFileName)
    }

    var isModelDownloaded: Bool {
        FileManager.default.fileExists(atPath: Self.modelFileURL.path)
    }

    var modelFileSizeFormatted: String {
        guard isModelDownloaded else { return "Not downloaded" }
        let attrs = try? FileManager.default.attributesOfItem(atPath: Self.modelFileURL.path)
        let size = attrs?[.size] as? Int64 ?? 0
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    init() {
        if isModelDownloaded { status = .downloaded }
    }

    // MARK: - Download with Safety Checks

    func downloadModel() {
        guard status == .notDownloaded || isErrorStatus else { return }

        let freeSpace = availableDiskSpace()
        guard freeSpace > 5_000_000_000 else {
            status = .error("Not enough disk space. Need 5 GB free.")
            return
        }

        try? FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)

        guard let url = URL(string: Self.modelDownloadURL) else {
            status = .error("Invalid download URL.")
            return
        }

        status = .downloading(progress: 0)

        let session = URLSession(configuration: .default)
        let task = session.downloadTask(with: url) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                guard let self else { return }

                if let error {
                    self.status = .error("Download failed: \(error.localizedDescription)")
                    return
                }
                guard let tempURL else {
                    self.status = .error("Download failed: no file received.")
                    return
                }
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    self.status = .error("Download failed: HTTP \(http.statusCode)")
                    return
                }

                do {
                    try? FileManager.default.removeItem(at: Self.modelFileURL)
                    try FileManager.default.moveItem(at: tempURL, to: Self.modelFileURL)

                    let attrs = try FileManager.default.attributesOfItem(atPath: Self.modelFileURL.path)
                    let fileSize = attrs[.size] as? Int64 ?? 0
                    guard fileSize > 1_000_000_000 else {
                        try? FileManager.default.removeItem(at: Self.modelFileURL)
                        self.status = .error("File too small (\(fileSize) bytes). May be corrupted.")
                        return
                    }
                    self.status = .downloaded
                } catch {
                    self.status = .error("Failed to save: \(error.localizedDescription)")
                }
            }
        }

        downloadObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.status = .downloading(progress: progress.fractionCompleted)
            }
        }

        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        downloadObservation = nil
        status = .notDownloaded
    }

    func deleteModel() {
        unloadModel()
        try? FileManager.default.removeItem(at: Self.modelFileURL)
        status = .notDownloaded
    }

    // MARK: - Model Loading
    // TODO: Wire to llama.cpp when XCFramework is built and linked

    func loadModel() {
        guard isModelDownloaded else {
            status = .error("Model not downloaded.")
            return
        }
        guard checkAvailableMemory() else {
            status = .error("Not enough RAM. Close other apps and try again.")
            return
        }

        status = .loading
        // Stub: mark as ready. Real loading will initialize llama.cpp context.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.status = .ready
        }
    }

    func unloadModel() {
        inferenceTask?.cancel()
        if status == .ready || status == .generating { status = .downloaded }
    }

    // MARK: - Inference
    // TODO: Replace with actual llama.cpp inference when XCFramework is linked

    func generate(systemPrompt: String, userMessage: String) async -> String {
        guard status == .ready else { return "" }
        status = .generating
        streamingText = ""

        // Stub: return empty to trigger keyword engine fallback
        // When llama.cpp is linked, this will:
        // 1. Tokenize the prompt in Llama-3.1 Instruct format
        // 2. Run inference token by token with Metal GPU
        // 3. Stream tokens into streamingText
        // 4. Return the full response

        try? await Task.sleep(nanoseconds: 100_000_000)
        status = .ready
        return ""
    }

    // MARK: - File Import

    func importModelFile(from sourceURL: URL) -> Bool {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.isReadableFile(atPath: sourceURL.path) else { return false }

        do {
            try? FileManager.default.createDirectory(at: Self.modelsDirectory, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: Self.modelFileURL)
            try FileManager.default.copyItem(at: sourceURL, to: Self.modelFileURL)

            let attrs = try FileManager.default.attributesOfItem(atPath: Self.modelFileURL.path)
            let fileSize = attrs[.size] as? Int64 ?? 0
            guard fileSize > 1_000_000_000 else {
                try? FileManager.default.removeItem(at: Self.modelFileURL)
                status = .error("File too small to be a valid model.")
                return false
            }

            status = .downloaded
            return true
        } catch {
            status = .error("Import failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Safety Checks

    private var isErrorStatus: Bool {
        if case .error = status { return true }
        return false
    }

    private func availableDiskSpace() -> Int64 {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let url = paths.first else { return 0 }
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func checkAvailableMemory() -> Bool {
        ProcessInfo.processInfo.physicalMemory >= 6_000_000_000
    }
}
