import SwiftUI

struct AssistantView: View {
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var service = AssistantService()
    @State private var inputText = ""
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
                if !messages.isEmpty {
                    Button("Clear") {
                        withAnimation { dataStore.clearAssistantMessages() }
                    }
                    .font(.callout)
                    .foregroundColor(.secondary)
                }
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
                .disabled(inputText.isEmpty)
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

            Spacer().frame(height: 40)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Send

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let userMsg = AssistantMessage(role: .user, content: text)
        dataStore.addAssistantMessage(userMsg)
        inputText = ""

        if service.isLLMAvailable {
            // LLM mode — stream response
            let placeholder = AssistantMessage(role: .assistant, content: "Thinking...")
            dataStore.addAssistantMessage(placeholder)

            Task {
                let systemPrompt = DataContextBuilder.buildSystemPrompt(from: dataStore)
                let response = await LLMService.shared.generate(systemPrompt: systemPrompt, userMessage: text)

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
