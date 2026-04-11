import Foundation
import CloudKit

// MARK: - Pay Application (AIA G703 Schedule of Values)

struct PayApplication: Identifiable, Codable, Hashable {
    let id: UUID
    var applicationNumber: Int
    var applicationDate: Date
    var periodTo: Date
    var projectID: String  // CKRecord.ID recordName
    var retainageRate: Decimal  // e.g., 0.10 for 10%
    var lineItems: [SOVLineItem]
    var notes: String

    init(
        id: UUID = UUID(),
        applicationNumber: Int = 1,
        applicationDate: Date = Date(),
        periodTo: Date = Date(),
        projectID: String,
        retainageRate: Decimal = 0.10,
        lineItems: [SOVLineItem] = [],
        notes: String = ""
    ) {
        self.id = id
        self.applicationNumber = applicationNumber
        self.applicationDate = applicationDate
        self.periodTo = periodTo
        self.projectID = projectID
        self.retainageRate = retainageRate
        self.lineItems = lineItems
        self.notes = notes
    }

    // MARK: - Computed Totals

    /// Column C: Total scheduled value of all line items
    var totalScheduledValue: Decimal {
        lineItems.reduce(0) { $0 + $1.scheduledValue }
    }

    /// Column D: Total work completed from previous applications
    var totalPreviousCompleted: Decimal {
        lineItems.reduce(0) { $0 + $1.previousCompleted }
    }

    /// Column E: Total work completed this period
    var totalThisPeriod: Decimal {
        lineItems.reduce(0) { $0 + $1.thisPeriodCompleted }
    }

    /// Column F: Total materials presently stored
    var totalMaterialsStored: Decimal {
        lineItems.reduce(0) { $0 + $1.materialsStored }
    }

    /// Column G: Total completed and stored to date (D + E + F)
    var totalCompletedToDate: Decimal {
        lineItems.reduce(0) { $0 + $1.totalCompletedToDate }
    }

    /// Overall completion percentage (G / C)
    var overallPercentComplete: Double {
        guard totalScheduledValue > 0 else { return 0 }
        return Double(truncating: (totalCompletedToDate / totalScheduledValue * 100) as NSDecimalNumber)
    }

    /// Column H: Total balance to finish (C - G)
    var totalBalanceToFinish: Decimal {
        lineItems.reduce(0) { $0 + $1.balanceToFinish }
    }

    /// Column I: Total retainage
    var totalRetainage: Decimal {
        lineItems.reduce(0) { $0 + $1.retainage(at: retainageRate) }
    }

    /// Net amount due this period (this period work - retainage on this period)
    var netAmountThisPeriod: Decimal {
        totalThisPeriod + totalMaterialsStored
    }
}

// MARK: - Schedule of Values Line Item

struct SOVLineItem: Identifiable, Codable, Hashable {
    let id: UUID
    var itemNumber: Int
    var description: String
    var scheduledValue: Decimal          // Column C: Original contract + CO value
    var previousCompleted: Decimal       // Column D: Sum from all previous pay apps
    var thisPeriodCompleted: Decimal      // Column E: Work completed this billing period
    var materialsStored: Decimal          // Column F: Materials on site, not yet installed
    var isChangeOrder: Bool              // True if this line item is from a CO
    var changeOrderID: UUID?             // Reference to the source CO if applicable

    init(
        id: UUID = UUID(),
        itemNumber: Int = 1,
        description: String,
        scheduledValue: Decimal,
        previousCompleted: Decimal = 0,
        thisPeriodCompleted: Decimal = 0,
        materialsStored: Decimal = 0,
        isChangeOrder: Bool = false,
        changeOrderID: UUID? = nil
    ) {
        self.id = id
        self.itemNumber = itemNumber
        self.description = description
        self.scheduledValue = scheduledValue
        self.previousCompleted = previousCompleted
        self.thisPeriodCompleted = thisPeriodCompleted
        self.materialsStored = materialsStored
        self.isChangeOrder = isChangeOrder
        self.changeOrderID = changeOrderID
    }

    /// Column G: Total completed and stored to date
    var totalCompletedToDate: Decimal {
        previousCompleted + thisPeriodCompleted + materialsStored
    }

    /// Percentage complete (G / C)
    var percentComplete: Double {
        guard scheduledValue > 0 else { return 0 }
        return Double(truncating: (totalCompletedToDate / scheduledValue * 100) as NSDecimalNumber)
    }

    /// Column H: Balance to finish (C - G)
    var balanceToFinish: Decimal {
        scheduledValue - totalCompletedToDate
    }

    /// Column I: Retainage at given rate
    func retainage(at rate: Decimal) -> Decimal {
        var result = Decimal()
        var val = totalCompletedToDate * rate
        NSDecimalRound(&result, &val, 2, .plain)
        return result
    }

    /// Maximum that can be billed this period (scheduled - previous)
    var maxBillableThisPeriod: Decimal {
        scheduledValue - previousCompleted
    }
}
