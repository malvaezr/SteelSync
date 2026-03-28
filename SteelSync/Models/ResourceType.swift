import Foundation
import SwiftUI

enum ResourceType: String, Codable, CaseIterable, Identifiable {
    case foreman = "Foreman"
    case ironworker = "Ironworker"
    case weldingMachine = "Welding Machine"
    case cuttingRig = "Cutting Rig"
    case truckAndTools = "Truck & Tools"
    case scissorLift = "Scissor/Boom/Forklift"
    case crane = "Crane"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .foreman: return "person.fill.checkmark"
        case .ironworker: return "person.fill"
        case .weldingMachine: return "flame.fill"
        case .cuttingRig: return "scissors"
        case .truckAndTools: return "truck.box.fill"
        case .scissorLift: return "arrow.up.arrow.down"
        case .crane: return "crane.fill"
        case .other: return "wrench.and.screwdriver.fill"
        }
    }

    var color: Color {
        switch self {
        case .foreman: return .blue
        case .ironworker: return .green
        case .weldingMachine: return .orange
        case .cuttingRig: return .red
        case .truckAndTools: return .purple
        case .scissorLift: return .yellow
        case .crane: return .cyan
        case .other: return .gray
        }
    }

    var unit: String {
        switch self {
        case .foreman, .ironworker: return "hours"
        default: return "units"
        }
    }
}

struct RateSchedule: Identifiable, Codable, Hashable {
    let id: UUID
    var clientID: UUID?
    var resourceRates: [ResourceType: ResourceRate]
    var effectiveDate: Date

    enum CodingKeys: String, CodingKey {
        case id, clientID, resourceRates, effectiveDate
    }

    init(id: UUID = UUID(), clientID: UUID? = nil, resourceRates: [ResourceType: ResourceRate] = [:], effectiveDate: Date = Date()) {
        self.id = id; self.clientID = clientID; self.resourceRates = resourceRates; self.effectiveDate = effectiveDate
    }

    func rate(for resource: ResourceType, type: RateType) -> Decimal {
        resourceRates[resource]?.rate(for: type) ?? 0
    }
}

struct ResourceRate: Codable, Hashable {
    var subcontractorRate: Decimal
    var generalContractorRate: Decimal

    func rate(for type: RateType) -> Decimal {
        switch type {
        case .subcontractor: return subcontractorRate
        case .generalContractor: return generalContractorRate
        }
    }
}

struct ResourceUsage: Codable, Hashable, Identifiable {
    let id: UUID
    var resourceType: ResourceType
    var quantity: Decimal

    init(id: UUID = UUID(), resourceType: ResourceType, quantity: Decimal) {
        self.id = id; self.resourceType = resourceType; self.quantity = quantity
    }
}
