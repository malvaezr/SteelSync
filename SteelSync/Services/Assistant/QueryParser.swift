import Foundation

/// Parses natural language queries into structured QueryIntent using keyword scoring.
struct QueryParser {

    /// Known entity names for fuzzy matching, injected from DataStore.
    var projectNames: [String] = []
    var bidNames: [String] = []
    var clientNames: [String] = []
    var lastProjectName: String?

    func parse(_ input: String) -> QueryIntent {
        let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if isGreeting(lower) { return .greeting }
        if lower.contains("help") || lower.contains("what can you") || lower.contains("what do you") {
            return .help
        }

        // --- Needs Attention / Action items ---
        if lower.contains("needs attention") || lower.contains("what needs") || lower.contains("what should i") ||
           lower.contains("action items") || lower.contains("what's urgent") || lower.contains("priorities") {
            return .needsAttention
        }

        // --- Time period detection ---
        let period = detectPeriod(lower)

        // --- Comparison: "compare X vs Y" ---
        if lower.contains("compare") || lower.contains(" vs ") || lower.contains(" versus ") {
            let names = extractComparisonNames(lower)
            if let a = names.0, let b = names.1 {
                return .compareProjects(nameA: a, nameB: b)
            }
        }

        // --- Entity extraction ---
        let mentionedProject = fuzzyMatch(lower, against: projectNames)
        let mentionedBid = fuzzyMatch(lower, against: bidNames)

        // --- Follow-up context: short queries that refer to last project ---
        if let lastProj = lastProjectName, mentionedProject == nil {
            let followUpIntents = detectFollowUp(lower, projectName: lastProj, period: period)
            if let intent = followUpIntents { return intent }
        }

        var scores: [(QueryIntent, Int)] = []

        // --- Timesheet / Payroll ---
        let tsWords = countKeywords(lower, ["timesheet", "hours worked", "who worked", "payroll hours", "crew hours", "labor hours"])
        let topWords = countKeywords(lower, ["most", "top", "highest", "who worked the most"])

        if tsWords > 0 && topWords > 0 { scores.append((.topWorkersByHours, tsWords + topWords + 5)) }
        if let proj = mentionedProject, tsWords > 0 {
            scores.append((.timesheetForProject(name: proj), tsWords + 8))
        }
        if tsWords > 0 && period != nil {
            scores.append((.totalPayrollThisPeriod(period: period!), tsWords + 6))
        }
        if tsWords > 0 { scores.append((.timesheetThisWeek, tsWords + 2)) }

        let payrollWords = countKeywords(lower, ["payroll", "labor cost", "labor total", "total payroll"])
        if payrollWords > 0 && period != nil {
            scores.append((.totalPayrollThisPeriod(period: period!), payrollWords + 6))
        }

        // --- Time-scoped financial ---
        let revWords = countKeywords(lower, ["revenue", "income", "earned", "total revenue"])
        let profitWords = countKeywords(lower, ["profit", "margin", "earnings", "net"])
        let costWords = countKeywords(lower, ["cost", "costs", "expenses", "spending", "spent"])

        if let p = period {
            if revWords > 0 { scores.append((.revenueForPeriod(period: p), revWords + 6)) }
            if profitWords > 0 && !lower.contains("cost") { scores.append((.profitForPeriod(period: p), profitWords + 6)) }
            if costWords > 0 && !lower.contains("profit") { scores.append((.costsForPeriod(period: p), costWords + 6)) }
        }

        // --- RFI ---
        let rfiWords = countKeywords(lower, ["rfi", "rfis", "request for information"])
        let overdueWords = countKeywords(lower, ["overdue", "late", "past due"])
        if rfiWords > 0 && overdueWords > 0 { scores.append((.overdueRFIs, rfiWords + overdueWords + 5)) }
        if rfiWords > 0 { scores.append((.overdueRFIs, rfiWords + 2)) }

        // --- Cost breakdown ---
        if let proj = mentionedProject, (lower.contains("breakdown") || lower.contains("cost breakdown") || lower.contains("job cost")) {
            scores.append((.costBreakdown(name: proj), 10))
        }

        // --- Margin trend ---
        if lower.contains("margin trend") || lower.contains("margins") || lower.contains("which project") && lower.contains("margin") {
            scores.append((.marginTrend, 8))
        }

        // --- Project health ---
        if let proj = mentionedProject, (lower.contains("health") || lower.contains("how is") || lower.contains("status")) {
            scores.append((.projectHealth(name: proj), 9))
        }

        // --- Financial ---
        let finWords = countKeywords(lower, ["financial", "summary", "overview", "how's the business", "how is the business", "p&l", "profit and loss", "bottom line"])
        if finWords > 0 { scores.append((.financialSummary, finWords + 5)) }

        if revWords > 0 && period == nil { scores.append((.totalRevenue, revWords + 3)) }

        if let proj = mentionedProject, (profitWords > 0 || costWords > 0 || lower.contains("how is") || lower.contains("how's")) {
            scores.append((.projectFinance(name: proj), profitWords + costWords + 8))
        }
        if profitWords > 0 && !lower.contains("cost") && period == nil { scores.append((.totalProfit, profitWords + 3)) }
        if lower.contains("margin") && period == nil { scores.append((.profitMargin, 6)) }
        if costWords > 0 && !lower.contains("profit") && period == nil { scores.append((.totalCosts, costWords + 3)) }

        // --- Projects ---
        let projWords = countKeywords(lower, ["project", "projects", "job", "jobs"])
        let activeWords = countKeywords(lower, ["active", "current", "ongoing", "in progress"])
        let completedWords = countKeywords(lower, ["completed", "done", "finished", "closed"])

        if let proj = mentionedProject, (lower.contains("detail") || lower.contains("tell me about") || lower.contains("show me")) {
            scores.append((.projectDetails(name: proj), 10))
        }
        if projWords > 0 && activeWords > 0 { scores.append((.activeProjects, projWords + activeWords + 3)) }
        if projWords > 0 && completedWords > 0 { scores.append((.completedProjects, projWords + completedWords + 3)) }
        if projWords > 0 && (lower.contains("all") || lower.contains("list")) { scores.append((.allProjects, projWords + 2)) }
        if projWords > 0 && (lower.contains("how many") || lower.contains("count")) { scores.append((.projectCount, projWords + 4)) }

        // --- Bidding ---
        let bidWords = countKeywords(lower, ["bid", "bids", "bidding", "pipeline"])
        let pendingWords = countKeywords(lower, ["pending", "open", "waiting"])
        let submittedWords = countKeywords(lower, ["submitted", "sent"])
        let wonWords = countKeywords(lower, ["won", "awarded"])
        let winRateWords = countKeywords(lower, ["win rate", "win percentage", "success rate"])

        if let bid = mentionedBid, (lower.contains("detail") || lower.contains("tell me about")) {
            scores.append((.bidDetails(name: bid), 10))
        }
        if bidWords > 0 && pendingWords > 0 { scores.append((.pendingBids, bidWords + pendingWords + 3)) }
        if bidWords > 0 && submittedWords > 0 { scores.append((.submittedBids, bidWords + submittedWords + 3)) }
        if bidWords > 0 && wonWords > 0 { scores.append((.awardedBids, bidWords + wonWords + 3)) }
        if winRateWords > 0 { scores.append((.bidWinRate, winRateWords + 5)) }
        if bidWords > 0 && (lower.contains("pipeline") || lower.contains("value")) { scores.append((.bidPipeline, bidWords + 3)) }

        // --- Clients ---
        let clientWords = countKeywords(lower, ["client", "clients", "customer", "gc", "general contractor"])
        if clientWords > 0 && (lower.contains("top") || lower.contains("best")) { scores.append((.topClients, clientWords + 5)) }
        if clientWords > 0 && (lower.contains("list") || lower.contains("all")) { scores.append((.clientList, clientWords + 2)) }
        if clientWords > 0 && lower.contains("how many") { scores.append((.clientCount, clientWords + 4)) }

        // --- Workforce ---
        let empWords = countKeywords(lower, ["employee", "employees", "crew", "workers", "staff", "team"])
        let foremanWords = countKeywords(lower, ["foreman", "foremen", "lead", "supervisor"])
        if foremanWords > 0 { scores.append((.foremen, foremanWords + 5)) }
        if empWords > 0 && lower.contains("how many") { scores.append((.employeeCount, empWords + 4)) }
        if empWords > 0 && activeWords > 0 { scores.append((.activeEmployees, empWords + activeWords + 3)) }
        if empWords > 0 { scores.append((.activeEmployees, empWords + 1)) }

        // --- Tasks ---
        let taskWords = countKeywords(lower, ["task", "tasks", "todo", "to-do", "to do", "todos"])
        let todayWords = countKeywords(lower, ["today", "today's", "due today"])
        if taskWords > 0 && overdueWords > 0 { scores.append((.overdueTodos, taskWords + overdueWords + 5)) }
        if overdueWords > 0 && rfiWords == 0 { scores.append((.overdueTodos, overdueWords + 3)) }
        if taskWords > 0 && todayWords > 0 { scores.append((.todayTodos, taskWords + todayWords + 5)) }
        if lower.contains("due today") || lower.contains("what's due") { scores.append((.todayTodos, 8)) }
        if taskWords > 0 && activeWords > 0 { scores.append((.activeTodos, taskWords + activeWords + 3)) }
        if taskWords > 0 && lower.contains("how many") { scores.append((.todoCount, taskWords + 4)) }
        if taskWords > 0 { scores.append((.activeTodos, taskWords + 1)) }

        // --- Equipment ---
        let equipWords = countKeywords(lower, ["equipment", "rental", "rentals", "crane", "boom", "lift"])
        if equipWords > 0 { scores.append((.activeRentals, equipWords + 3)) }

        // --- Schedule ---
        let schedWords = countKeywords(lower, ["schedule", "event", "events", "calendar", "meeting"])
        if schedWords > 0 && todayWords > 0 { scores.append((.todayEvents, schedWords + todayWords + 5)) }
        if schedWords > 0 && (lower.contains("upcoming") || lower.contains("next")) { scores.append((.upcomingEvents, schedWords + 4)) }

        // --- Change Orders ---
        let coWords = countKeywords(lower, ["change order", "change orders"])
        if let proj = mentionedProject, coWords > 0 { scores.append((.projectChangeOrders(name: proj), coWords + 8)) }
        if coWords > 0 { scores.append((.changeOrderSummary, coWords + 3)) }

        if let best = scores.max(by: { $0.1 < $1.1 }) { return best.0 }
        return .unknown(query: input)
    }

    // MARK: - Follow-up Context

    private func detectFollowUp(_ lower: String, projectName: String, period: TimePeriod?) -> QueryIntent? {
        let shortQuery = lower.count < 40
        if !shortQuery { return nil }

        if lower.contains("change order") { return .projectChangeOrders(name: projectName) }
        if lower.contains("cost") || lower.contains("breakdown") { return .costBreakdown(name: projectName) }
        if lower.contains("profit") || lower.contains("financ") || lower.contains("revenue") { return .projectFinance(name: projectName) }
        if lower.contains("timesheet") || lower.contains("hours") || lower.contains("labor") { return .timesheetForProject(name: projectName) }
        if lower.contains("health") || lower.contains("status") || lower.contains("how is it") { return .projectHealth(name: projectName) }
        if lower.contains("rfi") { return .projectHealth(name: projectName) }
        return nil
    }

    // MARK: - Time Period Detection

    private func detectPeriod(_ text: String) -> TimePeriod? {
        if text.contains("this week") { return .thisWeek }
        if text.contains("last week") { return .lastWeek }
        if text.contains("this month") { return .thisMonth }
        if text.contains("last month") { return .lastMonth }
        if text.contains("this quarter") || text.contains("quarter") { return .thisQuarter }
        if text.contains("this year") || text.contains("year to date") || text.contains("ytd") { return .thisYear }
        return nil
    }

    // MARK: - Comparison Extraction

    private func extractComparisonNames(_ text: String) -> (String?, String?) {
        // "compare X vs Y", "X versus Y", "compare X and Y"
        let separators = [" vs ", " versus ", " and ", " with "]
        let cleaned = text.replacingOccurrences(of: "compare ", with: "")
        for sep in separators {
            let parts = cleaned.components(separatedBy: sep)
            if parts.count >= 2 {
                let a = fuzzyMatch(parts[0].trimmingCharacters(in: .whitespaces), against: projectNames)
                let b = fuzzyMatch(parts[1].trimmingCharacters(in: .whitespaces), against: projectNames)
                if let a, let b { return (a, b) }
            }
        }
        return (nil, nil)
    }

    // MARK: - Helpers

    private func isGreeting(_ text: String) -> Bool {
        let greetings = ["hello", "hi", "hey", "good morning", "good afternoon", "good evening", "what's up", "howdy"]
        return greetings.contains(where: { text.hasPrefix($0) }) && text.count < 30
    }

    private func countKeywords(_ text: String, _ keywords: [String]) -> Int {
        keywords.reduce(0) { count, keyword in text.contains(keyword) ? count + 1 : count }
    }

    private func fuzzyMatch(_ input: String, against names: [String]) -> String? {
        let sorted = names.sorted { $0.count > $1.count }
        for name in sorted {
            if input.localizedCaseInsensitiveContains(name) { return name }
        }
        for name in sorted {
            let nameWords = name.lowercased().split(separator: " ").map(String.init)
            let matchCount = nameWords.filter { input.contains($0) }.count
            if matchCount >= 2 || (nameWords.count == 1 && matchCount == 1 && nameWords[0].count > 4) {
                return name
            }
        }
        return nil
    }
}
