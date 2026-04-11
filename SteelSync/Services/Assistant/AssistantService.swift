import Foundation

/// Central service that processes user queries and returns assistant responses.
/// Read-only access to DataStore — never modifies data.
@MainActor
class AssistantService: ObservableObject {
    private let formatter = ResponseFormatter()
    private var parser = QueryParser()

    /// Process a user query and return a response string.
    func processQuery(_ input: String, dataStore: DataStore) -> String {
        let sanitized = sanitize(input)
        guard !sanitized.isEmpty else {
            return "Please type a question about your projects, bids, or business data."
        }

        // Update parser with current entity names for fuzzy matching
        parser.projectNames = dataStore.projects.map(\.title)
        parser.bidNames = dataStore.bids.map(\.projectName)
        parser.clientNames = dataStore.clients.map(\.name)

        let intent = parser.parse(sanitized)
        return formatter.format(intent, dataStore: dataStore)
    }

    // MARK: - Input Safety

    /// Basic input sanitization — strips control characters and excessive length.
    private func sanitize(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // Cap length to prevent abuse
        if text.count > 500 { text = String(text.prefix(500)) }
        // Remove control characters
        text = text.filter { !$0.isNewline || $0 == " " }
            .components(separatedBy: .controlCharacters).joined()
        return text
    }
}
