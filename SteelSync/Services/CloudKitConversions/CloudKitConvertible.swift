import Foundation
import CloudKit

// MARK: - Protocol

protocol CloudKitConvertible {
    static var ckRecordType: String { get }
    var ckRecordName: String { get }
    func toCKRecord(in zoneID: CKRecordZone.ID) -> CKRecord
    static func from(_ record: CKRecord) -> Self?
}

// MARK: - Field Encoding/Decoding Helpers

enum CKField {
    static func decimal(_ record: CKRecord, _ key: String) -> Decimal {
        Decimal((record[key] as? Double) ?? 0)
    }

    static func string(_ record: CKRecord, _ key: String) -> String {
        (record[key] as? String) ?? ""
    }

    static func optString(_ record: CKRecord, _ key: String) -> String? {
        record[key] as? String
    }

    static func int(_ record: CKRecord, _ key: String) -> Int {
        Int((record[key] as? Int64) ?? 0)
    }

    static func double(_ record: CKRecord, _ key: String) -> Double {
        (record[key] as? Double) ?? 0
    }

    static func bool(_ record: CKRecord, _ key: String) -> Bool {
        ((record[key] as? Int64) ?? 0) != 0
    }

    static func date(_ record: CKRecord, _ key: String) -> Date {
        (record[key] as? Date) ?? Date()
    }

    static func optDate(_ record: CKRecord, _ key: String) -> Date? {
        record[key] as? Date
    }

    static func optDecimal(_ record: CKRecord, _ key: String) -> Decimal? {
        guard let d = record[key] as? Double else { return nil }
        return Decimal(d)
    }

    static func optDouble(_ record: CKRecord, _ key: String) -> Double? {
        record[key] as? Double
    }

    static func uuid(_ record: CKRecord, _ key: String) -> UUID {
        UUID(uuidString: (record[key] as? String) ?? "") ?? UUID()
    }

    static func optUUID(_ record: CKRecord, _ key: String) -> UUID? {
        guard let s = record[key] as? String else { return nil }
        return UUID(uuidString: s)
    }

    static func ref(_ record: CKRecord, _ key: String) -> CKRecord.Reference? {
        record[key] as? CKRecord.Reference
    }

    static func setDecimal(_ record: CKRecord, _ key: String, _ val: Decimal) {
        record[key] = NSDecimalNumber(decimal: val).doubleValue as CKRecordValue
    }

    static func setOptDecimal(_ record: CKRecord, _ key: String, _ val: Decimal?) {
        if let v = val { setDecimal(record, key, v) }
    }

    static func setBool(_ record: CKRecord, _ key: String, _ val: Bool) {
        record[key] = (val ? 1 : 0) as CKRecordValue
    }

    static func setRef(_ record: CKRecord, _ key: String, _ recordName: String?, zoneID: CKRecordZone.ID) {
        guard let name = recordName else { return }
        record[key] = CKRecord.Reference(recordID: CKRecord.ID(recordName: name, zoneID: zoneID), action: .none)
    }

    static func encodeJSON<T: Encodable>(_ val: T) -> String {
        (try? String(data: JSONEncoder().encode(val), encoding: .utf8)) ?? "[]"
    }

    static func decodeJSON<T: Decodable>(_ record: CKRecord, _ key: String, as type: T.Type) -> T? {
        guard let str = record[key] as? String, let data = str.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
