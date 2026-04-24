import Foundation

/// Builds a compact, dense text snapshot of DataStore for the LLM system prompt.
/// Read-only — never modifies DataStore. Output is never written to disk.
///
/// The format is **pipe-delimited rows under bracketed section headers**, designed
/// to minimize token usage while remaining parseable by the model. Currency is
/// stripped of $ and commas; dates are ISO yyyy-MM-dd. The system prompt prefix
/// explains the format so the model can read it correctly.
///
/// SECURITY: This data must ONLY be sent to the ON-DEVICE LLM. NEVER route this
/// output to any cloud/remote API. Contains sensitive business financials.
@MainActor
struct DataContextBuilder {

    static let systemPromptPrefix = """
    You are SteelSync Assistant, a project management AI for J&R Steel Welding LLC, \
    a Texas steel erection company. The data below is in a compact pipe-delimited format. \
    Currency values are USD integers (no $, no commas). Dates are ISO yyyy-MM-dd. \
    Each section starts with a header in [brackets]; column names follow `cols:`.

    HOW TO ANSWER:
    - Use ONLY the data below. Never invent numbers. If data to answer is missing, say so.
    - The [TODAY] section gives the current date. Use it to resolve relative phrases like \
    "this month", "last week", "this quarter", "year to date".
    - For TIME-SCOPED cost or equipment questions, FILTER the [RECENT_COSTS_90D] log by date \
    (and by category when relevant) and SUM the matching `amount` values yourself. Do not say \
    "I don't have that breakdown" if the cost log covers the requested range — compute it.
    - "Equipment" costs = Cost entries with category `Machinery`. Active rentals are separately \
    listed in [ACTIVE_RENTALS]; their `cost_so_far` is accrued spend, not yet a closed cost line.
    - "Labor" costs come from the [PROJECT_COSTS] / [COSTS_BY_CAT_ALL] sections (key `Labor`), \
    not the cost log.
    - For project-specific questions, check [PROJECTS], [PROJECT_COSTS], and [PROJECT_SCHEDULE] \
    for that project's row.
    - For INVOICE / cash flow questions ("what's outstanding", "which GC is slow to pay", \
    "how much overdue"), use [INVOICES] for totals, [AGING] for bucket analysis, and \
    [INVOICE_DETAIL] for per-invoice facts. Status `Overdue(Nd)` means an invoice is N days past \
    its due date. Filter by client name to answer GC-specific questions.

    In your responses, format currency naturally (e.g. $1,234) and dates readably. \
    Be concise and professional.
    """

    /// Builds the full system prompt with injected data context.
    /// WARNING: Output contains raw financial data. On-device use only.
    static func buildSystemPrompt(from dataStore: DataStore) -> String {
        var c = systemPromptPrefix + "\n\nDATA:\n\n"
        c += todaySection()
        c += financialSummary(dataStore)
        c += projectsList(dataStore)
        c += projectCostBreakdowns(dataStore)
        c += projectScheduleEmbed(dataStore)
        c += scheduleSummary(dataStore)
        c += bidsList(dataStore)
        c += invoicesSection(dataStore)
        c += timesheetSummary(dataStore)
        c += tasksSummary(dataStore)
        c += rfiSummary(dataStore)
        c += employeesSummary(dataStore)
        c += equipmentSummary(dataStore)
        c += activeRentalsDetail(dataStore)
        c += recentCostLog(dataStore)
        return c
    }

    // MARK: - Format Helpers

    /// Decimal → integer string (truncates fraction). Used for compact currency.
    private static func num(_ d: Decimal) -> String {
        String(NSDecimalNumber(decimal: d).int64Value)
    }

    /// Date → ISO yyyy-MM-dd string.
    private static func iso(_ d: Date) -> String {
        d.formatted("yyyy-MM-dd")
    }

    // MARK: - Section Builders

    /// Today's date as the model's anchor for relative-time phrases.
    /// Critical: without this the LLM cannot resolve "this month" / "last week"
    /// because it has no real-time clock.
    private static func todaySection() -> String {
        let now = Date()
        let today = now.formatted("yyyy-MM-dd")
        let weekday = now.formatted("EEEE")
        let monthLabel = now.formatted("MMMM yyyy")
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)).map(iso) ?? today
        let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)).map(iso) ?? today
        let yearStart = cal.date(from: cal.dateComponents([.year], from: now)).map(iso) ?? today
        return "[TODAY] date=\(today)|weekday=\(weekday)|month=\(monthLabel)|month_start=\(monthStart)|week_start=\(weekStart)|year_start=\(yearStart)\n\n"
    }

    private static func financialSummary(_ ds: DataStore) -> String {
        let s = ds.financialSummary
        return "[FIN] rev=\(num(ds.totalRevenue))|cost=\(num(ds.totalCosts))|profit=\(num(s.profit))|margin=\(String(format: "%.1f", s.margin))%|contract=\(num(ds.totalContractValue))|remaining=\(num(ds.totalRemainingBalance))\n\n"
    }

    private static func projectsList(_ ds: DataStore) -> String {
        let projects = ds.projects
        var t = "[PROJECTS \(projects.count)t \(ds.activeProjects.count)a] cols: name|contract|revenue|cost|profit|margin|status|COs|location\n"
        for p in projects.prefix(20) {
            let cos = ds.changeOrders(for: p.id).count
            t += "\(p.title)|\(num(p.contractAmount))|\(num(p.totalRevenue))|\(num(p.totalCosts))|\(num(p.profit))|\(String(format: "%.1f", p.profitMargin))%|\(p.computedStatus)|\(cos)|\(p.location)\n"
        }
        t += "\n"
        return t
    }

    private static func projectCostBreakdowns(_ ds: DataStore) -> String {
        var t = "[PROJECT_COSTS] cols: project|category|amount\n"
        var any = false
        for p in ds.projects.prefix(20) {
            var byCat: [String: Decimal] = [:]
            for c in ds.costs(for: p.id) {
                byCat[c.category.displayName, default: 0] += c.amount
            }
            let payroll = p.balanceSummary.payrollTotal
            if payroll > 0 {
                byCat["Labor"] = payroll
            }
            for (cat, amt) in byCat.sorted(by: { $0.value > $1.value }) {
                t += "\(p.title)|\(cat)|\(num(amt))\n"
                any = true
            }
        }
        if !any { t += "(none)\n" }
        t += "\n"
        return t
    }

    private static func projectScheduleEmbed(_ ds: DataStore) -> String {
        var t = "[PROJECT_SCHEDULE] cols: project|task|cat|start|end|status|prog\n"
        var any = false
        for p in ds.projects.prefix(20) {
            let tasks = ds.ganttTasks
                .filter { $0.projectID == p.id.recordName && $0.status != .completed }
                .sorted { $0.startDate < $1.startDate }
            for task in tasks.prefix(8) {
                t += "\(p.title)|\(task.name)|\(task.category.rawValue)|\(iso(task.startDate))|\(iso(task.endDate))|\(task.status.rawValue)|\(Int(task.progress * 100))\n"
                any = true
            }
        }
        if !any { t += "(none)\n" }
        t += "\n"
        return t
    }

    private static func scheduleSummary(_ ds: DataStore) -> String {
        let now = Date()
        let thirtyDaysOut = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now

        var projectTitles: [String: String] = [:]
        for p in ds.projects {
            projectTitles[p.id.recordName] = p.title
        }

        let upcoming = ds.ganttTasks
            .filter { $0.status != .completed && $0.endDate >= now && $0.startDate <= thirtyDaysOut }
            .sorted { $0.startDate < $1.startDate }
        let overdue = ds.ganttTasks
            .filter { $0.status != .completed && $0.endDate < now }
            .sorted { $0.endDate < $1.endDate }

        var t = "[SCHEDULE] tasks=\(ds.ganttTasks.count)|upcoming30=\(upcoming.count)|overdue=\(overdue.count)\n"
        if !overdue.isEmpty {
            t += "[OVERDUE_TASKS] cols: project|task|ended|status|prog\n"
            for task in overdue.prefix(8) {
                let proj = projectTitles[task.projectID] ?? "?"
                t += "\(proj)|\(task.name)|\(iso(task.endDate))|\(task.status.rawValue)|\(Int(task.progress * 100))\n"
            }
        }
        if !upcoming.isEmpty {
            t += "[UPCOMING_TASKS_30D] cols: project|task|cat|start|end|status|prog\n"
            for task in upcoming.prefix(15) {
                let proj = projectTitles[task.projectID] ?? "?"
                t += "\(proj)|\(task.name)|\(task.category.rawValue)|\(iso(task.startDate))|\(iso(task.endDate))|\(task.status.rawValue)|\(Int(task.progress * 100))\n"
            }
        }
        t += "\n"
        return t
    }

    /// Invoice / billing state. Lets the assistant answer "what's outstanding",
    /// "which GC is slow to pay", "show me overdue invoices", etc.
    private static func invoicesSection(_ ds: DataStore) -> String {
        let all = ds.allInvoices
        guard !all.isEmpty else {
            return "[INVOICES] (none)\n\n"
        }

        // Roll-up totals
        var outstanding: Decimal = 0
        var overdue: Decimal = 0
        var paid30: Decimal = 0  // paid in last 30 days
        let cal = Calendar.current
        let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        for entry in all {
            let remaining = ds.balanceRemaining(for: entry.invoice)
            if InvoiceStatus.outstandingCases.contains(entry.invoice.status) || entry.invoice.isOverdue {
                outstanding += remaining
            }
            if entry.invoice.isOverdue {
                overdue += remaining
            }
            if entry.invoice.status == .paid,
               let pd = entry.invoice.paidDate, pd >= thirtyDaysAgo {
                paid30 += entry.invoice.netAmountDue
            }
        }

        // Aging buckets (outstanding only)
        var current: Decimal = 0
        var b1: Decimal = 0
        var b2: Decimal = 0
        var b3: Decimal = 0
        var b4: Decimal = 0
        for entry in all where entry.invoice.status != .paid && entry.invoice.status != .draft {
            let remaining = ds.balanceRemaining(for: entry.invoice)
            let days = entry.invoice.daysOverdue
            if days <= 0 { current += remaining }
            else if days <= 30 { b1 += remaining }
            else if days <= 60 { b2 += remaining }
            else if days <= 90 { b3 += remaining }
            else { b4 += remaining }
        }

        var t = "[INVOICES \(all.count)t] outstanding=\(num(outstanding))|overdue=\(num(overdue))|paid_last30d=\(num(paid30))\n"
        t += "[AGING] current=\(num(current))|1-30d=\(num(b1))|31-60d=\(num(b2))|61-90d=\(num(b3))|90+d=\(num(b4))\n"

        // Per-invoice detail — cap at 25 most-recent non-paid + oldest overdue first
        let sorted = all.sorted { a, b in
            // Overdue first (sorted by days overdue desc), then outstanding by sent desc
            if a.invoice.isOverdue && !b.invoice.isOverdue { return true }
            if !a.invoice.isOverdue && b.invoice.isOverdue { return false }
            if a.invoice.isOverdue && b.invoice.isOverdue {
                return a.invoice.daysOverdue > b.invoice.daysOverdue
            }
            return (a.invoice.sentDate ?? .distantPast) > (b.invoice.sentDate ?? .distantPast)
        }

        t += "[INVOICE_DETAIL] cols: number|project|client|status|sent|due|invoiced|paid|remaining\n"
        for entry in sorted.prefix(25) {
            let inv = entry.invoice
            let paid = ds.totalPaid(for: inv.id)
            let remaining = ds.balanceRemaining(for: inv)
            let statusLabel = inv.isOverdue ? "Overdue(\(inv.daysOverdue)d)" : inv.status.rawValue
            let sent = inv.sentDate.map(iso) ?? "—"
            let due = inv.dueDate.map(iso) ?? "—"
            t += "\(inv.invoiceNumber)|\(entry.projectTitle)|\(inv.clientName)|\(statusLabel)|\(sent)|\(due)|\(num(inv.netAmountDue))|\(num(paid))|\(num(remaining))\n"
        }
        if sorted.count > 25 {
            t += "(+\(sorted.count - 25) more invoices truncated)\n"
        }
        t += "\n"
        return t
    }

    private static func bidsList(_ ds: DataStore) -> String {
        let bids = ds.bids
        if bids.isEmpty {
            return "[BIDS] (none)\n\n"
        }
        var t = "[BIDS \(bids.count)t \(ds.pendingBids.count)p win=\(String(format: "%.0f", ds.bidWinRate))%] cols: project|amount|due|status|client\n"
        for b in bids.prefix(15) {
            t += "\(b.projectName)|\(num(b.bidAmount))|\(iso(b.bidDueDate))|\(b.status.rawValue)|\(b.clientName)\n"
        }
        t += "\n"
        return t
    }

    private static func timesheetSummary(_ ds: DataStore) -> String {
        let weekStart = TimesheetEntry.currentWeekStart()
        let thisWeek = ds.timesheetEntries(for: weekStart)
        let totals = ds.timesheetWeekTotals(for: weekStart)

        var t = "[TIMESHEET_WEEK] entries=\(thisWeek.count)|hours=\(totals.hours)|pay=\(num(totals.pay))|perdiem=\(num(totals.perDiem))\n"
        if !thisWeek.isEmpty {
            var byWorker: [String: Decimal] = [:]
            for e in thisWeek { byWorker[e.employeeName, default: 0] += e.totalHours }
            let ranked = byWorker.sorted { $0.value > $1.value }.prefix(10)
            if !ranked.isEmpty {
                t += "[WORKER_HOURS] cols: name|hours\n"
                for (name, hours) in ranked {
                    t += "\(name)|\(hours)\n"
                }
            }
        }
        t += "\n"
        return t
    }

    private static func tasksSummary(_ ds: DataStore) -> String {
        let active = ds.activeTodos
        let overdue = ds.overdueTodos
        let completed = ds.completedTodos

        var projectTitles: [String: String] = [:]
        for p in ds.projects {
            projectTitles[p.id.recordName] = p.title
        }

        func projOf(_ t: TodoItem) -> String {
            guard let pid = t.relatedProjectID else { return "" }
            return projectTitles[pid] ?? ""
        }

        func dueOf(_ t: TodoItem) -> String {
            t.dueDate.map(iso) ?? ""
        }

        var s = "[TODOS] active=\(active.count)|overdue=\(overdue.count)|completed=\(completed.count)\n"

        if !overdue.isEmpty {
            s += "[OVERDUE_TODOS] cols: title|project|due|priority\n"
            for t in overdue.prefix(8) {
                s += "\(t.title)|\(projOf(t))|\(dueOf(t))|\(t.priority.displayName)\n"
            }
        }

        let notOverdue = active.filter { !$0.isOverdue }
        let urgent = notOverdue.filter { $0.priority == .urgent }
        let high = notOverdue.filter { $0.priority == .high }
        let medium = notOverdue.filter { $0.priority == .medium }

        if !urgent.isEmpty {
            s += "[URGENT_TODOS] cols: title|project|due\n"
            for t in urgent.prefix(6) { s += "\(t.title)|\(projOf(t))|\(dueOf(t))\n" }
        }
        if !high.isEmpty {
            s += "[HIGH_TODOS] cols: title|project|due\n"
            for t in high.prefix(6) { s += "\(t.title)|\(projOf(t))|\(dueOf(t))\n" }
        }
        if !medium.isEmpty {
            s += "[MEDIUM_TODOS] cols: title|project|due\n"
            for t in medium.prefix(5) { s += "\(t.title)|\(projOf(t))|\(dueOf(t))\n" }
        }

        s += "\n"
        return s
    }

    private static func rfiSummary(_ ds: DataStore) -> String {
        var total = 0
        var overdue = 0
        var open = 0
        for project in ds.projects {
            let rfis = ds.rfis(for: project.id)
            total += rfis.count
            overdue += rfis.filter { $0.isOverdue }.count
            open += rfis.filter { $0.status != .closed }.count
        }
        return "[RFI] total=\(total)|open=\(open)|overdue=\(overdue)\n\n"
    }

    private static func employeesSummary(_ ds: DataStore) -> String {
        let emps = ds.employees
        let active = ds.activeEmployees
        let contractors = active.filter { $0.employeeType == .contractor }
        let foremen = ds.foremen
        return "[EMPLOYEES] total=\(emps.count)|active=\(active.count)|foremen=\(foremen.count)|contractors=\(contractors.count)\n\n"
    }

    private static func equipmentSummary(_ ds: DataStore) -> String {
        let count = ds.allActiveRentalCount
        var t = "[EQUIPMENT] active_rentals=\(count)\n"

        var costsByCat: [String: Decimal] = [:]
        var totalPayroll: Decimal = 0
        for project in ds.projects {
            for cost in ds.costs(for: project.id) {
                costsByCat[cost.category.displayName, default: 0] += cost.amount
            }
            totalPayroll += project.balanceSummary.payrollTotal
        }
        if totalPayroll > 0 {
            costsByCat["Labor"] = totalPayroll
        }
        if !costsByCat.isEmpty {
            t += "[COSTS_BY_CAT_ALL] cols: category|amount\n"
            for (cat, amount) in costsByCat.sorted(by: { $0.value > $1.value }) {
                t += "\(cat)|\(num(amount))\n"
            }
        }
        t += "\n"
        return t
    }

    private static func activeRentalsDetail(_ ds: DataStore) -> String {
        var t = "[ACTIVE_RENTALS] cols: project|equipment|started|days|cost_so_far|daily|weekly|4wk\n"
        var any = false
        for project in ds.projects {
            let active = ds.activeRentals(for: project.id)
            for rental in active.prefix(12) {
                let dayLabel = rental.isScheduled ? "scheduled" : String(rental.daysSinceStart)
                t += "\(project.title)|\(rental.equipmentName)|\(iso(rental.startDate))|\(dayLabel)|\(num(rental.estimatedActiveCost))|\(num(rental.dailyRate))|\(num(rental.weeklyRate))|\(num(rental.fourWeekRate))\n"
                any = true
            }
        }
        if !any { t += "(none)\n" }
        t += "\n"
        return t
    }

    private static func recentCostLog(_ ds: DataStore) -> String {
        let now = Date()
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now

        struct LogEntry {
            let date: Date
            let projectTitle: String
            let category: String
            let description: String
            let amount: Decimal
        }

        var entries: [LogEntry] = []
        for project in ds.projects {
            for cost in ds.costs(for: project.id) where cost.date >= cutoff {
                entries.append(LogEntry(
                    date: cost.date,
                    projectTitle: project.title,
                    category: cost.category.displayName,
                    description: cost.description,
                    amount: cost.amount
                ))
            }
        }
        entries.sort { $0.date > $1.date }

        var t = "[RECENT_COSTS_90D entries=\(entries.count)] cols: date|project|category|description|amount\n"
        if entries.isEmpty {
            t += "(none)\n\n"
            return t
        }
        for entry in entries.prefix(40) {
            let desc = entry.description.isEmpty ? "-" : entry.description
            t += "\(iso(entry.date))|\(entry.projectTitle)|\(entry.category)|\(desc)|\(num(entry.amount))\n"
        }
        if entries.count > 40 {
            t += "(+\(entries.count - 40) older truncated)\n"
        }
        t += "\n"
        return t
    }
}
