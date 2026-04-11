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

/// Preset hourly rates for a client's change order labor categories
struct ClientRateSchedule: Codable, Hashable {
    var foremanRate: Decimal
    var ironWorkerRate: Decimal
    var weldingGenRate: Decimal
    var truckAndToolsRate: Decimal
    var torchRate: Decimal
    var scissorLiftRate: Decimal
    var forkliftRate: Decimal
    var boomLiftRate: Decimal

    static let `default` = ClientRateSchedule(
        foremanRate: 75, ironWorkerRate: 55, weldingGenRate: 20,
        truckAndToolsRate: 15, torchRate: 15, scissorLiftRate: 25,
        forkliftRate: 55, boomLiftRate: 40
    )
}

struct Client: Identifiable, Hashable {
    var id: CKRecord.ID
    var name: String
    var contactName: String
    var email: String
    var phone: String
    var billingAddress: String
    var preferredRateType: RateType
    var rateSchedule: ClientRateSchedule

    init(
        id: CKRecord.ID = CKRecord.ID(recordName: UUID().uuidString),
        name: String,
        contactName: String = "",
        email: String = "",
        phone: String = "",
        billingAddress: String = "",
        preferredRateType: RateType = .subcontractor,
        rateSchedule: ClientRateSchedule = .default
    ) {
        self.id = id
        self.name = name
        self.contactName = contactName
        self.email = email
        self.phone = phone
        self.billingAddress = billingAddress
        self.preferredRateType = preferredRateType
        self.rateSchedule = rateSchedule
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
