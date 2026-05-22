import Foundation
import CloudKit

@MainActor
class CloudKitService {
    private var container: CKContainer?
    private var privateDB: CKDatabase?
    private var sharedDB: CKDatabase?
    let zoneName = "SteelSyncZone"

    private(set) var isAvailable = false
    private(set) var userName = "Local User"
    private(set) var userRecordID: CKRecord.ID?
    var lastSyncError: String?
    var pendingSyncFailures: Int = 0

    static let cloudKitEnabled = true

    // MARK: - Role (owner vs participant in a shared zone)

    enum Role: Equatable {
        case owner
        case participant(ownerRecordName: String)
    }

    private static let roleKey = "SteelSync.CloudKit.Role"
    private static let participantOwnerKey = "SteelSync.CloudKit.ParticipantOwnerName"

    private(set) var role: Role = .owner

    var isParticipant: Bool {
        if case .participant = role { return true } else { return false }
    }

    /// Database to use for all reads/writes given the current role.
    /// Owner → privateDB. Participant → sharedDB.
    private var activeDatabase: CKDatabase? {
        switch role {
        case .owner: return privateDB
        case .participant: return sharedDB
        }
    }

    /// Zone ID for the current role. Owner uses their own zone; participant
    /// uses the owner's zone (same zone name, different owner record name).
    var zoneID: CKRecordZone.ID {
        switch role {
        case .owner:
            return CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        case .participant(let ownerName):
            return CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
        }
    }

    private func loadPersistedRole() {
        let raw = UserDefaults.standard.string(forKey: Self.roleKey) ?? "owner"
        if raw == "participant", let ownerName = UserDefaults.standard.string(forKey: Self.participantOwnerKey) {
            role = .participant(ownerRecordName: ownerName)
        } else {
            role = .owner
        }
    }

    /// Update the role and persist it. Called by the share-accept flow
    /// (step 4) to switch this device into participant mode after the user
    /// taps a SteelSync share URL.
    func setRole(_ newRole: Role) {
        role = newRole
        switch newRole {
        case .owner:
            UserDefaults.standard.set("owner", forKey: Self.roleKey)
            UserDefaults.standard.removeObject(forKey: Self.participantOwnerKey)
        case .participant(let ownerName):
            UserDefaults.standard.set("participant", forKey: Self.roleKey)
            UserDefaults.standard.set(ownerName, forKey: Self.participantOwnerKey)
        }
    }

    init() {
        loadPersistedRole()
    }

    private func initializeContainer() -> Bool {
        guard Self.cloudKitEnabled else { return false }
        guard container == nil else { return true }
        guard FileManager.default.ubiquityIdentityToken != nil else {
            print("[CloudKit] iCloud not available. Running in local mode.")
            return false
        }
        let c = CKContainer(identifier: "iCloud.com.jrfv.SteelSync")
        container = c
        privateDB = c.privateCloudDatabase
        sharedDB = c.sharedCloudDatabase
        return true
    }

    // MARK: - Account Status

    func checkAccountStatus() async -> Bool {
        guard initializeContainer(), let container = container else {
            isAvailable = false
            return false
        }
        do {
            let status = try await container.accountStatus()
            isAvailable = (status == .available)
            if isAvailable { await discoverUserIdentity() }
            return isAvailable
        } catch {
            isAvailable = false
            return false
        }
    }

    private func discoverUserIdentity() async {
        guard let container = container else { return }
        do {
            let recordID = try await container.userRecordID()
            userRecordID = recordID
            userName = recordID.recordName.prefix(8) == "__default" ? "Owner" : String(recordID.recordName.prefix(12))
        } catch { userName = "Unknown User" }
    }

    // MARK: - Zone Setup

    /// Owner-only: create the zone in the user's private database.
    /// Participants receive the zone via share acceptance; calling this in
    /// participant mode is a no-op (and would fail server-side anyway).
    func setupZone() async throws {
        guard role == .owner, let db = privateDB else { return }
        do {
            _ = try await db.save(CKRecordZone(zoneID: zoneID))
        } catch { /* zone may already exist */ }
    }

    // MARK: - Per-Record CRUD

    func saveRecord<T: CloudKitConvertible>(_ item: T) async {
        guard let db = activeDatabase else { return }
        let record = item.toCKRecord(in: zoneID)
        do {
            _ = try await db.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                let fresh = item.toCKRecord(in: zoneID)
                for key in fresh.allKeys() { serverRecord[key] = fresh[key] }
                do {
                    _ = try await db.save(serverRecord)
                } catch {
                    print("[CloudKit] Conflict resolution failed for \(T.ckRecordType): \(error.localizedDescription)")
                }
            }
        } catch {
            print("[CloudKit] Save \(T.ckRecordType) failed: \(error.localizedDescription)")
        }
    }

    func saveChildRecord<T: CloudKitConvertible>(_ item: T, parentProjectID: CKRecord.ID) async {
        guard let db = activeDatabase else { return }
        let record = item.toCKRecord(in: zoneID)
        let parentRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: parentProjectID.recordName, zoneID: zoneID), action: .none)
        record["projectRef"] = parentRef
        do {
            _ = try await db.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                let fresh = item.toCKRecord(in: zoneID)
                for key in fresh.allKeys() { serverRecord[key] = fresh[key] }
                serverRecord["projectRef"] = parentRef
                do {
                    _ = try await db.save(serverRecord)
                } catch {
                    print("[CloudKit] Child conflict resolution failed for \(T.ckRecordType): \(error.localizedDescription)")
                }
            }
        } catch {
            print("[CloudKit] Save child \(T.ckRecordType) failed: \(error.localizedDescription)")
        }
    }

    func deleteRecord(recordType: String, recordName: String) async {
        _ = await deleteRecordReturningSuccess(recordType: recordType, recordName: recordName)
    }

    /// Delete and report success. A "record not found" is treated as success
    /// (the record is already gone — the tombstone can be cleared). Returns
    /// false only when the delete genuinely failed and should be retried.
    func deleteRecordReturningSuccess(recordType: String, recordName: String) async -> Bool {
        guard let db = activeDatabase else { return false }
        let id = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        do {
            try await db.deleteRecord(withID: id)
            return true
        } catch let error as CKError where error.code == .unknownItem {
            return true
        } catch {
            print("[CloudKit] Delete \(recordType)/\(recordName) failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Zone-Based Fetch (no queryable indexes required)

    /// Fetch ALL records in the zone. Tries async API first, falls back to operation-based fetch.
    func fetchAllRecordsInZone() async throws -> [CKRecord] {
        guard let db = activeDatabase else { throw CloudKitError.notConfigured }

        // Try the modern async API first
        let changes = try await db.recordZoneChanges(inZoneWith: zoneID, since: nil)
        var records: [CKRecord] = []
        var failures = 0
        for (id, result) in changes.modificationResultsByID {
            switch result {
            case .success(let modification):
                records.append(modification.record)
            case .failure(let error):
                failures += 1
                print("[CloudKit] Record \(id.recordName) fetch error: \(error.localizedDescription)")
            }
        }
        print("[CloudKit] Zone fetch: \(changes.modificationResultsByID.count) results, \(records.count) records, \(failures) failures, \(changes.deletions.count) deletions")

        // If async API returned 0, fall back to operation-based fetch
        if records.isEmpty {
            print("[CloudKit] Async API returned 0 records, trying operation-based fallback...")
            records = try await fetchAllRecordsViaOperation(db: db)
            print("[CloudKit] Operation fallback fetched \(records.count) records")
        }

        return records
    }

    /// Fallback: fetch all records using CKFetchRecordZoneChangesOperation (more reliable cross-platform)
    private func fetchAllRecordsViaOperation(db: CKDatabase) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration(
                previousServerChangeToken: nil
            )
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )

            let lock = NSLock()
            var records: [CKRecord] = []

            operation.recordWasChangedBlock = { _, result in
                if let record = try? result.get() {
                    lock.lock()
                    records.append(record)
                    lock.unlock()
                }
            }

            operation.fetchRecordZoneChangesResultBlock = { result in
                lock.lock()
                let finalRecords = records
                lock.unlock()
                switch result {
                case .success:
                    print("[CloudKit] Operation fetch complete: \(finalRecords.count) records")
                    continuation.resume(returning: finalRecords)
                case .failure(let error):
                    print("[CloudKit] Operation fetch failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }

            db.add(operation)
        }
    }

    /// Check if cloud zone has any data (used for initial sync decision)
    func hasCloudData() async -> Bool {
        do {
            let records = try await fetchAllRecordsInZone()
            return !records.isEmpty
        } catch {
            print("[CloudKit] hasCloudData check failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Full Sync (fetch all from cloud, rebuild local state)

    /// Fetches all data from CloudKit into the DataStore via zone fetch. Returns true on success.
    func fetchAllDataFromCloud(into store: DataStore) async -> Bool {
        do {
            let allRecords = try await fetchAllRecordsInZone()

            // Group by record type
            var byType: [String: [CKRecord]] = [:]
            for record in allRecords {
                byType[record.recordType, default: []].append(record)
            }

            // Standalone records
            store.projects = (byType[Project.ckRecordType] ?? []).compactMap { Project.from($0) }
            store.clients = (byType[Client.ckRecordType] ?? []).compactMap { Client.from($0) }
            store.bids = (byType[BidProject.ckRecordType] ?? []).compactMap { BidProject.from($0) }
            store.employees = (byType[Employee.ckRecordType] ?? []).compactMap { Employee.from($0) }
            store.todos = (byType[TodoItem.ckRecordType] ?? []).compactMap { TodoItem.from($0) }
            store.calendarEvents = (byType[CalendarEvent.ckRecordType] ?? []).compactMap { CalendarEvent.from($0) }
            store.ganttTasks = (byType[GanttTask.ckRecordType] ?? []).compactMap { GanttTask.from($0) }
            store.auditLog = (byType[AuditEntry.ckRecordType] ?? []).compactMap { AuditEntry.from($0) }
            store.timesheetEntries = (byType[TimesheetEntry.ckRecordType] ?? []).compactMap { TimesheetEntry.from($0) }
            store.crewPresets = (byType[CrewPreset.ckRecordType] ?? []).compactMap { CrewPreset.from($0) }
            store.overheadExpenses = (byType[OverheadExpense.ckRecordType] ?? []).compactMap { OverheadExpense.from($0) }

            // Child records — extract projectRef and group by parent
            store.changeOrders = groupChildRecords(byType[ChangeOrder.ckRecordType] ?? [], as: ChangeOrder.self)
            store.payments = groupChildRecords(byType[Payment.ckRecordType] ?? [], as: Payment.self)
            store.payrollEntries = groupChildRecords(byType[PayrollEntry.ckRecordType] ?? [], as: PayrollEntry.self)
            store.costs = groupChildRecords(byType[Cost.ckRecordType] ?? [], as: Cost.self)
            store.equipmentRentals = groupChildRecords(byType[EquipmentRental.ckRecordType] ?? [], as: EquipmentRental.self)
            store.rfis = groupChildRecords(byType[RFI.ckRecordType] ?? [], as: RFI.self)
            store.dailyLogs = groupChildRecords(byType[DailyLog.ckRecordType] ?? [], as: DailyLog.self)
            store.payApplications = groupChildRecords(byType[PayApplication.ckRecordType] ?? [], as: PayApplication.self)
            store.invoices = groupChildRecords(byType[Invoice.ckRecordType] ?? [], as: Invoice.self)

            // Persist locally as cache
            PersistenceService.saveAll(from: store)
            lastSyncError = nil
            print("[CloudKit] Pull complete: \(store.projects.count) projects, \(store.clients.count) clients, \(store.bids.count) bids")
            return true
        } catch let ckError as CKError where ckError.code == .notAuthenticated {
            isAvailable = false
            lastSyncError = "Not signed into iCloud. Open System Settings → Apple Account → iCloud and sign in."
            print("[CloudKit] fetchAllDataFromCloud failed: Not authenticated. Sign into iCloud in System Settings.")
            return false
        } catch {
            lastSyncError = error.localizedDescription
            print("[CloudKit] fetchAllDataFromCloud failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Convert child CKRecords into a dictionary grouped by parent project ID
    private func groupChildRecords<T: CloudKitConvertible>(_ records: [CKRecord], as type: T.Type) -> [CKRecord.ID: [T]] {
        var dict: [CKRecord.ID: [T]] = [:]
        for record in records {
            guard let item = T.from(record),
                  let ref = record["projectRef"] as? CKRecord.Reference else { continue }
            dict[ref.recordID, default: []].append(item)
        }
        return dict
    }

    private func estimateBytes(_ record: CKRecord) -> Int64 {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true) else {
            return 0
        }
        return Int64(data.count)
    }

    /// Upload all local data to CloudKit using batch operations. Returns true if all saves succeeded.
    func uploadAllToCloud(from store: DataStore, onProgress: ((SyncProgress) -> Void)? = nil) async -> Bool {
        guard activeDatabase != nil else {
            lastSyncError = "CloudKit not configured"
            return false
        }

        // Build all CKRecords to upload
        var allRecords: [CKRecord] = []

        // Standalone records
        for p in store.projects { allRecords.append(p.toCKRecord(in: zoneID)) }
        for c in store.clients { allRecords.append(c.toCKRecord(in: zoneID)) }
        for b in store.bids { allRecords.append(b.toCKRecord(in: zoneID)) }
        for e in store.employees { allRecords.append(e.toCKRecord(in: zoneID)) }
        for t in store.todos { allRecords.append(t.toCKRecord(in: zoneID)) }
        for ev in store.calendarEvents { allRecords.append(ev.toCKRecord(in: zoneID)) }
        for g in store.ganttTasks { allRecords.append(g.toCKRecord(in: zoneID)) }
        for oh in store.overheadExpenses { allRecords.append(oh.toCKRecord(in: zoneID)) }

        // Child records — attach projectRef
        for (projectID, cos) in store.changeOrders {
            let ref = CKRecord.Reference(recordID: CKRecord.ID(recordName: projectID.recordName, zoneID: zoneID), action: .none)
            for co in cos { let r = co.toCKRecord(in: zoneID); r["projectRef"] = ref; allRecords.append(r) }
        }
        for (projectID, pmts) in store.payments {
            let ref = CKRecord.Reference(recordID: CKRecord.ID(recordName: projectID.recordName, zoneID: zoneID), action: .none)
            for p in pmts { let r = p.toCKRecord(in: zoneID); r["projectRef"] = ref; allRecords.append(r) }
        }
        for (projectID, entries) in store.payrollEntries {
            let ref = CKRecord.Reference(recordID: CKRecord.ID(recordName: projectID.recordName, zoneID: zoneID), action: .none)
            for e in entries { let r = e.toCKRecord(in: zoneID); r["projectRef"] = ref; allRecords.append(r) }
        }
        for (projectID, costs) in store.costs {
            let ref = CKRecord.Reference(recordID: CKRecord.ID(recordName: projectID.recordName, zoneID: zoneID), action: .none)
            for c in costs { let r = c.toCKRecord(in: zoneID); r["projectRef"] = ref; allRecords.append(r) }
        }
        for (projectID, rentals) in store.equipmentRentals {
            let ref = CKRecord.Reference(recordID: CKRecord.ID(recordName: projectID.recordName, zoneID: zoneID), action: .none)
            for rental in rentals { let r = rental.toCKRecord(in: zoneID); r["projectRef"] = ref; allRecords.append(r) }
        }

        // Audit entries (last 100)
        for a in store.auditLog.prefix(100) { allRecords.append(a.toCKRecord(in: zoneID)) }
        for ts in store.timesheetEntries { allRecords.append(ts.toCKRecord(in: zoneID)) }
        for cp in store.crewPresets { allRecords.append(cp.toCKRecord(in: zoneID)) }
        for (projectID, items) in store.rfis {
            let ref = CKRecord.Reference(recordID: CKRecord.ID(recordName: projectID.recordName, zoneID: zoneID), action: .none)
            for rfi in items { let r = rfi.toCKRecord(in: zoneID); r["projectRef"] = ref; allRecords.append(r) }
        }
        for (projectID, items) in store.dailyLogs {
            let ref = CKRecord.Reference(recordID: CKRecord.ID(recordName: projectID.recordName, zoneID: zoneID), action: .none)
            for log in items { let r = log.toCKRecord(in: zoneID); r["projectRef"] = ref; allRecords.append(r) }
        }
        for (projectID, items) in store.payApplications {
            let ref = CKRecord.Reference(recordID: CKRecord.ID(recordName: projectID.recordName, zoneID: zoneID), action: .none)
            for pa in items { let r = pa.toCKRecord(in: zoneID); r["projectRef"] = ref; allRecords.append(r) }
        }
        for (projectID, items) in store.invoices {
            let ref = CKRecord.Reference(recordID: CKRecord.ID(recordName: projectID.recordName, zoneID: zoneID), action: .none)
            for inv in items { let r = inv.toCKRecord(in: zoneID); r["projectRef"] = ref; allRecords.append(r) }
        }

        print("[CloudKit] Uploading \(allRecords.count) records in batches...")

        // Upload in batches of 400 (CloudKit limit)
        let batchSize = 400
        var totalFailed = 0
        let totalRecords = allRecords.count
        let recordSizes: [Int64] = allRecords.map { estimateBytes($0) }
        let totalBytes: Int64 = recordSizes.reduce(0, +)
        onProgress?(SyncProgress(itemsDone: 0, itemsTotal: totalRecords, bytesDone: 0, bytesTotal: totalBytes))
        var bytesDone: Int64 = 0
        for batchStart in stride(from: 0, to: totalRecords, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, totalRecords)
            let batch = Array(allRecords[batchStart..<batchEnd])
            let batchNum = (batchStart / batchSize) + 1
            let totalBatches = (totalRecords + batchSize - 1) / batchSize

            let failed = await saveBatch(batch, label: "Batch \(batchNum)/\(totalBatches)")
            totalFailed += failed

            bytesDone += recordSizes[batchStart..<batchEnd].reduce(0, +)
            onProgress?(SyncProgress(itemsDone: batchEnd, itemsTotal: totalRecords, bytesDone: bytesDone, bytesTotal: totalBytes))
        }

        if totalFailed > 0 {
            lastSyncError = "\(totalFailed) of \(allRecords.count) record(s) failed to upload"
            print("[CloudKit] Upload done with \(totalFailed) failures")
            return false
        }
        lastSyncError = nil
        print("[CloudKit] Upload complete: \(allRecords.count) records saved")
        return true
    }

    /// Save a batch of CKRecords using CKModifyRecordsOperation. Returns count of failures.
    private func saveBatch(_ records: [CKRecord], label: String) async -> Int {
        guard let db = activeDatabase else { return records.count }

        return await withCheckedContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.isAtomic = false  // Allow partial success

            let lock = NSLock()
            var failCount = 0

            operation.perRecordSaveBlock = { recordID, result in
                if case .failure(let error) = result {
                    lock.lock()
                    failCount += 1
                    lock.unlock()
                    print("[CloudKit] \(label) — failed \(recordID.recordName): \(error.localizedDescription)")
                }
            }

            operation.modifyRecordsResultBlock = { result in
                lock.lock()
                let finalFailCount: Int
                switch result {
                case .success:
                    finalFailCount = failCount
                    let succeeded = records.count - finalFailCount
                    lock.unlock()
                    print("[CloudKit] \(label) — \(succeeded)/\(records.count) saved")
                case .failure(let error):
                    finalFailCount = records.count
                    lock.unlock()
                    print("[CloudKit] \(label) — operation failed: \(error.localizedDescription)")
                }
                continuation.resume(returning: finalFailCount)
            }

            db.add(operation)
        }
    }

    /// Save a record and return success/failure
    func saveRecordReturningSuccess<T: CloudKitConvertible>(_ item: T) async -> Bool {
        guard let db = activeDatabase else { return false }
        let record = item.toCKRecord(in: zoneID)
        do {
            _ = try await db.save(record)
            return true
        } catch let error as CKError where error.code == .serverRecordChanged {
            if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                let fresh = item.toCKRecord(in: zoneID)
                for key in fresh.allKeys() { serverRecord[key] = fresh[key] }
                do {
                    _ = try await db.save(serverRecord)
                    return true
                } catch {
                    print("[CloudKit] Conflict resolution save failed for \(T.ckRecordType): \(error.localizedDescription)")
                    return false
                }
            }
            return false
        } catch {
            print("[CloudKit] Upload \(T.ckRecordType) failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Save a child record and return success/failure
    func saveChildReturningSuccess<T: CloudKitConvertible>(_ item: T, parentProjectID projectID: CKRecord.ID) async -> Bool {
        guard let db = activeDatabase else { return false }
        let record = item.toCKRecord(in: zoneID)
        let parentRef = CKRecord.Reference(recordID: CKRecord.ID(recordName: projectID.recordName, zoneID: zoneID), action: .none)
        record["projectRef"] = parentRef
        do {
            _ = try await db.save(record)
            return true
        } catch let error as CKError where error.code == .serverRecordChanged {
            if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                let fresh = item.toCKRecord(in: zoneID)
                for key in fresh.allKeys() { serverRecord[key] = fresh[key] }
                serverRecord["projectRef"] = parentRef
                do {
                    _ = try await db.save(serverRecord)
                    return true
                } catch {
                    print("[CloudKit] Child conflict resolution failed for \(T.ckRecordType): \(error.localizedDescription)")
                    return false
                }
            }
            return false
        } catch {
            print("[CloudKit] Upload child \(T.ckRecordType) failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Sharing

    /// Container exposed for share UI (UICloudSharingController needs it).
    var ckContainer: CKContainer? { container }

    /// Owner-only. Returns the existing zone share if one exists, otherwise
    /// creates and saves a new one. The returned share has a populated `url`
    /// suitable for sending in an invitation.
    func ensureZoneShare() async throws -> CKShare {
        guard role == .owner, let db = privateDB else { throw CloudKitError.notConfigured }

        if let existing = try await fetchExistingZoneShare() {
            return existing
        }

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "SteelSync Data" as CKRecordValue
        share.publicPermission = .none

        // CKModifyRecordsOperation reliably populates `share.url`;
        // bare db.save sometimes returns before the URL is provisioned.
        let (saveResults, _) = try await db.modifyRecords(saving: [share], deleting: [])
        guard case .success(let saved) = saveResults[share.recordID],
              let savedShare = saved as? CKShare else {
            throw CloudKitError.notConfigured
        }
        return savedShare
    }

    private func fetchExistingZoneShare() async throws -> CKShare? {
        let allRecords = try await fetchAllRecordsInZone()
        return allRecords.first(where: { $0.recordType == "cloudkit.share" }) as? CKShare
    }

    // MARK: - Types

    enum CloudKitError: LocalizedError {
        case notConfigured
        var errorDescription: String? { "CloudKit is not configured." }
    }

    struct SyncProgress: Equatable {
        var itemsDone: Int = 0
        var itemsTotal: Int = 0
        var bytesDone: Int64 = 0
        var bytesTotal: Int64 = 0
        var fraction: Double {
            itemsTotal == 0 ? 0 : Double(itemsDone) / Double(itemsTotal)
        }
    }

    enum SyncStatus: Equatable {
        case local, checking, syncing, synced, ready, error(String)

        var displayText: String {
            switch self {
            case .local: return "Local"
            case .checking: return "Checking..."
            case .syncing: return "Syncing..."
            case .synced: return "Synced"
            case .ready: return "Connected"
            case .error(let msg): return "Error: \(msg)"
            }
        }

        var indicatorColor: String {
            switch self {
            case .local: return "orange"
            case .checking, .syncing: return "blue"
            case .synced: return "green"
            case .ready: return "blue"
            case .error: return "red"
            }
        }
    }
}
