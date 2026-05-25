import Foundation
import CloudKit

// MARK: - Equipment Rate (Vendor Catalog)

struct EquipmentRate: Identifiable, Hashable {
    let id: UUID
    var name: String
    var dailyRate: Decimal
    var weeklyRate: Decimal
    var fourWeekRate: Decimal
    var vendor: String

    init(id: UUID = UUID(), name: String, dailyRate: Decimal, weeklyRate: Decimal, fourWeekRate: Decimal, vendor: String = "Equipment Depot Texas") {
        self.id = id; self.name = name
        self.dailyRate = dailyRate; self.weeklyRate = weeklyRate; self.fourWeekRate = fourWeekRate
        self.vendor = vendor
    }

    // EDTX standard charges
    static let edtxDeliveryCharge: Decimal = 140
    static let environmentalFeeRate = Decimal(sign: .plus, exponent: -3, significand: 24)   // 2.4%
    static let dealerInventoryTaxRate = Decimal(sign: .plus, exponent: -4, significand: 23)  // 0.23%
    /// Texas state + Corpus Christi local. EDTX invoices apply this on top of
    /// (equipment + env + dealer tax + delivery + fuel). Real EDTX invoices
    /// often run a few percent higher because of additional rental-specific
    /// surcharges, but 8.25% lands within ±$50–$100 on typical rentals.
    static let salesTaxRate = Decimal(sign: .plus, exponent: -4, significand: 825)          // 8.25%
    static let defaultFuelPricePerGallon = Decimal(sign: .plus, exponent: -2, significand: 995) // $9.95

    static let edtxCatalog: [EquipmentRate] = [
        EquipmentRate(name: "IC Pneum-5k", dailyRate: 280, weeklyRate: 725, fourWeekRate: 1385),
        EquipmentRate(name: "IC Cush Tire-5k", dailyRate: 250, weeklyRate: 680, fourWeekRate: 1360),
        EquipmentRate(name: "19' Slab Scissor", dailyRate: 150, weeklyRate: 290, fourWeekRate: 345),
        EquipmentRate(name: "Jib", dailyRate: 100, weeklyRate: 200, fourWeekRate: 325),
        EquipmentRate(name: "26' Slab Scissor", dailyRate: 195, weeklyRate: 405, fourWeekRate: 605),
        EquipmentRate(name: "32' Slab Scissor", dailyRate: 255, weeklyRate: 500, fourWeekRate: 805),
        EquipmentRate(name: "39'/40' Large Slab Scissor", dailyRate: 343, weeklyRate: 790, fourWeekRate: 1350),
        EquipmentRate(name: "26' RT Scissor", dailyRate: 265, weeklyRate: 705, fourWeekRate: 1005),
        EquipmentRate(name: "32'/33' RT Scissor", dailyRate: 321, weeklyRate: 795, fourWeekRate: 1225),
        EquipmentRate(name: "45' Straight Boom w/jib", dailyRate: 430, weeklyRate: 1050, fourWeekRate: 1625),
        EquipmentRate(name: "45' IC Articulating Boom w/jib", dailyRate: 430, weeklyRate: 1050, fourWeekRate: 1625),
        EquipmentRate(name: "65'/66' Straight Boom w/jib", dailyRate: 545, weeklyRate: 1270, fourWeekRate: 2150),
        EquipmentRate(name: "60' IC Articulating Boom w/jib", dailyRate: 540, weeklyRate: 1250, fourWeekRate: 2150),
        EquipmentRate(name: "85'/86' Straight Boom w/jib", dailyRate: 850, weeklyRate: 2100, fourWeekRate: 3750),
        EquipmentRate(name: "5.5K Telehandler", dailyRate: 415, weeklyRate: 1090, fourWeekRate: 1875),
        EquipmentRate(name: "6k Telehandler", dailyRate: 485, weeklyRate: 1270, fourWeekRate: 2005),
        EquipmentRate(name: "8k Telehandler", dailyRate: 525, weeklyRate: 1400, fourWeekRate: 2300),
        EquipmentRate(name: "10k Telehandler", dailyRate: 740, weeklyRate: 1875, fourWeekRate: 3200),
    ]
}

// MARK: - Equipment Request & Reconciliation

/// How a request was communicated to the supplier (for the documented record).
enum RentalContactMethod: String, Codable, CaseIterable, Identifiable {
    case phone = "Phone Call"
    case text = "Text"
    case email = "Email"
    case inPerson = "In Person"
    case portal = "Online Portal"
    case other = "Other"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .phone: return "phone.fill"
        case .text: return "message.fill"
        case .email: return "envelope.fill"
        case .inPerson: return "person.fill"
        case .portal: return "globe"
        case .other: return "ellipsis.circle"
        }
    }
}

/// Kind of entry in a rental's request/communication log.
enum RentalRequestKind: String, Codable {
    case deliveryRequested = "Delivery Requested"
    case deliveryConfirmed = "Delivery Confirmed"
    case pickupRequested = "Pickup Requested"     // the "cut" / off-rent request
    case pickupConfirmed = "Pickup Confirmed"
    case note = "Note"

    var icon: String {
        switch self {
        case .deliveryRequested: return "shippingbox.and.arrow.backward.fill"
        case .deliveryConfirmed: return "checkmark.circle.fill"
        case .pickupRequested: return "arrow.up.bin.fill"
        case .pickupConfirmed: return "checkmark.seal.fill"
        case .note: return "note.text"
        }
    }
    var isPickup: Bool { self == .pickupRequested || self == .pickupConfirmed }
    var isDelivery: Bool { self == .deliveryRequested || self == .deliveryConfirmed }
}

/// A single timestamped entry in a rental's request log — the documented paper
/// trail used to resolve date disputes with the supplier. `loggedAt` is set
/// once at creation and never edited.
struct RentalRequestEvent: Codable, Identifiable, Hashable {
    var id: UUID
    var kind: RentalRequestKind
    var requestedDate: Date?     // the date we asked the action to happen (deliver-by / pickup-by)
    var loggedAt: Date           // immutable timestamp this entry was recorded
    var method: RentalContactMethod
    var contactName: String      // supplier rep contacted
    var loggedBy: String         // our team member who made the request
    var notes: String

    init(id: UUID = UUID(), kind: RentalRequestKind, requestedDate: Date? = nil,
         loggedAt: Date = Date(), method: RentalContactMethod = .text,
         contactName: String = "", loggedBy: String = "", notes: String = "") {
        self.id = id; self.kind = kind; self.requestedDate = requestedDate
        self.loggedAt = loggedAt; self.method = method
        self.contactName = contactName; self.loggedBy = loggedBy; self.notes = notes
    }
}

/// State of checking a supplier invoice against our documented dates.
enum InvoiceCheckStatus: String, Codable, CaseIterable, Identifiable {
    case notReceived = "Not Received"
    case underReview = "Under Review"
    case matches = "Matches Our Records"
    case disputed = "Disputed"
    case approved = "Approved"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .notReceived: return "tray"
        case .underReview: return "magnifyingglass"
        case .matches: return "checkmark.circle"
        case .disputed: return "exclamationmark.triangle.fill"
        case .approved: return "checkmark.seal.fill"
        }
    }
}

/// High-level lifecycle stage, derived from dates + the request log.
enum RentalLifecycle: String {
    case requested = "Requested"
    case onRent = "On Rent"
    case pickupRequested = "Pickup Requested"
    case closed = "Closed"
}

// MARK: - Equipment Rental (Per-Project Instance)

struct EquipmentRental: Identifiable, Codable, Hashable {
    let id: UUID
    var equipmentRateID: UUID
    var equipmentName: String
    var dailyRate: Decimal
    var weeklyRate: Decimal
    var fourWeekRate: Decimal
    var startDate: Date
    var endDate: Date?
    var includeDelivery: Bool
    var includePickup: Bool
    var deliveryChargePerTrip: Decimal
    var unitInfo: String
    var fuelGallons: Decimal
    var fuelPricePerGallon: Decimal
    var notes: String
    var calculatedCost: Decimal?
    var costBreakdown: String?
    var linkedCostID: UUID?
    var recordID: CKRecord.ID?
    var projectRef: CKRecord.Reference?

    // MARK: - Request log + supplier-invoice reconciliation
    // All optional for Codable back-compat: rentals saved before this feature
    // decode these missing keys as nil (synthesized Codable handles optionals).
    var requestLog: [RentalRequestEvent]?
    var supplierInvoiceNumber: String?
    var invoiceReceivedDate: Date?
    var billedStartDate: Date?
    var billedEndDate: Date?
    var billedAmount: Decimal?
    var invoiceStatusRaw: String?
    var invoiceCheckNotes: String?

    enum CodingKeys: String, CodingKey {
        case id, equipmentRateID, equipmentName, dailyRate, weeklyRate, fourWeekRate
        case startDate, endDate, includeDelivery, includePickup, deliveryChargePerTrip
        case unitInfo, fuelGallons, fuelPricePerGallon
        case notes, calculatedCost, costBreakdown, linkedCostID
        case requestLog, supplierInvoiceNumber, invoiceReceivedDate
        case billedStartDate, billedEndDate, billedAmount, invoiceStatusRaw, invoiceCheckNotes
    }

    init(
        id: UUID = UUID(),
        equipmentRateID: UUID,
        equipmentName: String,
        dailyRate: Decimal,
        weeklyRate: Decimal,
        fourWeekRate: Decimal,
        startDate: Date = Date(),
        endDate: Date? = nil,
        includeDelivery: Bool = true,
        includePickup: Bool = true,
        deliveryChargePerTrip: Decimal = EquipmentRate.edtxDeliveryCharge,
        unitInfo: String = "",
        fuelGallons: Decimal = 0,
        fuelPricePerGallon: Decimal = EquipmentRate.defaultFuelPricePerGallon,
        notes: String = "",
        calculatedCost: Decimal? = nil,
        costBreakdown: String? = nil,
        linkedCostID: UUID? = nil,
        recordID: CKRecord.ID? = nil,
        projectRef: CKRecord.Reference? = nil,
        requestLog: [RentalRequestEvent]? = nil,
        supplierInvoiceNumber: String? = nil,
        invoiceReceivedDate: Date? = nil,
        billedStartDate: Date? = nil,
        billedEndDate: Date? = nil,
        billedAmount: Decimal? = nil,
        invoiceStatusRaw: String? = nil,
        invoiceCheckNotes: String? = nil
    ) {
        self.id = id; self.equipmentRateID = equipmentRateID
        self.equipmentName = equipmentName
        self.dailyRate = dailyRate; self.weeklyRate = weeklyRate; self.fourWeekRate = fourWeekRate
        self.startDate = startDate; self.endDate = endDate
        self.includeDelivery = includeDelivery; self.includePickup = includePickup
        self.deliveryChargePerTrip = deliveryChargePerTrip
        self.unitInfo = unitInfo
        self.fuelGallons = fuelGallons; self.fuelPricePerGallon = fuelPricePerGallon
        self.notes = notes; self.calculatedCost = calculatedCost; self.costBreakdown = costBreakdown
        self.linkedCostID = linkedCostID; self.recordID = recordID; self.projectRef = projectRef
        self.requestLog = requestLog
        self.supplierInvoiceNumber = supplierInvoiceNumber
        self.invoiceReceivedDate = invoiceReceivedDate
        self.billedStartDate = billedStartDate
        self.billedEndDate = billedEndDate
        self.billedAmount = billedAmount
        self.invoiceStatusRaw = invoiceStatusRaw
        self.invoiceCheckNotes = invoiceCheckNotes
    }

    // MARK: - Request log + lifecycle + reconciliation

    /// Ergonomic accessor over the optional `requestLog`.
    var events: [RentalRequestEvent] {
        get { requestLog ?? [] }
        set { requestLog = newValue.isEmpty ? nil : newValue }
    }

    var invoiceStatus: InvoiceCheckStatus {
        get { InvoiceCheckStatus(rawValue: invoiceStatusRaw ?? "") ?? .notReceived }
        set { invoiceStatusRaw = newValue.rawValue }
    }

    /// Most recent pickup ("cut") request — the off-rent date we're on record for.
    var latestPickupRequest: RentalRequestEvent? {
        events.filter { $0.kind == .pickupRequested }.max { $0.loggedAt < $1.loggedAt }
    }
    /// Earliest delivery request — our documented on-rent ask.
    var firstDeliveryRequest: RentalRequestEvent? {
        events.filter { $0.kind == .deliveryRequested }.min { $0.loggedAt < $1.loggedAt }
    }

    var lifecycle: RentalLifecycle {
        if endDate != nil { return .closed }
        if events.contains(where: { $0.kind == .pickupRequested }) { return .pickupRequested }
        let confirmedDelivery = events.contains { $0.kind == .deliveryConfirmed }
        let futureStartRequested = startDate.startOfDay > Date().startOfDay
            && events.contains { $0.kind == .deliveryRequested }
        if futureStartRequested && !confirmedDelivery { return .requested }
        return .onRent
    }

    /// Our documented start date: first delivery request's requested date, else `startDate`.
    var documentedStartDate: Date { firstDeliveryRequest?.requestedDate ?? startDate }
    /// Our documented off-rent date: latest pickup request's requested date, else actual `endDate`.
    var documentedOffRentDate: Date? { latestPickupRequest?.requestedDate ?? endDate }

    /// Comparison of a supplier invoice's billed dates against our documented
    /// dates. nil until any billed field is entered.
    var invoiceComparison: InvoiceComparison? {
        guard billedStartDate != nil || billedEndDate != nil || billedAmount != nil else { return nil }
        let cal = Calendar.current
        var startDelta: Int?
        if let bs = billedStartDate {
            startDelta = cal.dateComponents([.day], from: documentedStartDate.startOfDay, to: bs.startOfDay).day
        }
        var endOver: Int?
        var estOver: Decimal?
        if let be = billedEndDate, let off = documentedOffRentDate {
            let d = cal.dateComponents([.day], from: off.startOfDay, to: be.startOfDay).day ?? 0
            endOver = d
            if d > 0 { estOver = Decimal(d) * dailyRate }  // rough: extra days at the daily rate
        }
        var amtDelta: Decimal?
        if let ba = billedAmount, let est = calculatedCost { amtDelta = ba - est }
        let mismatch = (startDelta ?? 0) != 0 || (endOver ?? 0) != 0
        return InvoiceComparison(
            startDeltaDays: startDelta, endOverbillDays: endOver,
            estimatedOverbillAmount: estOver, amountDelta: amtDelta, hasMismatch: mismatch
        )
    }

    // MARK: - Rounding Helper

    private static func round2(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var val = value
        NSDecimalRound(&result, &val, 2, .plain)
        return result
    }

    // MARK: - Computed Properties

    var isActive: Bool { endDate == nil }

    var rentalDays: Int? {
        guard let end = endDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: startDate.startOfDay, to: end.startOfDay).day ?? 0
        return max(days + 1, 1)
    }

    /// Days of active rental. Returns 0 if the start date is in the future (scheduled but not yet on rent).
    var daysSinceStart: Int {
        let days = Calendar.current.dateComponents([.day], from: startDate.startOfDay, to: Date().startOfDay).day ?? 0
        guard days >= 0 else { return 0 }  // Future start date — not on rent yet
        return days + 1
    }

    /// True if the rental has not started yet (future start date)
    var isScheduled: Bool { startDate.startOfDay > Date().startOfDay }

    var totalDeliveryCharges: Decimal {
        (includeDelivery ? deliveryChargePerTrip : 0) + (includePickup ? deliveryChargePerTrip : 0)
    }

    var totalCost: Decimal? {
        guard let rental = calculatedCost else { return nil }
        return rental
    }

    // MARK: - All-In Cost (includes EDTX surcharges)

    /// Computes total cost including env fee, dealer tax, delivery, fuel, and
    /// 8.25% sales tax on the resulting subtotal.
    func allInCost(forDays days: Int, fuelGal: Decimal = 0, fuelPrice: Decimal = 0) -> Decimal {
        let base = EquipmentRental.calculateOptimalCost(totalDays: days, daily: dailyRate, weekly: weeklyRate, fourWeek: fourWeekRate).cost
        let envFee = Self.round2(base * EquipmentRate.environmentalFeeRate)
        let dealerTax = Self.round2(base * EquipmentRate.dealerInventoryTaxRate)
        let fuel = Self.round2(fuelGal * fuelPrice)
        let preTax = base + envFee + dealerTax + totalDeliveryCharges + fuel
        let salesTax = Self.round2(preTax * EquipmentRate.salesTaxRate)
        return preTax + salesTax
    }

    /// Full line-item breakdown for display
    func detailedCost(forDays days: Int, fuelGal: Decimal = 0, fuelPrice: Decimal = 0) -> RentalCostDetail {
        let result = EquipmentRental.calculateOptimalCost(totalDays: days, daily: dailyRate, weekly: weeklyRate, fourWeek: fourWeekRate)
        let envFee = Self.round2(result.cost * EquipmentRate.environmentalFeeRate)
        let dealerTax = Self.round2(result.cost * EquipmentRate.dealerInventoryTaxRate)
        let fuel = Self.round2(fuelGal * fuelPrice)
        let preTax = result.cost + envFee + dealerTax + totalDeliveryCharges + fuel
        let salesTax = Self.round2(preTax * EquipmentRate.salesTaxRate)
        return RentalCostDetail(
            equipmentCost: result.cost, breakdown: result.breakdown,
            environmentalFee: envFee, dealerInventoryTax: dealerTax,
            deliveryCharges: totalDeliveryCharges, fuelCharge: fuel,
            preTaxSubtotal: preTax, salesTax: salesTax,
            subtotal: preTax + salesTax
        )
    }

    var estimatedActiveCost: Decimal {
        guard daysSinceStart > 0 else { return 0 }  // Not on rent yet
        return allInCost(forDays: daysSinceStart)
    }

    // MARK: - Billing Cutoff Analysis

    var nextWeekCutoffDay: Int {
        guard daysSinceStart > 0 else { return 7 }
        return ((daysSinceStart - 1) / 7 + 1) * 7
    }
    var nextMonthCutoffDay: Int {
        guard daysSinceStart > 0 else { return 28 }
        return ((daysSinceStart - 1) / 28 + 1) * 28
    }
    var daysUntilWeekCutoff: Int { nextWeekCutoffDay - daysSinceStart }
    var daysUntilMonthCutoff: Int { nextMonthCutoffDay - daysSinceStart }

    var weekCutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: nextWeekCutoffDay - 1, to: startDate.startOfDay) ?? startDate
    }

    var monthCutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: nextMonthCutoffDay - 1, to: startDate.startOfDay) ?? startDate
    }

    /// All-in cost if returned today (no fuel estimate for active)
    var costIfCloseToday: Decimal { allInCost(forDays: daysSinceStart) }

    /// All-in cost if kept until end of current weekly period
    var costAtWeekCutoff: Decimal { allInCost(forDays: nextWeekCutoffDay) }

    /// All-in cost if kept until end of current 4-week period
    var costAtMonthCutoff: Decimal { allInCost(forDays: nextMonthCutoffDay) }

    var weekCutoffDelta: Decimal { costAtWeekCutoff - costIfCloseToday }
    var monthCutoffDelta: Decimal { costAtMonthCutoff - costIfCloseToday }
    var currentWeekPeriod: Int { (daysSinceStart - 1) / 7 + 1 }
    var currentMonthPeriod: Int { (daysSinceStart - 1) / 28 + 1 }

    var currentBreakdown: String {
        EquipmentRental.calculateOptimalCost(totalDays: daysSinceStart, daily: dailyRate, weekly: weeklyRate, fourWeek: fourWeekRate).breakdown
    }

    // MARK: - Cost Calculation Algorithm

    static func calculateOptimalCost(totalDays: Int, daily: Decimal, weekly: Decimal, fourWeek: Decimal) -> (cost: Decimal, breakdown: String) {
        guard totalDays > 0 else { return (0, "0 days") }

        var fourWeekPeriods = totalDays / 28
        var remaining = totalDays % 28
        var weeks = remaining / 7
        var days = remaining % 7

        if days > 0 && (Decimal(days) * daily) > weekly {
            weeks += 1
            days = 0
        }

        if weeks > 0 && (Decimal(weeks) * weekly) > fourWeek {
            fourWeekPeriods += 1
            weeks = 0
        }

        let weeksPlusDaysCost = (Decimal(weeks) * weekly) + (Decimal(days) * daily)
        if weeksPlusDaysCost > fourWeek && (weeks > 0 || days > 0) {
            fourWeekPeriods += 1
            weeks = 0
            days = 0
        }

        let cost = (Decimal(fourWeekPeriods) * fourWeek) + (Decimal(weeks) * weekly) + (Decimal(days) * daily)

        var parts: [String] = []
        if fourWeekPeriods > 0 {
            parts.append("\(fourWeekPeriods) x 4-week (\((Decimal(fourWeekPeriods) * fourWeek).currencyFormatted))")
        }
        if weeks > 0 {
            parts.append("\(weeks) x week (\((Decimal(weeks) * weekly).currencyFormatted))")
        }
        if days > 0 {
            parts.append("\(days) x day (\((Decimal(days) * daily).currencyFormatted))")
        }
        let breakdown = parts.isEmpty ? "0 days" : parts.joined(separator: " + ")

        return (cost, breakdown)
    }
}

// MARK: - Rental Cost Detail (line-item breakdown)

struct RentalCostDetail {
    let equipmentCost: Decimal
    let breakdown: String
    let environmentalFee: Decimal
    let dealerInventoryTax: Decimal
    let deliveryCharges: Decimal
    let fuelCharge: Decimal
    /// Sum of equipment + env + dealer tax + delivery + fuel — i.e. EDTX
    /// "Subtotal" line, before sales tax is layered on.
    let preTaxSubtotal: Decimal
    /// 8.25% sales tax computed on `preTaxSubtotal`.
    let salesTax: Decimal
    /// Final invoice total (`preTaxSubtotal + salesTax`).
    let subtotal: Decimal
}

// MARK: - Invoice Comparison (supplier invoice vs our documented dates)

struct InvoiceComparison {
    /// billedStart − our documented start, in days (≠0 ⇒ start-date mismatch).
    var startDeltaDays: Int?
    /// billedEnd − our documented off-rent date, in days (>0 ⇒ billed past our cut date).
    var endOverbillDays: Int?
    /// Rough $ of the over-billed days at the daily rate.
    var estimatedOverbillAmount: Decimal?
    /// billedAmount − our calculated estimate.
    var amountDelta: Decimal?
    /// True when start or end dates don't line up with our records.
    var hasMismatch: Bool
}
