import Foundation

/// Parses natural language queries into structured QueryIntent using keyword scoring.
struct QueryParser {

    /// Known project and bid names for fuzzy matching, injected from DataStore.
    var projectNames: [String] = []
    var bidNames: [String] = []
    var clientNames: [String] = []

    func parse(_ input: String) -> QueryIntent {
        let lower = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Greetings
        if isGreeting(lower) { return .greeting }

        // Help
        if lower.contains("help") || lower.contains("what can you") || lower.contains("what do you") {
            return .help
        }

        // Try to extract an entity name for project/bid/client-specific queries
        let mentionedProject = fuzzyMatch(lower, against: projectNames)
        let mentionedBid = fuzzyMatch(lower, against: bidNames)

        // Score each intent category
        var scores: [(QueryIntent, Int)] = []

        // --- Financial ---
        let finWords = countKeywords(lower, ["financial", "summary", "overview", "how's the business", "how is the business", "p&l", "profit and loss", "bottom line"])
        if finWords > 0 { scores.append((.financialSummary, finWords + 5)) }

        let revWords = countKeywords(lower, ["revenue", "income", "earned", "total revenue", "how much revenue"])
        if revWords > 0 { scores.append((.totalRevenue, revWords + 3)) }

        let profitWords = countKeywords(lower, ["profit", "margin", "earnings", "net"])
        let costWords = countKeywords(lower, ["cost", "costs", "expenses", "spending", "spent"])

        if let proj = mentionedProject, (profitWords > 0 || costWords > 0 || lower.contains("how is") || lower.contains("how's")) {
            scores.append((.projectFinance(name: proj), profitWords + costWords + 8))
        }
        if profitWords > 0 && !lower.contains("cost") {
            scores.append((.totalProfit, profitWords + 3))
        }
        if lower.contains("margin") {
            scores.append((.profitMargin, 6))
        }
        if costWords > 0 && !lower.contains("profit") {
            scores.append((.totalCosts, costWords + 3))
        }

        // --- Projects ---
        let projWords = countKeywords(lower, ["project", "projects", "job", "jobs"])
        let activeWords = countKeywords(lower, ["active", "current", "ongoing", "in progress"])
        let completedWords = countKeywords(lower, ["completed", "done", "finished", "closed"])

        if let proj = mentionedProject, (lower.contains("detail") || lower.contains("status") || lower.contains("tell me about") || lower.contains("show me")) {
            scores.append((.projectDetails(name: proj), 10))
        }
        if projWords > 0 && activeWords > 0 { scores.append((.activeProjects, projWords + activeWords + 3)) }
        if projWords > 0 && completedWords > 0 { scores.append((.completedProjects, projWords + completedWords + 3)) }
        if projWords > 0 && (lower.contains("all") || lower.contains("list")) { scores.append((.allProjects, projWords + 2)) }
        if projWords > 0 && (lower.contains("how many") || lower.contains("count") || lower.contains("total number")) {
            scores.append((.projectCount, projWords + 4))
        }

        // --- Bidding ---
        let bidWords = countKeywords(lower, ["bid", "bids", "bidding", "pipeline"])
        let pendingWords = countKeywords(lower, ["pending", "open", "waiting"])
        let submittedWords = countKeywords(lower, ["submitted", "sent"])
        let wonWords = countKeywords(lower, ["won", "awarded", "won"])
        let winRateWords = countKeywords(lower, ["win rate", "win percentage", "success rate", "hit rate"])

        if let bid = mentionedBid, (lower.contains("detail") || lower.contains("status") || lower.contains("tell me about")) {
            scores.append((.bidDetails(name: bid), 10))
        }
        if bidWords > 0 && pendingWords > 0 { scores.append((.pendingBids, bidWords + pendingWords + 3)) }
        if bidWords > 0 && submittedWords > 0 { scores.append((.submittedBids, bidWords + submittedWords + 3)) }
        if bidWords > 0 && wonWords > 0 { scores.append((.awardedBids, bidWords + wonWords + 3)) }
        if winRateWords > 0 { scores.append((.bidWinRate, winRateWords + 5)) }
        if bidWords > 0 && (lower.contains("pipeline") || lower.contains("value") || lower.contains("total")) {
            scores.append((.bidPipeline, bidWords + 3))
        }

        // --- Clients ---
        let clientWords = countKeywords(lower, ["client", "clients", "customer", "customers", "gc", "general contractor"])
        if clientWords > 0 && (lower.contains("top") || lower.contains("best") || lower.contains("most")) {
            scores.append((.topClients, clientWords + 5))
        }
        if clientWords > 0 && (lower.contains("list") || lower.contains("all") || lower.contains("show")) {
            scores.append((.clientList, clientWords + 2))
        }
        if clientWords > 0 && (lower.contains("how many") || lower.contains("count")) {
            scores.append((.clientCount, clientWords + 4))
        }

        // --- Workforce ---
        let empWords = countKeywords(lower, ["employee", "employees", "crew", "workers", "workforce", "staff", "team"])
        let foremanWords = countKeywords(lower, ["foreman", "foremen", "lead", "leads", "supervisor"])
        if foremanWords > 0 { scores.append((.foremen, foremanWords + 5)) }
        if empWords > 0 && (lower.contains("how many") || lower.contains("count")) {
            scores.append((.employeeCount, empWords + 4))
        }
        if empWords > 0 && activeWords > 0 { scores.append((.activeEmployees, empWords + activeWords + 3)) }
        if empWords > 0 { scores.append((.activeEmployees, empWords + 1)) }

        // --- Tasks ---
        let taskWords = countKeywords(lower, ["task", "tasks", "todo", "to-do", "to do", "todos"])
        let overdueWords = countKeywords(lower, ["overdue", "late", "past due", "behind"])
        let todayWords = countKeywords(lower, ["today", "today's", "due today"])
        if taskWords > 0 && overdueWords > 0 { scores.append((.overdueTodos, taskWords + overdueWords + 5)) }
        if overdueWords > 0 { scores.append((.overdueTodos, overdueWords + 3)) }
        if taskWords > 0 && todayWords > 0 { scores.append((.todayTodos, taskWords + todayWords + 5)) }
        if lower.contains("due today") || lower.contains("what's due") { scores.append((.todayTodos, 8)) }
        if taskWords > 0 && activeWords > 0 { scores.append((.activeTodos, taskWords + activeWords + 3)) }
        if taskWords > 0 && (lower.contains("how many") || lower.contains("count")) {
            scores.append((.todoCount, taskWords + 4))
        }
        if taskWords > 0 { scores.append((.activeTodos, taskWords + 1)) }

        // --- Equipment ---
        let equipWords = countKeywords(lower, ["equipment", "rental", "rentals", "crane", "boom", "lift", "machinery"])
        if equipWords > 0 { scores.append((.activeRentals, equipWords + 3)) }

        // --- Schedule ---
        let schedWords = countKeywords(lower, ["schedule", "event", "events", "calendar", "meeting", "meetings"])
        if schedWords > 0 && todayWords > 0 { scores.append((.todayEvents, schedWords + todayWords + 5)) }
        if schedWords > 0 && (lower.contains("upcoming") || lower.contains("next") || lower.contains("soon")) {
            scores.append((.upcomingEvents, schedWords + 4))
        }
        if todayWords > 0 && schedWords > 0 { scores.append((.todayEvents, 6)) }

        // --- Change Orders ---
        let coWords = countKeywords(lower, ["change order", "change orders"])
        if let proj = mentionedProject, coWords > 0 {
            scores.append((.projectChangeOrders(name: proj), coWords + 8))
        }
        if coWords > 0 { scores.append((.changeOrderSummary, coWords + 3)) }

        // Return highest scoring intent
        if let best = scores.max(by: { $0.1 < $1.1 }) {
            return best.0
        }

        return .unknown(query: input)
    }

    // MARK: - Helpers

    private func isGreeting(_ text: String) -> Bool {
        let greetings = ["hello", "hi", "hey", "good morning", "good afternoon", "good evening", "what's up", "howdy"]
        return greetings.contains(where: { text.hasPrefix($0) }) && text.count < 30
    }

    private func countKeywords(_ text: String, _ keywords: [String]) -> Int {
        keywords.reduce(0) { count, keyword in
            text.contains(keyword) ? count + 1 : count
        }
    }

    /// Finds the best matching name from a list, using case-insensitive substring matching.
    private func fuzzyMatch(_ input: String, against names: [String]) -> String? {
        // First try exact substring match (longest match wins)
        let sorted = names.sorted { $0.count > $1.count }
        for name in sorted {
            if input.localizedCaseInsensitiveContains(name) {
                return name
            }
        }
        // Try matching individual words from the name
        for name in sorted {
            let nameWords = name.lowercased().split(separator: " ").map(String.init)
            let matchCount = nameWords.filter { input.contains($0) }.count
            if matchCount >= 2 || (nameWords.count == 1 && matchCount == 1 && nameWords[0].count > 3) {
                return name
            }
        }
        return nil
    }
}
