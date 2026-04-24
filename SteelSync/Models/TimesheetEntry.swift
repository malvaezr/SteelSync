import Foundation
import CloudKit

/// A single row in the weekly timesheet grid.
/// Each entry = one worker + one project + daily hours for one pay period week.
struct TimesheetEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var employeeName: String            // "Byron Aguilar"
    var employeeType: String            // "1099", "W2", "Foreman"
    var employeeRef: String             // Employee record name for linking
    var projectName: String             // "Ward & Burke Warehouse"
    var projectRef: String              // Project record name for linking
    var hourlyRate: Decimal
    var mondayHours: Decimal
    var tuesdayHours: Decimal
    var wednesdayHours: Decimal
    var thursdayHours: Decimal
    var fridayHours: Decimal
    var saturdayHours: Decimal
    var sundayHours: Decimal
    var perDiem: Decimal
    var notes: String
    var weekStartDate: Date             // Monday of the pay period
    var recordID: CKRecord.ID?

    init(
        id: UUID = UUID(),
        employeeName: String = "",
        employeeType: String = "",
        employeeRef: String = "",
        projectName: String = "",
        projectRef: String = "",
        hourlyRate: Decimal = 0,
        mondayHours: Decimal = 0,
        tuesdayHours: Decimal = 0,
        wednesdayHours: Decimal = 0,
        thursdayHours: Decimal = 0,
        fridayHours: Decimal = 0,
        saturdayHours: Decimal = 0,
        sundayHours: Decimal = 0,
        perDiem: Decimal = 0,
        notes: String = "",
        weekStartDate: Date = TimesheetEntry.currentWeekStart(),
        recordID: CKRecord.ID? = nil
    ) {
        self.id = id
        self.employeeName = employeeName
        self.employeeType = employeeType
        self.employeeRef = employeeRef
        self.projectName = projectName
        self.projectRef = projectRef
        self.hourlyRate = hourlyRate
        self.mondayHours = mondayHours
        self.tuesdayHours = tuesdayHours
        self.wednesdayHours = wednesdayHours
        self.thursdayHours = thursdayHours
        self.fridayHours = fridayHours
        self.saturdayHours = saturdayHours
        self.sundayHours = sundayHours
        self.perDiem = perDiem
        self.notes = notes
        self.weekStartDate = weekStartDate
        self.recordID = recordID
    }

    // MARK: - Computed

    var totalHours: Decimal {
        mondayHours + tuesdayHours + wednesdayHours + thursdayHours + fridayHours + saturdayHours + sundayHours
    }

    /// Number of days in the week that have any hours logged. Drives per-diem
    /// calculation since `perDiem` is a per-day rate, not a weekly total.
    var daysWorked: Int {
        [mondayHours, tuesdayHours, wednesdayHours, thursdayHours, fridayHours, saturdayHours, sundayHours]
            .reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
    }

    /// Total per-diem for the week: `perDiem` (per-day rate) × `daysWorked`.
    var totalPerDiem: Decimal {
        perDiem * Decimal(daysWorked)
    }

    var totalPay: Decimal {
        (hourlyRate * totalHours) + totalPerDiem
    }

    var displayName: String {
        let type = employeeType.isEmpty ? "" : " (\(employeeType))"
        return "\(employeeName)\(type)"
    }

    var weekEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? weekStartDate
    }

    var weekLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let start = fmt.string(from: weekStartDate)
        let end = fmt.string(from: weekEndDate)
        let yearFmt = DateFormatter()
        yearFmt.dateFormat = ", yyyy"
        return "\(start) - \(end)\(yearFmt.string(from: weekStartDate))"
    }

    // MARK: - Helpers

    static func currentWeekStart() -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        // Monday = 2 in Calendar. Shift to Monday-based week.
        let daysToMonday = (weekday == 1) ? -6 : (2 - weekday)
        return cal.date(byAdding: .day, value: daysToMonday, to: today) ?? today
    }

    static func weekStart(for date: Date) -> Date {
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: day)
        let daysToMonday = (weekday == 1) ? -6 : (2 - weekday)
        return cal.date(byAdding: .day, value: daysToMonday, to: day) ?? day
    }

    // CodingKeys excluding recordID (not Codable)
    enum CodingKeys: String, CodingKey {
        case id, employeeName, employeeType, employeeRef
        case projectName, projectRef, hourlyRate
        case mondayHours, tuesdayHours, wednesdayHours, thursdayHours
        case fridayHours, saturdayHours, sundayHours
        case perDiem, notes, weekStartDate
    }
}
