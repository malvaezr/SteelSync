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

    /// Project recordNames the user has pinned. Persisted in UserDefaults so
    /// the order survives app launches. Surface order = pin order so the
    /// user can drag to reorder later if we add that.
    @Published var pinnedProjectIDs: [String] {
        didSet {
            UserDefaults.standard.set(pinnedProjectIDs, forKey: Self.pinnedKey)
        }
    }

    /// Set this from anywhere to request navigation to a specific project.
    /// `DashboardView` watches it, picks the project as its selection, and
    /// clears the value so it doesn't fire repeatedly.
    @Published var requestedProjectID: String?

    /// Drives the Global Search (⌘K) sheet's presentation state. Toggled
    /// from the macOS menu bar / keyboard shortcut.
    @Published var showGlobalSearch: Bool = false

    private static let pinnedKey = "SteelSync.pinnedProjectIDs"

    init() {
        self.pinnedProjectIDs = UserDefaults.standard.stringArray(forKey: Self.pinnedKey) ?? []
    }

    /// Idempotent toggle. Adds at the end (most recently pinned) when
    /// pinning, removes when unpinning.
    func togglePin(projectID: String) {
        if let idx = pinnedProjectIDs.firstIndex(of: projectID) {
            pinnedProjectIDs.remove(at: idx)
        } else {
            pinnedProjectIDs.append(projectID)
        }
    }

    func isPinned(projectID: String) -> Bool {
        pinnedProjectIDs.contains(projectID)
    }

    /// Convenience: switch the sidebar to the Projects section and request
    /// the given project be selected as the detail.
    func navigate(toProjectID id: String) {
        selectedSection = .dashboard
        requestedProjectID = id
    }
}

// Wrapper to make CKRecord.ID work with SwiftUI selection
import CloudKit
struct CKRecordIDWrapper: Hashable, Identifiable {
    let recordID: CKRecord.ID
    var id: CKRecord.ID { recordID }
}
