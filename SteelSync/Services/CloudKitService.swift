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

    init() {}

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

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    func setupZone() async throws {
        guard let db = privateDB else { return }
        do {
            _ = try await db.save(CKRecordZone(zoneID: zoneID))
        } catch { /* zone may already exist */ }
    }

    // MARK: - Per-Record CRUD

    func saveRecord<T: CloudKitConvertible>(_ item: T) async {
        guard let db = privateDB else { return }
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
        guard let db = privateDB else { return }
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
        guard let db = privateDB else { return }
        let id = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        do {
            try await db.deleteRecord(withID: id)
        } catch {
            print("[CloudKit] Delete \(recordType)/\(recordName) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Zone-Based Fetch (no queryable indexes required)

    /// Fetch ALL records in the zone. Tries async API first, falls back to operation-based fetch.
    func fetchAllRecordsInZone() async throws -> [CKRecord] {
        guard let db = privateDB else { throw CloudKitError.notConfigured }

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

            // Child records — extract projectRef and group by parent
            store.changeOrders = groupChildRecords(byType[ChangeOrder.ckRecordType] ?? [], as: ChangeOrder.self)
            store.payments = groupChildRecords(byType[Payment.ckRecordType] ?? [], as: Payment.self)
            store.payrollEntries = groupChildRecords(byType[PayrollEntry.ckRecordType] ?? [], as: PayrollEntry.self)
            store.costs = groupChildRecords(byType[Cost.ckRecordType] ?? [], as: Cost.self)
            store.equipmentRentals = groupChildRecords(byType[EquipmentRental.ckRecordType] ?? [], as: EquipmentRental.self)

            // Persist locally as cache
            PersistenceService.saveAll(from: store)
            lastSyncError = nil
            print("[CloudKit] Pull complete: \(store.projects.count) projects, \(store.clients.count) clients, \(store.bids.count) bids")
            return true
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

    /// Upload all local data to CloudKit using batch operations. Returns true if all saves succeeded.
    func uploadAllToCloud(from store: DataStore, onProgress: ((Double) -> Void)? = nil) async -> Bool {
        guard privateDB != nil else {
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

        print("[CloudKit] Uploading \(allRecords.count) records in batches...")

        // Upload in batches of 400 (CloudKit limit)
        let batchSize = 400
        var totalFailed = 0
        let totalRecords = allRecords.count
        for batchStart in stride(from: 0, to: totalRecords, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, totalRecords)
            let batch = Array(allRecords[batchStart..<batchEnd])
            let batchNum = (batchStart / batchSize) + 1
            let totalBatches = (totalRecords + batchSize - 1) / batchSize

            let failed = await saveBatch(batch, label: "Batch \(batchNum)/\(totalBatches)")
            totalFailed += failed

            // Report progress (0.0 to 1.0)
            let progress = Double(batchEnd) / Double(totalRecords)
            onProgress?(progress)
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
        guard let db = privateDB else { return records.count }

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
        guard let db = privateDB else { return false }
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
        guard let db = privateDB else { return false }
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

    // MARK: - Orphan Cleanup (delete cloud records not present locally)

    /// After uploading, delete any cloud records whose IDs are not in the local set.
    func deleteOrphanedRecords(localIDs: Set<String>) async -> Int {
        guard let db = privateDB else { return 0 }
        do {
            let allRecords = try await fetchAllRecordsInZone()
            var deleted = 0
            for record in allRecords {
                // Skip CKShare records and zone-level records
                guard record.recordType != "cloudkit.share" else { continue }
                if !localIDs.contains(record.recordID.recordName) {
                    do {
                        try await db.deleteRecord(withID: record.recordID)
                        deleted += 1
                        print("[CloudKit] Deleted orphan: \(record.recordType)/\(record.recordID.recordName)")
                    } catch {
                        print("[CloudKit] Failed to delete orphan: \(error.localizedDescription)")
                    }
                }
            }
            return deleted
        } catch {
            print("[CloudKit] Orphan cleanup failed: \(error.localizedDescription)")
            return 0
        }
    }

    // MARK: - Sharing

    func createZoneShare() async throws -> CKShare {
        guard let db = privateDB else { throw CloudKitError.notConfigured }
        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "SteelSync Data" as CKRecordValue
        share.publicPermission = .none
        _ = try await db.save(share)
        return share
    }

    // MARK: - Types

    enum CloudKitError: LocalizedError {
        case notConfigured
        var errorDescription: String? { "CloudKit is not configured." }
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
