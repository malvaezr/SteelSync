import Foundation

/// Creates time-machine-style backups of all SteelSync data. Read-only by
/// design: the live `DataStore` is never modified while exporting.
///
/// A snapshot is a folder on disk containing:
///   - `manifest.json`  — metadata (timestamp, counts, app version, label)
///   - `AppData/`       — verbatim copy of PersistenceService.storageDir at snapshot time
///   - `attachments/`   — copies of any referenced files (check images, bid docs, RFI attachments)
///
/// Rather than reimplement serialization, we piggy-back on `PersistenceService`
/// which already writes the DataStore state to disk as JSON via Codable wrapper
/// types (CodableProject, CodableBid, etc.). Creating a snapshot is:
///   1. Flush live data via `store.persistNow()`
///   2. Copy the PersistenceService storage dir into the snapshot folder
///   3. Copy referenced attachment files
///   4. Write a manifest
///
/// Restoring is the inverse: copy the snapshot's AppData folder back into the
/// live storage dir, then ask the DataStore to reload. A "pre-restore" snapshot
/// is taken first so the operation is reversible.
@MainActor
struct SnapshotService {

    // MARK: - Snapshot Root

    static var snapshotRoot: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("SteelSync/Snapshots", isDirectory: true)
    }

    /// All saved snapshots on disk, newest first.
    static func listSnapshots() -> [SnapshotDescriptor] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: snapshotRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .compactMap { url -> SnapshotDescriptor? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                guard let manifest = readManifest(at: url) else { return nil }
                return SnapshotDescriptor(
                    url: url,
                    folderName: url.lastPathComponent,
                    createdAt: values?.contentModificationDate ?? manifest.createdAt,
                    manifest: manifest,
                    sizeBytes: folderSize(url)
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Create

    /// Captures the current DataStore state into a new snapshot folder.
    /// Non-destructive — the live store is only flushed, never overwritten.
    @discardableResult
    static func createSnapshot(from store: DataStore, label: String = "") throws -> SnapshotDescriptor {
        // Flush any in-memory changes first so the copy picks them up.
        store.persistNow()

        let timestamp = Date()
        let folderName = folderName(for: timestamp, label: label)
        let snapshotURL = snapshotRoot.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: snapshotURL, withIntermediateDirectories: true)

        // 1. Copy the entire AppData directory. This is whatever PersistenceService
        //    wrote during persistNow() — all the model JSON files.
        let storageDir = PersistenceService.storageDir
        let appDataDest = snapshotURL.appendingPathComponent("AppData", isDirectory: true)
        if FileManager.default.fileExists(atPath: storageDir.path) {
            try FileManager.default.copyItem(at: storageDir, to: appDataDest)
        } else {
            try FileManager.default.createDirectory(at: appDataDest, withIntermediateDirectories: true)
        }

        // 2. Copy referenced attachment files so the snapshot is self-contained.
        let attachmentsDir = snapshotURL.appendingPathComponent("attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        let copiedFileCount = copyAttachments(from: store, to: attachmentsDir)

        // 3. Write the manifest with complete per-collection counts
        let totalChangeOrders = store.changeOrders.values.reduce(0) { $0 + $1.count }
        let totalPayments = store.payments.values.reduce(0) { $0 + $1.count }
        let totalPayroll = store.payrollEntries.values.reduce(0) { $0 + $1.count }
        let totalCosts = store.costs.values.reduce(0) { $0 + $1.count }
        let totalRentals = store.equipmentRentals.values.reduce(0) { $0 + $1.count }
        let totalPayApps = store.payApplications.values.reduce(0) { $0 + $1.count }
        let totalInvoices = store.allInvoices.count
        let totalRFIs = store.rfis.values.reduce(0) { $0 + $1.count }

        let manifest = SnapshotManifest(
            version: 1,
            appVersion: "1.0",
            createdAt: timestamp,
            label: label,
            projectCount: store.projects.count,
            clientCount: store.clients.count,
            bidCount: store.bids.count,
            employeeCount: store.employees.count,
            todoCount: store.todos.count,
            calendarEventCount: store.calendarEvents.count,
            changeOrderCount: totalChangeOrders,
            paymentCount: totalPayments,
            payrollEntryCount: totalPayroll,
            costCount: totalCosts,
            equipmentRentalCount: totalRentals,
            ganttTaskCount: store.ganttTasks.count,
            payApplicationCount: totalPayApps,
            invoiceCount: totalInvoices,
            timesheetEntryCount: store.timesheetEntries.count,
            rfiCount: totalRFIs,
            planningPadCount: store.planningPads.count,
            assistantMessageCount: store.assistantMessages.count,
            auditLogCount: store.auditLog.count,
            attachmentCount: copiedFileCount
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let manifestJSON = try encoder.encode(manifest)
        try manifestJSON.write(to: snapshotURL.appendingPathComponent("manifest.json"))

        return SnapshotDescriptor(
            url: snapshotURL,
            folderName: folderName,
            createdAt: timestamp,
            manifest: manifest,
            sizeBytes: folderSize(snapshotURL)
        )
    }

    // MARK: - Restore

    /// Restores a snapshot into the live DataStore.
    /// Takes a "pre-restore" safety snapshot first so the operation is reversible.
    /// After files are in place, calls `store.reloadFromDisk()` so the UI updates.
    static func restore(from snapshot: SnapshotDescriptor, into store: DataStore) throws {
        // Safety net
        _ = try? createSnapshot(from: store, label: "pre-restore")

        let snapAppData = snapshot.url.appendingPathComponent("AppData", isDirectory: true)
        let liveStorage = PersistenceService.storageDir

        guard FileManager.default.fileExists(atPath: snapAppData.path) else {
            throw SnapshotError.missingAppData
        }

        // Remove current live storage and replace with the snapshot's copy.
        if FileManager.default.fileExists(atPath: liveStorage.path) {
            try FileManager.default.removeItem(at: liveStorage)
        }
        try FileManager.default.createDirectory(
            at: liveStorage.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: snapAppData, to: liveStorage)

        // Hot-reload the DataStore from the new files.
        store.reloadFromDisk()
    }

    // MARK: - Delete

    static func delete(_ snapshot: SnapshotDescriptor) throws {
        try FileManager.default.removeItem(at: snapshot.url)
    }

    // MARK: - Internal helpers

    private static func folderName(for date: Date, label: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let base = "Snapshot_\(f.string(from: date))"
        if label.isEmpty { return base }
        let safe = label
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        return "\(base)_\(safe)"
    }

    private static func readManifest(at folderURL: URL) -> SnapshotManifest? {
        let url = folderURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SnapshotManifest.self, from: data)
    }

    private static func folderSize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }

    /// Copies attachment files referenced by DataStore entities into the
    /// snapshot attachments folder. De-dups by filename.
    private static func copyAttachments(from store: DataStore, to dest: URL) -> Int {
        var urls: [URL] = []
        for bid in store.bids {
            urls.append(contentsOf: bid.attachments.compactMap { $0.fileURL })
        }
        for (_, list) in store.payments {
            for payment in list {
                urls.append(contentsOf: payment.attachments.compactMap { $0.fileURL })
            }
        }
        for (_, list) in store.costs {
            for cost in list {
                urls.append(contentsOf: cost.attachments.compactMap { $0.fileURL })
            }
        }
        for (_, list) in store.rfis {
            for rfi in list {
                urls.append(contentsOf: rfi.attachments.compactMap { $0.fileURL })
            }
        }

        var copied = 0
        for src in urls {
            let destURL = dest.appendingPathComponent(src.lastPathComponent)
            if FileManager.default.fileExists(atPath: destURL.path) { continue }
            if (try? FileManager.default.copyItem(at: src, to: destURL)) != nil {
                copied += 1
            }
        }
        return copied
    }
}

// MARK: - Types

struct SnapshotDescriptor: Identifiable {
    let url: URL
    let folderName: String
    let createdAt: Date
    let manifest: SnapshotManifest
    let sizeBytes: Int64

    var id: String { folderName }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: createdAt)
    }
}

struct SnapshotManifest: Codable {
    let version: Int
    let appVersion: String
    let createdAt: Date
    let label: String
    // Full per-collection counts so the user can see EXACTLY what's captured.
    // A snapshot always copies the entire PersistenceService storage directory,
    // so every DataStore collection is included — this manifest just reports
    // what was there at capture time.
    let projectCount: Int
    let clientCount: Int
    let bidCount: Int
    let employeeCount: Int
    let todoCount: Int
    let calendarEventCount: Int
    let changeOrderCount: Int
    let paymentCount: Int
    let payrollEntryCount: Int
    let costCount: Int
    let equipmentRentalCount: Int
    let ganttTaskCount: Int
    let payApplicationCount: Int
    let invoiceCount: Int
    let timesheetEntryCount: Int
    let rfiCount: Int
    let planningPadCount: Int
    let assistantMessageCount: Int
    let auditLogCount: Int
    let attachmentCount: Int
}

enum SnapshotError: LocalizedError {
    case missingAppData

    var errorDescription: String? {
        switch self {
        case .missingAppData: return "Snapshot is missing its AppData folder and cannot be restored."
        }
    }
}
