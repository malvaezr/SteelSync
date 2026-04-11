import Foundation

struct AssistantMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var role: MessageRole
    var content: String
    var timestamp: Date

    enum MessageRole: String, Codable, Hashable {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id; self.role = role; self.content = content; self.timestamp = timestamp
    }
}
