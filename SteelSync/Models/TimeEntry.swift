import Foundation
import CloudKit

struct TimeEntry: Identifiable, Hashable {
    var id: UUID
    var assignmentRef: CKRecord.Reference
    var projectRef: CKRecord.Reference
    var employeeRef: CKRecord.Reference
    var clockInTime: Date
    var clockOutTime: Date?
    var totalHours: Decimal
    var hourlyRate: Decimal
    var totalPay: Decimal
    var entryType: TimeEntryType
    var notes: String
    var createdByForeman: Bool
    var createdDate: Date
    var modifiedDate: Date?
    var modifiedByAdmin: Bool
    var recordID: CKRecord.ID?

    init(
        id: UUID = UUID(), assignmentRef: CKRecord.Reference, projectRef: CKRecord.Reference,
        employeeRef: CKRecord.Reference, clockInTime: Date, clockOutTime: Date? = nil,
        totalHours: Decimal = 0, hourlyRate: Decimal, totalPay: Decimal = 0,
        entryType: TimeEntryType = .regular, notes: String = "",
        createdByForeman: Bool = true, createdDate: Date = Date(),
        modifiedDate: Date? = nil, modifiedByAdmin: Bool = false, recordID: CKRecord.ID? = nil
    ) {
        self.id = id; self.assignmentRef = assignmentRef; self.projectRef = projectRef
        self.employeeRef = employeeRef; self.clockInTime = clockInTime
        self.clockOutTime = clockOutTime; self.hourlyRate = hourlyRate
        self.entryType = entryType; self.notes = notes
        self.createdByForeman = createdByForeman; self.createdDate = createdDate
        self.modifiedDate = modifiedDate; self.modifiedByAdmin = modifiedByAdmin
        self.recordID = recordID

        if let clockOut = clockOutTime {
            self.totalHours = Self.calculateHours(from: clockInTime, to: clockOut)
            self.totalPay = self.totalHours * hourlyRate
        } else {
            self.totalHours = totalHours
            self.totalPay = totalPay
        }
    }

    static func calculateHours(from start: Date, to end: Date) -> Decimal {
        let interval = end.timeIntervalSince(start)
        return Decimal(interval / 3600).rounded(2)
    }

    var isClockedIn: Bool { clockOutTime == nil }
    var hoursWorked: String { String(format: "%.2f hrs", NSDecimalNumber(decimal: totalHours).doubleValue) }
    var payAmount: String { totalPay.currencyFormatted }

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: clockInTime)
    }

    var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let start = formatter.string(from: clockInTime)
        if let clockOut = clockOutTime {
            return "\(start) - \(formatter.string(from: clockOut))"
        }
        return "\(start) - Present"
    }
}

enum TimeEntryType: String, CaseIterable {
    case regular = "Regular"
    case adminOverride = "Admin Override"
    var displayName: String { rawValue }
}

extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var result = self
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, scale, .plain)
        return rounded
    }
}
