import Foundation

/// Represents a parsed user query mapped to a specific data request.
enum QueryIntent {
    // Financial
    case financialSummary
    case totalRevenue
    case totalProfit
    case totalCosts
    case profitMargin
    case projectFinance(name: String)

    // Projects
    case activeProjects
    case completedProjects
    case allProjects
    case projectDetails(name: String)
    case projectCount

    // Bidding
    case pendingBids
    case submittedBids
    case awardedBids
    case bidWinRate
    case bidPipeline
    case bidDetails(name: String)

    // Clients
    case clientList
    case clientCount
    case topClients

    // Workforce
    case employeeCount
    case activeEmployees
    case foremen

    // Tasks
    case overdueTodos
    case todayTodos
    case activeTodos
    case todoCount

    // Equipment
    case activeRentals

    // Schedule
    case todayEvents
    case upcomingEvents

    // Change Orders
    case changeOrderSummary
    case projectChangeOrders(name: String)

    // Timesheet / Payroll
    case timesheetThisWeek
    case timesheetForProject(name: String)
    case topWorkersByHours
    case totalPayrollThisPeriod(period: TimePeriod)

    // Time-scoped financial
    case revenueForPeriod(period: TimePeriod)
    case costsForPeriod(period: TimePeriod)
    case profitForPeriod(period: TimePeriod)

    // Comparison
    case compareProjects(nameA: String, nameB: String)

    // Action / attention
    case needsAttention
    case overdueRFIs
    case projectHealth(name: String)

    // Detailed analysis
    case costBreakdown(name: String)
    case marginTrend

    // Follow-up (uses last context)
    case followUp(query: String)

    // Help / unknown
    case help
    case greeting
    case unknown(query: String)
}

/// Time period for scoped queries
enum TimePeriod {
    case thisWeek
    case lastWeek
    case thisMonth
    case lastMonth
    case thisQuarter
    case thisYear

    var dateRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .thisWeek:
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (start, now)
        case .lastWeek:
            let thisWeekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let start = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) ?? now
            return (start, thisWeekStart)
        case .thisMonth:
            let start = cal.dateInterval(of: .month, for: now)?.start ?? now
            return (start, now)
        case .lastMonth:
            let thisMonthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
            let start = cal.date(byAdding: .month, value: -1, to: thisMonthStart) ?? now
            return (start, thisMonthStart)
        case .thisQuarter:
            let month = cal.component(.month, from: now)
            let qStart = ((month - 1) / 3) * 3 + 1
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: qStart, day: 1)) ?? now
            return (start, now)
        case .thisYear:
            let start = cal.date(from: DateComponents(year: cal.component(.year, from: now), month: 1, day: 1)) ?? now
            return (start, now)
        }
    }

    var label: String {
        switch self {
        case .thisWeek: return "this week"
        case .lastWeek: return "last week"
        case .thisMonth: return "this month"
        case .lastMonth: return "last month"
        case .thisQuarter: return "this quarter"
        case .thisYear: return "this year"
        }
    }
}
