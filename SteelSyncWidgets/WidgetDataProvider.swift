import Foundation

// MARK: - Shared Data Models

/// Lightweight summary data written by the main app and read by widgets.
/// The main app should write this to the shared UserDefaults suite on every `persistData()` call.
struct WidgetData: Codable {
    var activeProjects: Int
    var totalRevenue: Double
    var totalProfit: Double
    var topProjects: [WidgetProjectItem]
    var activeTodos: Int
    var overdueTodos: Int
    var completedTodos: Int
    var dueTodayTodos: Int
    var recentTodos: [WidgetTodoItem]
    var pipelineValue: Double
    var pendingBids: Int
    var nextBidDue: Date?
    var nextBidName: String?
    var upcomingBids: [WidgetBidItem]

    static let empty = WidgetData(
        activeProjects: 0, totalRevenue: 0, totalProfit: 0, topProjects: [],
        activeTodos: 0, overdueTodos: 0, completedTodos: 0, dueTodayTodos: 0, recentTodos: [],
        pipelineValue: 0, pendingBids: 0, nextBidDue: nil, nextBidName: nil, upcomingBids: []
    )

    /// Placeholder data shown during widget preview and snapshot
    static let placeholder = WidgetData(
        activeProjects: 4,
        totalRevenue: 875_000,
        totalProfit: 218_750,
        topProjects: [
            WidgetProjectItem(name: "Metro Tower Steel", amount: 350_000),
            WidgetProjectItem(name: "Harrison Bridge Rework", amount: 275_000),
            WidgetProjectItem(name: "Westside Warehouse", amount: 250_000)
        ],
        activeTodos: 8,
        overdueTodos: 2,
        completedTodos: 15,
        dueTodayTodos: 3,
        recentTodos: [
            WidgetTodoItem(id: "1", title: "Submit Metro Tower bid", isCompleted: false, isOverdue: false, priority: 3),
            WidgetTodoItem(id: "2", title: "Follow up with Acme", isCompleted: false, isOverdue: true, priority: 2),
            WidgetTodoItem(id: "3", title: "Order steel beams", isCompleted: false, isOverdue: false, priority: 1)
        ],
        pipelineValue: 1_250_000,
        pendingBids: 6,
        nextBidDue: Date().addingTimeInterval(86400 * 3),
        nextBidName: "Downtown Office Tower",
        upcomingBids: [
            WidgetBidItem(id: "1", name: "Downtown Office Tower", client: "Acme Developers", amount: 250_000, dueDate: Date().addingTimeInterval(86400 * 3)),
            WidgetBidItem(id: "2", name: "Riverside Complex", client: "Smith Construction", amount: 480_000, dueDate: Date().addingTimeInterval(86400 * 7)),
            WidgetBidItem(id: "3", name: "Airport Hangar", client: "Metro Aviation", amount: 520_000, dueDate: Date().addingTimeInterval(86400 * 14))
        ]
    )
}

struct WidgetProjectItem: Codable, Identifiable {
    var id: String { name }
    var name: String
    var amount: Double
}

struct WidgetTodoItem: Codable, Identifiable {
    var id: String
    var title: String
    var isCompleted: Bool
    var isOverdue: Bool
    var priority: Int
}

struct WidgetBidItem: Codable, Identifiable {
    var id: String
    var name: String
    var client: String
    var amount: Double
    var dueDate: Date
}

// MARK: - Widget Data Provider

/// Reads widget data from the shared UserDefaults suite.
/// The main app must write WidgetData JSON to this suite for widgets to display real data.
struct WidgetDataStore {

    /// App Group suite name for shared data between the main app and widgets.
    /// TODO: Add "group.com.jrfv.SteelSync.shared" App Group to both the main app and widget extension
    /// capabilities in Xcode, then enable App Groups entitlement.
    static let suiteName = "group.com.jrfv.SteelSync.shared"
    static let widgetDataKey = "steelsync_widget_data"

    /// Loads the current widget data from shared UserDefaults written by the main app.
    static func load() -> WidgetData {
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return .placeholder
        }

        // Check if data was ever written
        guard defaults.double(forKey: "updatedAt") > 0 else {
            return .placeholder
        }

        let topNames = defaults.stringArray(forKey: "topProjectNames") ?? []
        let topAmounts = defaults.array(forKey: "topProjectAmounts") as? [Double] ?? []
        let topProjects = zip(topNames, topAmounts).map { WidgetProjectItem(name: $0, amount: $1) }

        let todoTitles = defaults.stringArray(forKey: "recentTodoTitles") ?? []
        let todoPriorities = defaults.array(forKey: "recentTodoPriorities") as? [Int] ?? []
        let todoOverdue = defaults.array(forKey: "recentTodoOverdue") as? [Bool] ?? []
        let recentTodos = todoTitles.enumerated().map { i, title in
            WidgetTodoItem(
                id: "\(i)", title: title, isCompleted: false,
                isOverdue: i < todoOverdue.count ? todoOverdue[i] : false,
                priority: i < todoPriorities.count ? todoPriorities[i] : 0
            )
        }

        var nextBidDue: Date? = nil
        let nextBidTimestamp = defaults.double(forKey: "nextBidDue")
        if nextBidTimestamp > 0 { nextBidDue = Date(timeIntervalSince1970: nextBidTimestamp) }

        return WidgetData(
            activeProjects: defaults.integer(forKey: "activeProjects"),
            totalRevenue: defaults.double(forKey: "totalRevenue"),
            totalProfit: defaults.double(forKey: "totalProfit"),
            topProjects: topProjects,
            activeTodos: defaults.integer(forKey: "activeTodos"),
            overdueTodos: defaults.integer(forKey: "overdueTodos"),
            completedTodos: defaults.integer(forKey: "completedTodos"),
            dueTodayTodos: defaults.integer(forKey: "dueTodayTodos"),
            recentTodos: recentTodos,
            pipelineValue: defaults.double(forKey: "pipelineValue"),
            pendingBids: defaults.integer(forKey: "pendingBids"),
            nextBidDue: nextBidDue,
            nextBidName: defaults.string(forKey: "nextBidName"),
            upcomingBids: []
        )
    }
}
