import Foundation
import CloudKit

enum RFIStatus: String, Codable, CaseIterable, Hashable {
    case draft = "Draft"
    case submitted = "Submitted"
    case responded = "Responded"
    case closed = "Closed"

    var color: String {
        switch self {
        case .draft: return "gray"
        case .submitted: return "blue"
        case .responded: return "orange"
        case .closed: return "green"
        }
    }
}

enum RFIPriority: String, Codable, CaseIterable, Hashable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case urgent = "Urgent"
}

struct RFI: Identifiable, Codable, Hashable {
    let id: UUID
    var number: Int
    var subject: String
    var submittedTo: String
    var submittedDate: Date
    var responseDueDate: Date
    var responseReceivedDate: Date?
    var status: RFIStatus
    var priority: RFIPriority
    var notes: String
    var attachments: [Attachment]       // The actual RFI document(s)
    var recordID: CKRecord.ID?
    var projectRef: CKRecord.Reference?

    enum CodingKeys: String, CodingKey {
        case id, number, subject, submittedTo
        case submittedDate, responseDueDate, responseReceivedDate
        case status, priority, notes, attachments
    }

    init(
        id: UUID = UUID(),
        number: Int = 1,
        subject: String = "",
        submittedTo: String = "",
        submittedDate: Date = Date(),
        responseDueDate: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date(),
        responseReceivedDate: Date? = nil,
        status: RFIStatus = .draft,
        priority: RFIPriority = .medium,
        notes: String = "",
        attachments: [Attachment] = [],
        recordID: CKRecord.ID? = nil,
        projectRef: CKRecord.Reference? = nil
    ) {
        self.id = id; self.number = number; self.subject = subject
        self.submittedTo = submittedTo
        self.submittedDate = submittedDate; self.responseDueDate = responseDueDate
        self.responseReceivedDate = responseReceivedDate
        self.status = status; self.priority = priority
        self.notes = notes; self.attachments = attachments
        self.recordID = recordID; self.projectRef = projectRef
    }

    var isOverdue: Bool {
        status != .closed && status != .responded && Date() > responseDueDate
    }

    var daysOpen: Int {
        let end = responseReceivedDate ?? Date()
        return Calendar.current.dateComponents([.day], from: submittedDate, to: end).day ?? 0
    }

    var ckRecordName: String { id.uuidString }
}
