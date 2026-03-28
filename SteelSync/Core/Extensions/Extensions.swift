import Foundation

// MARK: - Date Extensions
extension Date {
    func formatted(_ format: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter.string(from: self)
    }

    var shortDate: String { formatted("MMM d, yyyy") }
    var mediumDate: String { formatted("MMMM d, yyyy") }

    var timeAgo: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }
        return shortDate
    }

    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var isFuture: Bool { self > Date() }
    var isPast: Bool { self < Date() }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    func adding(months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }
}

// MARK: - CKRecord Codable Support
import CloudKit

struct CodableCKRecordID: Codable, Hashable {
    let recordName: String
    init(_ id: CKRecord.ID) { self.recordName = id.recordName }
    var ckRecordID: CKRecord.ID { CKRecord.ID(recordName: recordName) }
}

struct CodableCKReference: Codable, Hashable {
    let recordName: String
    init(_ ref: CKRecord.Reference) { self.recordName = ref.recordID.recordName }
    var ckReference: CKRecord.Reference { CKRecord.Reference(recordID: CKRecord.ID(recordName: recordName), action: .none) }
}

// MARK: - Decimal Extensions
extension Decimal {
    var currencyFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: self as NSDecimalNumber) ?? "$0"
    }

    var currencyWithCents: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: self as NSDecimalNumber) ?? "$0.00"
    }

    var decimalFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return formatter.string(from: self as NSDecimalNumber) ?? "0"
    }
}
