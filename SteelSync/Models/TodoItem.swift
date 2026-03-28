import Foundation
import CloudKit

enum TodoPriority: Int, Codable, CaseIterable {
    case low = 0, medium = 1, high = 2, urgent = 3

    var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .urgent: return "Urgent"
        }
    }

    var color: String {
        switch self {
        case .low: return "gray"
        case .medium: return "blue"
        case .high: return "orange"
        case .urgent: return "red"
        }
    }
}

enum TodoCategory: String, Codable, CaseIterable {
    case general = "General"
    case bidFollowUp = "Bid Follow-up"
    case bidDeadline = "Bid Deadline"
    case projectTask = "Project Task"
    case meeting = "Meeting"
    case inspection = "Inspection"
    case payment = "Payment"
    case other = "Other"

    var icon: String {
        switch self {
        case .general: return "checklist"
        case .bidFollowUp: return "phone.arrow.up.right"
        case .bidDeadline: return "calendar.badge.exclamationmark"
        case .projectTask: return "folder"
        case .meeting: return "person.2"
        case .inspection: return "magnifyingglass"
        case .payment: return "dollarsign.circle"
        case .other: return "ellipsis.circle"
        }
    }
}

struct TodoItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var notes: String
    var dueDate: Date?
    var priority: TodoPriority
    var category: TodoCategory
    var isCompleted: Bool
    var completedDate: Date?
    var createdDate: Date
    var relatedBidID: String?
    var relatedProjectID: String?
    var recordID: CKRecord.ID?

    enum CodingKeys: String, CodingKey {
        case id, title, notes, dueDate, priority, category, isCompleted
        case completedDate, createdDate, relatedBidID, relatedProjectID
    }

    init(
        id: UUID = UUID(), title: String, notes: String = "", dueDate: Date? = nil,
        priority: TodoPriority = .medium, category: TodoCategory = .general,
        isCompleted: Bool = false, completedDate: Date? = nil, createdDate: Date = Date(),
        relatedBidID: String? = nil, relatedProjectID: String? = nil, recordID: CKRecord.ID? = nil
    ) {
        self.id = id; self.title = title; self.notes = notes; self.dueDate = dueDate
        self.priority = priority; self.category = category; self.isCompleted = isCompleted
        self.completedDate = completedDate; self.createdDate = createdDate
        self.relatedBidID = relatedBidID; self.relatedProjectID = relatedProjectID
        self.recordID = recordID
    }

    var isOverdue: Bool {
        guard let dueDate = dueDate, !isCompleted else { return false }
        return dueDate < Date()
    }
    var isDueToday: Bool {
        guard let dueDate = dueDate, !isCompleted else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }
    var isDueSoon: Bool {
        guard let dueDate = dueDate, !isCompleted else { return false }
        let threeDays = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
        return dueDate <= threeDays && dueDate > Date()
    }
}

extension TodoItem {
    static let preview = TodoItem(
        title: "Follow up on Downtown Project bid",
        notes: "Call John to discuss pricing",
        dueDate: Date().addingTimeInterval(86400 * 2),
        priority: .high, category: .bidFollowUp
    )

    static let sampleTodos: [TodoItem] = [
        TodoItem(title: "Submit Metro Tower bid", dueDate: Date().addingTimeInterval(86400 * 5), priority: .urgent, category: .bidDeadline),
        TodoItem(title: "Follow up with Acme Construction", notes: "They requested updated pricing", dueDate: Date().addingTimeInterval(86400), priority: .high, category: .bidFollowUp),
        TodoItem(title: "Order materials for Harrison Bridge", dueDate: Date().addingTimeInterval(86400 * 3), priority: .medium, category: .projectTask),
        TodoItem(title: "Review employee timesheets", priority: .low, category: .general, isCompleted: true, completedDate: Date().addingTimeInterval(-86400))
    ]
}
