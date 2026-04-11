import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case clients = "Clients"
    case bidding = "Bidding"
    case timekeeping = "Timekeeping"
    case schedule = "Schedule"
    case equipment = "Equipment"
    case todo = "To-Do"
    case planningPad = "Planning Pad"
    case reports = "Reports"
    case activity = "Activity"
    case assistant = "Assistant"
    case settings = "Settings"

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
        case .planningPad: return "pencil.and.outline"
        case .reports: return "chart.bar.fill"
        case .activity: return "clock.arrow.circlepath"
        case .assistant: return "bubble.left.and.text.bubble.right"
        case .settings: return "gearshape.fill"
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
        case .planningPad: return "pencil.and.outline"
        case .reports: return "chart.bar.fill"
        case .activity: return "clock.arrow.circlepath"
        case .assistant: return "bubble.left.and.text.bubble.right.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

@MainActor
class NavigationState: ObservableObject {
    @Published var selectedSection: SidebarItem? = .dashboard
    @Published var selectedProjectID: CKRecordIDWrapper?
    @Published var selectedBidID: CKRecordIDWrapper?
    @Published var columnVisibility: NavigationSplitViewVisibility = .automatic
}

// Wrapper to make CKRecord.ID work with SwiftUI selection
import CloudKit
struct CKRecordIDWrapper: Hashable, Identifiable {
    let recordID: CKRecord.ID
    var id: CKRecord.ID { recordID }
}
