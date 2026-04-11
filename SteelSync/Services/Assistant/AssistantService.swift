import Foundation

/// Central service that processes user queries and returns assistant responses.
/// Read-only access to DataStore — never modifies data.
@MainActor
class AssistantService: ObservableObject {
    private let formatter = ResponseFormatter()
    private var parser = QueryParser()

    /// Last discussed entity for follow-up context
    var lastProjectName: String?
    var lastBidName: String?
    var lastIntent: QueryIntent?

    /// Process a user query. Uses LLM if available, falls back to keyword engine.
    func processQuery(_ input: String, dataStore: DataStore) -> String {
        let sanitized = sanitize(input)
        guard !sanitized.isEmpty else {
            return "Please type a question about your projects, bids, or business data."
        }

        // Update parser with current entity names for fuzzy matching
        parser.projectNames = dataStore.projects.map(\.title)
        parser.bidNames = dataStore.bids.map(\.projectName)
        parser.clientNames = dataStore.clients.map(\.name)
        parser.lastProjectName = lastProjectName

        let intent = parser.parse(sanitized)
        updateContext(from: intent)

        // Always use keyword engine for now (LLM streaming handled separately)
        return formatter.format(intent, dataStore: dataStore)
    }

    /// Process a query through the LLM with streaming. Returns true if LLM was used.
    func processQueryWithLLM(_ input: String, dataStore: DataStore) async -> Bool {
        let llm = LLMService.shared
        guard llm.status == .ready else { return false }

        let systemPrompt = DataContextBuilder.buildSystemPrompt(from: dataStore)
        let response = await llm.generate(systemPrompt: systemPrompt, userMessage: input)

        // If LLM returned empty (not yet integrated), return false to trigger fallback
        return !response.isEmpty
    }

    var isLLMAvailable: Bool {
        LLMService.shared.status == .ready
    }

    var isLLMDownloaded: Bool {
        LLMService.shared.isModelDownloaded
    }

    private func updateContext(from intent: QueryIntent) {
        lastIntent = intent
        switch intent {
        case .projectDetails(let name), .projectFinance(let name),
             .projectChangeOrders(let name), .timesheetForProject(let name),
             .costBreakdown(let name), .projectHealth(let name):
            lastProjectName = name
        case .bidDetails(let name):
            lastBidName = name
        case .compareProjects(let a, _):
            lastProjectName = a
        default:
            break
        }
    }

    // MARK: - Input Safety

    private func sanitize(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 500 { text = String(text.prefix(500)) }
        text = text.filter { !$0.isNewline || $0 == " " }
            .components(separatedBy: .controlCharacters).joined()
        return text
    }
}
