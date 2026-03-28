import Foundation
import CloudKit

struct Project: Identifiable, Hashable {
    var id: CKRecord.ID
    var clientRef: CKRecord.Reference?       // primary client (kept for backwards compat)
    var gcClientRef: CKRecord.Reference?     // General Contractor
    var subClientRef: CKRecord.Reference?    // Subcontractor
    var title: String
    var location: String
    var contractAmount: Decimal
    var startDate: Date?
    var endDate: Date?
    var actualCompletionDate: Date?
    var status: String
    var changeOrderCounter: Int
    var notes: String
    var balanceSummary: ProjectBalanceSummary
    var completionSummary: String?
    var originalBidID: String?
    var progressOverride: Double?

    init(
        id: CKRecord.ID = CKRecord.ID(recordName: UUID().uuidString),
        clientRef: CKRecord.Reference? = nil,
        gcClientRef: CKRecord.Reference? = nil,
        subClientRef: CKRecord.Reference? = nil,
        title: String,
        location: String = "",
        contractAmount: Decimal,
        startDate: Date? = Date(),
        endDate: Date? = nil,
        actualCompletionDate: Date? = nil,
        status: String = "Active",
        changeOrderCounter: Int = 0,
        notes: String = "",
        balanceSummary: ProjectBalanceSummary = ProjectBalanceSummary(),
        completionSummary: String? = nil,
        originalBidID: String? = nil,
        progressOverride: Double? = nil
    ) {
        self.id = id
        self.clientRef = clientRef
        self.gcClientRef = gcClientRef
        self.subClientRef = subClientRef
        self.title = title
        self.location = location
        self.contractAmount = contractAmount
        self.startDate = startDate
        self.endDate = endDate
        self.actualCompletionDate = actualCompletionDate
        self.status = status
        self.changeOrderCounter = changeOrderCounter
        self.notes = notes
        self.balanceSummary = balanceSummary
        self.completionSummary = completionSummary
        self.originalBidID = originalBidID
        self.progressOverride = progressOverride
    }

    var totalRevenue: Decimal { balanceSummary.contractAmount + balanceSummary.changeOrderTotal }
    var totalPayments: Decimal { balanceSummary.paymentsTotal }
    var totalCosts: Decimal { balanceSummary.totalCosts }
    var remainingBalance: Decimal { balanceSummary.remainingContractBalance }
    var profit: Decimal { balanceSummary.profit }

    var computedStatus: String {
        let now = Date()
        if actualCompletionDate != nil { return "Completed" }
        if let start = startDate, start > now { return "Upcoming" }
        if let start = startDate, start <= now { return "Active" }
        return status
    }

    var profitMargin: Double {
        guard totalRevenue > 0 else { return 0 }
        return Double(truncating: (profit / totalRevenue * 100) as NSDecimalNumber)
    }

    var progress: Double {
        if let override = progressOverride {
            return min(max(override, 0.0), 1.0)
        }
        guard totalRevenue > 0 else { return 0 }
        return Double(truncating: (totalPayments / totalRevenue) as NSDecimalNumber)
    }

    var changeOrders: [ChangeOrder] { [] }
    var payments: [Payment] { [] }
    var payrollEntries: [PayrollEntry] { [] }
}

enum PaymentAppliesTo: Int, Codable {
    case contract
    case changeOrder
}

struct ProjectBalanceSummary: Codable, Hashable {
    var contractAmount: Decimal
    var changeOrderTotal: Decimal
    var paymentsTotal: Decimal
    var costTotal: Decimal
    var payrollTotal: Decimal

    init(
        contractAmount: Decimal = 0,
        changeOrderTotal: Decimal = 0,
        paymentsTotal: Decimal = 0,
        costTotal: Decimal = 0,
        payrollTotal: Decimal = 0
    ) {
        self.contractAmount = contractAmount
        self.changeOrderTotal = changeOrderTotal
        self.paymentsTotal = paymentsTotal
        self.costTotal = costTotal
        self.payrollTotal = payrollTotal
    }

    var totalCosts: Decimal { costTotal + payrollTotal }
    var remainingContractBalance: Decimal { contractAmount + changeOrderTotal - paymentsTotal }
    var profit: Decimal { (contractAmount + changeOrderTotal) - totalCosts }
}

// MARK: - Labor & Equipment Categories (J&R Standard Rates)

enum LaborCategory: String, Codable, CaseIterable, Identifiable {
    case foreman = "Foreman"
    case ironWorkers = "Iron Workers"
    case weldingGenerators = "Welding Generators"
    case truckAndTools = "Truck and Tools"
    case torch = "Torch"
    case scissorLift = "Scissor Lift"
    case forkliftTelehandler = "Forklift/Telehandler"
    case boomLift = "Boom Lift"

    var id: String { rawValue }
    var displayName: String { rawValue }

    var defaultRate: Decimal {
        switch self {
        case .foreman: return 75
        case .ironWorkers: return 55
        case .weldingGenerators: return 20
        case .truckAndTools: return 15
        case .torch: return 15
        case .scissorLift: return 25
        case .forkliftTelehandler: return 55
        case .boomLift: return 40
        }
    }
}

struct LaborLineItem: Identifiable, Codable, Hashable {
    let id: UUID
    var category: LaborCategory
    var quantity: Decimal
    var hours: Decimal
    var rate: Decimal

    var lineTotal: Decimal { quantity * hours * rate }

    init(id: UUID = UUID(), category: LaborCategory, quantity: Decimal = 0, hours: Decimal = 0, rate: Decimal? = nil) {
        self.id = id; self.category = category
        self.quantity = quantity; self.hours = hours
        self.rate = rate ?? category.defaultRate
    }

    static func defaultSet() -> [LaborLineItem] {
        LaborCategory.allCases.map { LaborLineItem(category: $0) }
    }
}

struct AdditionalChargeItem: Identifiable, Codable, Hashable {
    let id: UUID
    var description: String
    var quantity: Decimal
    var hours: Decimal
    var rate: Decimal

    var lineTotal: Decimal { quantity * hours * rate }

    init(id: UUID = UUID(), description: String = "", quantity: Decimal = 0, hours: Decimal = 0, rate: Decimal = 0) {
        self.id = id; self.description = description
        self.quantity = quantity; self.hours = hours; self.rate = rate
    }
}

// MARK: - Change Order / Work Order Invoice

struct ChangeOrder: Identifiable, Codable, Hashable {
    let id: UUID
    var number: Int
    var description: String
    var amount: Decimal
    var submittedDate: Date
    var signedDate: Date?
    var scope: String
    var resourceUsage: [ResourceUsage]
    var attachments: [Attachment]
    var recordID: CKRecord.ID?
    var projectRef: CKRecord.Reference?

    // Invoice fields
    var invoiceNumber: String
    var invoiceDate: Date
    var workOrderNumber: String
    var poNumber: String
    var laborLineItems: [LaborLineItem]
    var additionalCharges: [AdditionalChargeItem]
    var taxRate: Decimal
    var paymentTerms: String
    var additionalNotes: String

    enum CodingKeys: String, CodingKey {
        case id, number, description, amount, submittedDate, signedDate, scope
        case resourceUsage, attachments
        case invoiceNumber, invoiceDate, workOrderNumber, poNumber
        case laborLineItems, additionalCharges, taxRate, paymentTerms, additionalNotes
    }

    init(
        id: UUID = UUID(),
        number: Int,
        description: String,
        amount: Decimal = 0,
        submittedDate: Date = Date(),
        signedDate: Date? = nil,
        scope: String = "",
        resourceUsage: [ResourceUsage] = [],
        attachments: [Attachment] = [],
        recordID: CKRecord.ID? = nil,
        projectRef: CKRecord.Reference? = nil,
        invoiceNumber: String = "",
        invoiceDate: Date = Date(),
        workOrderNumber: String = "",
        poNumber: String = "",
        laborLineItems: [LaborLineItem] = LaborLineItem.defaultSet(),
        additionalCharges: [AdditionalChargeItem] = [],
        taxRate: Decimal = 0,
        paymentTerms: String = "Net 30 Days",
        additionalNotes: String = ""
    ) {
        self.id = id; self.number = number; self.description = description
        self.amount = amount; self.submittedDate = submittedDate; self.signedDate = signedDate
        self.scope = scope; self.resourceUsage = resourceUsage; self.attachments = attachments
        self.recordID = recordID; self.projectRef = projectRef
        self.invoiceNumber = invoiceNumber; self.invoiceDate = invoiceDate
        self.workOrderNumber = workOrderNumber; self.poNumber = poNumber
        self.laborLineItems = laborLineItems; self.additionalCharges = additionalCharges
        self.taxRate = taxRate; self.paymentTerms = paymentTerms; self.additionalNotes = additionalNotes
    }

    var isSigned: Bool { signedDate != nil }

    var laborSubtotal: Decimal { laborLineItems.reduce(0) { $0 + $1.lineTotal } }
    var additionalSubtotal: Decimal { additionalCharges.reduce(0) { $0 + $1.lineTotal } }
    var subtotal: Decimal { laborSubtotal + additionalSubtotal }
    var taxAmount: Decimal {
        var result = Decimal()
        var val = subtotal * taxRate / 100
        NSDecimalRound(&result, &val, 2, .plain)
        return result
    }
    var totalDue: Decimal { subtotal + taxAmount }
}

struct Payment: Identifiable, Codable, Hashable {
    let id: UUID
    var amount: Decimal
    var date: Date
    var appliedToChangeOrder: UUID?
    var notes: String
    var attachments: [Attachment]
    var recordID: CKRecord.ID?
    var projectRef: CKRecord.Reference?

    enum CodingKeys: String, CodingKey {
        case id, amount, date, appliedToChangeOrder, notes, attachments
    }

    init(
        id: UUID = UUID(), amount: Decimal, date: Date = Date(),
        appliedToChangeOrder: UUID? = nil, notes: String = "", attachments: [Attachment] = [],
        recordID: CKRecord.ID? = nil, projectRef: CKRecord.Reference? = nil
    ) {
        self.id = id; self.amount = amount; self.date = date
        self.appliedToChangeOrder = appliedToChangeOrder; self.notes = notes
        self.attachments = attachments; self.recordID = recordID; self.projectRef = projectRef
    }
}

struct EmployeePayrollDetail: Identifiable, Codable, Hashable {
    let id: UUID
    var employeeName: String
    var hourlyRate: Decimal
    var hoursWorked: Decimal
    var projectName: String
    var totalPay: Decimal { hourlyRate * hoursWorked }

    init(id: UUID = UUID(), employeeName: String, hourlyRate: Decimal, hoursWorked: Decimal, projectName: String) {
        self.id = id; self.employeeName = employeeName; self.hourlyRate = hourlyRate
        self.hoursWorked = hoursWorked; self.projectName = projectName
    }
}

struct PayrollEntry: Identifiable, Codable, Hashable {
    let id: UUID
    var weekNumber: Int
    var year: Int
    var totalHours: Decimal
    var totalAmount: Decimal
    var notes: String
    var employeeDetails: [EmployeePayrollDetail]
    var recordID: CKRecord.ID?
    var projectRef: CKRecord.Reference?

    enum CodingKeys: String, CodingKey {
        case id, weekNumber, year, totalHours, totalAmount, notes, employeeDetails
    }

    init(
        id: UUID = UUID(), weekNumber: Int, year: Int, totalHours: Decimal,
        totalAmount: Decimal, notes: String = "", employeeDetails: [EmployeePayrollDetail] = [],
        recordID: CKRecord.ID? = nil, projectRef: CKRecord.Reference? = nil
    ) {
        self.id = id; self.weekNumber = weekNumber; self.year = year
        self.totalHours = totalHours; self.totalAmount = totalAmount; self.notes = notes
        self.employeeDetails = employeeDetails; self.recordID = recordID; self.projectRef = projectRef
    }

    var weekStartDate: Date {
        Calendar.current.date(from: DateComponents(weekOfYear: weekNumber, yearForWeekOfYear: year)) ?? Date()
    }
    var weekEndDate: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: weekStartDate) ?? Date()
    }
    var weekDateRange: String { "\(weekStartDate.shortDate) - \(weekEndDate.shortDate)" }
    var employeesByProject: [String: [EmployeePayrollDetail]] {
        Dictionary(grouping: employeeDetails, by: { $0.projectName })
    }
}

struct Cost: Identifiable, Codable, Hashable {
    let id: UUID
    var category: CostCategory
    var description: String
    var amount: Decimal
    var date: Date
    var attachments: [Attachment]
    var recordID: CKRecord.ID?
    var projectRef: CKRecord.Reference?

    enum CodingKeys: String, CodingKey {
        case id, category, description, amount, date, attachments
    }

    enum CostCategory: String, Codable, CaseIterable {
        case machinery = "Machinery"
        case hotel = "Hotel/Hospitality"
        case gas = "Gas"
        case diesel = "Diesel"
        case insurance = "Insurance"
        case materialsAndTools = "Materials & Tools"
        case subcontractor = "Subcontractor"
        case permits = "Permits"
        case other = "Other"

        var categoryGroup: CostCategoryGroup {
            switch self {
            case .machinery: return .machinery
            case .hotel, .gas, .diesel, .insurance, .materialsAndTools: return .overhead
            case .subcontractor, .permits, .other: return .other
            }
        }
        var displayName: String { rawValue }
    }

    enum CostCategoryGroup: String, CaseIterable {
        case machinery = "Machinery"
        case overhead = "Overhead"
        case other = "Other Costs"

        var categories: [CostCategory] {
            switch self {
            case .machinery: return [.machinery]
            case .overhead: return [.hotel, .gas, .diesel, .insurance, .materialsAndTools]
            case .other: return [.subcontractor, .permits, .other]
            }
        }
    }

    init(
        id: UUID = UUID(), category: CostCategory, description: String, amount: Decimal,
        date: Date = Date(), attachments: [Attachment] = [],
        recordID: CKRecord.ID? = nil, projectRef: CKRecord.Reference? = nil
    ) {
        self.id = id; self.category = category; self.description = description
        self.amount = amount; self.date = date; self.attachments = attachments
        self.recordID = recordID; self.projectRef = projectRef
    }
}

extension Project {
    static let preview = Project(
        title: "Downtown Office Tower",
        location: "123 Main St, City, ST",
        contractAmount: 250_000,
        startDate: Date().addingTimeInterval(-86400 * 60),
        endDate: Date().addingTimeInterval(86400 * 30),
        status: "Active",
        notes: "On schedule. Client is satisfied with progress.",
        balanceSummary: ProjectBalanceSummary(
            contractAmount: 250_000, changeOrderTotal: 15_000,
            paymentsTotal: 180_000, costTotal: 95_000, payrollTotal: 45_000
        )
    )
}
