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
        for (_, items) in changeOrders { for co in items { localIDs.insert(co.ckRecordName) } }
        for (_, items) in payments { for p in items { localIDs.insert(p.ckRecordName) } }
        for (_, items) in payrollEntries { for e in items { localIDs.insert(e.ckRecordName) } }
        for (_, items) in costs { for c in items { localIDs.insert(c.ckRecordName) } }
        for (_, items) in equipmentRentals { for r in items { localIDs.insert(r.ckRecordName) } }

        let orphansDeleted = await cloudKit.deleteOrphanedRecords(localIDs: localIDs)
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

    /// Saves locally. Called via logAudit after every mutation.
    private func persistData() {
        PersistenceService.saveAll(from: self)
        WidgetBridge.updateWidgets(from: self)
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
        auditLog.insert(entry, at: 0)
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
            bids[index] = bid
            logAudit(.updated, type: "Bid", name: bid.projectName)
            syncRecord(bid)
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

    // MARK: - Balance Recalculation

    func recalculateBalance(for projectID: CKRecord.ID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let cos = changeOrders[projectID] ?? []
        let pmts = payments[projectID] ?? []
        let payroll = payrollEntries[projectID] ?? []
        let csts = costs[projectID] ?? []

        projects[index].balanceSummary = ProjectBalanceSummary(
            contractAmount: projects[index].contractAmount,
            changeOrderTotal: cos.reduce(0) { $0 + $1.amount },
            paymentsTotal: pmts.reduce(0) { $0 + $1.amount },
            costTotal: csts.reduce(0) { $0 + $1.amount },
            payrollTotal: payroll.reduce(0) { $0 + $1.totalAmount }
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
        desc += " | Tax \(detail.dealerInventoryTax.currencyFormatted)"
        if detail.deliveryCharges > 0 { desc += " | Transport \(detail.deliveryCharges.currencyFormatted)" }
        if detail.fuelCharge > 0 { desc += " | Fuel \(detail.fuelCharge.currencyFormatted)" }

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

    func generateSampleGanttTasks() {
        for project in projects {
            let tasks = GanttTask.sampleTasks(for: project.id.recordName)
            ganttTasks.append(contentsOf: tasks)
        }
        persistData()
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
