import Foundation
import SwiftUI

struct GanttTask: Identifiable, Codable, Hashable {
    var id: UUID
    var projectID: String
    var name: String
    var category: TaskCategory
    var status: TaskStatus
    var startDate: Date

    enum CodingKeys: String, CodingKey {
        case id, projectID, name, category, status, startDate
        case durationDays, assignedTo, notes, sortOrder, progress, includesSaturdays
        case predecessorIDs, isPinned
    }

    var durationDays: Int
    var assignedTo: String
    var notes: String
    var sortOrder: Int
    var progress: Double
    var includesSaturdays: Bool
    /// IDs of tasks that must finish before this one can start (for dependency lines + critical path).
    var predecessorIDs: [UUID]
    /// When true, the bar cannot be dragged or resized. Toggle from the bar context menu or edit sheet.
    var isPinned: Bool

    init(
        id: UUID = UUID(), projectID: String, name: String,
        category: TaskCategory = .other, status: TaskStatus = .notStarted,
        startDate: Date = Date(), durationDays: Int = 5,
        assignedTo: String = "", notes: String = "",
        sortOrder: Int = 0, progress: Double = 0,
        includesSaturdays: Bool = false,
        predecessorIDs: [UUID] = [],
        isPinned: Bool = false
    ) {
        self.id = id; self.projectID = projectID; self.name = name
        self.category = category; self.status = status
        self.startDate = startDate; self.durationDays = durationDays
        self.assignedTo = assignedTo; self.notes = notes
        self.sortOrder = sortOrder; self.progress = progress
        self.includesSaturdays = includesSaturdays
        self.predecessorIDs = predecessorIDs
        self.isPinned = isPinned
    }

    /// Custom decoder so older persisted tasks (before predecessorIDs / isPinned existed)
    /// still deserialize cleanly with safe defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.projectID = try c.decode(String.self, forKey: .projectID)
        self.name = try c.decode(String.self, forKey: .name)
        self.category = try c.decode(TaskCategory.self, forKey: .category)
        self.status = try c.decode(TaskStatus.self, forKey: .status)
        self.startDate = try c.decode(Date.self, forKey: .startDate)
        self.durationDays = try c.decode(Int.self, forKey: .durationDays)
        self.assignedTo = try c.decode(String.self, forKey: .assignedTo)
        self.notes = try c.decode(String.self, forKey: .notes)
        self.sortOrder = try c.decode(Int.self, forKey: .sortOrder)
        self.progress = try c.decode(Double.self, forKey: .progress)
        self.includesSaturdays = try c.decode(Bool.self, forKey: .includesSaturdays)
        self.predecessorIDs = try c.decodeIfPresent([UUID].self, forKey: .predecessorIDs) ?? []
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    /// Returns true if this task is overdue — end date has passed and it's not completed.
    var isOverdue: Bool {
        endDate < Date() && status != .completed && status != .milestone
    }

    /// Milestones reduce to a single-day diamond regardless of durationDays.
    var isMilestone: Bool { status == .milestone }

    var endDate: Date {
        startDate.addingWorkdays(durationDays, includeSaturdays: includesSaturdays)
    }

    var calendarSpan: Int {
        max(1, Calendar.current.dateComponents([.day], from: startDate.startOfDay, to: endDate.startOfDay).day ?? 1)
    }

    var barColor: Color { category.color }
    var statusColor: Color { status.color }
}

// MARK: - Task Category
enum TaskCategory: String, Codable, CaseIterable, Identifiable {
    case leadTime = "Lead Time"
    case fabrication = "Fabrication"
    case delivery = "Delivery"
    case erection = "Erection"
    case inspection = "Inspection"
    case rfiSubmittal = "RFI/Submittal"
    case deadline = "Deadline"
    case meetings = "Meetings"
    case payApp = "Pay App"
    case other = "Other"

    var id: String { rawValue }

    /// Per-category color used both on-screen and in the exported PDF. Hex
    /// values are mirrored in `GanttPDFRenderer.categoryColor(_:)` — keep the
    /// two in sync. Palette tuned for distinct hues on print.
    var color: Color {
        switch self {
        case .leadTime: return Color(hex: "#607D8B")      // slate
        case .fabrication: return Color(hex: "#6A1B9A")   // deep purple
        case .delivery: return Color(hex: "#1976D2")      // blue
        case .erection: return Color(hex: "#E65100")      // deep orange
        case .inspection: return Color(hex: "#2E7D32")    // green
        case .rfiSubmittal: return Color(hex: "#00838F")  // cyan
        case .deadline: return Color(hex: "#C62828")      // red
        case .meetings: return Color(hex: "#4527A0")      // indigo
        case .payApp: return Color(hex: "#00695C")        // dark teal
        case .other: return Color(hex: "#5D4037")         // brown
        }
    }

    var icon: String {
        switch self {
        case .leadTime: return "clock.arrow.circlepath"
        case .fabrication: return "hammer.fill"
        case .delivery: return "shippingbox.fill"
        case .erection: return "building.2.fill"
        case .inspection: return "checkmark.seal.fill"
        case .rfiSubmittal: return "doc.text.fill"
        case .deadline: return "flag.fill"
        case .meetings: return "person.2.fill"
        case .payApp: return "dollarsign.circle.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

// MARK: - Task Status
enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case notStarted = "Not Started"
    case inProgress = "In Progress"
    case completed = "Completed"
    case delayed = "Delayed"
    case onHold = "On Hold"
    case milestone = "Milestone"

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .notStarted: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        case .delayed: return .red
        case .onHold: return .orange
        case .milestone: return .purple
        }
    }

    var icon: String {
        switch self {
        case .notStarted: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .completed: return "checkmark.circle.fill"
        case .delayed: return "exclamationmark.triangle.fill"
        case .onHold: return "pause.circle.fill"
        case .milestone: return "diamond.fill"
        }
    }
}

// MARK: - Date Work Day Extensions
extension Date {
    func addingWorkdays(_ days: Int, includeSaturdays: Bool = false) -> Date {
        var result = self
        var added = 0
        while added < days {
            result = Calendar.current.date(byAdding: .day, value: 1, to: result) ?? result
            let weekday = Calendar.current.component(.weekday, from: result)
            let isSunday = weekday == 1
            let isSaturday = weekday == 7
            if isSunday || (isSaturday && !includeSaturdays) { continue }
            added += 1
        }
        return result
    }

    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    var isWeekend: Bool {
        let weekday = Calendar.current.component(.weekday, from: self)
        return weekday == 1 || weekday == 7
    }

    var dayOfMonth: Int {
        Calendar.current.component(.day, from: self)
    }

    var monthAbbrev: String {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: self)
    }

    var monthYear: String {
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"; return f.string(from: self)
    }
}

// MARK: - Sample Gantt Data
extension GanttTask {
    static func sampleTasks(for projectID: String) -> [GanttTask] {
        let today = Date()
        return [
            GanttTask(projectID: projectID, name: "Shop Drawings", category: .rfiSubmittal, status: .completed,
                      startDate: today.adding(days: -30), durationDays: 10, sortOrder: 0, progress: 1.0),
            GanttTask(projectID: projectID, name: "Drawing Review", category: .rfiSubmittal, status: .completed,
                      startDate: today.adding(days: -18), durationDays: 5, sortOrder: 1, progress: 1.0),
            GanttTask(projectID: projectID, name: "Steel Fabrication", category: .fabrication, status: .inProgress,
                      startDate: today.adding(days: -12), durationDays: 20, sortOrder: 2, progress: 0.65),
            GanttTask(projectID: projectID, name: "Anchor Bolt Delivery", category: .delivery, status: .completed,
                      startDate: today.adding(days: -5), durationDays: 3, sortOrder: 3, progress: 1.0),
            GanttTask(projectID: projectID, name: "Steel Delivery", category: .delivery, status: .notStarted,
                      startDate: today.adding(days: 10), durationDays: 3, sortOrder: 4),
            GanttTask(projectID: projectID, name: "Erection Phase 1", category: .erection, status: .notStarted,
                      startDate: today.adding(days: 14), durationDays: 15, sortOrder: 5),
            GanttTask(projectID: projectID, name: "Welding & Connections", category: .erection, status: .notStarted,
                      startDate: today.adding(days: 20), durationDays: 12, sortOrder: 6),
            GanttTask(projectID: projectID, name: "Structural Inspection", category: .inspection, status: .notStarted,
                      startDate: today.adding(days: 35), durationDays: 2, sortOrder: 7),
            GanttTask(projectID: projectID, name: "Erection Phase 2", category: .erection, status: .notStarted,
                      startDate: today.adding(days: 38), durationDays: 10, sortOrder: 8),
            GanttTask(projectID: projectID, name: "Final Inspection", category: .inspection, status: .notStarted,
                      startDate: today.adding(days: 50), durationDays: 2, sortOrder: 9),
            GanttTask(projectID: projectID, name: "Pay App #1", category: .payApp, status: .notStarted,
                      startDate: today.adding(days: 30), durationDays: 1, sortOrder: 10),
            GanttTask(projectID: projectID, name: "Progress Meeting", category: .meetings, status: .notStarted,
                      startDate: today.adding(days: 21), durationDays: 1, sortOrder: 11),
        ]
    }
}
