import SwiftUI
import Darwin

struct AssistantView: View {
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var service = AssistantService()
    @State private var inputText = ""
    @State private var saveAlertMessage = ""
    @State private var showSaveAlert = false
    @State private var showSavedBrowser = false
    @FocusState private var inputFocused: Bool

    private var messages: [AssistantMessage] { dataStore.assistantMessages }

    private let suggestedQueries = [
        "What needs attention?",
        "How's the business?",
        "Who worked the most this week?",
        "Payroll this month",
        "Margin trend",
        "Overdue RFIs",
        "Active projects",
        "Pending bids",
        "Costs this quarter",
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: service.isLLMAvailable ? "brain" : "cpu.fill")
                    .font(.title2)
                    .foregroundColor(service.isLLMAvailable ? .green : .blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text("SteelSync Assistant")
                        .font(AppTheme.Typography.title2)
                    Text(service.isLLMAvailable ? "AI Mode (Llama 8B)" : "Basic Mode")
                        .font(.caption2)
                        .foregroundColor(service.isLLMAvailable ? .green : .secondary)
                }
                Spacer()
                if service.isLLMAvailable && LLMService.shared.tokensPerSecond > 0 {
                    Text("\(String(format: "%.1f", LLMService.shared.tokensPerSecond)) tok/s")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.gray.opacity(0.15))
                        .clipShape(Capsule())
                }
                if LLMService.shared.status == .generating {
                    ProgressView()
                        .controlSize(.small)
                }
                Menu {
                    Button {
                        showSavedBrowser = true
                    } label: {
                        Label("Browse Saved Conversations…", systemImage: "folder")
                    }
                    if !messages.isEmpty {
                        Divider()
                        Button {
                            saveConversation()
                        } label: {
                            Label("Save This Conversation", systemImage: "square.and.arrow.down")
                        }
                        Button(role: .destructive) {
                            withAnimation {
                                dataStore.clearAssistantMessages()
                                LLMService.shared.clearChatHistory()
                            }
                        } label: {
                            Label("Clear Conversation", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .help("Conversation actions")
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        if messages.isEmpty {
                            welcomeSection
                        }

                        ForEach(messages) { msg in
                            ChatBubbleView(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.md)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            // Input bar
            HStack(spacing: AppTheme.Spacing.sm) {
                TextField("Ask about your projects, bids, finances...", text: $inputText)
                    .textFieldStyle(.roundedBorder)
                    .focused($inputFocused)
                    .onSubmit { sendMessage() }
                    #if os(iOS)
                    .submitLabel(.send)
                    #endif

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundColor(inputText.isEmpty ? .gray : AppTheme.primaryOrange)
                }
                .disabled(inputText.isEmpty || LLMService.shared.status == .generating)
                .buttonStyle(.plain)
            }
            .padding(AppTheme.Spacing.md)
        }
        .toolbar {
            #if os(iOS)
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { inputFocused = false }
                    .fontWeight(.semibold)
            }
            #endif
        }
        .onAppear {
            #if os(macOS)
            inputFocused = true
            #endif
        }
        .alert("Save Conversation", isPresented: $showSaveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveAlertMessage)
        }
        .sheet(isPresented: $showSavedBrowser) {
            SavedConversationsView { reopenedMessages in
                reopen(messages: reopenedMessages)
            }
            .environmentObject(dataStore)
        }
    }

    private func reopen(messages: [AssistantMessage]) {
        dataStore.clearAssistantMessages()
        LLMService.shared.clearChatHistory()
        for m in messages {
            dataStore.addAssistantMessage(m)
        }
        LLMService.shared.restoreChatHistory(from: messages)
    }

    // MARK: - Welcome / Suggested Queries

    @ViewBuilder
    private var welcomeSection: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer().frame(height: 40)

            Image(systemName: "cpu.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue.opacity(0.6))

            Text("SteelSync Assistant")
                .font(AppTheme.Typography.title2)

            Text("Ask questions about your projects, bids, finances, tasks, and more. All data stays on-device.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            // Suggested chips
            FlowLayout(spacing: 8) {
                ForEach(suggestedQueries, id: \.self) { query in
                    Button {
                        inputText = query
                        sendMessage()
                    } label: {
                        Text(query)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(AppTheme.primaryOrange.opacity(0.12))
                            .foregroundColor(AppTheme.primaryOrange)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 500)

            // Browse saved conversations — discoverable affordance for new users
            Button {
                showSavedBrowser = true
            } label: {
                Label("Browse saved conversations", systemImage: "folder")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 8)

            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Save Conversation

    /// Exports the current conversation to a Markdown file in
    /// Documents/SteelSync/Conversations/. Also embeds a snapshot of the
    /// business data context that was visible to the model at save time,
    /// so the conversation can be re-read without its references going stale.
    private func saveConversation() {
        guard !messages.isEmpty else { return }

        let now = Date()

        let fileNameFormatter = DateFormatter()
        fileNameFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let fileName = "Assistant_\(fileNameFormatter.string(from: now)).md"

        let readableFormatter = DateFormatter()
        readableFormatter.dateStyle = .medium
        readableFormatter.timeStyle = .short

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        timeFormatter.dateStyle = .none

        var md = "# SteelSync Assistant Conversation\n\n"
        md += "**Saved:** \(readableFormatter.string(from: now))  \n"
        md += "**Messages:** \(messages.count)  \n"
        md += "**Mode:** \(service.isLLMAvailable ? "AI (Llama)" : "Basic (Keyword)")  \n\n"
        md += "---\n\n## Conversation\n\n"

        for msg in messages {
            let role = msg.role == .user ? "You" : "SteelSync Assistant"
            md += "### \(role) — \(timeFormatter.string(from: msg.timestamp))\n\n"
            md += msg.content.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n"
        }

        md += "---\n\n## Data Snapshot at Save Time\n\n"
        md += "_This is a frozen copy of the business data the assistant had in context. "
        md += "It may be stale if you reopen this file later._\n\n"
        md += "<details>\n<summary>Expand business data context</summary>\n\n"
        md += "```\n"
        md += DataContextBuilder.buildSystemPrompt(from: dataStore)
        md += "\n```\n\n</details>\n"

        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let docsURL else {
            saveAlertMessage = "Could not locate Documents directory."
            showSaveAlert = true
            return
        }
        let folderURL = docsURL.appendingPathComponent("SteelSync/Conversations", isDirectory: true)
        let fileURL = folderURL.appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            try md.write(to: fileURL, atomically: true, encoding: .utf8)
            saveAlertMessage = "Saved \(messages.count) messages to:\n\n\(fileURL.path)"
        } catch {
            saveAlertMessage = "Save failed: \(error.localizedDescription)"
        }
        showSaveAlert = true
    }

    // MARK: - Send

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMsg = AssistantMessage(role: .user, content: text)
        dataStore.addAssistantMessage(userMsg)
        inputText = ""

        if service.isLLMAvailable {
            // LLM mode — sanitize input and strip Llama special tokens
            var sanitizedForLLM = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if sanitizedForLLM.count > 500 { sanitizedForLLM = String(sanitizedForLLM.prefix(500)) }
            // Strip ALL Llama special token patterns (<|...|>) — not just a hardcoded list.
            // This catches <|begin_of_text|>, <|python_tag|>, <|eot_id|>, and any future tokens.
            // Also normalizes Unicode homoglyphs of < > | to prevent bypass.
            sanitizedForLLM = sanitizedForLLM
                .replacingOccurrences(of: "\u{FF1C}", with: "<")  // fullwidth <
                .replacingOccurrences(of: "\u{FF1E}", with: ">")  // fullwidth >
                .replacingOccurrences(of: "\u{FF5C}", with: "|")  // fullwidth |
                .replacingOccurrences(of: "\u{2329}", with: "<")  // left angle bracket
                .replacingOccurrences(of: "\u{232A}", with: ">")  // right angle bracket
            // Now strip any <|...|> pattern (greedy, catches all special tokens)
            while let range = sanitizedForLLM.range(of: #"<\|[^|]*\|>"#, options: .regularExpression) {
                sanitizedForLLM.removeSubrange(range)
            }
            sanitizedForLLM = sanitizedForLLM.components(separatedBy: .controlCharacters).joined()

            let placeholder = AssistantMessage(role: .assistant, content: "Thinking...")
            dataStore.addAssistantMessage(placeholder)

            Task {
                let systemPrompt = DataContextBuilder.buildSystemPrompt(from: dataStore)
                let response = await LLMService.shared.generate(systemPrompt: systemPrompt, userMessage: sanitizedForLLM)

                // Replace placeholder with final response
                if !response.isEmpty {
                    var updated = placeholder
                    updated = AssistantMessage(id: placeholder.id, role: .assistant, content: response)
                    // Remove placeholder and add final
                    dataStore.assistantMessages.removeAll { $0.id == placeholder.id }
                    dataStore.addAssistantMessage(updated)
                } else {
                    // LLM returned empty — fall back to keyword engine
                    let fallback = service.processQuery(text, dataStore: dataStore)
                    dataStore.assistantMessages.removeAll { $0.id == placeholder.id }
                    dataStore.addAssistantMessage(AssistantMessage(role: .assistant, content: fallback))
                }
            }
        } else {
            // Keyword engine mode
            let response = service.processQuery(text, dataStore: dataStore)
            let assistantMsg = AssistantMessage(role: .assistant, content: response)
            dataStore.addAssistantMessage(assistantMsg)
        }
    }
}

// MARK: - Saved Conversations

struct SavedConversationFile: Identifiable {
    let id = UUID()
    let url: URL
    let fileName: String
    let modifiedDate: Date
    let fileSize: Int64

    var displayName: String {
        // "Assistant_2026-04-12_15-45-30.md" → "Assistant 2026-04-12 15:45:30"
        fileName
            .replacingOccurrences(of: ".md", with: "")
            .replacingOccurrences(of: "_", with: " ")
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: modifiedDate)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

struct SavedConversationsView: View {
    @Environment(\.dismiss) var dismiss
    let onReopen: ([AssistantMessage]) -> Void

    @State private var files: [SavedConversationFile] = []

    static var conversationsFolder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("SteelSync/Conversations", isDirectory: true)
    }

    var body: some View {
        NavigationStack {
            Group {
                if files.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No saved conversations")
                            .font(.headline)
                        Text("Use the Save button in the Assistant header to save a conversation.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(files) { file in
                            SavedConversationRow(file: file) {
                                reopen(file)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(file)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved Conversations")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { loadFiles() }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func loadFiles() {
        let folder = Self.conversationsFolder
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            files = []
            return
        }
        files = contents
            .filter { $0.pathExtension.lowercased() == "md" }
            .map { url -> SavedConversationFile in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                return SavedConversationFile(
                    url: url,
                    fileName: url.lastPathComponent,
                    modifiedDate: values?.contentModificationDate ?? Date(),
                    fileSize: Int64(values?.fileSize ?? 0)
                )
            }
            .sorted { $0.modifiedDate > $1.modifiedDate }
    }

    private func reopen(_ file: SavedConversationFile) {
        guard let content = try? String(contentsOf: file.url, encoding: .utf8) else { return }
        let parsed = Self.parseConversation(content)
        onReopen(parsed)
        dismiss()
    }

    private func delete(_ file: SavedConversationFile) {
        try? FileManager.default.removeItem(at: file.url)
        loadFiles()
    }

    /// Parses the markdown back into AssistantMessage list.
    /// Looks for "### You — " or "### SteelSync Assistant — " headers
    /// in the ## Conversation section, stopping at ## Data Snapshot.
    static func parseConversation(_ md: String) -> [AssistantMessage] {
        guard let convStart = md.range(of: "## Conversation") else { return [] }
        let convEnd = md.range(of: "\n## Data Snapshot")?.lowerBound ?? md.endIndex
        let section = String(md[convStart.upperBound..<convEnd])

        var messages: [AssistantMessage] = []
        let parts = section.components(separatedBy: "\n### ")
        for part in parts.dropFirst() {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let newlineIdx = trimmed.firstIndex(of: "\n") else { continue }
            let header = String(trimmed[..<newlineIdx])
            let role: AssistantMessage.MessageRole = header.hasPrefix("You") ? .user : .assistant
            let content = String(trimmed[trimmed.index(after: newlineIdx)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                messages.append(AssistantMessage(role: role, content: content))
            }
        }
        return messages
    }
}

private struct SavedConversationRow: View {
    let file: SavedConversationFile
    let onReopen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(file.displayName)
                .font(.headline)
                .lineLimit(1)
            HStack {
                Text(file.formattedDate)
                Spacer()
                Text(file.formattedSize)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            HStack(spacing: 10) {
                Button {
                    onReopen()
                } label: {
                    Label("Reopen", systemImage: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                ShareLink(item: file.url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Memory Monitor

/// Reads the app's resident memory footprint via Mach task_info.
/// `phys_footprint` is the same metric iOS uses for jetsam decisions
/// and what Xcode displays in the debug memory gauge.
@MainActor
final class MemoryMonitor: ObservableObject {
    static let shared = MemoryMonitor()

    @Published var usedMB: Double = 0
    let totalMB: Double

    private var timer: Timer?

    private init() {
        self.totalMB = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024
        refresh()
    }

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            usedMB = Double(info.phys_footprint) / 1024 / 1024
        }
    }

    var percentage: Double {
        guard totalMB > 0 else { return 0 }
        return (usedMB / totalMB) * 100
    }

    /// Status color based on how close we are to jetsam (iOS) or a
    /// reasonable ceiling (macOS). Thresholds differ because iOS kills
    /// apps well before they exhaust physical RAM.
    var statusColor: Color {
        let pct = percentage
        #if os(iOS)
        if pct < 25 { return .green }
        if pct < 40 { return .yellow }
        return .red
        #else
        if pct < 50 { return .green }
        if pct < 75 { return .yellow }
        return .red
        #endif
    }

    var formattedUsed: String {
        if usedMB >= 1024 {
            return String(format: "%.1f GB", usedMB / 1024)
        }
        return String(format: "%.0f MB", usedMB)
    }

    var formattedTotal: String {
        String(format: "%.0f GB", totalMB / 1024)
    }
}

// MARK: - Memory Badge View

struct MemoryBadgeView: View {
    @ObservedObject var monitor: MemoryMonitor

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.25))
                    .frame(width: 40, height: 5)
                Capsule()
                    .fill(monitor.statusColor)
                    .frame(width: 40 * min(1, max(0, monitor.percentage / 100)), height: 5)
            }
            Text(monitor.formattedUsed)
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.gray.opacity(0.15))
        .clipShape(Capsule())
        .help("App memory: \(monitor.formattedUsed) of \(monitor.formattedTotal) (\(String(format: "%.1f%%", monitor.percentage)))")
    }
}

// MARK: - Simple FlowLayout for suggested chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, pos) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }
        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}
