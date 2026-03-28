import Foundation
import CloudKit

struct Employee: Identifiable, Codable, Hashable {
    var id: UUID
    var employeeID: String
    var firstName: String
    var lastName: String
    var email: String
    var phone: String
    var employeeType: EmployeeType
    var defaultHourlyRate: Decimal
    var status: EmployeeStatus
    var notes: String
    var createdDate: Date
    var updatedDate: Date
    var recordID: CKRecord.ID?

    enum CodingKeys: String, CodingKey {
        case id, employeeID, firstName, lastName, email, phone
        case employeeType, defaultHourlyRate, status, notes, createdDate, updatedDate
    }

    init(
        id: UUID = UUID(), employeeID: String, firstName: String, lastName: String,
        email: String = "", phone: String = "", employeeType: EmployeeType,
        defaultHourlyRate: Decimal, status: EmployeeStatus = .active, notes: String = "",
        createdDate: Date = Date(), updatedDate: Date = Date(), recordID: CKRecord.ID? = nil
    ) {
        self.id = id; self.employeeID = employeeID; self.firstName = firstName
        self.lastName = lastName; self.email = email; self.phone = phone
        self.employeeType = employeeType; self.defaultHourlyRate = defaultHourlyRate
        self.status = status; self.notes = notes; self.createdDate = createdDate
        self.updatedDate = updatedDate; self.recordID = recordID
    }

    var fullName: String { "\(firstName) \(lastName)" }
    var isActive: Bool { status == .active }
    var isForeman: Bool { employeeType == .foreman }
}

enum EmployeeType: String, Codable, CaseIterable {
    case w2 = "W2"
    case contractor = "Contractor"
    case foreman = "Foreman"
    var displayName: String { rawValue }
}

enum EmployeeStatus: String, Codable, CaseIterable {
    case active = "Active"
    case inactive = "Inactive"
    case terminated = "Terminated"
    var displayName: String { rawValue }
}
