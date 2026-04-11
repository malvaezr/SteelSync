import Foundation

/// Builds a text snapshot of DataStore for the LLM system prompt.
/// Read-only — never modifies DataStore. Output is never written to disk.
@MainActor
struct DataContextBuilder {

    static let systemPromptPrefix = """
    You are SteelSync Assistant, a project management AI for J&R Steel & Welding LLC, \
    a steel erection company based in Texas. You ONLY answer questions about the company's \
    projects, bids, costs, payroll, RFIs, change orders, equipment, and scheduling using \
    the data provided below. Do not make up numbers — use only the data given. If you don't \
    have the data to answer, say so. Be concise and professional. Format currency as USD.
    """

    /// Builds the full system prompt with injected data context
    static func buildSystemPrompt(from dataStore: DataStore) -> String {
        var context = systemPromptPrefix + "\n\nCURRENT DATA:\n\n"
        context += financialSummary(dataStore)
        context += projectsList(dataStore)
        context += bidsList(dataStore)
        context += timesheetSummary(dataStore)
        context += tasksSummary(dataStore)
        context += rfiSummary(dataStore)
        context += employeesSummary(dataStore)
        context += equipmentSummary(dataStore)
        return context
    }

    // MARK: - Section Builders

    private static func financialSummary(_ ds: DataStore) -> String {
        let s = ds.financialSummary
        return """
        FINANCIAL SUMMARY:
        Total Revenue: \(ds.totalRevenue.currencyFormatted)
        Total Costs: \(ds.totalCosts.currencyFormatted)
        Total Profit: \(s.profit.currencyFormatted)
        Margin: \(String(format: "%.1f%%", s.margin))
        Total Contract Value: \(ds.totalContractValue.currencyFormatted)
        Remaining Balance: \(ds.totalRemainingBalance.currencyFormatted)

        """
    }

    private static func projectsList(_ ds: DataStore) -> String {
        let projects = ds.projects
        var text = "PROJECTS (\(projects.count) total, \(ds.activeProjects.count) active):\n"
        for p in projects.prefix(20) {
            let cos = ds.changeOrders(for: p.id)
            text += "- \(p.title): Contract \(p.contractAmount.currencyFormatted) | Revenue \(p.totalRevenue.currencyFormatted) | Costs \(p.totalCosts.currencyFormatted) | Profit \(p.profit.currencyFormatted) | Margin \(String(format: "%.1f%%", p.profitMargin)) | \(p.computedStatus) | COs: \(cos.count) | Location: \(p.location)\n"
        }
        text += "\n"
        return text
    }

    private static func bidsList(_ ds: DataStore) -> String {
        let bids = ds.bids
        guard !bids.isEmpty else { return "BIDS: None\n\n" }
        var text = "BIDS (\(bids.count) total, \(ds.pendingBids.count) pending, win rate \(String(format: "%.0f%%", ds.bidWinRate))):\n"
        for b in bids.prefix(15) {
            text += "- \(b.projectName): \(b.bidAmount.currencyFormatted) | Due \(b.bidDueDate.shortDate) | \(b.status.rawValue) | Client: \(b.clientName)\n"
        }
        text += "\n"
        return text
    }

    private static func timesheetSummary(_ ds: DataStore) -> String {
        let weekStart = TimesheetEntry.currentWeekStart()
        let thisWeek = ds.timesheetEntries(for: weekStart)
        let totals = ds.timesheetWeekTotals(for: weekStart)

        var text = "TIMESHEET THIS WEEK:\n"
        text += "Entries: \(thisWeek.count) | Hours: \(totals.hours.formatted()) | Pay: \(totals.pay.currencyFormatted) | Per Diem: \(totals.perDiem.currencyFormatted)\n"
        if !thisWeek.isEmpty {
            // Group by worker
            var byWorker: [String: Decimal] = [:]
            for e in thisWeek { byWorker[e.employeeName, default: 0] += e.totalHours }
            let ranked = byWorker.sorted { $0.value > $1.value }.prefix(10)
            for (name, hours) in ranked {
                text += "  \(name): \(hours.formatted()) hrs\n"
            }
        }
        text += "\n"
        return text
    }

    private static func tasksSummary(_ ds: DataStore) -> String {
        let active = ds.activeTodos
        let overdue = ds.overdueTodos
        var text = "TASKS: \(active.count) active, \(overdue.count) overdue, \(ds.completedTodos.count) completed\n"
        if !overdue.isEmpty {
            text += "Overdue:\n"
            for t in overdue.prefix(5) {
                text += "  - \(t.title) (due \(t.dueDate?.shortDate ?? "no date"))\n"
            }
        }
        text += "\n"
        return text
    }

    private static func rfiSummary(_ ds: DataStore) -> String {
        var totalRFIs = 0
        var overdueRFIs = 0
        var openRFIs = 0
        for project in ds.projects {
            let rfis = ds.rfis(for: project.id)
            totalRFIs += rfis.count
            overdueRFIs += rfis.filter { $0.isOverdue }.count
            openRFIs += rfis.filter { $0.status != .closed }.count
        }
        return "RFIs: \(totalRFIs) total, \(openRFIs) open, \(overdueRFIs) overdue\n\n"
    }

    private static func employeesSummary(_ ds: DataStore) -> String {
        let emps = ds.employees
        let active = ds.activeEmployees
        let contractors = active.filter { $0.employeeType == .contractor }
        let foremen = ds.foremen
        return "EMPLOYEES: \(emps.count) total, \(active.count) active (\(foremen.count) foremen, \(contractors.count) contractors)\n\n"
    }

    private static func equipmentSummary(_ ds: DataStore) -> String {
        let count = ds.allActiveRentalCount
        return "ACTIVE EQUIPMENT RENTALS: \(count)\n\n"
    }
}
