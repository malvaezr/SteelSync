import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case clients = "Clients"
    case bidding = "Bidding"
    case timekeeping = "Timekeeping"
    case schedule = "Schedule"
    case equipment = "Equipment"
    case todo = "To-Do"
    case reports = "Reports"
    case activity = "Activity"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .dashboard: return "building.2.fill"
        case .clients: return "person.2.fill"
        case .bidding: return "doc.text.fill"
        case .timekeeping: return "clock.fill"
        case .schedule: return "calendar.day.timeline.left"
        case .equipment: return "shippingbox.fill"
        case .todo: return "checklist"
        case .reports: return "chart.bar.fill"
        case .activity: return "clock.arrow.circlepath"
        }
    }

    var selectedIcon: String {
        switch self {
        case .dashboard: return "building.2.fill"
        case .clients: return "person.2.fill"
        case .bidding: return "doc.text.fill"
        case .timekeeping: return "clock.fill"
        case .schedule: return "calendar.day.timeline.left"
        case .equipment: return "shippingbox.fill"
        case .todo: return "checklist"
        case .reports: return "chart.bar.fill"
        case .activity: return "clock.arrow.circlepath"
        }
    }
}

@MainActor
class NavigationState: ObservableObject {
    @Published var selectedSection: SidebarItem? = .dashboard
    @Published var selectedProjectID: CKRecordIDWrapper?
    @Published var selectedBidID: CKRecordIDWrapper?
}

// Wrapper to make CKRecord.ID work with SwiftUI selection
import CloudKit
struct CKRecordIDWrapper: Hashable, Identifiable {
    let recordID: CKRecord.ID
    var id: CKRecord.ID { recordID }
}
