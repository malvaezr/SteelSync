import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    // TODAY — what needs attention right now
    case today = "Today"
    case schedule = "Schedule"
    case todo = "Tasks"

    // PROJECTS — the work itself
    case dashboard = "Active Projects"
    case rfis = "RFIs"
    case invoices = "Invoices"
    case reports = "Reports"

    // OPERATIONS — field execution
    case timekeeping = "Crew & Timesheets"
    case equipment = "Equipment"
    case calendar = "Calendar"
    case overhead = "Overhead"

    // PIPELINE — money and relationships
    case bidding = "Bidding"
    case clients = "Clients"

    // TOOLS — assistive
    case assistant = "Assistant"
    case activity = "Activity"
    case settings = "Settings"

    // iPad-only
    case planningPad = "Planning Pad"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .schedule: return "calendar.day.timeline.left"
        case .todo: return "checklist"
        case .dashboard: return "building.2.fill"
        case .rfis: return "questionmark.bubble.fill"
        case .invoices: return "doc.plaintext.fill"
        case .reports: return "chart.bar.fill"
        case .timekeeping: return "person.3.fill"
        case .equipment: return "shippingbox.fill"
        case .calendar: return "calendar"
        case .overhead: return "briefcase.fill"
        case .bidding: return "doc.text.fill"
        case .clients: return "person.2.fill"
        case .assistant: return "bubble.left.and.text.bubble.right"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        case .planningPad: return "pencil.and.outline"
        }
    }

    var selectedIcon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .schedule: return "calendar.day.timeline.left"
        case .todo: return "checklist"
        case .dashboard: return "building.2.fill"
        case .rfis: return "questionmark.bubble.fill"
        case .invoices: return "doc.plaintext.fill"
        case .reports: return "chart.bar.fill"
        case .timekeeping: return "person.3.fill"
        case .equipment: return "shippingbox.fill"
        case .calendar: return "calendar"
        case .overhead: return "briefcase.fill"
        case .bidding: return "doc.text.fill"
        case .clients: return "person.2.fill"
        case .assistant: return "bubble.left.and.text.bubble.right.fill"
        case .activity: return "clock.arrow.circlepath"
        case .settings: return "gearshape.fill"
        case .planningPad: return "pencil.and.outline"
        }
    }
}

@MainActor
class NavigationState: ObservableObject {
    @Published var selectedSection: SidebarItem? = .today
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
