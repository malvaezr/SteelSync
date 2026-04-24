import Foundation
import llama

/// Manages local LLM model lifecycle: download, load, inference, unload.
/// All inference runs on-device. Zero network calls after model download.
@MainActor
class LLMService: ObservableObject {
    static let shared = LLMService()

    // Model configuration
    static let modelFileName = "Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
    static let modelDownloadURL = "https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf"
    static let maxResponseTokens: Int32 = 512
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
    @Published var tokensPerSecond: Double = 0

    private var downloadTask: URLSessionDownloadTask?
    private var downloadObservation: NSKeyValueObservation?
    private var llamaModel: OpaquePointer?  // llama_model *
    private var inferenceTask: Task<String, Never>?
    /// Set to true while inference is executing inside a llama.cpp C call.
    /// Checked by unloadModel to ensure C resources are not in use before freeing.
    private let inferenceActive = NSLock()

    /// Multi-turn conversation history. Each generate() call appends the new
    /// user/assistant pair on success. Cleared via clearChatHistory().
    struct ChatTurn: Equatable {
        let role: String  // "user" or "assistant"
        let content: String
    }
    private var chatHistory: [ChatTurn] = []

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
        llama_backend_init()
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
                        self.status = .error("File too small. May be corrupted.")
                        return
                    }
                    guard self.validateGGUFHeader(at: Self.modelFileURL) else {
                        try? FileManager.default.removeItem(at: Self.modelFileURL)
                        self.status = .error("Invalid model file. Not a valid GGUF format.")
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
        clearChatHistory()
        try? FileManager.default.removeItem(at: Self.modelFileURL)
        status = .notDownloaded
    }

    // MARK: - Model Loading

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

        let modelPath = Self.modelFileURL.path
        Task.detached { [weak self] in
            var params = llama_model_default_params()
            params.n_gpu_layers = 99 // Use Metal GPU for all layers

            guard let model = llama_model_load_from_file(modelPath, params) else {
                await MainActor.run { self?.status = .error("Failed to load model.") }
                return
            }

            await MainActor.run {
                self?.llamaModel = model
                self?.status = .ready
            }
        }
    }

    func unloadModel() {
        // Cancel in-flight inference first to prevent use-after-free
        let taskToAwait = inferenceTask
        inferenceTask?.cancel()
        inferenceTask = nil

        if let taskToAwait, status == .generating {
            // Await the inference task to ensure llama.cpp C calls have finished
            // before freeing the model pointer. The heuristic 0.5s delay is replaced
            // by actually waiting for the task + acquiring the inference lock.
            Task { [weak self] in
                _ = await taskToAwait.value  // Wait for inference loop to exit
                self?.inferenceActive.lock()  // Ensure no C call is mid-flight
                self?.inferenceActive.unlock()
                await MainActor.run {
                    if let m = self?.llamaModel { llama_model_free(m) }
                    self?.llamaModel = nil
                    self?.status = .downloaded
                }
            }
        } else {
            if let m = llamaModel { llama_model_free(m) }
            llamaModel = nil
            if status == .ready { status = .downloaded }
        }
    }

    // MARK: - Inference

    func generate(systemPrompt: String, userMessage: String) async -> String {
        guard status == .ready, let model = llamaModel else { return "" }

        status = .generating
        streamingText = ""

        // Build prompt with system + prior conversation history + new user turn.
        // History is trimmed from the oldest end until total chars fit the budget,
        // keeping ~2000 tokens of the 4096 ctx window free for the model's response.
        var prompt = "<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n\(systemPrompt)<|eot_id|>"
        let newUserTurn = "<|start_header_id|>user<|end_header_id|>\n\n\(userMessage)<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\n"

        // Char-based budget as a rough token estimator (~4 chars/token for English).
        // n_ctx 8192 - 512 response - 256 safety ≈ 7424 tokens ≈ 29,696 chars total.
        let maxPromptChars = 29_696
        let fixedChars = prompt.utf8.count + newUserTurn.utf8.count
        var historyBudget = maxPromptChars - fixedChars

        var includedHistory: [ChatTurn] = []
        for turn in chatHistory.reversed() {
            let turnChars = turn.content.utf8.count + 80  // +header/footer overhead
            if turnChars > historyBudget { break }
            includedHistory.insert(turn, at: 0)
            historyBudget -= turnChars
        }
        for turn in includedHistory {
            prompt += "<|start_header_id|>\(turn.role)<|end_header_id|>\n\n\(turn.content)<|eot_id|>"
        }
        prompt += newUserTurn
        let fullPrompt = prompt
        print("[LLM] History: \(includedHistory.count) turns included / \(chatHistory.count) total, prompt chars: \(fullPrompt.utf8.count)")

        let inferLock = self.inferenceActive
        let task = Task.detached { [weak self] () -> String in
            // Create context
            var ctxParams = llama_context_default_params()
            ctxParams.n_ctx = 8192
            ctxParams.n_batch = 512

            inferLock.lock()
            print("[LLM] Creating context with n_ctx=8192, n_batch=512...")
            guard let ctx = llama_init_from_model(model, ctxParams) else {
                print("[LLM] ERROR: Failed to create context")
                inferLock.unlock()
                return ""
            }
            defer {
                llama_free(ctx)
                inferLock.unlock()
            }
            print("[LLM] Context created successfully")

            // Get vocab once — used for both tokenize and token_to_piece
            let vocab = llama_model_get_vocab(model)

            // Resolve Llama-3.1 end-of-turn token ID.
            // Some GGUF conversions don't mark <|eot_id|> (128009) as EOG,
            // so llama_vocab_is_eog misses it and generation hallucinates new turns.
            let eotText = "<|eot_id|>"
            var eotBuf = [llama_token](repeating: 0, count: 8)
            let eotCount = llama_tokenize(vocab, eotText, Int32(eotText.utf8.count), &eotBuf, 8, false, true)
            let eotTokenId: llama_token = eotCount == 1 ? eotBuf[0] : -1
            print("[LLM] EOT token ID: \(eotTokenId)")

            // Tokenize (requires llama_vocab*, NOT llama_model*)
            let nMaxTokens = Int32(fullPrompt.utf8.count) + 128
            var tokens = [llama_token](repeating: 0, count: Int(nMaxTokens))
            let nTokens = llama_tokenize(vocab, fullPrompt, Int32(fullPrompt.utf8.count), &tokens, nMaxTokens, true, false)
            print("[LLM] Tokenized: \(nTokens) tokens (prompt \(fullPrompt.utf8.count) bytes)")
            guard nTokens > 0 else {
                print("[LLM] ERROR: Tokenization failed")
                return ""
            }

            // Evaluate prompt in chunks of n_batch to avoid exceeding batch size
            var promptTokens = Array(tokens.prefix(Int(nTokens)))
            let batchSize = Int(ctxParams.n_batch)
            var promptFailed = false

            for chunkStart in stride(from: 0, to: Int(nTokens), by: batchSize) {
                let chunkEnd = min(chunkStart + batchSize, Int(nTokens))
                let chunkCount = Int32(chunkEnd - chunkStart)
                print("[LLM] Decoding chunk \(chunkStart)..\(chunkEnd) (\(chunkCount) tokens)")

                let result: Int32 = promptTokens.withUnsafeMutableBufferPointer { bufPtr in
                    let chunkPtr = bufPtr.baseAddress! + chunkStart
                    var batch = llama_batch_get_one(chunkPtr, chunkCount)
                    return llama_decode(ctx, batch)
                }
                if result != 0 {
                    print("[LLM] ERROR: Decode failed at chunk \(chunkStart) with result \(result)")
                    promptFailed = true
                    break
                }
            }
            guard !promptFailed else {
                print("[LLM] ERROR: Prompt evaluation failed")
                return ""
            }
            print("[LLM] Prompt evaluation complete. Starting generation...")

            // Set up sampler chain: temp -> top_p -> sample
            let samplerParams = llama_sampler_chain_default_params()
            guard let sampler = llama_sampler_chain_init(samplerParams) else { return "" }
            llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7))
            llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
            llama_sampler_chain_add(sampler, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
            defer { llama_sampler_free(sampler) }

            // Generate tokens
            var output = ""
            var nCur = nTokens
            let nCtx = Int32(ctxParams.n_ctx)
            let startTime = Date()

            for _ in 0..<Self.maxResponseTokens {
                if Date().timeIntervalSince(startTime) > Self.inferenceTimeout { break }
                if Task.isCancelled { break }
                // Prevent KV cache overflow — stop before exceeding context window
                if nCur >= nCtx - 1 { break }

                // Sample next token
                let newToken = llama_sampler_sample(sampler, ctx, -1)

                // Check for end of generation — multiple methods for robustness
                if llama_vocab_is_eog(vocab, newToken) { break }
                if eotTokenId >= 0 && newToken == eotTokenId { break }

                // Convert token to text (buffer +1 for null terminator safety)
                var buf = [CChar](repeating: 0, count: 257)
                let len = llama_token_to_piece(vocab, newToken, &buf, 256, 0, false)
                if len > 0 && len < 257 {
                    buf[Int(len)] = 0
                    let piece = String(cString: buf)
                    output += piece

                    let currentOutput = Self.sanitizeOutput(output)
                    Task { @MainActor in
                        self?.streamingText = currentOutput
                    }
                }

                // Decode next token
                var nextToken = newToken
                var nextBatch = llama_batch_get_one(&nextToken, 1)
                guard llama_decode(ctx, nextBatch) == 0 else { break }
                nCur += 1
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let tokenCount = nCur - nTokens
            let tokPerSec = elapsed > 0 ? Double(tokenCount) / elapsed : 0
            print("[LLM] Generation complete: \(tokenCount) tokens in \(String(format: "%.1f", elapsed))s (\(String(format: "%.1f", tokPerSec)) tok/s)")
            Task { @MainActor in
                self?.tokensPerSecond = tokPerSec
            }
            return output
        }
        inferenceTask = task
        let result = await task.value

        inferenceTask = nil
        status = .ready
        let cleaned = Self.sanitizeOutput(result)
        streamingText = cleaned

        // Append to history only on a successful (non-empty) response.
        if !cleaned.isEmpty {
            chatHistory.append(ChatTurn(role: "user", content: userMessage))
            chatHistory.append(ChatTurn(role: "assistant", content: cleaned))
        }

        return cleaned
    }

    /// Wipes all multi-turn conversation history and releases its memory.
    /// Call this when the user clears the chat — each next generate() will
    /// start from a fresh system-only prompt.
    func clearChatHistory() {
        chatHistory.removeAll(keepingCapacity: false)
        streamingText = ""
        tokensPerSecond = 0
        print("[LLM] Chat history cleared.")
    }

    /// Rebuilds the multi-turn history from a saved conversation so that
    /// follow-up questions can reference earlier turns.
    func restoreChatHistory(from messages: [AssistantMessage]) {
        chatHistory = messages.map { msg in
            ChatTurn(
                role: msg.role == .user ? "user" : "assistant",
                content: msg.content
            )
        }
        print("[LLM] Chat history restored: \(chatHistory.count) turns.")
    }

    /// Strip any Llama special tokens that leaked into the output
    private nonisolated static func sanitizeOutput(_ text: String) -> String {
        var s = text
        // If an end-of-turn marker leaked, truncate everything after it —
        // anything past <|eot_id|> is a hallucinated next turn.
        if let eotRange = s.range(of: "<|eot_id|>") {
            s = String(s[..<eotRange.lowerBound])
        }
        // Strip full header blocks including the role text between them
        // (e.g. "<|start_header_id|>assistant<|end_header_id|>" → "")
        while let range = s.range(of: #"<\|start_header_id\|>[\s\S]*?<\|end_header_id\|>"#, options: .regularExpression) {
            s.removeSubrange(range)
        }
        // Remove any remaining <|...|> special tokens
        while let range = s.range(of: #"<\|[^|]*\|>"#, options: .regularExpression) {
            s.removeSubrange(range)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
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
            guard validateGGUFHeader(at: Self.modelFileURL) else {
                try? FileManager.default.removeItem(at: Self.modelFileURL)
                status = .error("Invalid file. Not a valid GGUF model format.")
                return false
            }
            status = .downloaded
            return true
        } catch {
            status = .error("Import failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Safety

    private var isErrorStatus: Bool {
        if case .error = status { return true }
        return false
    }

    /// Validates that a file has a valid GGUF magic header (0x46475547 = "GGUF")
    private func validateGGUFHeader(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { handle.closeFile() }
        let magic = handle.readData(ofLength: 4)
        // GGUF magic bytes: 0x47, 0x47, 0x55, 0x46 ("GGUF")
        return magic == Data([0x47, 0x47, 0x55, 0x46])
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
