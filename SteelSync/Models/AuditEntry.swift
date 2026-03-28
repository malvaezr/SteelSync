import Foundation
import CloudKit

enum AuditAction: String, Codable, CaseIterable {
    case created = "Created"
    case updated = "Updated"
    case deleted = "Deleted"

    var icon: String {
        switch self {
        case .created: return "plus.circle.fill"
        case .updated: return "pencil.circle.fill"
        case .deleted: return "trash.circle.fill"
        }
    }

    var color: String {
        switch self {
        case .created: return "green"
        case .updated: return "blue"
        case .deleted: return "red"
        }
    }
}

struct AuditEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var timestamp: Date
    var action: AuditAction
    var entityType: String
    var entityID: String
    var entityDescription: String
    var userIdentifier: String
    var userName: String
    var details: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: AuditAction,
        entityType: String,
        entityID: String = "",
        entityDescription: String,
        userIdentifier: String = "local",
        userName: String = "Local User",
        details: String = ""
    ) {
        self.id = id; self.timestamp = timestamp; self.action = action
        self.entityType = entityType; self.entityID = entityID
        self.entityDescription = entityDescription
        self.userIdentifier = userIdentifier; self.userName = userName
        self.details = details
    }
}
