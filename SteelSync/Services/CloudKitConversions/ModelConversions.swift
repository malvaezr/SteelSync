import Foundation
import CloudKit

// MARK: - Project

extension Project: CloudKitConvertible {
    static let ckRecordType = "SS_Project"
    var ckRecordName: String { id.recordName }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["title"] = title as CKRecordValue; r["location"] = location as CKRecordValue
        CKField.setDecimal(r, "contractAmount", contractAmount)
        if let d = startDate { r["startDate"] = d as CKRecordValue }
        if let d = endDate { r["endDate"] = d as CKRecordValue }
        if let d = actualCompletionDate { r["actualCompletionDate"] = d as CKRecordValue }
        r["status"] = status as CKRecordValue; r["changeOrderCounter"] = changeOrderCounter as CKRecordValue
        r["notes"] = notes as CKRecordValue
        CKField.setRef(r, "gcClientRef", gcClientRef?.recordID.recordName, zoneID: zoneID)
        CKField.setRef(r, "subClientRef", subClientRef?.recordID.recordName, zoneID: zoneID)
        CKField.setRef(r, "clientRef", clientRef?.recordID.recordName, zoneID: zoneID)
        r["balanceSummaryJSON"] = CKField.encodeJSON(balanceSummary) as CKRecordValue
        if let s = completionSummary { r["completionSummary"] = s as CKRecordValue }
        if let s = originalBidID { r["originalBidID"] = s as CKRecordValue }
        if let p = progressOverride { r["progressOverride"] = p as CKRecordValue }
        return r
    }

    static func from(_ record: CKRecord) -> Project? {
        let balance = CKField.decodeJSON(record, "balanceSummaryJSON", as: ProjectBalanceSummary.self) ?? ProjectBalanceSummary()
        return Project(
            id: record.recordID,
            clientRef: CKField.ref(record, "clientRef"),
            gcClientRef: CKField.ref(record, "gcClientRef"),
            subClientRef: CKField.ref(record, "subClientRef"),
            title: CKField.string(record, "title"),
            location: CKField.string(record, "location"),
            contractAmount: CKField.decimal(record, "contractAmount"),
            startDate: CKField.optDate(record, "startDate"),
            endDate: CKField.optDate(record, "endDate"),
            actualCompletionDate: CKField.optDate(record, "actualCompletionDate"),
            status: CKField.string(record, "status"),
            changeOrderCounter: CKField.int(record, "changeOrderCounter"),
            notes: CKField.string(record, "notes"),
            balanceSummary: balance,
            completionSummary: CKField.optString(record, "completionSummary"),
            originalBidID: CKField.optString(record, "originalBidID"),
            progressOverride: CKField.optDouble(record, "progressOverride")
        )
    }
}

// MARK: - Client

extension Client: CloudKitConvertible {
    static let ckRecordType = "SS_Client"
    var ckRecordName: String { id.recordName }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["name"] = name as CKRecordValue; r["contactName"] = contactName as CKRecordValue
        r["email"] = email as CKRecordValue; r["phone"] = phone as CKRecordValue
        r["billingAddress"] = billingAddress as CKRecordValue
        r["preferredRateType"] = preferredRateType.rawValue as CKRecordValue
        return r
    }

    static func from(_ record: CKRecord) -> Client? {
        Client(
            id: record.recordID, name: CKField.string(record, "name"),
            contactName: CKField.string(record, "contactName"),
            email: CKField.string(record, "email"), phone: CKField.string(record, "phone"),
            billingAddress: CKField.string(record, "billingAddress"),
            preferredRateType: RateType(rawValue: CKField.int(record, "preferredRateType")) ?? .subcontractor
        )
    }
}

// MARK: - BidProject

extension BidProject: CloudKitConvertible {
    static let ckRecordType = "SS_BidProject"
    var ckRecordName: String { recordID.recordName }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["projectName"] = projectName as CKRecordValue; r["clientName"] = clientName as CKRecordValue
        r["address"] = address as CKRecordValue
        CKField.setDecimal(r, "bidAmount", bidAmount)
        r["bidDueDate"] = bidDueDate as CKRecordValue; r["createdDate"] = createdDate as CKRecordValue
        CKField.setBool(r, "isSubmitted", isSubmitted)
        if let d = submittedDate { r["submittedDate"] = d as CKRecordValue }
        if let s = awardedProjectID { r["awardedProjectID"] = s as CKRecordValue }
        CKField.setBool(r, "isReadyToSubmit", isReadyToSubmit)
        CKField.setBool(r, "isLost", isLost)
        CKField.setBool(r, "isWorkingOn", isWorkingOn)
        r["squareFeet"] = squareFeet as CKRecordValue; r["numberOfBeams"] = numberOfBeams as CKRecordValue
        r["numberOfColumns"] = numberOfColumns as CKRecordValue; r["numberOfJoists"] = numberOfJoists as CKRecordValue
        r["numberOfWallPanels"] = numberOfWallPanels as CKRecordValue
        r["estimatedTons"] = estimatedTons as CKRecordValue
        r["touchpointsJSON"] = CKField.encodeJSON(touchpoints) as CKRecordValue
        r["attachmentsJSON"] = CKField.encodeJSON(attachments) as CKRecordValue
        r["notes"] = notes as CKRecordValue
        if let d = nextFollowUp { r["nextFollowUp"] = d as CKRecordValue }
        if let d = reminderDate { r["reminderDate"] = d as CKRecordValue }
        CKField.setRef(r, "clientRef", clientRef?.recordID.recordName, zoneID: zoneID)

        // Upload actual file data as CKAssets for cross-device sync
        let assets: [CKAsset] = attachments.compactMap { att in
            guard let url = att.fileURL, FileManager.default.isReadableFile(atPath: url.path) else { return nil }
            return CKAsset(fileURL: url)
        }
        if !assets.isEmpty {
            r["attachmentAssets"] = assets as CKRecordValue
        }
        return r
    }

    static func from(_ record: CKRecord) -> BidProject? {
        // Decode attachment metadata from JSON
        var attachments = CKField.decodeJSON(record, "attachmentsJSON", as: [Attachment].self) ?? []

        // If CKAsset files are present, download them to local storage and update file URLs
        let assets = record["attachmentAssets"] as? [CKAsset] ?? []
        let bidID = record.recordID.recordName
        if !assets.isEmpty {
            let localFolder = (try? FileStorageService.bidFolder(for: bidID)) ?? FileStorageService.documentsRoot
            for i in 0..<min(assets.count, attachments.count) {
                guard let tempURL = assets[i].fileURL else { continue }
                let destURL = localFolder.appendingPathComponent(attachments[i].filename)
                // Only copy if the file doesn't already exist locally
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.copyItem(at: tempURL, to: destURL)
                }
                // Update the local file size from the actual file
                let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path)
                let fileSize = attrs?[.size] as? Int64 ?? attachments[i].fileSize
                attachments[i] = Attachment(
                    id: attachments[i].id,
                    filename: attachments[i].filename,
                    fileSize: fileSize,
                    fileURL: destURL,
                    uploadedDate: attachments[i].uploadedDate
                )
            }
        }

        return BidProject(
            recordID: record.recordID,
            projectName: CKField.string(record, "projectName"),
            clientName: CKField.string(record, "clientName"),
            clientRef: CKField.ref(record, "clientRef"),
            address: CKField.string(record, "address"),
            bidAmount: CKField.decimal(record, "bidAmount"),
            bidDueDate: CKField.date(record, "bidDueDate"),
            createdDate: CKField.date(record, "createdDate"),
            isSubmitted: CKField.bool(record, "isSubmitted"),
            submittedDate: CKField.optDate(record, "submittedDate"),
            awardedProjectID: CKField.optString(record, "awardedProjectID"),
            isReadyToSubmit: CKField.bool(record, "isReadyToSubmit"),
            isLost: CKField.bool(record, "isLost"),
            isWorkingOn: CKField.bool(record, "isWorkingOn"),
            squareFeet: CKField.int(record, "squareFeet"),
            numberOfBeams: CKField.int(record, "numberOfBeams"),
            numberOfColumns: CKField.int(record, "numberOfColumns"),
            numberOfJoists: CKField.int(record, "numberOfJoists"),
            numberOfWallPanels: CKField.int(record, "numberOfWallPanels"),
            estimatedTons: CKField.double(record, "estimatedTons"),
            touchpoints: CKField.decodeJSON(record, "touchpointsJSON", as: [Touchpoint].self) ?? [],
            nextFollowUp: CKField.optDate(record, "nextFollowUp"),
            reminderDate: CKField.optDate(record, "reminderDate"),
            notes: CKField.string(record, "notes"),
            attachments: attachments
        )
    }
}

// MARK: - Employee

extension Employee: CloudKitConvertible {
    static let ckRecordType = "SS_Employee"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue; r["employeeID"] = employeeID as CKRecordValue
        r["firstName"] = firstName as CKRecordValue; r["lastName"] = lastName as CKRecordValue
        r["email"] = email as CKRecordValue; r["phone"] = phone as CKRecordValue
        r["employeeType"] = employeeType.rawValue as CKRecordValue
        CKField.setDecimal(r, "defaultHourlyRate", defaultHourlyRate)
        r["status"] = status.rawValue as CKRecordValue; r["notes"] = notes as CKRecordValue
        r["createdDate"] = createdDate as CKRecordValue; r["updatedDate"] = updatedDate as CKRecordValue
        return r
    }

    static func from(_ record: CKRecord) -> Employee? {
        Employee(
            id: CKField.uuid(record, "uuid"), employeeID: CKField.string(record, "employeeID"),
            firstName: CKField.string(record, "firstName"), lastName: CKField.string(record, "lastName"),
            email: CKField.string(record, "email"), phone: CKField.string(record, "phone"),
            employeeType: EmployeeType(rawValue: CKField.string(record, "employeeType")) ?? .w2,
            defaultHourlyRate: CKField.decimal(record, "defaultHourlyRate"),
            status: EmployeeStatus(rawValue: CKField.string(record, "status")) ?? .active,
            notes: CKField.string(record, "notes"),
            createdDate: CKField.date(record, "createdDate"), updatedDate: CKField.date(record, "updatedDate")
        )
    }
}

// MARK: - ChangeOrder (child of Project)

extension ChangeOrder: CloudKitConvertible {
    static let ckRecordType = "SS_ChangeOrder"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue; r["number"] = number as CKRecordValue
        r["desc"] = description as CKRecordValue
        CKField.setDecimal(r, "amount", amount)
        r["submittedDate"] = submittedDate as CKRecordValue
        if let d = signedDate { r["signedDate"] = d as CKRecordValue }
        r["scope"] = scope as CKRecordValue
        r["invoiceNumber"] = invoiceNumber as CKRecordValue; r["invoiceDate"] = invoiceDate as CKRecordValue
        r["workOrderNumber"] = workOrderNumber as CKRecordValue; r["poNumber"] = poNumber as CKRecordValue
        r["laborLineItemsJSON"] = CKField.encodeJSON(laborLineItems) as CKRecordValue
        r["additionalChargesJSON"] = CKField.encodeJSON(additionalCharges) as CKRecordValue
        CKField.setDecimal(r, "taxRate", taxRate)
        r["paymentTerms"] = paymentTerms as CKRecordValue; r["additionalNotes"] = additionalNotes as CKRecordValue
        return r
    }

    static func from(_ record: CKRecord) -> ChangeOrder? {
        ChangeOrder(
            id: CKField.uuid(record, "uuid"), number: CKField.int(record, "number"),
            description: CKField.string(record, "desc"), amount: CKField.decimal(record, "amount"),
            submittedDate: CKField.date(record, "submittedDate"), signedDate: CKField.optDate(record, "signedDate"),
            scope: CKField.string(record, "scope"),
            invoiceNumber: CKField.string(record, "invoiceNumber"), invoiceDate: CKField.date(record, "invoiceDate"),
            workOrderNumber: CKField.string(record, "workOrderNumber"), poNumber: CKField.string(record, "poNumber"),
            laborLineItems: CKField.decodeJSON(record, "laborLineItemsJSON", as: [LaborLineItem].self) ?? LaborLineItem.defaultSet(),
            additionalCharges: CKField.decodeJSON(record, "additionalChargesJSON", as: [AdditionalChargeItem].self) ?? [],
            taxRate: CKField.decimal(record, "taxRate"),
            paymentTerms: CKField.string(record, "paymentTerms"), additionalNotes: CKField.string(record, "additionalNotes")
        )
    }
}

// MARK: - Payment (child of Project)

extension Payment: CloudKitConvertible {
    static let ckRecordType = "SS_Payment"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue
        CKField.setDecimal(r, "amount", amount)
        r["date"] = date as CKRecordValue; r["notes"] = notes as CKRecordValue
        if let coID = appliedToChangeOrder { r["appliedToChangeOrder"] = coID.uuidString as CKRecordValue }
        // Payment ↔ Invoice link plus the proof/method fields. Without these
        // round-tripping, an iPad pulling from cloud would lose the invoice
        // application and "Remaining" balances would compute incorrectly.
        if let invID = appliedToInvoiceID { r["appliedToInvoiceID"] = invID.uuidString as CKRecordValue }
        r["paymentMethod"] = paymentMethod.rawValue as CKRecordValue
        r["referenceNumber"] = referenceNumber as CKRecordValue
        r["proofReason"] = proofReason as CKRecordValue
        r["attachmentsJSON"] = CKField.encodeJSON(attachments) as CKRecordValue
        return r
    }

    static func from(_ record: CKRecord) -> Payment? {
        Payment(
            id: CKField.uuid(record, "uuid"), amount: CKField.decimal(record, "amount"),
            date: CKField.date(record, "date"),
            appliedToChangeOrder: CKField.optUUID(record, "appliedToChangeOrder"),
            appliedToInvoiceID: CKField.optUUID(record, "appliedToInvoiceID"),
            paymentMethod: PaymentMethod(rawValue: CKField.string(record, "paymentMethod")) ?? .check,
            referenceNumber: CKField.string(record, "referenceNumber"),
            proofReason: CKField.string(record, "proofReason"),
            notes: CKField.string(record, "notes"),
            attachments: CKField.decodeJSON(record, "attachmentsJSON", as: [Attachment].self) ?? []
        )
    }
}

// MARK: - CrewPreset (standalone)

extension CrewPreset: CloudKitConvertible {
    static let ckRecordType = "SS_CrewPreset"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue
        r["name"] = name as CKRecordValue
        r["createdDate"] = createdDate as CKRecordValue
        r["membersJSON"] = CKField.encodeJSON(members) as CKRecordValue
        return r
    }

    static func from(_ record: CKRecord) -> CrewPreset? {
        CrewPreset(
            id: CKField.uuid(record, "uuid"),
            name: CKField.string(record, "name"),
            members: CKField.decodeJSON(record, "membersJSON", as: [CrewPresetMember].self) ?? [],
            createdDate: CKField.date(record, "createdDate")
        )
    }
}

// MARK: - PayApplication (child of Project)

extension PayApplication: CloudKitConvertible {
    static let ckRecordType = "SS_PayApplication"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue
        r["applicationNumber"] = applicationNumber as CKRecordValue
        r["applicationDate"] = applicationDate as CKRecordValue
        r["periodTo"] = periodTo as CKRecordValue
        r["projectIDString"] = projectID as CKRecordValue
        CKField.setDecimal(r, "retainageRate", retainageRate)
        r["lineItemsJSON"] = CKField.encodeJSON(lineItems) as CKRecordValue
        r["notes"] = notes as CKRecordValue
        CKField.setBool(r, "isRetainageRelease", isRetainageRelease)
        if let invID = linkedInvoiceID { r["linkedInvoiceID"] = invID.uuidString as CKRecordValue }
        return r
    }

    static func from(_ record: CKRecord) -> PayApplication? {
        PayApplication(
            id: CKField.uuid(record, "uuid"),
            applicationNumber: CKField.int(record, "applicationNumber"),
            applicationDate: CKField.date(record, "applicationDate"),
            periodTo: CKField.date(record, "periodTo"),
            projectID: CKField.string(record, "projectIDString"),
            retainageRate: CKField.decimal(record, "retainageRate"),
            lineItems: CKField.decodeJSON(record, "lineItemsJSON", as: [SOVLineItem].self) ?? [],
            notes: CKField.string(record, "notes"),
            isRetainageRelease: CKField.bool(record, "isRetainageRelease"),
            linkedInvoiceID: CKField.optUUID(record, "linkedInvoiceID")
        )
    }
}

// MARK: - Invoice (child of Project)

extension Invoice: CloudKitConvertible {
    static let ckRecordType = "SS_Invoice"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue
        r["invoiceNumber"] = invoiceNumber as CKRecordValue
        r["invType"] = type.rawValue as CKRecordValue
        r["status"] = status.rawValue as CKRecordValue
        CKField.setDecimal(r, "amount", amount)
        CKField.setDecimal(r, "retainageHeld", retainageHeld)
        if let s = sentDate { r["sentDate"] = s as CKRecordValue }
        if let d = dueDate { r["dueDate"] = d as CKRecordValue }
        if let p = paidDate { r["paidDate"] = p as CKRecordValue }
        r["paymentTermsDays"] = paymentTermsDays as CKRecordValue
        if let pa = linkedPayAppID { r["linkedPayAppID"] = pa.uuidString as CKRecordValue }
        r["projectIDString"] = projectID as CKRecordValue
        r["clientName"] = clientName as CKRecordValue
        if let bt = billToClientID { r["billToClientID"] = bt as CKRecordValue }
        r["notes"] = notes as CKRecordValue
        r["attachmentsJSON"] = CKField.encodeJSON(attachments) as CKRecordValue
        return r
    }

    static func from(_ record: CKRecord) -> Invoice? {
        Invoice(
            id: CKField.uuid(record, "uuid"),
            invoiceNumber: CKField.string(record, "invoiceNumber"),
            type: InvoiceType(rawValue: CKField.string(record, "invType")) ?? .payApplication,
            status: InvoiceStatus(rawValue: CKField.string(record, "status")) ?? .draft,
            amount: CKField.decimal(record, "amount"),
            retainageHeld: CKField.decimal(record, "retainageHeld"),
            sentDate: CKField.optDate(record, "sentDate"),
            dueDate: CKField.optDate(record, "dueDate"),
            paidDate: CKField.optDate(record, "paidDate"),
            paymentTermsDays: CKField.int(record, "paymentTermsDays"),
            linkedPayAppID: CKField.optUUID(record, "linkedPayAppID"),
            projectID: CKField.string(record, "projectIDString"),
            clientName: CKField.string(record, "clientName"),
            billToClientID: CKField.optString(record, "billToClientID"),
            notes: CKField.string(record, "notes"),
            attachments: CKField.decodeJSON(record, "attachmentsJSON", as: [Attachment].self) ?? []
        )
    }
}

// MARK: - PayrollEntry (child of Project)

extension PayrollEntry: CloudKitConvertible {
    static let ckRecordType = "SS_PayrollEntry"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue; r["weekNumber"] = weekNumber as CKRecordValue
        r["year"] = year as CKRecordValue
        CKField.setDecimal(r, "totalHours", totalHours); CKField.setDecimal(r, "totalAmount", totalAmount)
        r["notes"] = notes as CKRecordValue
        r["employeeDetailsJSON"] = CKField.encodeJSON(employeeDetails) as CKRecordValue
        return r
    }

    static func from(_ record: CKRecord) -> PayrollEntry? {
        PayrollEntry(
            id: CKField.uuid(record, "uuid"), weekNumber: CKField.int(record, "weekNumber"),
            year: CKField.int(record, "year"),
            totalHours: CKField.decimal(record, "totalHours"), totalAmount: CKField.decimal(record, "totalAmount"),
            notes: CKField.string(record, "notes"),
            employeeDetails: CKField.decodeJSON(record, "employeeDetailsJSON", as: [EmployeePayrollDetail].self) ?? []
        )
    }
}

// MARK: - Cost (child of Project)

extension Cost: CloudKitConvertible {
    static let ckRecordType = "SS_Cost"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue
        r["category"] = category.rawValue as CKRecordValue; r["desc"] = description as CKRecordValue
        CKField.setDecimal(r, "amount", amount); r["date"] = date as CKRecordValue
        return r
    }

    static func from(_ record: CKRecord) -> Cost? {
        Cost(
            id: CKField.uuid(record, "uuid"),
            category: CostCategory(rawValue: CKField.string(record, "category")) ?? .other,
            description: CKField.string(record, "desc"),
            amount: CKField.decimal(record, "amount"), date: CKField.date(record, "date")
        )
    }
}

// MARK: - EquipmentRental (child of Project)

extension EquipmentRental: CloudKitConvertible {
    static let ckRecordType = "SS_EquipmentRental"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue
        r["equipmentRateID"] = equipmentRateID.uuidString as CKRecordValue
        r["equipmentName"] = equipmentName as CKRecordValue
        CKField.setDecimal(r, "dailyRate", dailyRate); CKField.setDecimal(r, "weeklyRate", weeklyRate)
        CKField.setDecimal(r, "fourWeekRate", fourWeekRate)
        r["startDate"] = startDate as CKRecordValue
        if let d = endDate { r["endDate"] = d as CKRecordValue }
        CKField.setBool(r, "includeDelivery", includeDelivery); CKField.setBool(r, "includePickup", includePickup)
        CKField.setDecimal(r, "deliveryChargePerTrip", deliveryChargePerTrip)
        r["unitInfo"] = unitInfo as CKRecordValue
        CKField.setDecimal(r, "fuelGallons", fuelGallons); CKField.setDecimal(r, "fuelPricePerGallon", fuelPricePerGallon)
        r["notes"] = notes as CKRecordValue
        CKField.setOptDecimal(r, "calculatedCost", calculatedCost)
        if let s = costBreakdown { r["costBreakdown"] = s as CKRecordValue }
        if let c = linkedCostID { r["linkedCostID"] = c.uuidString as CKRecordValue }
        return r
    }

    static func from(_ record: CKRecord) -> EquipmentRental? {
        EquipmentRental(
            id: CKField.uuid(record, "uuid"),
            equipmentRateID: CKField.uuid(record, "equipmentRateID"),
            equipmentName: CKField.string(record, "equipmentName"),
            dailyRate: CKField.decimal(record, "dailyRate"), weeklyRate: CKField.decimal(record, "weeklyRate"),
            fourWeekRate: CKField.decimal(record, "fourWeekRate"),
            startDate: CKField.date(record, "startDate"), endDate: CKField.optDate(record, "endDate"),
            includeDelivery: CKField.bool(record, "includeDelivery"), includePickup: CKField.bool(record, "includePickup"),
            deliveryChargePerTrip: CKField.decimal(record, "deliveryChargePerTrip"),
            unitInfo: CKField.string(record, "unitInfo"),
            fuelGallons: CKField.decimal(record, "fuelGallons"),
            fuelPricePerGallon: CKField.decimal(record, "fuelPricePerGallon"),
            notes: CKField.string(record, "notes"),
            calculatedCost: CKField.optDecimal(record, "calculatedCost"),
            costBreakdown: CKField.optString(record, "costBreakdown"),
            linkedCostID: CKField.optUUID(record, "linkedCostID")
        )
    }
}

// MARK: - TodoItem

extension TodoItem: CloudKitConvertible {
    static let ckRecordType = "SS_TodoItem"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue; r["title"] = title as CKRecordValue
        r["notes"] = notes as CKRecordValue
        if let d = dueDate { r["dueDate"] = d as CKRecordValue }
        r["priority"] = priority.rawValue as CKRecordValue; r["category"] = category.rawValue as CKRecordValue
        CKField.setBool(r, "isCompleted", isCompleted)
        if let d = completedDate { r["completedDate"] = d as CKRecordValue }
        r["createdDate"] = createdDate as CKRecordValue
        if let s = relatedBidID { r["relatedBidID"] = s as CKRecordValue }
        if let s = relatedProjectID { r["relatedProjectID"] = s as CKRecordValue }
        return r
    }

    static func from(_ record: CKRecord) -> TodoItem? {
        TodoItem(
            id: CKField.uuid(record, "uuid"), title: CKField.string(record, "title"),
            notes: CKField.string(record, "notes"), dueDate: CKField.optDate(record, "dueDate"),
            priority: TodoPriority(rawValue: CKField.int(record, "priority")) ?? .medium,
            category: TodoCategory(rawValue: CKField.string(record, "category")) ?? .general,
            isCompleted: CKField.bool(record, "isCompleted"),
            completedDate: CKField.optDate(record, "completedDate"),
            createdDate: CKField.date(record, "createdDate"),
            relatedBidID: CKField.optString(record, "relatedBidID"),
            relatedProjectID: CKField.optString(record, "relatedProjectID")
        )
    }
}

// MARK: - CalendarEvent

extension CalendarEvent: CloudKitConvertible {
    static let ckRecordType = "SS_CalendarEvent"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue; r["title"] = title as CKRecordValue
        r["desc"] = description as CKRecordValue; r["startDate"] = startDate as CKRecordValue
        r["endDate"] = endDate as CKRecordValue
        r["eventType"] = type.rawValue as CKRecordValue
        CKField.setBool(r, "isAllDay", isAllDay)
        if let pid = projectID { r["projectID"] = pid.uuidString as CKRecordValue }
        return r
    }

    static func from(_ record: CKRecord) -> CalendarEvent? {
        CalendarEvent(
            id: CKField.uuid(record, "uuid"),
            projectID: CKField.optUUID(record, "projectID"),
            title: CKField.string(record, "title"),
            description: CKField.string(record, "desc"),
            startDate: CKField.date(record, "startDate"),
            endDate: CKField.optDate(record, "endDate"),
            type: EventType(rawValue: CKField.string(record, "eventType")) ?? .other,
            isAllDay: CKField.bool(record, "isAllDay")
        )
    }
}

// MARK: - GanttTask

extension GanttTask: CloudKitConvertible {
    static let ckRecordType = "SS_GanttTask"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue; r["projectID"] = projectID as CKRecordValue
        r["name"] = name as CKRecordValue; r["category"] = category.rawValue as CKRecordValue
        r["status"] = status.rawValue as CKRecordValue; r["startDate"] = startDate as CKRecordValue
        r["durationDays"] = durationDays as CKRecordValue; r["assignedTo"] = assignedTo as CKRecordValue
        r["notes"] = notes as CKRecordValue; r["sortOrder"] = sortOrder as CKRecordValue
        r["progress"] = progress as CKRecordValue; CKField.setBool(r, "includesSaturdays", includesSaturdays)
        return r
    }

    static func from(_ record: CKRecord) -> GanttTask? {
        GanttTask(
            id: CKField.uuid(record, "uuid"), projectID: CKField.string(record, "projectID"),
            name: CKField.string(record, "name"),
            category: TaskCategory(rawValue: CKField.string(record, "category")) ?? .other,
            status: TaskStatus(rawValue: CKField.string(record, "status")) ?? .notStarted,
            startDate: CKField.date(record, "startDate"), durationDays: CKField.int(record, "durationDays"),
            assignedTo: CKField.string(record, "assignedTo"), notes: CKField.string(record, "notes"),
            sortOrder: CKField.int(record, "sortOrder"), progress: CKField.double(record, "progress"),
            includesSaturdays: CKField.bool(record, "includesSaturdays")
        )
    }
}

// MARK: - AuditEntry

extension AuditEntry: CloudKitConvertible {
    static let ckRecordType = "SS_AuditEntry"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue; r["timestamp"] = timestamp as CKRecordValue
        r["action"] = action.rawValue as CKRecordValue; r["entityType"] = entityType as CKRecordValue
        r["entityID"] = entityID as CKRecordValue; r["entityDescription"] = entityDescription as CKRecordValue
        r["userIdentifier"] = userIdentifier as CKRecordValue; r["userName"] = userName as CKRecordValue
        r["details"] = details as CKRecordValue
        return r
    }

    static func from(_ record: CKRecord) -> AuditEntry? {
        AuditEntry(
            id: CKField.uuid(record, "uuid"), timestamp: CKField.date(record, "timestamp"),
            action: AuditAction(rawValue: CKField.string(record, "action")) ?? .updated,
            entityType: CKField.string(record, "entityType"), entityID: CKField.string(record, "entityID"),
            entityDescription: CKField.string(record, "entityDescription"),
            userIdentifier: CKField.string(record, "userIdentifier"), userName: CKField.string(record, "userName"),
            details: CKField.string(record, "details")
        )
    }
}

// MARK: - TimesheetEntry

extension TimesheetEntry: CloudKitConvertible {
    static let ckRecordType = "SS_TimesheetEntry"
    var ckRecordName: String { id.uuidString }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue
        r["employeeName"] = employeeName as CKRecordValue
        r["employeeType"] = employeeType as CKRecordValue
        r["employeeRef"] = employeeRef as CKRecordValue
        r["projectName"] = projectName as CKRecordValue
        r["projectRef"] = projectRef as CKRecordValue
        CKField.setDecimal(r, "hourlyRate", hourlyRate)
        CKField.setDecimal(r, "mondayHours", mondayHours)
        CKField.setDecimal(r, "tuesdayHours", tuesdayHours)
        CKField.setDecimal(r, "wednesdayHours", wednesdayHours)
        CKField.setDecimal(r, "thursdayHours", thursdayHours)
        CKField.setDecimal(r, "fridayHours", fridayHours)
        CKField.setDecimal(r, "saturdayHours", saturdayHours)
        CKField.setDecimal(r, "sundayHours", sundayHours)
        CKField.setDecimal(r, "perDiem", perDiem)
        r["notes"] = notes as CKRecordValue
        r["weekStartDate"] = weekStartDate as CKRecordValue
        return r
    }

    static func from(_ record: CKRecord) -> TimesheetEntry? {
        TimesheetEntry(
            id: CKField.uuid(record, "uuid"),
            employeeName: CKField.string(record, "employeeName"),
            employeeType: CKField.string(record, "employeeType"),
            employeeRef: CKField.string(record, "employeeRef"),
            projectName: CKField.string(record, "projectName"),
            projectRef: CKField.string(record, "projectRef"),
            hourlyRate: CKField.decimal(record, "hourlyRate"),
            mondayHours: CKField.decimal(record, "mondayHours"),
            tuesdayHours: CKField.decimal(record, "tuesdayHours"),
            wednesdayHours: CKField.decimal(record, "wednesdayHours"),
            thursdayHours: CKField.decimal(record, "thursdayHours"),
            fridayHours: CKField.decimal(record, "fridayHours"),
            saturdayHours: CKField.decimal(record, "saturdayHours"),
            sundayHours: CKField.decimal(record, "sundayHours"),
            perDiem: CKField.decimal(record, "perDiem"),
            notes: CKField.string(record, "notes"),
            weekStartDate: CKField.date(record, "weekStartDate"),
            recordID: record.recordID
        )
    }
}

// MARK: - RFI

extension RFI: CloudKitConvertible {
    static let ckRecordType = "SS_RFI"

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType, recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["uuid"] = id.uuidString as CKRecordValue
        r["number"] = number as CKRecordValue
        r["subject"] = subject as CKRecordValue
        r["submittedTo"] = submittedTo as CKRecordValue
        r["submittedDate"] = submittedDate as CKRecordValue
        r["responseDueDate"] = responseDueDate as CKRecordValue
        if let d = responseReceivedDate { r["responseReceivedDate"] = d as CKRecordValue }
        r["status"] = status.rawValue as CKRecordValue
        r["priority"] = priority.rawValue as CKRecordValue
        r["notes"] = notes as CKRecordValue
        r["attachmentsJSON"] = CKField.encodeJSON(attachments) as CKRecordValue
        if let ref = projectRef { r["projectRef"] = ref }
        return r
    }

    static func from(_ record: CKRecord) -> RFI? {
        RFI(
            id: CKField.uuid(record, "uuid"),
            number: CKField.int(record, "number"),
            subject: CKField.string(record, "subject"),
            submittedTo: CKField.string(record, "submittedTo"),
            submittedDate: CKField.date(record, "submittedDate"),
            responseDueDate: CKField.date(record, "responseDueDate"),
            responseReceivedDate: CKField.optDate(record, "responseReceivedDate"),
            status: RFIStatus(rawValue: CKField.string(record, "status")) ?? .draft,
            priority: RFIPriority(rawValue: CKField.string(record, "priority")) ?? .medium,
            notes: CKField.string(record, "notes"),
            attachments: CKField.decodeJSON(record, "attachmentsJSON", as: [Attachment].self) ?? [],
            recordID: record.recordID
        )
    }
}

// MARK: - Overhead Expense

extension OverheadExpense: CloudKitConvertible {
    static let ckRecordType = "SS_OverheadExpense"
    var ckRecordName: String { recordID.recordName }

    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let r = CKRecord(recordType: Self.ckRecordType,
                         recordID: CKRecord.ID(recordName: ckRecordName, zoneID: zoneID))
        r["date"] = date as CKRecordValue
        CKField.setDecimal(r, "amount", amount)
        r["category"] = category.rawValue as CKRecordValue
        r["vendor"] = vendor as CKRecordValue
        r["expenseDescription"] = expenseDescription as CKRecordValue
        r["notes"] = notes as CKRecordValue
        r["recurrence"] = recurrence.rawValue as CKRecordValue
        if let parent = parentRecurringID {
            r["parentRecurringID"] = parent as CKRecordValue
        }
        r["distributionMode"] = distributionMode.rawValue as CKRecordValue
        r["distributionProjectIDsJSON"] = CKField.encodeJSON(distributionProjectIDs) as CKRecordValue
        r["attachmentsJSON"] = CKField.encodeJSON(attachments) as CKRecordValue

        // Upload actual file data as CKAssets for cross-device sync
        let assets: [CKAsset] = attachments.compactMap { att in
            guard let url = att.fileURL, FileManager.default.isReadableFile(atPath: url.path) else { return nil }
            return CKAsset(fileURL: url)
        }
        if !assets.isEmpty {
            r["attachmentAssets"] = assets as CKRecordValue
        }
        return r
    }

    static func from(_ record: CKRecord) -> OverheadExpense? {
        // Decode attachment metadata from JSON
        var attachments = CKField.decodeJSON(record, "attachmentsJSON", as: [Attachment].self) ?? []

        // If CKAsset files are present, download them to local storage and update file URLs
        let assets = record["attachmentAssets"] as? [CKAsset] ?? []
        let expenseID = record.recordID.recordName
        if !assets.isEmpty {
            let localFolder = (try? FileStorageService.overheadFolder(for: expenseID)) ?? FileStorageService.documentsRoot
            for i in 0..<min(assets.count, attachments.count) {
                guard let tempURL = assets[i].fileURL else { continue }
                let destURL = localFolder.appendingPathComponent(attachments[i].filename)
                if !FileManager.default.fileExists(atPath: destURL.path) {
                    try? FileManager.default.copyItem(at: tempURL, to: destURL)
                }
                let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path)
                let fileSize = attrs?[.size] as? Int64 ?? attachments[i].fileSize
                attachments[i] = Attachment(
                    id: attachments[i].id,
                    filename: attachments[i].filename,
                    fileSize: fileSize,
                    fileURL: destURL,
                    uploadedDate: attachments[i].uploadedDate
                )
            }
        }

        return OverheadExpense(
            recordID: record.recordID,
            date: CKField.date(record, "date"),
            amount: CKField.decimal(record, "amount"),
            category: OverheadCategory(rawValue: CKField.string(record, "category")) ?? .other,
            vendor: CKField.string(record, "vendor"),
            expenseDescription: CKField.string(record, "expenseDescription"),
            notes: CKField.string(record, "notes"),
            recurrence: RecurrenceInterval(rawValue: CKField.string(record, "recurrence")) ?? .none,
            parentRecurringID: CKField.optString(record, "parentRecurringID"),
            distributionMode: OverheadDistributionMode(rawValue: CKField.string(record, "distributionMode")) ?? .allActive,
            distributionProjectIDs: CKField.decodeJSON(record, "distributionProjectIDsJSON", as: [String].self) ?? [],
            attachments: attachments
        )
    }
}
