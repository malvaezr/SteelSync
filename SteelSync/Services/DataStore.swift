import SwiftUI
import CloudKit

@MainActor
class DataStore: ObservableObject {
    // IMPORTANT: Default to EMPTY arrays, not SampleData.
    // SampleData is only used on the very first launch (no saved data + no prior launch).
    @Published var projects: [Project] = []
    @Published var bids: [BidProject] = []
    @Published var clients: [Client] = []
    @Published var employees: [Employee] = []
    @Published var todos: [TodoItem] = []
    @Published var calendarEvents: [CalendarEvent] = []
    @Published var changeOrders: [CKRecord.ID: [ChangeOrder]] = [:]
    @Published var payments: [CKRecord.ID: [Payment]] = [:]
    @Published var payrollEntries: [CKRecord.ID: [PayrollEntry]] = [:]
    @Published var costs: [CKRecord.ID: [Cost]] = [:]
    @Published var equipmentRentals: [CKRecord.ID: [EquipmentRental]] = [:]
    @Published var ganttTasks: [GanttTask] = []
    @Published var payApplications: [CKRecord.ID: [PayApplication]] = [:]
    @Published var invoices: [CKRecord.ID: [Invoice]] = [:]
    @Published var timesheetEntries: [TimesheetEntry] = []
    @Published var crewPresets: [CrewPreset] = []
    @Published var rfis: [CKRecord.ID: [RFI]] = [:]
    @Published var overheadExpenses: [OverheadExpense] = []
    @Published var planningPads: [PlanningPad] = []
    @Published var assistantMessages: [AssistantMessage] = []
    @Published var auditLog: [AuditEntry] = []
    @Published var isLoading = false
    @Published var cloudKitAvailable = false
    @Published var syncStatus: CloudKitService.SyncStatus = .local
    @Published var lastSyncDate: Date?
    @Published var isSyncing = false
    @Published var syncProgress: Double = 0  // 0.0 to 1.0

    private static let hasLaunchedKey = "SteelSync.hasLaunchedBefore"

    let containerID = "iCloud.com.jrfv.SteelSync"
    let cloudKit = CloudKitService()

    init() {
        // Load persisted data from disk
        let loaded = PersistenceService.loadAll(into: self)

        if !loaded {
            // No saved data found
            if !UserDefaults.standard.bool(forKey: Self.hasLaunchedKey) {
                // True first launch ever — populate with sample data
                projects = SampleData.projects
                bids = SampleData.bids
                clients = SampleData.clients
                employees = SampleData.employees
                todos = SampleData.todos
                calendarEvents = SampleData.calendarEvents
                UserDefaults.standard.set(true, forKey: Self.hasLaunchedKey)
                PersistenceService.saveAll(from: self)
            }
        }

        // Recalculate all project balances to pick up timesheet costs
        recalculateAllBalances()

        // Defer CloudKit check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.performInitialSync()
            }
        }
    }

    /// Initial check on app launch — only checks CloudKit availability, NEVER auto-syncs data.
    /// All data movement requires explicit user action via Push/Pull buttons.
    private func performInitialSync() async {
        syncStatus = .checking
        let available = await cloudKit.checkAccountStatus()
        cloudKitAvailable = available

        guard available else {
            syncStatus = .local
            return
        }

        try? await cloudKit.setupZone()
        // Ready for manual sync — local data is untouched
        syncStatus = .ready
    }

    // MARK: - Manual Sync

    /// Push local data to CloudKit (Mac → Cloud). Does NOT overwrite local data.
    /// Also deletes cloud records that no longer exist locally (orphan cleanup).
    func pushToCloud() async {
        guard !isSyncing else { return }
        guard cloudKitAvailable else {
            syncStatus = .error("iCloud not available")
            return
        }
        persistNow() // Flush pending writes before syncing
        isSyncing = true
        syncProgress = 0
        syncStatus = .syncing
        try? await cloudKit.setupZone()
        let success = await cloudKit.uploadAllToCloud(from: self) { [weak self] progress in
            Task { @MainActor in self?.syncProgress = progress }
        }

        // Always clean up orphans — collect all local record IDs
        var localIDs = Set<String>()
        for p in projects { localIDs.insert(p.ckRecordName) }
        for c in clients { localIDs.insert(c.ckRecordName) }
        for b in bids { localIDs.insert(b.ckRecordName) }
        for e in employees { localIDs.insert(e.ckRecordName) }
        for t in todos { localIDs.insert(t.ckRecordName) }
        for ev in calendarEvents { localIDs.insert(ev.ckRecordName) }
        for g in ganttTasks { localIDs.insert(g.ckRecordName) }
        for a in auditLog { localIDs.insert(a.ckRecordName) }
        for ts in timesheetEntries { localIDs.insert(ts.ckRecordName) }
        for cp in crewPresets { localIDs.insert(cp.ckRecordName) }
        for oh in overheadExpenses { localIDs.insert(oh.ckRecordName) }
        for (_, items) in changeOrders { for co in items { localIDs.insert(co.ckRecordName) } }
        for (_, items) in payments { for p in items { localIDs.insert(p.ckRecordName) } }
        for (_, items) in payrollEntries { for e in items { localIDs.insert(e.ckRecordName) } }
        for (_, items) in costs { for c in items { localIDs.insert(c.ckRecordName) } }
        for (_, items) in equipmentRentals { for r in items { localIDs.insert(r.ckRecordName) } }
        // Pay apps + invoices: include so the orphan sweep doesn't delete the
        // records we just uploaded for them. Missing these here was the cause
        // of invoices never reaching the iPad.
        for (_, items) in payApplications { for pa in items { localIDs.insert(pa.ckRecordName) } }
        for (_, items) in invoices { for inv in items { localIDs.insert(inv.ckRecordName) } }
        for (_, items) in rfis { for r in items { localIDs.insert(r.ckRecordName) } }

        // Defensive: if a collection is locally empty, protect that record
        // type from the orphan sweep. This prevents a freshly installed device
        // (e.g. iPad before its first successful pull) from wiping cloud data
        // for that type. A genuine "delete the last one" still works because
        // individual deletes go through `deleteFromCloud` directly.
        var protectedTypes: Set<String> = []
        if invoices.values.allSatisfy({ $0.isEmpty }) { protectedTypes.insert(Invoice.ckRecordType) }
        if payApplications.values.allSatisfy({ $0.isEmpty }) { protectedTypes.insert(PayApplication.ckRecordType) }
        if rfis.values.allSatisfy({ $0.isEmpty }) { protectedTypes.insert(RFI.ckRecordType) }
        if changeOrders.values.allSatisfy({ $0.isEmpty }) { protectedTypes.insert(ChangeOrder.ckRecordType) }
        if payments.values.allSatisfy({ $0.isEmpty }) { protectedTypes.insert(Payment.ckRecordType) }
        if payrollEntries.values.allSatisfy({ $0.isEmpty }) { protectedTypes.insert(PayrollEntry.ckRecordType) }
        if costs.values.allSatisfy({ $0.isEmpty }) { protectedTypes.insert(Cost.ckRecordType) }
        if equipmentRentals.values.allSatisfy({ $0.isEmpty }) { protectedTypes.insert(EquipmentRental.ckRecordType) }
        if projects.isEmpty { protectedTypes.insert(Project.ckRecordType) }
        if clients.isEmpty { protectedTypes.insert(Client.ckRecordType) }
        if bids.isEmpty { protectedTypes.insert(BidProject.ckRecordType) }
        if employees.isEmpty { protectedTypes.insert(Employee.ckRecordType) }
        if todos.isEmpty { protectedTypes.insert(TodoItem.ckRecordType) }
        if calendarEvents.isEmpty { protectedTypes.insert(CalendarEvent.ckRecordType) }
        if ganttTasks.isEmpty { protectedTypes.insert(GanttTask.ckRecordType) }
        if timesheetEntries.isEmpty { protectedTypes.insert(TimesheetEntry.ckRecordType) }
        if crewPresets.isEmpty { protectedTypes.insert(CrewPreset.ckRecordType) }

        let orphansDeleted = await cloudKit.deleteOrphanedRecords(localIDs: localIDs, protectedTypes: protectedTypes)
        if orphansDeleted > 0 {
            print("[Sync] Deleted \(orphansDeleted) orphaned cloud records")
        }

        if success {
            syncStatus = .synced
            lastSyncDate = Date()
        } else {
            syncStatus = .error(cloudKit.lastSyncError ?? "Upload failed")
        }
        isSyncing = false
    }

    /// Pull data from CloudKit to local (Cloud → Local). Backs up local data first, then overwrites.
    func pullFromCloud() async {
        guard !isSyncing else { return }
        guard cloudKitAvailable else {
            syncStatus = .error("iCloud not available")
            return
        }
        isSyncing = true
        syncProgress = 0
        syncStatus = .syncing

        // SAFETY: backup local data before overwriting
        PersistenceService.backupAll()
        syncProgress = 0.1  // Backup done

        let success = await cloudKit.fetchAllDataFromCloud(into: self)
        syncProgress = 1.0
        cloudKitAvailable = cloudKit.isAvailable
        if success {
            syncStatus = .synced
            lastSyncDate = Date()
        } else {
            // Restore from backup on failure
            _ = PersistenceService.loadAll(into: self)
            syncStatus = .error(cloudKit.lastSyncError ?? "Fetch failed")
        }
        isSyncing = false
    }

    /// Saves locally with debounce — buffers rapid mutations into a single write.
    private var persistWorkItem: DispatchWorkItem?

    private func persistData() {
        persistWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            PersistenceService.saveAll(from: self)
            WidgetBridge.updateWidgets(from: self)
        }
        persistWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    /// Force immediate save (used before cloud sync or app termination).
    func persistNow() {
        persistWorkItem?.cancel()
        PersistenceService.saveAll(from: self)
        WidgetBridge.updateWidgets(from: self)
    }

    /// Hot-reload all collections from the on-disk JSON files. Used by
    /// SnapshotService after a restore to make the UI reflect the new state
    /// without requiring an app restart.
    func reloadFromDisk() {
        _ = PersistenceService.loadAll(into: self)
    }

    // MARK: - CloudKit Sync Helpers

    private func syncRecord<T: CloudKitConvertible>(_ item: T) {
        guard cloudKitAvailable else { return }
        Task {
            let success = await cloudKit.saveRecordReturningSuccess(item)
            if !success { cloudKit.pendingSyncFailures += 1 }
        }
    }

    private func syncChild<T: CloudKitConvertible>(_ item: T, projectID: CKRecord.ID) {
        guard cloudKitAvailable else { return }
        Task {
            let success = await cloudKit.saveChildReturningSuccess(item, parentProjectID: projectID)
            if !success { cloudKit.pendingSyncFailures += 1 }
        }
    }

    private func deleteFromCloud<T: CloudKitConvertible>(_ item: T) {
        guard cloudKitAvailable else { return }
        Task { await cloudKit.deleteRecord(recordType: T.ckRecordType, recordName: item.ckRecordName) }
    }

    func checkCloudKitAvailability() {
        Task {
            cloudKitAvailable = await cloudKit.checkAccountStatus()
            syncStatus = cloudKitAvailable ? .ready : .local
        }
    }

    // MARK: - Audit Logging

    private func logAudit(_ action: AuditAction, type: String, name: String, id: String = "", details: String = "") {
        let entry = AuditEntry(
            action: action,
            entityType: type,
            entityID: id,
            entityDescription: name,
            userIdentifier: cloudKit.userRecordID?.recordName ?? "local",
            userName: cloudKit.isAvailable ? cloudKit.userName : "Local User",
            details: details.isEmpty ? "\(action.rawValue) \(type.lowercased())" : details
        )
        auditLog.append(entry)
        persistData()
    }

    // MARK: - Project Operations

    var activeProjects: [Project] { projects.filter { $0.computedStatus == "Active" } }
    var upcomingProjects: [Project] { projects.filter { $0.computedStatus == "Upcoming" } }
    var completedProjects: [Project] { projects.filter { $0.computedStatus == "Completed" } }

    var totalContractValue: Decimal { projects.reduce(0) { $0 + $1.contractAmount } }
    var totalRevenue: Decimal { projects.reduce(0) { $0 + $1.totalRevenue } }
    var totalProfit: Decimal { projects.reduce(0) { $0 + $1.profit } }
    var totalCosts: Decimal { projects.reduce(0) { $0 + $1.totalCosts } }
    var totalRemainingBalance: Decimal { projects.reduce(0) { $0 + $1.remainingBalance } }

    func addProject(_ project: Project) {
        projects.append(project)
        logAudit(.created, type: "Project", name: project.title)
        syncRecord(project)
    }

    func updateProject(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index] = project
            logAudit(.updated, type: "Project", name: project.title)
            syncRecord(project)
        }
    }

    func deleteProject(_ project: Project) {
        projects.removeAll { $0.id == project.id }
        logAudit(.deleted, type: "Project", name: project.title)
        deleteFromCloud(project)
    }

    // MARK: - Bid Operations

    var pendingBids: [BidProject] { bids.filter { $0.status == .pending } }
    var submittedBids: [BidProject] { bids.filter { $0.status == .submitted } }
    var awardedBids: [BidProject] { bids.filter { $0.status == .awarded } }
    var lostBids: [BidProject] { bids.filter { $0.status == .lost } }

    var totalBidPipeline: Decimal {
        bids.filter { !$0.isLost && !$0.isAwarded }.reduce(0) { $0 + $1.bidAmount }
    }

    var bidWinRate: Double {
        let decided = bids.filter { $0.isAwarded || $0.isLost }
        guard !decided.isEmpty else { return 0 }
        let won = decided.filter { $0.isAwarded }.count
        return Double(won) / Double(decided.count) * 100
    }

    func addBid(_ bid: BidProject) {
        bids.append(bid)
        logAudit(.created, type: "Bid", name: bid.projectName)
        syncRecord(bid)
    }

    func updateBid(_ bid: BidProject) {
        if let index = bids.firstIndex(where: { $0.id == bid.id }) {
            let previous = bids[index]
            bids[index] = bid
            logAudit(.updated, type: "Bid", name: bid.projectName)
            syncRecord(bid)
            // Auto-generate a follow-up task when the bid is submitted or a
            // new touchpoint is logged. Runs on every update so we only need
            // to wire it in one place.
            autoCreateBidFollowUp(previous: previous, current: bid)
        }
    }

    // MARK: - Bid Follow-up Automation

    /// Creates (or updates) a To-Do item for following up on a bid.
    /// Triggered when:
    ///   - A bid transitions from unsubmitted to submitted
    ///   - A new touchpoint is added
    /// Uses `nextFollowUp` as the due date if set, otherwise defaults to 7 days
    /// after the relevant action (submission or last touchpoint).
    ///
    /// Only one open follow-up task exists per bid at a time — if an existing
    /// uncompleted task with category .bidFollowUp matches this bid, we update
    /// its due date and notes in place instead of creating a duplicate.
    private func autoCreateBidFollowUp(previous: BidProject, current: BidProject) {
        // Case 1: bid just submitted
        let wasJustSubmitted = !previous.isSubmitted && current.isSubmitted
        if wasJustSubmitted {
            let baseDate = current.submittedDate ?? Date()
            let defaultFollowUp = Calendar.current.date(byAdding: .day, value: 7, to: baseDate) ?? baseDate
            let dueDate = current.nextFollowUp ?? defaultFollowUp
            let notes = "Bid submitted \(baseDate.shortDate) to \(current.clientName). Follow up on status."
            upsertBidFollowUpTask(bid: current, dueDate: dueDate, notes: notes)
            return
        }

        // Case 2: a new touchpoint was added (compare counts)
        if current.touchpoints.count > previous.touchpoints.count {
            // Use the newest touchpoint as the anchor
            guard let latest = current.touchpoints.sorted(by: { $0.date > $1.date }).first else { return }
            let defaultFollowUp = Calendar.current.date(byAdding: .day, value: 7, to: latest.date) ?? latest.date
            let dueDate = current.nextFollowUp ?? defaultFollowUp
            let summary = latest.notes.isEmpty
                ? "After \(latest.type.rawValue) on \(latest.date.shortDate)."
                : "After \(latest.type.rawValue) on \(latest.date.shortDate): \(latest.notes)"
            let notes = "\(summary) Follow up on \(current.clientName)."
            upsertBidFollowUpTask(bid: current, dueDate: dueDate, notes: notes)
        }
    }

    /// Looks up an existing open follow-up task for this bid. If found, updates
    /// its due date + notes. Otherwise creates a new one.
    private func upsertBidFollowUpTask(bid: BidProject, dueDate: Date, notes: String) {
        let bidIDString = bid.id.recordName
        if let idx = todos.firstIndex(where: {
            $0.relatedBidID == bidIDString
                && $0.category == .bidFollowUp
                && !$0.isCompleted
        }) {
            var updated = todos[idx]
            updated.dueDate = dueDate
            updated.notes = notes
            updateTodo(updated)
        } else {
            let todo = TodoItem(
                title: "Follow up on bid: \(bid.projectName)",
                notes: notes,
                dueDate: dueDate,
                priority: .medium,
                category: .bidFollowUp,
                relatedBidID: bidIDString
            )
            addTodo(todo)
        }
    }

    func deleteBid(_ bid: BidProject) {
        bids.removeAll { $0.id == bid.id }
        logAudit(.deleted, type: "Bid", name: bid.projectName)
        deleteFromCloud(bid)
    }

    func addAttachment(_ attachment: Attachment, to bidID: CKRecord.ID) {
        guard let index = bids.firstIndex(where: { $0.id == bidID }) else { return }
        bids[index].attachments.append(attachment)
        logAudit(.created, type: "Attachment", name: attachment.filename, details: "Uploaded to \(bids[index].projectName)")
        syncRecord(bids[index])
    }

    func removeAttachment(_ attachment: Attachment, from bidID: CKRecord.ID) {
        guard let index = bids.firstIndex(where: { $0.id == bidID }) else { return }
        let bidName = bids[index].projectName
        FileStorageService.deleteFile(attachment)
        bids[index].attachments.removeAll { $0.id == attachment.id }
        logAudit(.deleted, type: "Attachment", name: attachment.filename, details: "Removed from \(bidName)")
        syncRecord(bids[index])
    }

    func convertBidToProject(_ bid: BidProject, contractAmount: Decimal) -> Project {
        let project = Project(
            clientRef: bid.clientRef,
            title: bid.projectName,
            location: bid.address,
            contractAmount: contractAmount,
            status: "Active",
            balanceSummary: ProjectBalanceSummary(contractAmount: contractAmount),
            originalBidID: bid.recordID.recordName
        )
        addProject(project)
        var updatedBid = bid
        updatedBid.awardedProjectID = project.id.recordName
        updateBid(updatedBid)
        logAudit(.created, type: "Project", name: bid.projectName, details: "Converted from bid")
        return project
    }

    // MARK: - Change Order Operations

    func changeOrders(for projectID: CKRecord.ID) -> [ChangeOrder] {
        changeOrders[projectID] ?? []
    }

    func addChangeOrder(_ co: ChangeOrder, to projectID: CKRecord.ID) {
        var list = changeOrders[projectID] ?? []
        list.append(co)
        changeOrders[projectID] = list
        recalculateBalance(for: projectID)
        logAudit(.created, type: "Change Order", name: "CO #\(co.number): \(co.description)", details: co.amount.currencyFormatted)
        syncChild(co, projectID: projectID)
    }

    func updateChangeOrder(_ co: ChangeOrder, in projectID: CKRecord.ID) {
        guard var list = changeOrders[projectID],
              let idx = list.firstIndex(where: { $0.id == co.id }) else { return }
        list[idx] = co
        changeOrders[projectID] = list
        recalculateBalance(for: projectID)
        logAudit(.updated, type: "Change Order", name: "CO #\(co.number): \(co.description)")
        syncChild(co, projectID: projectID)
    }

    func deleteChangeOrder(_ co: ChangeOrder, from projectID: CKRecord.ID) {
        changeOrders[projectID]?.removeAll { $0.id == co.id }
        recalculateBalance(for: projectID)
        logAudit(.deleted, type: "Change Order", name: "CO #\(co.number): \(co.description)")
        deleteFromCloud(co)
    }

    // MARK: - Payment Operations

    func payments(for projectID: CKRecord.ID) -> [Payment] {
        payments[projectID] ?? []
    }

    func addPayment(_ payment: Payment, to projectID: CKRecord.ID) {
        var list = payments[projectID] ?? []
        list.append(payment)
        payments[projectID] = list
        recalculateBalance(for: projectID)
        logAudit(.created, type: "Payment", name: payment.amount.currencyFormatted, details: payment.notes)
        syncChild(payment, projectID: projectID)
    }

    func deletePayment(_ payment: Payment, from projectID: CKRecord.ID) {
        payments[projectID]?.removeAll { $0.id == payment.id }
        recalculateBalance(for: projectID)
        logAudit(.deleted, type: "Payment", name: payment.amount.currencyFormatted)
        deleteFromCloud(payment)
    }

    // MARK: - Payroll Operations

    func payrollEntries(for projectID: CKRecord.ID) -> [PayrollEntry] {
        payrollEntries[projectID] ?? []
    }

    func addPayrollEntry(_ entry: PayrollEntry, to projectID: CKRecord.ID) {
        var list = payrollEntries[projectID] ?? []
        list.append(entry)
        payrollEntries[projectID] = list
        recalculateBalance(for: projectID)
        logAudit(.created, type: "Payroll Entry", name: entry.weekDateRange, details: "\(entry.totalHours.decimalFormatted) hrs, \(entry.totalAmount.currencyFormatted)")
        syncChild(entry, projectID: projectID)
    }

    func deletePayrollEntry(_ entry: PayrollEntry, from projectID: CKRecord.ID) {
        payrollEntries[projectID]?.removeAll { $0.id == entry.id }
        recalculateBalance(for: projectID)
        logAudit(.deleted, type: "Payroll Entry", name: entry.weekDateRange)
        deleteFromCloud(entry)
    }

    // MARK: - Cost Operations

    func costs(for projectID: CKRecord.ID) -> [Cost] {
        costs[projectID] ?? []
    }

    func addCost(_ cost: Cost, to projectID: CKRecord.ID) {
        var list = costs[projectID] ?? []
        list.append(cost)
        costs[projectID] = list
        recalculateBalance(for: projectID)
        logAudit(.created, type: "Cost", name: cost.description, details: "\(cost.category.displayName) — \(cost.amount.currencyFormatted)")
        syncChild(cost, projectID: projectID)
    }

    func deleteCost(_ cost: Cost, from projectID: CKRecord.ID) {
        costs[projectID]?.removeAll { $0.id == cost.id }
        recalculateBalance(for: projectID)
        logAudit(.deleted, type: "Cost", name: cost.description)
        deleteFromCloud(cost)
    }

    func updateCost(_ cost: Cost, in projectID: CKRecord.ID) {
        guard var list = costs[projectID],
              let index = list.firstIndex(where: { $0.id == cost.id }) else { return }
        list[index] = cost
        costs[projectID] = list
        recalculateBalance(for: projectID)
        logAudit(.updated, type: "Cost", name: cost.description,
                 details: "\(cost.category.displayName) — \(cost.amount.currencyFormatted)")
        syncChild(cost, projectID: projectID)
    }

    // MARK: - Balance Recalculation

    func recalculateAllBalances() {
        for project in projects {
            recalculateBalance(for: project.id)
        }
    }

    func recalculateBalance(for projectID: CKRecord.ID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let cos = changeOrders[projectID] ?? []
        let pmts = payments[projectID] ?? []
        let payroll = payrollEntries[projectID] ?? []
        let csts = costs[projectID] ?? []

        // Include timesheet labor costs linked to this project
        let timesheetLabor = timesheetEntries
            .filter { $0.projectRef == projectID.recordName }
            .reduce(Decimal.zero) { $0 + $1.totalPay }

        projects[index].balanceSummary = ProjectBalanceSummary(
            contractAmount: projects[index].contractAmount,
            changeOrderTotal: cos.reduce(0) { $0 + $1.amount },
            paymentsTotal: pmts.reduce(0) { $0 + $1.amount },
            costTotal: csts.reduce(0) { $0 + $1.amount },
            payrollTotal: payroll.reduce(0) { $0 + $1.totalAmount } + timesheetLabor
        )
    }

    // MARK: - Employee Operations

    var activeEmployees: [Employee] { employees.filter { $0.isActive } }
    var foremen: [Employee] { employees.filter { $0.isForeman && $0.isActive } }

    func addEmployee(_ employee: Employee) {
        employees.append(employee)
        logAudit(.created, type: "Employee", name: employee.fullName, details: employee.employeeType.displayName)
        syncRecord(employee)
    }

    func updateEmployee(_ employee: Employee) {
        if let index = employees.firstIndex(where: { $0.id == employee.id }) {
            employees[index] = employee
            logAudit(.updated, type: "Employee", name: employee.fullName)
            syncRecord(employee)
        }
    }

    func deleteEmployee(_ employee: Employee) {
        employees.removeAll { $0.id == employee.id }
        logAudit(.deleted, type: "Employee", name: employee.fullName)
        deleteFromCloud(employee)
    }

    func nextEmployeeID() -> String {
        let maxNum = employees.compactMap { id -> Int? in
            let parts = id.employeeID.split(separator: "-")
            guard parts.count == 2 else { return nil }
            return Int(parts[1])
        }.max() ?? 0
        return String(format: "JRF-%03d", maxNum + 1)
    }

    // MARK: - Todo Operations

    var activeTodos: [TodoItem] { todos.filter { !$0.isCompleted } }
    var completedTodos: [TodoItem] { todos.filter { $0.isCompleted } }
    var overdueTodos: [TodoItem] { todos.filter { $0.isOverdue } }

    func addTodo(_ todo: TodoItem) {
        todos.append(todo)
        logAudit(.created, type: "Todo", name: todo.title)
        syncRecord(todo)
    }

    func updateTodo(_ todo: TodoItem) {
        if let index = todos.firstIndex(where: { $0.id == todo.id }) {
            todos[index] = todo
            logAudit(.updated, type: "Todo", name: todo.title)
            syncRecord(todo)
        }
    }

    func toggleTodo(_ todo: TodoItem) {
        guard let index = todos.firstIndex(where: { $0.id == todo.id }) else { return }
        todos[index].isCompleted.toggle()
        todos[index].completedDate = todos[index].isCompleted ? Date() : nil
        logAudit(.updated, type: "Todo", name: todo.title, details: todos[index].isCompleted ? "Completed" : "Reopened")
        syncRecord(todos[index])
    }

    func deleteTodo(_ todo: TodoItem) {
        todos.removeAll { $0.id == todo.id }
        logAudit(.deleted, type: "Todo", name: todo.title)
        deleteFromCloud(todo)
    }

    // MARK: - Calendar Operations

    var upcomingEvents: [CalendarEvent] { calendarEvents.filter { $0.isUpcoming }.sorted { $0.startDate < $1.startDate } }
    var todayEvents: [CalendarEvent] { calendarEvents.filter { $0.isToday } }

    func events(for date: Date) -> [CalendarEvent] {
        calendarEvents.filter { Calendar.current.isDate($0.startDate, inSameDayAs: date) }
    }

    func addEvent(_ event: CalendarEvent) {
        calendarEvents.append(event)
        logAudit(.created, type: "Calendar Event", name: event.title)
        syncRecord(event)
    }

    func updateEvent(_ event: CalendarEvent) {
        if let index = calendarEvents.firstIndex(where: { $0.id == event.id }) {
            calendarEvents[index] = event
            logAudit(.updated, type: "Calendar Event", name: event.title)
            syncRecord(event)
        }
    }

    func deleteEvent(_ event: CalendarEvent) {
        calendarEvents.removeAll { $0.id == event.id }
        logAudit(.deleted, type: "Calendar Event", name: event.title)
        deleteFromCloud(event)
    }

    // MARK: - Client Operations

    func addClient(_ client: Client) {
        clients.append(client)
        logAudit(.created, type: "Client", name: client.name, details: client.preferredRateType.displayName)
        syncRecord(client)
    }

    func client(for ref: CKRecord.Reference?) -> Client? {
        guard let ref = ref else { return nil }
        return clients.first { $0.id == ref.recordID }
    }

    func updateClient(_ client: Client) {
        if let index = clients.firstIndex(where: { $0.id == client.id }) {
            clients[index] = client
            logAudit(.updated, type: "Client", name: client.name)
            syncRecord(client)
        }
    }

    func deleteClient(_ client: Client) {
        clients.removeAll { $0.id == client.id }
        logAudit(.deleted, type: "Client", name: client.name)
        deleteFromCloud(client)
    }

    var subcontractorClients: [Client] { clients.filter { $0.preferredRateType == .subcontractor } }
    var gcClients: [Client] { clients.filter { $0.preferredRateType == .generalContractor } }

    func projects(for client: Client) -> [Project] {
        projects.filter {
            $0.clientRef?.recordID == client.id ||
            $0.gcClientRef?.recordID == client.id ||
            $0.subClientRef?.recordID == client.id
        }
    }

    func bids(for client: Client) -> [BidProject] {
        bids.filter { $0.clientRef?.recordID == client.id }
    }

    func clientName(for project: Project) -> String? {
        // Return both client names if both are set
        let gc = client(for: project.gcClientRef)
        let sub = client(for: project.subClientRef)
        let legacy = client(for: project.clientRef)

        var names: [String] = []
        if let gc = gc { names.append(gc.name) }
        if let sub = sub { names.append(sub.name) }
        if names.isEmpty, let legacy = legacy { names.append(legacy.name) }
        return names.isEmpty ? nil : names.joined(separator: " / ")
    }

    func gcClient(for project: Project) -> Client? {
        client(for: project.gcClientRef) ??
        (client(for: project.clientRef).flatMap { $0.preferredRateType == .generalContractor ? $0 : nil })
    }

    func subClient(for project: Project) -> Client? {
        client(for: project.subClientRef) ??
        (client(for: project.clientRef).flatMap { $0.preferredRateType == .subcontractor ? $0 : nil })
    }

    /// Default bill-to for a project. When a project has both a GC and a Sub
    /// (i.e. J&R is working under another sub on the GC's job), invoices go to
    /// the sub by default — they're who's writing J&R the check. If only one
    /// client is set, that one wins. Falls back to the legacy primary client.
    func defaultBillToClient(for project: Project) -> Client? {
        let sub = subClient(for: project)
        let gc = gcClient(for: project)
        if sub != nil && gc != nil { return sub }
        return sub ?? gc ?? client(for: project.clientRef)
    }

    /// All clients eligible to be selected as the bill-to on a project's
    /// invoice. De-duplicated; preserves Sub-then-GC order so the sub appears
    /// first in pickers (matches the default).
    func billToCandidates(for project: Project) -> [Client] {
        let candidates: [Client?] = [
            subClient(for: project),
            gcClient(for: project),
            client(for: project.clientRef)
        ]
        var seen = Set<CKRecord.ID>()
        var result: [Client] = []
        for candidate in candidates.compactMap({ $0 }) where seen.insert(candidate.id).inserted {
            result.append(candidate)
        }
        return result
    }

    /// The client an invoice was billed to, looked up by its persisted ID.
    /// Returns nil for legacy invoices that pre-date `billToClientID`.
    func billToClient(for invoice: Invoice) -> Client? {
        guard let recordName = invoice.billToClientID else { return nil }
        return clients.first { $0.id.recordName == recordName }
    }

    // MARK: - Per-Client Billing Aggregates

    /// All invoices billed to this client across every project, paired with the
    /// project they belong to. Sorted newest-first by sent date.
    func invoices(billedTo client: Client) -> [(invoice: Invoice, projectID: CKRecord.ID, projectTitle: String)] {
        let recordName = client.id.recordName
        return allInvoices
            .filter { $0.invoice.billToClientID == recordName }
            .sorted { ($0.invoice.sentDate ?? .distantFuture) > ($1.invoice.sentDate ?? .distantFuture) }
    }

    /// Total invoiced (net of retainage withheld) to this client.
    func totalInvoiced(billedTo client: Client) -> Decimal {
        invoices(billedTo: client).reduce(Decimal(0)) { $0 + $1.invoice.netAmountDue }
    }

    /// Total payments received against invoices billed to this client.
    func totalPaid(billedTo client: Client) -> Decimal {
        invoices(billedTo: client).reduce(Decimal(0)) { acc, entry in
            acc + totalPaid(for: entry.invoice.id)
        }
    }

    /// Outstanding balance owed by this client across all of their invoices.
    func outstandingBalance(billedTo client: Client) -> Decimal {
        totalInvoiced(billedTo: client) - totalPaid(billedTo: client)
    }

    /// Invoices with no persisted bill-to client. These are typically legacy
    /// invoices created before per-client tracking landed; they're surfaced in
    /// a dedicated "Not Assigned" bucket so AR doesn't lose them.
    func unassignedInvoices() -> [(invoice: Invoice, projectID: CKRecord.ID, projectTitle: String)] {
        allInvoices
            .filter { $0.invoice.billToClientID == nil }
            .sorted { ($0.invoice.sentDate ?? .distantFuture) > ($1.invoice.sentDate ?? .distantFuture) }
    }

    func totalUnassignedInvoiced() -> Decimal {
        unassignedInvoices().reduce(Decimal(0)) { $0 + $1.invoice.netAmountDue }
    }

    func totalUnassignedPaid() -> Decimal {
        unassignedInvoices().reduce(Decimal(0)) { acc, entry in
            acc + totalPaid(for: entry.invoice.id)
        }
    }

    func unassignedOutstandingBalance() -> Decimal {
        totalUnassignedInvoiced() - totalUnassignedPaid()
    }

    // MARK: - Equipment Rental Operations

    func rentals(for projectID: CKRecord.ID) -> [EquipmentRental] {
        equipmentRentals[projectID] ?? []
    }

    func activeRentals(for projectID: CKRecord.ID) -> [EquipmentRental] {
        rentals(for: projectID).filter { $0.isActive }
    }

    func closedRentals(for projectID: CKRecord.ID) -> [EquipmentRental] {
        rentals(for: projectID).filter { !$0.isActive }
    }

    func addRental(_ rental: EquipmentRental, to projectID: CKRecord.ID) {
        var list = equipmentRentals[projectID] ?? []
        list.append(rental)
        equipmentRentals[projectID] = list
        logAudit(.created, type: "Equipment Rental", name: rental.equipmentName, details: "Started \(rental.startDate.shortDate)")
        syncChild(rental, projectID: projectID)
    }

    func closeRental(_ rental: EquipmentRental, endDate: Date, fuelGallons: Decimal = 0, fuelPricePerGallon: Decimal = 0, in projectID: CKRecord.ID) {
        guard var list = equipmentRentals[projectID],
              let idx = list.firstIndex(where: { $0.id == rental.id }) else { return }

        var updated = rental
        updated.endDate = endDate
        updated.fuelGallons = fuelGallons
        updated.fuelPricePerGallon = fuelPricePerGallon

        let days = updated.rentalDays ?? 1
        let detail = updated.detailedCost(forDays: days, fuelGal: fuelGallons, fuelPrice: fuelPricePerGallon)
        updated.calculatedCost = detail.subtotal
        updated.costBreakdown = detail.breakdown

        // Build description with all line items
        var desc = "Equipment Rental: \(updated.equipmentName) — \(detail.breakdown)"
        desc += " | Env \(detail.environmentalFee.currencyFormatted)"
        desc += " | Inv Tax \(detail.dealerInventoryTax.currencyFormatted)"
        if detail.deliveryCharges > 0 { desc += " | Transport \(detail.deliveryCharges.currencyFormatted)" }
        if detail.fuelCharge > 0 { desc += " | Fuel \(detail.fuelCharge.currencyFormatted)" }
        desc += " | Sales Tax \(detail.salesTax.currencyFormatted)"

        let cost = Cost(
            category: .machinery,
            description: desc,
            amount: detail.subtotal,
            date: endDate
        )
        updated.linkedCostID = cost.id

        list[idx] = updated
        equipmentRentals[projectID] = list

        addCost(cost, to: projectID)
    }

    var allActiveRentalCount: Int {
        equipmentRentals.values.flatMap { $0 }.filter { $0.isActive }.count
    }

    func deleteRental(_ rental: EquipmentRental, from projectID: CKRecord.ID) {
        // If closed, also remove linked cost from local AND cloud
        if let costID = rental.linkedCostID,
           let linkedCost = costs[projectID]?.first(where: { $0.id == costID }) {
            costs[projectID]?.removeAll { $0.id == costID }
            recalculateBalance(for: projectID)
            deleteFromCloud(linkedCost)
        }
        equipmentRentals[projectID]?.removeAll { $0.id == rental.id }
        logAudit(.deleted, type: "Equipment Rental", name: rental.equipmentName)
        deleteFromCloud(rental)
    }

    // MARK: - Gantt Task Operations

    func addGanttTask(_ task: GanttTask) {
        ganttTasks.append(task)
        logAudit(.created, type: "Gantt Task", name: task.name)
        syncRecord(task)
    }

    func updateGanttTask(_ task: GanttTask) {
        if let index = ganttTasks.firstIndex(where: { $0.id == task.id }) {
            ganttTasks[index] = task
            logAudit(.updated, type: "Gantt Task", name: task.name)
            syncRecord(task)
        }
    }

    func deleteGanttTask(_ task: GanttTask) {
        ganttTasks.removeAll { $0.id == task.id }
        logAudit(.deleted, type: "Gantt Task", name: task.name)
        deleteFromCloud(task)
    }

    /// Swap `task`'s sortOrder with the entry directly above it in
    /// `visibleTasks`. The visible list (after filtering/sort) is what the
    /// user sees, so swapping by visual neighbor matches their intent even
    /// when other projects' tasks have intervening sortOrder values.
    func moveGanttTaskUp(_ task: GanttTask, in visibleTasks: [GanttTask]) {
        guard let idx = visibleTasks.firstIndex(where: { $0.id == task.id }), idx > 0 else { return }
        swapGanttSortOrder(task, with: visibleTasks[idx - 1])
    }

    func moveGanttTaskDown(_ task: GanttTask, in visibleTasks: [GanttTask]) {
        guard let idx = visibleTasks.firstIndex(where: { $0.id == task.id }),
              idx < visibleTasks.count - 1 else { return }
        swapGanttSortOrder(task, with: visibleTasks[idx + 1])
    }

    private func swapGanttSortOrder(_ a: GanttTask, with b: GanttTask) {
        guard let aIdx = ganttTasks.firstIndex(where: { $0.id == a.id }),
              let bIdx = ganttTasks.firstIndex(where: { $0.id == b.id }) else { return }
        // Tasks can share sortOrder defaults (all zero); if so, seed them
        // from current visible position before swapping so subsequent moves
        // produce visible deltas.
        if ganttTasks[aIdx].sortOrder == ganttTasks[bIdx].sortOrder {
            normalizeGanttSortOrders()
        }
        ganttTasks[aIdx].sortOrder = b.sortOrder == a.sortOrder ? b.sortOrder + 1 : b.sortOrder
        ganttTasks[bIdx].sortOrder = a.sortOrder
        logAudit(.updated, type: "Gantt Task", name: a.name, details: "Reordered")
        syncRecord(ganttTasks[aIdx])
        syncRecord(ganttTasks[bIdx])
    }

    /// Reseeds sortOrder values to match current array order so subsequent
    /// swaps have a unique value to swap against. Idempotent.
    private func normalizeGanttSortOrders() {
        for (i, task) in ganttTasks.enumerated() where task.sortOrder != i {
            ganttTasks[i].sortOrder = i
            syncRecord(ganttTasks[i])
        }
    }

    func generateSampleGanttTasks() {
        for project in projects {
            let tasks = GanttTask.sampleTasks(for: project.id.recordName)
            ganttTasks.append(contentsOf: tasks)
        }
        persistData()
    }

    // MARK: - Pay Application / SOV Operations

    func payApps(for projectID: CKRecord.ID) -> [PayApplication] {
        (payApplications[projectID] ?? []).sorted { $0.applicationNumber < $1.applicationNumber }
    }

    func addPayApplication(_ payApp: PayApplication, to projectID: CKRecord.ID) {
        var list = payApplications[projectID] ?? []
        list.append(payApp)
        payApplications[projectID] = list
        logAudit(.created, type: "Pay App", name: "Application #\(payApp.applicationNumber)", details: "Period to \(payApp.periodTo.shortDate)")
        syncChild(payApp, projectID: projectID)
    }

    func updatePayApplication(_ payApp: PayApplication, in projectID: CKRecord.ID) {
        guard var list = payApplications[projectID],
              let idx = list.firstIndex(where: { $0.id == payApp.id }) else { return }
        list[idx] = payApp
        payApplications[projectID] = list
        logAudit(.updated, type: "Pay App", name: "Application #\(payApp.applicationNumber)")
        syncChild(payApp, projectID: projectID)
    }

    func deletePayApplication(_ payApp: PayApplication, from projectID: CKRecord.ID) {
        payApplications[projectID]?.removeAll { $0.id == payApp.id }
        // Cascade: remove the linked invoice too if one exists
        var linkedInvoice: Invoice?
        if let invoiceID = payApp.linkedInvoiceID {
            linkedInvoice = invoices[projectID]?.first { $0.id == invoiceID }
            invoices[projectID]?.removeAll { $0.id == invoiceID }
        }
        logAudit(.deleted, type: "Pay App", name: "Application #\(payApp.applicationNumber)")
        deleteFromCloud(payApp)
        if let inv = linkedInvoice { deleteFromCloud(inv) }
    }

    // MARK: - Invoice Operations

    func invoices(for projectID: CKRecord.ID) -> [Invoice] {
        (invoices[projectID] ?? []).sorted { $0.sentDate ?? .distantFuture > $1.sentDate ?? .distantFuture }
    }

    /// All invoices across every project. Drives the top-level InvoicesView.
    var allInvoices: [(invoice: Invoice, projectID: CKRecord.ID, projectTitle: String)] {
        var result: [(Invoice, CKRecord.ID, String)] = []
        for project in projects {
            for invoice in invoices[project.id] ?? [] {
                result.append((invoice, project.id, project.title))
            }
        }
        return result
    }

    func addInvoice(_ invoice: Invoice, to projectID: CKRecord.ID) {
        var list = invoices[projectID] ?? []
        list.append(invoice)
        invoices[projectID] = list
        logAudit(.created, type: "Invoice", name: invoice.invoiceNumber, details: "Amount: \(invoice.amount)")
        syncChild(invoice, projectID: projectID)
    }

    func updateInvoice(_ invoice: Invoice, in projectID: CKRecord.ID) {
        guard var list = invoices[projectID],
              let idx = list.firstIndex(where: { $0.id == invoice.id }) else { return }
        list[idx] = invoice
        invoices[projectID] = list
        logAudit(.updated, type: "Invoice", name: invoice.invoiceNumber)
        syncChild(invoice, projectID: projectID)
    }

    func deleteInvoice(_ invoice: Invoice, from projectID: CKRecord.ID) {
        invoices[projectID]?.removeAll { $0.id == invoice.id }
        // Unlink from pay app if this was a pay-app-generated invoice
        var updatedPayApp: PayApplication?
        if let payAppID = invoice.linkedPayAppID {
            if var payApps = payApplications[projectID],
               let idx = payApps.firstIndex(where: { $0.id == payAppID }) {
                payApps[idx].linkedInvoiceID = nil
                updatedPayApp = payApps[idx]
                payApplications[projectID] = payApps
            }
        }
        // Cascade: remove Payment records linked to this invoice across every
        // project so they don't orphan. We also remove the files-on-disk because
        // FileStorageService stores them in a folder keyed by invoice ID.
        var removedPaymentCount = 0
        var removedPayments: [Payment] = []
        for (pid, list) in payments {
            let kept = list.filter { payment in
                if payment.appliedToInvoiceID == invoice.id {
                    // Clean up attached files too
                    for att in payment.attachments {
                        FileStorageService.deleteFile(att)
                    }
                    removedPaymentCount += 1
                    removedPayments.append(payment)
                    return false
                }
                return true
            }
            payments[pid] = kept
        }
        logAudit(
            .deleted,
            type: "Invoice",
            name: invoice.invoiceNumber,
            details: removedPaymentCount > 0 ? "Cascaded \(removedPaymentCount) linked payment(s)" : ""
        )
        deleteFromCloud(invoice)
        if let pa = updatedPayApp { syncChild(pa, projectID: projectID) }
        for p in removedPayments { deleteFromCloud(p) }
    }

    func invoice(for payAppID: UUID, in projectID: CKRecord.ID) -> Invoice? {
        (invoices[projectID] ?? []).first { $0.linkedPayAppID == payAppID }
    }

    /// All payments that were applied to the given invoice across any project.
    func payments(for invoiceID: UUID) -> [Payment] {
        var result: [Payment] = []
        for (_, list) in payments {
            result.append(contentsOf: list.filter { $0.appliedToInvoiceID == invoiceID })
        }
        return result.sorted { $0.date < $1.date }
    }

    func totalPaid(for invoiceID: UUID) -> Decimal {
        payments(for: invoiceID).reduce(Decimal(0)) { $0 + $1.amount }
    }

    func balanceRemaining(for invoice: Invoice) -> Decimal {
        invoice.netAmountDue - totalPaid(for: invoice.id)
    }

    /// Auto-generates an invoice number in the format "{PROJECT-PREFIX}-PA-{###}"
    /// where project prefix = uppercased first word of the project title.
    func suggestedInvoiceNumber(for projectID: CKRecord.ID, type: InvoiceType = .payApplication) -> String {
        let project = projects.first { $0.id == projectID }
        let title = project?.title ?? "INV"
        let prefix = title.components(separatedBy: .whitespaces).first?.uppercased() ?? "INV"
        let typeCode: String
        switch type {
        case .payApplication: typeCode = "PA"
        case .standalone: typeCode = "INV"
        case .retainageRelease: typeCode = "RET"
        }
        let existing = invoices[projectID] ?? []
        let sequence = existing.count + 1
        return String(format: "%@-%@-%03d", prefix, typeCode, sequence)
    }

    /// Creates an Invoice from a PayApplication and links them.
    /// Called from "Mark as Sent" on the pay app row.
    @discardableResult
    func createInvoiceFromPayApp(
        _ payApp: PayApplication,
        in projectID: CKRecord.ID,
        sentDate: Date = Date(),
        termsDays: Int = 30,
        billToClient: Client? = nil
    ) -> Invoice {
        let project = projects.first { $0.id == projectID }
        let resolvedBillTo = billToClient ?? project.flatMap { defaultBillToClient(for: $0) }
        let clientName = resolvedBillTo?.name ?? ""
        let dueDate = Calendar.current.date(byAdding: .day, value: termsDays, to: sentDate)
        let number = suggestedInvoiceNumber(for: projectID, type: payApp.isRetainageRelease ? .retainageRelease : .payApplication)

        let invoice = Invoice(
            invoiceNumber: number,
            type: payApp.isRetainageRelease ? .retainageRelease : .payApplication,
            status: .sent,
            amount: payApp.netAmountThisPeriod,
            retainageHeld: payApp.totalRetainage,
            sentDate: sentDate,
            dueDate: dueDate,
            paymentTermsDays: termsDays,
            linkedPayAppID: payApp.id,
            projectID: projectID.recordName,
            clientName: clientName,
            billToClientID: resolvedBillTo?.id.recordName
        )
        addInvoice(invoice, to: projectID)

        // Back-link the invoice on the pay app, and push the updated pay app
        // to cloud so the iPad sees the linkage too.
        if var list = payApplications[projectID],
           let idx = list.firstIndex(where: { $0.id == payApp.id }) {
            list[idx].linkedInvoiceID = invoice.id
            payApplications[projectID] = list
            syncChild(list[idx], projectID: projectID)
        }
        return invoice
    }

    /// Re-evaluates an invoice's status based on its payment history. Called
    /// after a payment is added/removed. Transitions draft → sent → pendingPayment
    /// → partiallyPaid → paid automatically.
    func refreshInvoiceStatus(_ invoice: Invoice, in projectID: CKRecord.ID) {
        let paid = totalPaid(for: invoice.id)
        var updated = invoice
        if paid >= invoice.netAmountDue && invoice.netAmountDue > 0 {
            updated.status = .paid
            if updated.paidDate == nil { updated.paidDate = Date() }
        } else if paid > 0 {
            updated.status = .partiallyPaid
        } else if invoice.sentDate != nil {
            updated.status = .pendingPayment
        }
        updateInvoice(updated, in: projectID)
    }

    /// Build a new pay application, auto-populating from previous pay apps and change orders
    func buildNewPayApp(for projectID: CKRecord.ID, periodTo: Date, retainageRate: Decimal = 0.10) -> PayApplication {
        let project = projects.first { $0.id == projectID }
        let previousApps = payApps(for: projectID)
        let nextNumber = (previousApps.map(\.applicationNumber).max() ?? 0) + 1
        let cos = changeOrders(for: projectID)

        // Get the most recent pay app to carry forward totals
        let lastApp = previousApps.last

        // Build contract line items from project scope
        var lineItems: [SOVLineItem] = []
        var itemNum = 1

        // If there was a previous pay app, carry forward its line items with updated previous totals
        if let last = lastApp {
            for prevItem in last.lineItems {
                let item = SOVLineItem(
                    itemNumber: itemNum,
                    description: prevItem.description,
                    scheduledValue: prevItem.scheduledValue,
                    previousCompleted: prevItem.totalCompletedToDate,
                    isChangeOrder: prevItem.isChangeOrder,
                    changeOrderID: prevItem.changeOrderID
                )
                lineItems.append(item)
                itemNum += 1
            }

            // Add any NEW change orders not already in the SOV (all COs included regardless of date)
            let existingCOIDs = Set(last.lineItems.compactMap(\.changeOrderID))
            for co in cos where !existingCOIDs.contains(co.id) {
                lineItems.append(SOVLineItem(
                    itemNumber: itemNum,
                    description: "CO #\(co.number): \(co.description)",
                    scheduledValue: co.amount,
                    isChangeOrder: true,
                    changeOrderID: co.id
                ))
                itemNum += 1
            }
        } else {
            // First pay app — start with contract amount as line item 1
            if let p = project {
                lineItems.append(SOVLineItem(
                    itemNumber: 1,
                    description: "Original Contract",
                    scheduledValue: p.contractAmount
                ))
                itemNum = 2
            }

            // Add all existing change orders
            for co in cos {
                lineItems.append(SOVLineItem(
                    itemNumber: itemNum,
                    description: "CO #\(co.number): \(co.description)",
                    scheduledValue: co.amount,
                    isChangeOrder: true,
                    changeOrderID: co.id
                ))
                itemNum += 1
            }
        }

        return PayApplication(
            applicationNumber: nextNumber,
            periodTo: periodTo,
            projectID: projectID.recordName,
            retainageRate: retainageRate,
            lineItems: lineItems
        )
    }

    // MARK: - RFI Operations

    func rfis(for projectID: CKRecord.ID) -> [RFI] {
        (rfis[projectID] ?? []).sorted { $0.number < $1.number }
    }

    func addRFI(_ rfi: RFI, to projectID: CKRecord.ID) {
        var list = rfis[projectID] ?? []
        list.append(rfi)
        rfis[projectID] = list
        logAudit(.created, type: "RFI", name: "RFI #\(rfi.number): \(rfi.subject)", details: rfi.submittedTo)
        persistData()
    }

    func updateRFI(_ rfi: RFI, in projectID: CKRecord.ID) {
        guard var list = rfis[projectID],
              let idx = list.firstIndex(where: { $0.id == rfi.id }) else { return }
        list[idx] = rfi
        rfis[projectID] = list
        logAudit(.updated, type: "RFI", name: "RFI #\(rfi.number)")
        persistData()
    }

    func deleteRFI(_ rfi: RFI, from projectID: CKRecord.ID) {
        rfis[projectID]?.removeAll { $0.id == rfi.id }
        logAudit(.deleted, type: "RFI", name: "RFI #\(rfi.number)")
        persistData()
    }

    func nextRFINumber(for projectID: CKRecord.ID) -> Int {
        (rfis[projectID]?.map(\.number).max() ?? 0) + 1
    }

    // MARK: - Planning Pad Operations

    func planningPad(for date: Date) -> PlanningPad? {
        let cal = Calendar.current
        return planningPads.first { cal.isDate($0.date, inSameDayAs: date) }
    }

    func savePlanningPad(_ pad: PlanningPad) {
        if let idx = planningPads.firstIndex(where: { $0.id == pad.id }) {
            planningPads[idx] = pad
        } else {
            planningPads.append(pad)
        }
        persistData()
    }

    // MARK: - Assistant Message Operations

    func addAssistantMessage(_ message: AssistantMessage) {
        assistantMessages.append(message)
        // Keep last 200 messages to prevent unbounded growth
        if assistantMessages.count > 200 {
            assistantMessages = Array(assistantMessages.suffix(200))
        }
        persistData()
    }

    func clearAssistantMessages() {
        assistantMessages.removeAll()
        persistData()
    }

    // MARK: - Timesheet Operations

    func timesheetEntries(for weekStart: Date) -> [TimesheetEntry] {
        let cal = Calendar.current
        return timesheetEntries.filter { cal.isDate($0.weekStartDate, inSameDayAs: weekStart) }
            .sorted { $0.employeeName < $1.employeeName }
    }

    func addTimesheetEntry(_ entry: TimesheetEntry) {
        timesheetEntries.append(entry)
        logAudit(.created, type: "Timesheet", name: entry.employeeName, details: "\(entry.projectName) — \(entry.weekLabel)")
        recalculateTimesheetProject(entry)
        persistData()
    }

    func updateTimesheetEntry(_ entry: TimesheetEntry) {
        guard let idx = timesheetEntries.firstIndex(where: { $0.id == entry.id }) else { return }
        timesheetEntries[idx] = entry
        recalculateTimesheetProject(entry)
        persistData()
    }

    func deleteTimesheetEntry(_ entry: TimesheetEntry) {
        timesheetEntries.removeAll { $0.id == entry.id }
        logAudit(.deleted, type: "Timesheet", name: entry.employeeName)
        recalculateTimesheetProject(entry)
        persistData()
    }

    private func recalculateTimesheetProject(_ entry: TimesheetEntry) {
        if let project = projects.first(where: { $0.id.recordName == entry.projectRef }) {
            recalculateBalance(for: project.id)
        }
    }

    // MARK: - Crew Preset Operations

    func addCrewPreset(_ preset: CrewPreset) {
        crewPresets.append(preset)
        logAudit(.created, type: "Crew Preset", name: preset.name, details: "\(preset.members.count) member(s)")
        syncRecord(preset)
        persistData()
    }

    func updateCrewPreset(_ preset: CrewPreset) {
        guard let idx = crewPresets.firstIndex(where: { $0.id == preset.id }) else { return }
        crewPresets[idx] = preset
        logAudit(.updated, type: "Crew Preset", name: preset.name)
        syncRecord(preset)
        persistData()
    }

    func deleteCrewPreset(_ preset: CrewPreset) {
        crewPresets.removeAll { $0.id == preset.id }
        logAudit(.deleted, type: "Crew Preset", name: preset.name)
        deleteFromCloud(preset)
        persistData()
    }

    /// Drops one TimesheetEntry per preset member into the given week. Members
    /// whose linked employee already has a row that week are skipped (no
    /// duplicate rows). Returns the number of rows actually added so the UI
    /// can confirm. If `defaultProject` is nil the rows go in with a blank
    /// project — the user fills it in per row.
    @discardableResult
    func applyCrewPreset(
        _ preset: CrewPreset,
        to weekStart: Date,
        defaultProject: Project? = nil
    ) -> Int {
        let existing = timesheetEntries(for: weekStart)
        var added = 0
        for member in preset.members {
            // Skip if this employee is already on the week's roster.
            if let ref = member.employeeRef,
               existing.contains(where: { $0.employeeRef == ref }) {
                continue
            }
            let employee = member.employeeRef.flatMap { ref in
                employees.first { $0.id.uuidString == ref }
            }
            let resolvedName = employee?.fullName ?? member.employeeName
            let resolvedType = employee?.employeeType.rawValue ?? member.employeeType
            let resolvedRate = member.hourlyRateOverride ?? employee?.defaultHourlyRate ?? 0

            let entry = TimesheetEntry(
                employeeName: resolvedName,
                employeeType: resolvedType,
                employeeRef: employee?.id.uuidString ?? "",
                projectName: defaultProject?.title ?? "",
                projectRef: defaultProject?.id.recordName ?? "",
                hourlyRate: resolvedRate,
                mondayHours: member.dailyHours[0],
                tuesdayHours: member.dailyHours[1],
                wednesdayHours: member.dailyHours[2],
                thursdayHours: member.dailyHours[3],
                fridayHours: member.dailyHours[4],
                saturdayHours: member.dailyHours[5],
                sundayHours: member.dailyHours[6],
                perDiem: member.perDiem,
                weekStartDate: weekStart
            )
            addTimesheetEntry(entry)
            added += 1
        }
        logAudit(.created, type: "Crew Preset Apply", name: preset.name, details: "Added \(added) row(s) to week of \(weekStart.shortDate)")
        return added
    }

    func timesheetWeekTotals(for weekStart: Date) -> (hours: Decimal, perDiem: Decimal, pay: Decimal) {
        let entries = timesheetEntries(for: weekStart)
        let hours = entries.reduce(Decimal.zero) { $0 + $1.totalHours }
        let perDiem = entries.reduce(Decimal.zero) { $0 + $1.totalPerDiem }
        let pay = entries.reduce(Decimal.zero) { $0 + $1.totalPay }
        return (hours, perDiem, pay)
    }

    // MARK: - Overhead Operations

    /// Top-level recurring templates (one row per recurring series).
    var overheadRecurringTemplates: [OverheadExpense] {
        overheadExpenses.filter { $0.isRecurringTemplate }
    }

    /// All entries within a given date range (inclusive of both ends).
    func overheadEntries(in range: ClosedRange<Date>) -> [OverheadExpense] {
        overheadExpenses.filter { range.contains($0.date) }
    }

    /// Total overhead amount for the given date range.
    func overheadTotal(in range: ClosedRange<Date>) -> Decimal {
        overheadEntries(in: range).reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// Sum grouped by category for the given date range, largest first.
    func overheadByCategory(in range: ClosedRange<Date>) -> [(OverheadCategory, Decimal)] {
        let entries = overheadEntries(in: range)
        var totals: [OverheadCategory: Decimal] = [:]
        for entry in entries {
            totals[entry.category, default: 0] += entry.amount
        }
        return totals.sorted { $0.value > $1.value }
    }

    /// Returns the allocated share of overhead each project absorbs across the
    /// given range. Uses pro-rata distribution by `Project.contractAmount`.
    /// Company-only expenses (`distributionMode == .companyOnly`) are excluded.
    ///
    /// - Returns: `(total: raw sum for the range, perProject: recordName → share)`
    func allocateOverhead(in range: ClosedRange<Date>) -> (total: Decimal, perProject: [String: Decimal]) {
        var total = Decimal.zero
        var perProject: [String: Decimal] = [:]

        for expense in overheadEntries(in: range) {
            total += expense.amount

            let targets: [Project]
            switch expense.distributionMode {
            case .companyOnly:
                continue
            case .allActive:
                targets = projects.filter { $0.wasActive(on: expense.date) }
            case .specificProjects:
                let ids = Set(expense.distributionProjectIDs)
                targets = projects.filter { ids.contains($0.id.recordName) }
            }

            let totalContract = targets.reduce(Decimal.zero) { $0 + $1.contractAmount }
            guard totalContract > 0, !targets.isEmpty else { continue }

            for project in targets {
                let share = expense.amount * (project.contractAmount / totalContract)
                perProject[project.id.recordName, default: 0] += share
            }
        }
        return (total, perProject)
    }

    func addOverhead(_ expense: OverheadExpense) {
        overheadExpenses.append(expense)
        logAudit(.created, type: "Overhead", name: overheadAuditName(expense))
        syncRecord(expense)
    }

    func updateOverhead(_ expense: OverheadExpense) {
        guard let index = overheadExpenses.firstIndex(where: { $0.id == expense.id }) else { return }
        overheadExpenses[index] = expense
        logAudit(.updated, type: "Overhead", name: overheadAuditName(expense))
        syncRecord(expense)
    }

    func deleteOverhead(_ expense: OverheadExpense) {
        overheadExpenses.removeAll { $0.id == expense.id }
        // Children of a recurring template survive — they're real historical
        // expenses. We just detach them by clearing parentRecurringID so they
        // don't reference a missing parent.
        if expense.isRecurringTemplate {
            let parentName = expense.recordID.recordName
            for i in overheadExpenses.indices where overheadExpenses[i].parentRecurringID == parentName {
                overheadExpenses[i].parentRecurringID = nil
                syncRecord(overheadExpenses[i])
            }
        }
        logAudit(.deleted, type: "Overhead", name: overheadAuditName(expense))
        deleteFromCloud(expense)
    }

    private func overheadAuditName(_ e: OverheadExpense) -> String {
        let label = e.expenseDescription.isEmpty ? e.category.rawValue : e.expenseDescription
        return e.vendor.isEmpty ? label : "\(label) — \(e.vendor)"
    }

    func addOverheadAttachment(_ attachment: Attachment, to expenseID: CKRecord.ID) {
        guard let idx = overheadExpenses.firstIndex(where: { $0.id == expenseID }) else { return }
        overheadExpenses[idx].attachments.append(attachment)
        logAudit(.created, type: "Attachment", name: attachment.filename,
                 details: "Attached to \(overheadAuditName(overheadExpenses[idx]))")
        syncRecord(overheadExpenses[idx])
    }

    func removeOverheadAttachment(_ attachment: Attachment, from expenseID: CKRecord.ID) {
        guard let idx = overheadExpenses.firstIndex(where: { $0.id == expenseID }) else { return }
        overheadExpenses[idx].attachments.removeAll { $0.id == attachment.id }
        FileStorageService.deleteFile(attachment)
        logAudit(.deleted, type: "Attachment", name: attachment.filename)
        syncRecord(overheadExpenses[idx])
    }

    /// Generates missing recurring-overhead instances up through today. Called
    /// from app launch. For each recurring template, walks forward by its
    /// interval and creates a new child (with `recurrence = .none` and
    /// `parentRecurringID` pointing back) for every interval that has elapsed
    /// since the last known occurrence.
    ///
    /// Idempotent: re-running it on the same day is a no-op.
    @discardableResult
    func generateRecurringOverhead(asOf today: Date = Date()) -> Int {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: today)
        var created = 0

        for template in overheadRecurringTemplates {
            let parentName = template.recordID.recordName
            let children = overheadExpenses.filter { $0.parentRecurringID == parentName }
            let lastOccurrence = (children.map(\.date) + [template.date]).max() ?? template.date

            var next = template.recurrence.next(after: lastOccurrence, calendar: cal)
            while let nextDate = next, cal.startOfDay(for: nextDate) <= todayStart {
                let newEntry = OverheadExpense(
                    date: nextDate,
                    amount: template.amount,
                    category: template.category,
                    vendor: template.vendor,
                    expenseDescription: template.expenseDescription,
                    notes: template.notes,
                    recurrence: .none,
                    parentRecurringID: parentName,
                    distributionMode: template.distributionMode,
                    distributionProjectIDs: template.distributionProjectIDs
                )
                overheadExpenses.append(newEntry)
                syncRecord(newEntry)
                created += 1
                next = template.recurrence.next(after: nextDate, calendar: cal)
            }
        }

        if created > 0 {
            logAudit(.created, type: "Overhead",
                     name: "\(created) recurring entries",
                     details: "Auto-generated on \(todayStart.shortDate)")
        }
        return created
    }

    // MARK: - Report Calculations

    var financialSummary: (revenue: Decimal, costs: Decimal, profit: Decimal, margin: Double) {
        let rev = totalRevenue
        let cost = totalCosts
        let prof = totalProfit
        let margin = rev > 0 ? Double(truncating: (prof / rev * 100) as NSDecimalNumber) : 0
        return (rev, cost, prof, margin)
    }
}
