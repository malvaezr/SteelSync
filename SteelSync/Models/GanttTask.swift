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
    }

    var durationDays: Int
    var assignedTo: String
    var notes: String
    var sortOrder: Int
    var progress: Double
    var includesSaturdays: Bool

    init(
        id: UUID = UUID(), projectID: String, name: String,
        category: TaskCategory = .other, status: TaskStatus = .notStarted,
        startDate: Date = Date(), durationDays: Int = 5,
        assignedTo: String = "", notes: String = "",
        sortOrder: Int = 0, progress: Double = 0,
        includesSaturdays: Bool = false
    ) {
        self.id = id; self.projectID = projectID; self.name = name
        self.category = category; self.status = status
        self.startDate = startDate; self.durationDays = durationDays
        self.assignedTo = assignedTo; self.notes = notes
        self.sortOrder = sortOrder; self.progress = progress
        self.includesSaturdays = includesSaturdays
    }

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

    var color: Color {
        switch self {
        case .leadTime: return Color(hex: "#78909C")
        case .fabrication: return Color(hex: "#5C6BC0")
        case .delivery: return Color(hex: "#26A69A")
        case .erection: return Color(hex: "#FF7043")
        case .inspection: return Color(hex: "#AB47BC")
        case .rfiSubmittal: return Color(hex: "#42A5F5")
        case .deadline: return Color(hex: "#EF5350")
        case .meetings: return Color(hex: "#00897B")
        case .payApp: return Color(hex: "#5E35B1")
        case .other: return Color(hex: "#8D6E63")
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
