import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Writes critical PM metrics to the shared App Group UserDefaults for widget consumption.
struct WidgetBridge {
    static let suiteName = "group.com.jrfv.SteelSync.shared"

    @MainActor
    static func updateWidgets(from store: DataStore) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let weekOut = cal.date(byAdding: .day, value: 7, to: today)!

        // MARK: - PM Performance Metrics
        let winRate = store.bidWinRate
        let totalProjects = store.projects.count
        let activeProjects = store.activeProjects.count
        let completedProjects = store.completedProjects.count

        // Average profit margin across active projects
        let margins = store.activeProjects.compactMap { p -> Double? in
            let rev = p.totalRevenue
            guard rev > 0 else { return nil }
            return Double(truncating: (p.profit / rev * 100) as NSDecimalNumber)
        }
        let avgMargin = margins.isEmpty ? 0.0 : margins.reduce(0, +) / Double(margins.count)

        // Projects at risk — active projects past their end date or within 3 days
        let threeDaysOut = cal.date(byAdding: .day, value: 3, to: today)!
        let atRiskProjects = store.activeProjects.filter { p in
            guard let end = p.endDate else { return false }
            return end <= threeDaysOut
        }

        // MARK: - Task Metrics
        let overdueTodos = store.overdueTodos
        let dueTodayTodos = store.todos.filter { !$0.isCompleted && $0.dueDate != nil && $0.dueDate! >= today && $0.dueDate! < tomorrow }
        let activeTodos = store.activeTodos

        // Sort overdue by urgency (oldest due date first)
        let sortedOverdue = overdueTodos.sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
        // Sort due today + active by priority (highest first)
        let sortedDueToday = dueTodayTodos.sorted { $0.priority.rawValue > $1.priority.rawValue }
        let urgentTasks = (sortedOverdue + sortedDueToday).prefix(5)

        // MARK: - Bid Metrics
        let allPending = store.bids.filter { !$0.isSubmitted && !$0.isLost && $0.awardedProjectID == nil }
        let bidsDueThisWeek = allPending.filter { $0.bidDueDate >= today && $0.bidDueDate <= weekOut }
            .sorted { $0.bidDueDate < $1.bidDueDate }
        let submittedBids = store.submittedBids
        let totalDecided = store.bids.filter { $0.isAwarded || $0.isLost }.count

        // MARK: - Write to shared defaults
        let data: [String: Any] = [
            // Performance
            "winRate": winRate,
            "avgMargin": avgMargin,
            "activeProjects": activeProjects,
            "completedProjects": completedProjects,
            "totalProjects": totalProjects,
            "atRiskCount": atRiskProjects.count,
            "atRiskNames": atRiskProjects.prefix(3).map { $0.title },

            // Tasks
            "overdueCount": overdueTodos.count,
            "dueTodayCount": dueTodayTodos.count,
            "activeTaskCount": activeTodos.count,
            "completedTaskCount": store.completedTodos.count,
            "urgentTaskTitles": urgentTasks.map { $0.title },
            "urgentTaskOverdue": urgentTasks.map { $0.isOverdue },
            "urgentTaskPriorities": urgentTasks.map { $0.priority.rawValue },
            "urgentTaskDueDates": urgentTasks.compactMap { $0.dueDate?.timeIntervalSince1970 },

            // Bids
            "bidsDueThisWeekCount": bidsDueThisWeek.count,
            "pendingBidCount": allPending.count,
            "submittedBidCount": submittedBids.count,
            "totalDecidedBids": totalDecided,
            "pipelineValue": NSDecimalNumber(decimal: store.totalBidPipeline).doubleValue,
            "bidsDueNames": bidsDueThisWeek.prefix(4).map { $0.projectName },
            "bidsDueClients": bidsDueThisWeek.prefix(4).map { $0.clientName },
            "bidsDueAmounts": bidsDueThisWeek.prefix(4).map { NSDecimalNumber(decimal: $0.bidAmount).doubleValue },
            "bidsDueDates": bidsDueThisWeek.prefix(4).map { $0.bidDueDate.timeIntervalSince1970 },

            "updatedAt": Date().timeIntervalSince1970
        ]

        for (key, value) in data { defaults.set(value, forKey: key) }

        // MARK: - Gantt Tasks (separate writes to avoid dict size issues)
        let ganttTasks = store.ganttTasks
            .sorted { $0.startDate < $1.startDate }
            .prefix(12)
        defaults.set(ganttTasks.map { $0.name }, forKey: "ganttTaskNames")
        defaults.set(ganttTasks.map { $0.projectID }, forKey: "ganttTaskProjectIDs")
        defaults.set(ganttTasks.map { $0.startDate.timeIntervalSince1970 }, forKey: "ganttTaskStarts")
        defaults.set(ganttTasks.map { $0.endDate.timeIntervalSince1970 }, forKey: "ganttTaskEnds")
        defaults.set(ganttTasks.map { $0.status.rawValue }, forKey: "ganttTaskStatuses")
        defaults.set(ganttTasks.map { $0.progress }, forKey: "ganttTaskProgress")
        // Map project IDs to names for display
        let projectIDToName = Dictionary(uniqueKeysWithValues: store.projects.map { ($0.id.recordName, $0.title) })
        let projectIDs = Array(Set(ganttTasks.map { $0.projectID }))
        defaults.set(projectIDs, forKey: "ganttProjectIDs")
        defaults.set(projectIDs.map { projectIDToName[$0] ?? "Unknown" }, forKey: "ganttProjectNames")

        // Foreman bonus pool snapshot (year-to-date, revenue basis, 2 %
        // multiplier) — drives the ForemanBonusWidget. Multiplier tweaks live
        // in Reports → Bonuses for what-if analysis; the widget shows the
        // default snapshot.
        let bonusPool = NSDecimalNumber(decimal: store.bonusPoolYTD()).doubleValue
        defaults.set(bonusPool, forKey: "bonusPoolYTD")
        defaults.set(store.employees.filter { $0.isForeman }.count, forKey: "foremenCount")

        // Top 3 active equipment rentals (sorted longest-on-rent first) —
        // drives the EquipmentRentalWidget. Active = `endDate == nil`.
        var rentalEntries: [(name: String, days: Int, projectName: String)] = []
        for (projectID, rentals) in store.equipmentRentals {
            let projectName = store.projects.first(where: { $0.id == projectID })?.title ?? "Unknown"
            for r in rentals where r.endDate == nil {
                let days = cal.dateComponents([.day], from: r.startDate, to: Date()).day ?? 0
                rentalEntries.append((r.equipmentName, days, projectName))
            }
        }
        rentalEntries.sort { $0.days > $1.days }
        let topRentals = Array(rentalEntries.prefix(3))
        defaults.set(topRentals.map(\.name), forKey: "rentalNames")
        defaults.set(topRentals.map(\.days), forKey: "rentalDays")
        defaults.set(topRentals.map(\.projectName), forKey: "rentalProjectNames")
        defaults.set(rentalEntries.count, forKey: "activeRentalsCount")

        // Next milestone — drives NextMilestoneWidget. Earliest future
        // GanttTask with status == .milestone (any project).
        let nowDate = Date()
        let futureMilestones: [GanttTask] = store.ganttTasks.filter { task in
            task.status == .milestone && task.startDate > nowDate
        }
        let sortedMilestones = futureMilestones.sorted { $0.startDate < $1.startDate }
        if let milestone = sortedMilestones.first {
            let projectName = store.projects.first(where: { $0.id.recordName == milestone.projectID })?.title ?? ""
            defaults.set(milestone.name, forKey: "nextMilestoneTitle")
            defaults.set(milestone.startDate.timeIntervalSince1970, forKey: "nextMilestoneDate")
            defaults.set(projectName, forKey: "nextMilestoneProject")
        } else {
            defaults.set("", forKey: "nextMilestoneTitle")
            defaults.set(0.0, forKey: "nextMilestoneDate")
            defaults.set("", forKey: "nextMilestoneProject")
        }

        // Crew clocked-in snapshot — same shared writer the phone uses, so the
        // keys match. On Mac/iPad the session is nil, so this writes empties.
        ClockInWidgetData.write(to: defaults, session: store.activeClockInSession, employees: store.employees)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
