import Foundation

/// Formats query results from DataStore into readable text responses.
@MainActor
struct ResponseFormatter {

    /// Escapes Markdown special characters in data values to prevent injection.
    private func esc(_ text: String) -> String {
        var s = text
        for char in ["\\", "`", "*", "_", "~", "[", "]", "(", ")", "#", "+", "-", ".", "!"] {
            s = s.replacingOccurrences(of: char, with: "\\" + char)
        }
        return s
    }

    func format(_ intent: QueryIntent, dataStore: DataStore) -> String {
        switch intent {

        // MARK: - Financial

        case .financialSummary:
            let s = dataStore.financialSummary
            let activeCount = dataStore.activeProjects.count
            let bidCount = dataStore.pendingBids.count
            return """
            Here's your business overview:

            **Active Projects:** \(activeCount)
            **Open Bids:** \(bidCount)

            **Revenue:** \(s.revenue.currencyFormatted)
            **Costs:** \(s.costs.currencyFormatted)
            **Profit:** \(s.profit.currencyFormatted)
            **Margin:** \(String(format: "%.1f%%", s.margin))

            **Contract Value:** \(dataStore.totalContractValue.currencyFormatted)
            **Remaining Balance:** \(dataStore.totalRemainingBalance.currencyFormatted)
            """

        case .totalRevenue:
            return "Total revenue across all projects: **\(dataStore.totalRevenue.currencyFormatted)**"

        case .totalProfit:
            let s = dataStore.financialSummary
            return "Total profit: **\(s.profit.currencyFormatted)** (\(String(format: "%.1f%%", s.margin)) margin)"

        case .totalCosts:
            return "Total costs across all projects: **\(dataStore.totalCosts.currencyFormatted)**"

        case .profitMargin:
            let s = dataStore.financialSummary
            return "Overall profit margin: **\(String(format: "%.1f%%", s.margin))** (\(s.profit.currencyFormatted) profit on \(s.revenue.currencyFormatted) revenue)"

        case .projectFinance(let name):
            guard let project = findProject(name, in: dataStore) else {
                return "I couldn't find a project matching \"\(esc(name))\". Try \"list projects\" to see all projects."
            }
            let cos = dataStore.changeOrders(for: project.id)
            let coTotal = cos.reduce(Decimal.zero) { $0 + $1.amount }
            return """
            **\(esc(project.title))** — Financial Summary:

            **Contract:** \(project.contractAmount.currencyFormatted)
            **Change Orders:** \(cos.count) totaling \(coTotal.currencyFormatted)
            **Revenue:** \(project.totalRevenue.currencyFormatted)
            **Costs:** \(project.totalCosts.currencyFormatted)
            **Profit:** \(project.profit.currencyFormatted)
            **Remaining Balance:** \(project.remainingBalance.currencyFormatted)
            **Status:** \(project.computedStatus)
            """

        // MARK: - Projects

        case .activeProjects:
            let active = dataStore.activeProjects
            if active.isEmpty { return "No active projects right now." }
            let list = active.map { "• \(projectSummaryLine($0))" }.joined(separator: "\n")
            return "**\(active.count) Active Project\(active.count == 1 ? "" : "s"):**\n\n\(list)"

        case .completedProjects:
            let completed = dataStore.completedProjects
            if completed.isEmpty { return "No completed projects." }
            let list = completed.map { "• \(projectSummaryLine($0))" }.joined(separator: "\n")
            return "**\(completed.count) Completed Project\(completed.count == 1 ? "" : "s"):**\n\n\(list)"

        case .allProjects:
            let all = dataStore.projects
            if all.isEmpty { return "No projects found." }
            let list = all.map { "• \(projectSummaryLine($0))" }.joined(separator: "\n")
            return "**\(all.count) Total Project\(all.count == 1 ? "" : "s"):**\n\n\(list)"

        case .projectDetails(let name):
            guard let project = findProject(name, in: dataStore) else {
                return "I couldn't find a project matching \"\(esc(name))\"."
            }
            let cos = dataStore.changeOrders(for: project.id)
            let clientName = dataStore.client(for: project.gcClientRef)?.name
                ?? dataStore.client(for: project.subClientRef)?.name
                ?? "—"
            return """
            **\(esc(project.title))**
            **Client:** \(esc(clientName))
            **Location:** \(esc(project.location))
            **Status:** \(project.computedStatus)
            **Contract:** \(project.contractAmount.currencyFormatted)
            **Change Orders:** \(cos.count)
            **Revenue:** \(project.totalRevenue.currencyFormatted)
            **Profit:** \(project.profit.currencyFormatted)
            **Start:** \(project.startDate?.shortDate ?? "Not set")
            """

        case .projectCount:
            let total = dataStore.projects.count
            let active = dataStore.activeProjects.count
            let completed = dataStore.completedProjects.count
            return "You have **\(total)** total projects: \(active) active, \(completed) completed."

        // MARK: - Bidding

        case .pendingBids:
            let bids = dataStore.pendingBids
            if bids.isEmpty { return "No pending bids." }
            let list = bids.map { "• **\(esc($0.projectName))** — \($0.bidAmount.currencyFormatted) (due \($0.bidDueDate.shortDate))" }.joined(separator: "\n")
            return "**\(bids.count) Pending Bid\(bids.count == 1 ? "" : "s"):**\n\n\(list)"

        case .submittedBids:
            let bids = dataStore.submittedBids
            if bids.isEmpty { return "No submitted bids." }
            let list = bids.map { "• **\(esc($0.projectName))** — \($0.bidAmount.currencyFormatted)" }.joined(separator: "\n")
            return "**\(bids.count) Submitted Bid\(bids.count == 1 ? "" : "s"):**\n\n\(list)"

        case .awardedBids:
            let bids = dataStore.awardedBids
            if bids.isEmpty { return "No awarded bids yet." }
            let list = bids.map { "• **\(esc($0.projectName))** — \($0.bidAmount.currencyFormatted)" }.joined(separator: "\n")
            return "**\(bids.count) Awarded Bid\(bids.count == 1 ? "" : "s"):**\n\n\(list)"

        case .bidWinRate:
            let rate = dataStore.bidWinRate
            let total = dataStore.bids.count
            let won = dataStore.awardedBids.count
            return "Bid win rate: **\(String(format: "%.0f%%", rate))** (\(won) won out of \(total) total bids)"

        case .bidPipeline:
            let pipeline = dataStore.totalBidPipeline
            let pending = dataStore.pendingBids.count
            let submitted = dataStore.submittedBids.count
            return """
            **Bid Pipeline:** \(pipeline.currencyFormatted)
            • Pending: \(pending)
            • Submitted: \(submitted)
            • Win Rate: \(String(format: "%.0f%%", dataStore.bidWinRate))
            """

        case .bidDetails(let name):
            guard let bid = findBid(name, in: dataStore) else {
                return "I couldn't find a bid matching \"\(esc(name))\"."
            }
            return """
            **\(esc(bid.projectName))**
            **Client:** \(esc(bid.clientName))
            **Amount:** \(bid.bidAmount.currencyFormatted)
            **Due:** \(bid.bidDueDate.shortDate)
            **Status:** \(bid.status.rawValue.capitalized)
            **Location:** \(esc(bid.address))
            """

        // MARK: - Clients

        case .clientList:
            let clients = dataStore.clients
            if clients.isEmpty { return "No clients on record." }
            let list = clients.map { "• **\(esc($0.name))** (\($0.preferredRateType.rawValue))" }.joined(separator: "\n")
            return "**\(clients.count) Client\(clients.count == 1 ? "" : "s"):**\n\n\(list)"

        case .clientCount:
            return "You have **\(dataStore.clients.count)** clients on record."

        case .topClients:
            let clients = dataStore.clients
            if clients.isEmpty { return "No clients on record." }
            let ranked = clients.map { client -> (String, Int) in
                let projectCount = dataStore.projects.filter { p in
                    dataStore.client(for: p.gcClientRef)?.id == client.id
                    || dataStore.client(for: p.subClientRef)?.id == client.id
                }.count
                return (client.name, projectCount)
            }.sorted { $0.1 > $1.1 }.prefix(5)
            let list = ranked.map { "• **\($0.0)** — \($0.1) project\($0.1 == 1 ? "" : "s")" }.joined(separator: "\n")
            return "**Top Clients (by projects):**\n\n\(list)"

        // MARK: - Workforce

        case .employeeCount:
            let total = dataStore.employees.count
            let active = dataStore.activeEmployees.count
            return "You have **\(total)** employees (\(active) active)."

        case .activeEmployees:
            let emps = dataStore.activeEmployees
            if emps.isEmpty { return "No active employees." }
            let list = emps.map { "• **\(esc($0.fullName))** — \($0.employeeType.rawValue)" }.joined(separator: "\n")
            return "**\(emps.count) Active Employee\(emps.count == 1 ? "" : "s"):**\n\n\(list)"

        case .foremen:
            let fmen = dataStore.foremen
            if fmen.isEmpty { return "No active foremen." }
            let list = fmen.map { "• **\(esc($0.fullName))**" }.joined(separator: "\n")
            return "**\(fmen.count) Foreman/Foremen:**\n\n\(list)"

        // MARK: - Tasks

        case .overdueTodos:
            let overdue = dataStore.overdueTodos
            if overdue.isEmpty { return "No overdue tasks — you're all caught up!" }
            let list = overdue.map { "• \(esc($0.title))\(formatDueDate($0.dueDate))" }.joined(separator: "\n")
            return "**\(overdue.count) Overdue Task\(overdue.count == 1 ? "" : "s"):**\n\n\(list)"

        case .todayTodos:
            let today = dataStore.activeTodos.filter { $0.isDueToday }
            if today.isEmpty { return "Nothing due today." }
            let list = today.map { "• \(esc($0.title)) [\($0.priority.rawValue)]" }.joined(separator: "\n")
            return "**\(today.count) Task\(today.count == 1 ? "" : "s") Due Today:**\n\n\(list)"

        case .activeTodos:
            let active = dataStore.activeTodos
            if active.isEmpty { return "No active tasks." }
            let list = active.prefix(10).map { "• \(esc($0.title))\(formatDueDate($0.dueDate)) [\($0.priority.rawValue)]" }.joined(separator: "\n")
            let more = active.count > 10 ? "\n\n...and \(active.count - 10) more" : ""
            return "**\(active.count) Active Task\(active.count == 1 ? "" : "s"):**\n\n\(list)\(more)"

        case .todoCount:
            let active = dataStore.activeTodos.count
            let completed = dataStore.completedTodos.count
            let overdue = dataStore.overdueTodos.count
            return "Tasks: **\(active)** active, **\(overdue)** overdue, **\(completed)** completed."

        // MARK: - Equipment

        case .activeRentals:
            let count = dataStore.allActiveRentalCount
            if count == 0 { return "No active equipment rentals." }
            // Gather all active rentals across projects
            var allRentals: [(String, EquipmentRental)] = []
            for project in dataStore.projects {
                let rentals = dataStore.equipmentRentals[project.id] ?? []
                for r in rentals where r.isActive {
                    allRentals.append((esc(project.title), r))
                }
            }
            let list = allRentals.map { "• **\(esc($0.1.equipmentName))** on \($0.0)" }.joined(separator: "\n")
            return "**\(count) Active Rental\(count == 1 ? "" : "s"):**\n\n\(list)"

        // MARK: - Schedule

        case .todayEvents:
            let events = dataStore.todayEvents
            if events.isEmpty { return "No events scheduled for today." }
            let list = events.map { "• **\(esc($0.title))** — \($0.type.rawValue)" }.joined(separator: "\n")
            return "**Today's Events (\(events.count)):**\n\n\(list)"

        case .upcomingEvents:
            let events = dataStore.upcomingEvents.prefix(10)
            if events.isEmpty { return "No upcoming events." }
            let list = events.map { "• **\(esc($0.title))** — \($0.startDate.shortDate) (\($0.type.rawValue))" }.joined(separator: "\n")
            return "**Upcoming Events:**\n\n\(list)"

        // MARK: - Change Orders

        case .changeOrderSummary:
            var totalCOs = 0
            var totalAmount: Decimal = 0
            for project in dataStore.projects {
                let cos = dataStore.changeOrders(for: project.id)
                totalCOs += cos.count
                totalAmount += cos.reduce(Decimal.zero) { $0 + $1.amount }
            }
            if totalCOs == 0 { return "No change orders across any projects." }
            return "**\(totalCOs) Total Change Orders** across all projects, totaling \(totalAmount.currencyFormatted)."

        case .projectChangeOrders(let name):
            guard let project = findProject(name, in: dataStore) else {
                return "I couldn't find a project matching \"\(esc(name))\"."
            }
            let cos = dataStore.changeOrders(for: project.id)
            if cos.isEmpty { return "No change orders on **\(esc(project.title))**." }
            let list = cos.map { co in
                let desc = co.description.isEmpty ? "No description" : esc(co.description)
                return "• CO #\(co.number): \(desc) — \(co.amount.currencyFormatted) (\(co.isSigned ? "Signed" : "Pending"))"
            }.joined(separator: "\n")
            return "**\(cos.count) Change Order\(cos.count == 1 ? "" : "s") on \(esc(project.title)):**\n\n\(list)"

        // MARK: - Help / Greeting / Unknown

        case .greeting:
            let hour = Calendar.current.component(.hour, from: Date())
            let timeGreeting = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
            let overdue = dataStore.overdueTodos.count
            let active = dataStore.activeProjects.count
            var msg = "\(timeGreeting)! You have \(active) active project\(active == 1 ? "" : "s")"
            if overdue > 0 { msg += " and \(overdue) overdue task\(overdue == 1 ? "" : "s")" }
            msg += ". How can I help?"
            return msg

        case .help:
            return """
            I can answer questions about your SteelSync data. Try asking:

            **Financial:** "How's the business?", "Total profit", "Revenue"
            **Projects:** "Active projects", "Tell me about [project name]"
            **Bids:** "Pending bids", "Win rate", "Bid pipeline"
            **Clients:** "Client list", "Top clients"
            **Workforce:** "Active employees", "Foremen"
            **Tasks:** "Overdue tasks", "What's due today?"
            **Equipment:** "Active rentals"
            **Schedule:** "Today's events", "Upcoming events"
            **Change Orders:** "Change order summary"
            """

        case .unknown(let query):
            return "I'm not sure how to answer \"\(esc(query))\". Type **help** to see what I can answer, or try rephrasing."
        }
    }

    // MARK: - Helpers

    private func findProject(_ name: String, in dataStore: DataStore) -> Project? {
        if let exact = dataStore.projects.first(where: { $0.title.localizedCaseInsensitiveContains(name) }) {
            return exact
        }
        let searchWords = name.lowercased().split(separator: " ").map(String.init)
        return dataStore.projects.first(where: { p in
            let titleLower = p.title.lowercased()
            return searchWords.filter { titleLower.contains($0) }.count >= 2
        })
    }

    private func findBid(_ name: String, in dataStore: DataStore) -> BidProject? {
        if let exact = dataStore.bids.first(where: { esc($0.projectName).localizedCaseInsensitiveContains(name) }) {
            return exact
        }
        let searchWords = name.lowercased().split(separator: " ").map(String.init)
        return dataStore.bids.first(where: { b in
            let bidLower = b.projectName.lowercased()
            return searchWords.filter { bidLower.contains($0) }.count >= 2
        })
    }

    private func projectSummaryLine(_ p: Project) -> String {
        "**\(p.title)** — \(p.contractAmount.currencyFormatted) [\(p.computedStatus)]"
    }

    private func formatDueDate(_ date: Date?) -> String {
        guard let d = date else { return "" }
        return " (due \(d.shortDate))"
    }
}
