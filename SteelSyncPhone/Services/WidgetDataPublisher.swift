import Foundation
import WidgetKit

/// Writes SteelSync's current business state to the shared UserDefaults suite
/// that widgets read from. The host app calls `publish(from:)` after any
/// meaningful change so the widget timelines refresh with fresh numbers.
///
/// Keys must match the reads in `WidgetDataStore.load()`. Widgets and this
/// writer share the same keyset via the `WidgetDataKey` enum below to prevent
/// drift.
@MainActor
struct WidgetDataPublisher {
    static let suiteName = "group.com.jrfv.SteelSync.shared"

    /// Pull the values we need out of DataStore and write them to the shared
    /// UserDefaults suite. Non-destructive — DataStore is read-only here.
    static func publish(from store: DataStore) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }

        // Core project / finance metrics
        defaults.set(store.activeProjects.count, forKey: "activeProjects")
        defaults.set(NSDecimalNumber(decimal: store.totalRevenue).doubleValue, forKey: "totalRevenue")
        defaults.set(NSDecimalNumber(decimal: store.totalProfit).doubleValue, forKey: "totalProfit")

        let top = store.projects.prefix(3)
        defaults.set(top.map { $0.title }, forKey: "topProjectNames")
        defaults.set(top.map { NSDecimalNumber(decimal: $0.contractAmount).doubleValue }, forKey: "topProjectAmounts")

        // Todos
        defaults.set(store.activeTodos.count, forKey: "activeTodos")
        defaults.set(store.overdueTodos.count, forKey: "overdueTodos")
        defaults.set(store.completedTodos.count, forKey: "completedTodos")
        let dueToday = store.todos.filter { $0.isDueToday }.count
        defaults.set(dueToday, forKey: "dueTodayTodos")

        let recentTodos = Array(store.activeTodos.prefix(3))
        defaults.set(recentTodos.map { $0.title }, forKey: "recentTodoTitles")
        defaults.set(recentTodos.map { $0.priority.rawValue }, forKey: "recentTodoPriorities")
        defaults.set(recentTodos.map { $0.isOverdue }, forKey: "recentTodoOverdue")

        // Bids
        defaults.set(NSDecimalNumber(decimal: store.totalBidPipeline).doubleValue, forKey: "pipelineValue")
        defaults.set(store.pendingBids.count, forKey: "pendingBids")
        if let nextBid = store.bids.sorted(by: { $0.bidDueDate < $1.bidDueDate }).first {
            defaults.set(nextBid.bidDueDate.timeIntervalSince1970, forKey: "nextBidDue")
            defaults.set(nextBid.projectName, forKey: "nextBidName")
        } else {
            defaults.set(0.0, forKey: "nextBidDue")
            defaults.set("", forKey: "nextBidName")
        }

        // Invoices + aging
        var outstanding: Double = 0
        var overdue: Double = 0
        var agingCurrent: Double = 0
        var aging1to30: Double = 0
        var aging31to60: Double = 0
        var aging61to90: Double = 0
        var agingOver90: Double = 0
        for entry in store.allInvoices {
            let remaining = NSDecimalNumber(decimal: store.balanceRemaining(for: entry.invoice)).doubleValue
            let status = entry.invoice.status
            let isOutstanding = InvoiceStatus.outstandingCases.contains(status) || entry.invoice.isOverdue
            if isOutstanding { outstanding += remaining }
            if entry.invoice.isOverdue { overdue += remaining }
            if status != .paid && status != .draft {
                let days = entry.invoice.daysOverdue
                if days <= 0 { agingCurrent += remaining }
                else if days <= 30 { aging1to30 += remaining }
                else if days <= 60 { aging31to60 += remaining }
                else if days <= 90 { aging61to90 += remaining }
                else { agingOver90 += remaining }
            }
        }
        defaults.set(outstanding, forKey: "outstandingInvoiced")
        defaults.set(overdue, forKey: "overdueInvoiced")
        defaults.set(agingCurrent, forKey: "agingCurrent")
        defaults.set(aging1to30, forKey: "aging1to30")
        defaults.set(aging31to60, forKey: "aging31to60")
        defaults.set(aging61to90, forKey: "aging61to90")
        defaults.set(agingOver90, forKey: "agingOver90")

        // RFIs
        var openRFIs = 0
        var overdueRFIs = 0
        for project in store.projects {
            let rfis = store.rfis(for: project.id)
            openRFIs += rfis.filter { $0.status != .closed }.count
            overdueRFIs += rfis.filter { $0.isOverdue }.count
        }
        defaults.set(openRFIs, forKey: "openRFIs")
        defaults.set(overdueRFIs, forKey: "overdueRFIs")

        // Today attention roll-up
        let attention = store.overdueTodos.count + overdueRFIs
            + store.ganttTasks.filter { $0.endDate < Date() && $0.status != .completed }.count
        defaults.set(attention, forKey: "todayAttentionCount")

        // Timestamp marker so WidgetDataStore knows real data has been written
        defaults.set(Date().timeIntervalSince1970, forKey: "updatedAt")

        // Ask WidgetKit to refresh timelines
        WidgetCenter.shared.reloadAllTimelines()
    }
}
