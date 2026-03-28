import Foundation
import CloudKit

struct SampleData {
    // Stable client IDs for linking
    private static let acmeID = CKRecord.ID(recordName: "client-acme")
    private static let metroID = CKRecord.ID(recordName: "client-metro")
    private static let pacificID = CKRecord.ID(recordName: "client-pacific")
    private static let summitID = CKRecord.ID(recordName: "client-summit")

    static let clients: [Client] = [
        Client(id: acmeID, name: "Acme Developers", contactName: "John Smith",
               email: "john@acme.com", phone: "(555) 123-4567",
               billingAddress: "100 Developer Way, Austin, TX 78701",
               preferredRateType: .generalContractor),
        Client(id: metroID, name: "Metro Construction Co", contactName: "Sarah Johnson",
               email: "sarah@metro.com", phone: "(555) 234-5678",
               billingAddress: "250 Builder Blvd, Austin, TX 78702",
               preferredRateType: .generalContractor),
        Client(id: pacificID, name: "Pacific Steel Group", contactName: "Mike Chen",
               email: "mike@pacific.com", phone: "(555) 345-6789",
               billingAddress: "500 Steel Ave, San Marcos, TX 78666",
               preferredRateType: .subcontractor),
        Client(id: summitID, name: "Summit Building Corp", contactName: "Lisa Davis",
               email: "lisa@summit.com", phone: "(555) 456-7890",
               billingAddress: "800 Summit Dr, Cedar Park, TX 78613",
               preferredRateType: .subcontractor)
    ]

    static let projects: [Project] = [
        Project(clientRef: CKRecord.Reference(recordID: acmeID, action: .none),
                title: "Downtown Office Tower", location: "123 Main St, Austin, TX", contractAmount: 485_000,
                startDate: Date().addingTimeInterval(-86400 * 45), endDate: Date().addingTimeInterval(86400 * 60), status: "Active",
                balanceSummary: ProjectBalanceSummary(contractAmount: 485_000, changeOrderTotal: 32_000, paymentsTotal: 285_000, costTotal: 125_000, payrollTotal: 85_000)),
        Project(clientRef: CKRecord.Reference(recordID: metroID, action: .none),
                title: "Harrison Bridge Expansion", location: "Highway 71 Bridge, Bastrop, TX", contractAmount: 320_000,
                startDate: Date().addingTimeInterval(-86400 * 90), endDate: Date().addingTimeInterval(86400 * 15), status: "Active",
                balanceSummary: ProjectBalanceSummary(contractAmount: 320_000, changeOrderTotal: 18_000, paymentsTotal: 248_000, costTotal: 95_000, payrollTotal: 72_000)),
        Project(clientRef: CKRecord.Reference(recordID: pacificID, action: .none),
                title: "Riverside Medical Center", location: "500 River Rd, San Marcos, TX", contractAmount: 750_000,
                startDate: Date().addingTimeInterval(86400 * 14), status: "Upcoming",
                balanceSummary: ProjectBalanceSummary(contractAmount: 750_000)),
        Project(clientRef: CKRecord.Reference(recordID: summitID, action: .none),
                title: "Cedar Park Warehouse", location: "1200 Commerce Blvd, Cedar Park, TX", contractAmount: 195_000,
                startDate: Date().addingTimeInterval(-86400 * 120), actualCompletionDate: Date().addingTimeInterval(-86400 * 10), status: "Completed",
                balanceSummary: ProjectBalanceSummary(contractAmount: 195_000, changeOrderTotal: 8_500, paymentsTotal: 203_500, costTotal: 62_000, payrollTotal: 48_000))
    ]

    static let bids: [BidProject] = [
        BidProject(projectName: "Metro Tower Phase 2", clientName: "Metro Construction Co",
                   clientRef: CKRecord.Reference(recordID: metroID, action: .none),
                   address: "456 Commerce Dr, Austin, TX",
                   bidAmount: 620_000, bidDueDate: Date().addingTimeInterval(86400 * 7), squareFeet: 65000,
                   numberOfBeams: 180, numberOfColumns: 60, numberOfJoists: 240, estimatedTons: 385,
                   touchpoints: [Touchpoint(type: .call, date: Date().addingTimeInterval(-86400 * 3), notes: "Discussed scope and timeline"),
                                 Touchpoint(type: .email, date: Date().addingTimeInterval(-86400), notes: "Sent preliminary estimate")]),
        BidProject(projectName: "Lakeway Resort Expansion", clientName: "Summit Building Corp",
                   clientRef: CKRecord.Reference(recordID: summitID, action: .none),
                   address: "789 Lake Travis Blvd, Lakeway, TX",
                   bidAmount: 410_000, bidDueDate: Date().addingTimeInterval(86400 * 21),
                   isReadyToSubmit: true,
                   squareFeet: 42000, numberOfBeams: 95, numberOfColumns: 38, estimatedTons: 220),
        BidProject(projectName: "Airport Hangar B", clientName: "Pacific Steel Group",
                   clientRef: CKRecord.Reference(recordID: pacificID, action: .none),
                   address: "Austin-Bergstrom Intl Airport",
                   bidAmount: 890_000, bidDueDate: Date().addingTimeInterval(-86400 * 5), isSubmitted: true,
                   submittedDate: Date().addingTimeInterval(-86400 * 5), squareFeet: 95000, estimatedTons: 580),
        BidProject(projectName: "Round Rock Sports Complex", clientName: "Acme Developers",
                   clientRef: CKRecord.Reference(recordID: acmeID, action: .none),
                   address: "2100 Sports Way, Round Rock, TX",
                   bidAmount: 275_000, bidDueDate: Date().addingTimeInterval(-86400 * 30), isSubmitted: true,
                   submittedDate: Date().addingTimeInterval(-86400 * 30), isLost: true, squareFeet: 32000, estimatedTons: 150)
    ]

    static let employees: [Employee] = [
        Employee(employeeID: "JRF-001", firstName: "Carlos", lastName: "Rodriguez", phone: "(555) 111-2222", employeeType: .foreman, defaultHourlyRate: 45),
        Employee(employeeID: "JRF-002", firstName: "James", lastName: "Williams", phone: "(555) 222-3333", employeeType: .w2, defaultHourlyRate: 35),
        Employee(employeeID: "JRF-003", firstName: "Miguel", lastName: "Santos", phone: "(555) 333-4444", employeeType: .w2, defaultHourlyRate: 35),
        Employee(employeeID: "JRF-004", firstName: "David", lastName: "Martinez", phone: "(555) 444-5555", employeeType: .contractor, defaultHourlyRate: 42),
        Employee(employeeID: "JRF-005", firstName: "Robert", lastName: "Johnson", phone: "(555) 555-6666", employeeType: .foreman, defaultHourlyRate: 45)
    ]

    static let todos: [TodoItem] = TodoItem.sampleTodos

    static let calendarEvents: [CalendarEvent] = [
        CalendarEvent(title: "Downtown Tower - Steel Delivery", description: "First steel shipment arriving", startDate: Date().addingTimeInterval(86400 * 2), type: .delivery),
        CalendarEvent(title: "Harrison Bridge - Inspection", description: "DOT structural inspection", startDate: Date().addingTimeInterval(86400 * 5), type: .inspection),
        CalendarEvent(title: "Metro Tower Bid Meeting", description: "Final scope review with client", startDate: Date().addingTimeInterval(86400 * 6), type: .meeting),
        CalendarEvent(title: "Riverside Medical - Milestone", description: "Foundation complete target", startDate: Date().addingTimeInterval(86400 * 30), type: .milestone),
        CalendarEvent(title: "Quarterly Safety Review", description: "All hands safety meeting", startDate: Date().addingTimeInterval(86400 * 10), type: .meeting, isAllDay: true)
    ]
}
