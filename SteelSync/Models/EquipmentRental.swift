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

    enum CodingKeys: String, CodingKey {
        case id, equipmentRateID, equipmentName, dailyRate, weeklyRate, fourWeekRate
        case startDate, endDate, includeDelivery, includePickup, deliveryChargePerTrip
        case unitInfo, fuelGallons, fuelPricePerGallon
        case notes, calculatedCost, costBreakdown, linkedCostID
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
        projectRef: CKRecord.Reference? = nil
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

    var daysSinceStart: Int {
        let days = Calendar.current.dateComponents([.day], from: startDate.startOfDay, to: Date().startOfDay).day ?? 0
        return max(days + 1, 1)
    }

    var totalDeliveryCharges: Decimal {
        (includeDelivery ? deliveryChargePerTrip : 0) + (includePickup ? deliveryChargePerTrip : 0)
    }

    var totalCost: Decimal? {
        guard let rental = calculatedCost else { return nil }
        return rental
    }

    // MARK: - All-In Cost (includes EDTX surcharges)

    /// Computes total cost including env fee, dealer tax, delivery, and optionally fuel
    func allInCost(forDays days: Int, fuelGal: Decimal = 0, fuelPrice: Decimal = 0) -> Decimal {
        let base = EquipmentRental.calculateOptimalCost(totalDays: days, daily: dailyRate, weekly: weeklyRate, fourWeek: fourWeekRate).cost
        let envFee = Self.round2(base * EquipmentRate.environmentalFeeRate)
        let dealerTax = Self.round2(base * EquipmentRate.dealerInventoryTaxRate)
        let fuel = Self.round2(fuelGal * fuelPrice)
        return base + envFee + dealerTax + totalDeliveryCharges + fuel
    }

    /// Full line-item breakdown for display
    func detailedCost(forDays days: Int, fuelGal: Decimal = 0, fuelPrice: Decimal = 0) -> RentalCostDetail {
        let result = EquipmentRental.calculateOptimalCost(totalDays: days, daily: dailyRate, weekly: weeklyRate, fourWeek: fourWeekRate)
        let envFee = Self.round2(result.cost * EquipmentRate.environmentalFeeRate)
        let dealerTax = Self.round2(result.cost * EquipmentRate.dealerInventoryTaxRate)
        let fuel = Self.round2(fuelGal * fuelPrice)
        let subtotal = result.cost + envFee + dealerTax + totalDeliveryCharges + fuel
        return RentalCostDetail(
            equipmentCost: result.cost, breakdown: result.breakdown,
            environmentalFee: envFee, dealerInventoryTax: dealerTax,
            deliveryCharges: totalDeliveryCharges, fuelCharge: fuel,
            subtotal: subtotal
        )
    }

    var estimatedActiveCost: Decimal {
        allInCost(forDays: daysSinceStart)
    }

    // MARK: - Billing Cutoff Analysis

    var nextWeekCutoffDay: Int { ((daysSinceStart - 1) / 7 + 1) * 7 }
    var nextMonthCutoffDay: Int { ((daysSinceStart - 1) / 28 + 1) * 28 }
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
    let subtotal: Decimal
}
