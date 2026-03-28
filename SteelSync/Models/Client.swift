import Foundation
import CloudKit

enum RateType: Int, Codable, CaseIterable {
    case subcontractor = 0
    case generalContractor = 1

    var displayName: String {
        switch self {
        case .subcontractor: return "Subcontractor"
        case .generalContractor: return "General Contractor"
        }
    }
}

struct Client: Identifiable, Hashable {
    var id: CKRecord.ID
    var name: String
    var contactName: String
    var email: String
    var phone: String
    var billingAddress: String
    var preferredRateType: RateType

    init(
        id: CKRecord.ID = CKRecord.ID(recordName: UUID().uuidString),
        name: String,
        contactName: String = "",
        email: String = "",
        phone: String = "",
        billingAddress: String = "",
        preferredRateType: RateType = .subcontractor
    ) {
        self.id = id
        self.name = name
        self.contactName = contactName
        self.email = email
        self.phone = phone
        self.billingAddress = billingAddress
        self.preferredRateType = preferredRateType
    }
}

extension Client {
    static let preview = Client(
        name: "Acme Developers",
        contactName: "John Smith",
        email: "contact@acme.com",
        phone: "(555) 123-4567",
        billingAddress: "123 Main St, City, ST 12345"
    )
}
