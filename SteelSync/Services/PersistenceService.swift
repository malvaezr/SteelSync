import Foundation
import CloudKit

/// Saves and loads all DataStore data to/from JSON files in the app's Documents directory.
/// Models with CKRecord.ID/CKRecord.Reference are encoded via intermediate Codable wrappers.
struct PersistenceService {

    static var storageDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("SteelSync/AppData", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func fileURL(_ name: String) -> URL {
        storageDir.appendingPathComponent("\(name).json")
    }

    // MARK: - Generic JSON Read/Write

    static func save<T: Encodable>(_ value: T, as name: String) {
        do {
            let data = try JSONEncoder().encode(value)
            let url = fileURL(name)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            print("[Persistence] Failed to save \(name): \(error)")
        }
    }

    static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        let url = fileURL(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("[Persistence] Failed to load \(name): \(error)")
            return nil
        }
    }

    // MARK: - Codable Wrappers for CKRecord-based Models

    struct CodableProject: Codable {
        let idName: String
        var clientRefName: String?
        var gcClientRefName: String?
        var subClientRefName: String?
        var title: String; var location: String; var contractAmount: Decimal
        var startDate: Date?; var endDate: Date?; var actualCompletionDate: Date?
        var status: String; var changeOrderCounter: Int; var notes: String
        var balanceSummary: ProjectBalanceSummary
        var completionSummary: String?; var originalBidID: String?; var progressOverride: Double?

        init(_ p: Project) {
            idName = p.id.recordName; clientRefName = p.clientRef?.recordID.recordName
            gcClientRefName = p.gcClientRef?.recordID.recordName
            subClientRefName = p.subClientRef?.recordID.recordName
            title = p.title; location = p.location; contractAmount = p.contractAmount
            startDate = p.startDate; endDate = p.endDate; actualCompletionDate = p.actualCompletionDate
            status = p.status; changeOrderCounter = p.changeOrderCounter; notes = p.notes
            balanceSummary = p.balanceSummary; completionSummary = p.completionSummary
            originalBidID = p.originalBidID; progressOverride = p.progressOverride
        }

        func toProject() -> Project {
            Project(
                id: CKRecord.ID(recordName: idName),
                clientRef: clientRefName.map { CKRecord.Reference(recordID: CKRecord.ID(recordName: $0), action: .none) },
                gcClientRef: gcClientRefName.map { CKRecord.Reference(recordID: CKRecord.ID(recordName: $0), action: .none) },
                subClientRef: subClientRefName.map { CKRecord.Reference(recordID: CKRecord.ID(recordName: $0), action: .none) },
                title: title, location: location, contractAmount: contractAmount,
                startDate: startDate, endDate: endDate, actualCompletionDate: actualCompletionDate,
                status: status, changeOrderCounter: changeOrderCounter, notes: notes,
                balanceSummary: balanceSummary, completionSummary: completionSummary,
                originalBidID: originalBidID, progressOverride: progressOverride
            )
        }
    }

    struct CodableClient: Codable {
        let idName: String
        var name: String; var contactName: String; var email: String
        var phone: String; var billingAddress: String; var preferredRateType: RateType

        init(_ c: Client) {
            idName = c.id.recordName; name = c.name; contactName = c.contactName
            email = c.email; phone = c.phone; billingAddress = c.billingAddress
            preferredRateType = c.preferredRateType
        }

        func toClient() -> Client {
            Client(id: CKRecord.ID(recordName: idName), name: name, contactName: contactName,
                   email: email, phone: phone, billingAddress: billingAddress,
                   preferredRateType: preferredRateType)
        }
    }

    struct CodableBid: Codable {
        let idName: String
        var projectName: String; var clientName: String; var clientRefName: String?
        var address: String; var bidAmount: Decimal; var bidDueDate: Date; var createdDate: Date
        var isSubmitted: Bool; var submittedDate: Date?; var awardedProjectID: String?
        var isReadyToSubmit: Bool; var isLost: Bool
        var squareFeet: Int; var numberOfBeams: Int; var numberOfColumns: Int
        var numberOfJoists: Int; var numberOfWallPanels: Int; var estimatedTons: Double
        var touchpoints: [Touchpoint]; var nextFollowUp: Date?; var reminderDate: Date?
        var notes: String; var attachments: [Attachment]

        init(_ b: BidProject) {
            idName = b.recordID.recordName; projectName = b.projectName; clientName = b.clientName
            clientRefName = b.clientRef?.recordID.recordName; address = b.address
            bidAmount = b.bidAmount; bidDueDate = b.bidDueDate; createdDate = b.createdDate
            isSubmitted = b.isSubmitted; submittedDate = b.submittedDate
            awardedProjectID = b.awardedProjectID; isReadyToSubmit = b.isReadyToSubmit; isLost = b.isLost
            squareFeet = b.squareFeet; numberOfBeams = b.numberOfBeams
            numberOfColumns = b.numberOfColumns; numberOfJoists = b.numberOfJoists
            numberOfWallPanels = b.numberOfWallPanels; estimatedTons = b.estimatedTons
            touchpoints = b.touchpoints; nextFollowUp = b.nextFollowUp
            reminderDate = b.reminderDate; notes = b.notes; attachments = b.attachments
        }

        func toBid() -> BidProject {
            BidProject(
                recordID: CKRecord.ID(recordName: idName),
                projectName: projectName, clientName: clientName,
                clientRef: clientRefName.map { CKRecord.Reference(recordID: CKRecord.ID(recordName: $0), action: .none) },
                address: address, bidAmount: bidAmount, bidDueDate: bidDueDate, createdDate: createdDate,
                isSubmitted: isSubmitted, submittedDate: submittedDate,
                awardedProjectID: awardedProjectID, isReadyToSubmit: isReadyToSubmit, isLost: isLost,
                squareFeet: squareFeet, numberOfBeams: numberOfBeams, numberOfColumns: numberOfColumns,
                numberOfJoists: numberOfJoists, numberOfWallPanels: numberOfWallPanels,
                estimatedTons: estimatedTons, touchpoints: touchpoints, nextFollowUp: nextFollowUp,
                reminderDate: reminderDate, notes: notes, attachments: attachments
            )
        }
    }

    // MARK: - Dictionary Key Wrapper (CKRecord.ID is not Codable, so dict keys need string conversion)

    struct CodableDictEntry<V: Codable>: Codable {
        let key: String
        let values: [V]
    }

    static func encodeDict<V: Codable>(_ dict: [CKRecord.ID: [V]]) -> [CodableDictEntry<V>] {
        dict.map { CodableDictEntry(key: $0.key.recordName, values: $0.value) }
    }

    static func decodeDict<V: Codable>(_ entries: [CodableDictEntry<V>]) -> [CKRecord.ID: [V]] {
        var result: [CKRecord.ID: [V]] = [:]
        for entry in entries {
            result[CKRecord.ID(recordName: entry.key)] = entry.values
        }
        return result
    }

    // MARK: - Backup (before any cloud pull)

    private static var backupDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("SteelSync/Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func backupAll() {
        let fm = FileManager.default
        let names = ["projects", "bids", "clients", "employees", "todos", "calendarEvents",
                     "changeOrders", "payments", "payrollEntries", "costs", "equipmentRentals",
                     "ganttTasks", "auditLog"]
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupFolder = backupDir.appendingPathComponent(timestamp, isDirectory: true)
        try? fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        for name in names {
            let src = fileURL(name)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: backupFolder.appendingPathComponent("\(name).json"))
            }
        }
        print("[Persistence] Backup saved to \(backupFolder.lastPathComponent)")
    }

    // MARK: - Save All

    @MainActor
    static func saveAll(from store: DataStore) {
        save(store.projects.map { CodableProject($0) }, as: "projects")
        save(store.bids.map { CodableBid($0) }, as: "bids")
        save(store.clients.map { CodableClient($0) }, as: "clients")
        save(store.employees, as: "employees")
        save(store.todos, as: "todos")
        save(store.calendarEvents, as: "calendarEvents")
        save(encodeDict(store.changeOrders), as: "changeOrders")
        save(encodeDict(store.payments), as: "payments")
        save(encodeDict(store.payrollEntries), as: "payrollEntries")
        save(encodeDict(store.costs), as: "costs")
        save(encodeDict(store.equipmentRentals), as: "equipmentRentals")
        save(store.ganttTasks, as: "ganttTasks")
        save(store.auditLog, as: "auditLog")
    }

    // MARK: - Load All

    @MainActor
    static func loadAll(into store: DataStore) -> Bool {
        guard FileManager.default.fileExists(atPath: fileURL("projects").path) else { return false }

        if let p: [CodableProject] = load([CodableProject].self, from: "projects") {
            store.projects = p.map { $0.toProject() }
        }
        if let b: [CodableBid] = load([CodableBid].self, from: "bids") {
            store.bids = b.map { $0.toBid() }
        }
        if let c: [CodableClient] = load([CodableClient].self, from: "clients") {
            store.clients = c.map { $0.toClient() }
        }
        if let e = load([Employee].self, from: "employees") { store.employees = e }
        if let t = load([TodoItem].self, from: "todos") { store.todos = t }
        if let ev = load([CalendarEvent].self, from: "calendarEvents") { store.calendarEvents = ev }
        if let co: [CodableDictEntry<ChangeOrder>] = load([CodableDictEntry<ChangeOrder>].self, from: "changeOrders") {
            store.changeOrders = decodeDict(co)
        }
        if let pm: [CodableDictEntry<Payment>] = load([CodableDictEntry<Payment>].self, from: "payments") {
            store.payments = decodeDict(pm)
        }
        if let pr: [CodableDictEntry<PayrollEntry>] = load([CodableDictEntry<PayrollEntry>].self, from: "payrollEntries") {
            store.payrollEntries = decodeDict(pr)
        }
        if let cs: [CodableDictEntry<Cost>] = load([CodableDictEntry<Cost>].self, from: "costs") {
            store.costs = decodeDict(cs)
        }
        if let er: [CodableDictEntry<EquipmentRental>] = load([CodableDictEntry<EquipmentRental>].self, from: "equipmentRentals") {
            store.equipmentRentals = decodeDict(er)
        }
        if let g = load([GanttTask].self, from: "ganttTasks") { store.ganttTasks = g }
        if let a = load([AuditEntry].self, from: "auditLog") { store.auditLog = a }
        return true
    }
}
