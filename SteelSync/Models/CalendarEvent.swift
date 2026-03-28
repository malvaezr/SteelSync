import Foundation
import CloudKit

struct CalendarEvent: Identifiable, Codable, Hashable {
    let id: UUID
    var projectID: UUID?
    var title: String
    var description: String
    var startDate: Date
    var endDate: Date
    var type: EventType
    var isAllDay: Bool
    var recordID: CKRecord.ID?

    enum CodingKeys: String, CodingKey {
        case id, projectID, title, description, startDate, endDate, type, isAllDay
    }

    enum EventType: String, Codable, CaseIterable {
        case milestone = "Milestone"
        case meeting = "Meeting"
        case inspection = "Inspection"
        case delivery = "Delivery"
        case deadline = "Deadline"
        case other = "Other"

        var icon: String {
            switch self {
            case .milestone: return "flag.fill"
            case .meeting: return "person.2.fill"
            case .inspection: return "checkmark.seal.fill"
            case .delivery: return "shippingbox.fill"
            case .deadline: return "clock.fill"
            case .other: return "calendar"
            }
        }

        var color: String {
            switch self {
            case .milestone: return "blue"
            case .meeting: return "green"
            case .inspection: return "orange"
            case .delivery: return "purple"
            case .deadline: return "red"
            case .other: return "gray"
            }
        }
    }

    init(
        id: UUID = UUID(), projectID: UUID? = nil, title: String, description: String = "",
        startDate: Date, endDate: Date? = nil, type: EventType = .other,
        isAllDay: Bool = false, recordID: CKRecord.ID? = nil
    ) {
        self.id = id; self.projectID = projectID; self.title = title
        self.description = description; self.startDate = startDate
        self.endDate = endDate ?? startDate; self.type = type
        self.isAllDay = isAllDay; self.recordID = recordID
    }

    var isUpcoming: Bool { startDate > Date() }
    var isPast: Bool { endDate < Date() }
    var isToday: Bool { Calendar.current.isDateInToday(startDate) }
}

extension CalendarEvent {
    static let preview = CalendarEvent(
        title: "Foundation Inspection", description: "City inspector scheduled",
        startDate: Date().addingTimeInterval(86400 * 3), type: .inspection
    )
}
