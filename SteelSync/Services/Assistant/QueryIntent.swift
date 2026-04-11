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

    // Help / unknown
    case help
    case greeting
    case unknown(query: String)
}
