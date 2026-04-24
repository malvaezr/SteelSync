import Foundation
import CloudKit

// MARK: - Invoice

/// First-class invoice record for SteelSync.
///
/// Most J&R invoices flow from pay apps: a user creates a PayApplication, fills
/// out the SOV, and clicks "Mark as Sent" — which creates an Invoice linked via
/// `linkedPayAppID`. Invoices can also stand alone (equipment rental to another
/// sub, T&M work, closeout retainage release) — those have `linkedPayAppID == nil`
/// and `type == .standalone` or `.retainageRelease`.
///
/// The Invoice is the source of truth for billing state (sent / paid / overdue).
/// A linked PayApplication keeps its SOV line items; the Invoice just references it.
struct Invoice: Identifiable, Codable, Hashable {
    let id: UUID
    var invoiceNumber: String           // e.g. "GATX-PA-003", hybrid auto+manual
    var type: InvoiceType
    var status: InvoiceStatus
    var amount: Decimal                 // Total amount billed on this invoice
    var retainageHeld: Decimal          // Amount withheld for retainage
    var sentDate: Date?                 // nil = draft, set on "Mark as Sent"
    var dueDate: Date?                  // Typically sentDate + paymentTermsDays
    var paidDate: Date?                 // Set when isFullyPaid flips to true
    var paymentTermsDays: Int           // Default 30 (net 30), editable per invoice
    var linkedPayAppID: UUID?           // Nil for standalone invoices
    var projectID: String               // CKRecord.ID recordName, matches PayApp
    var clientName: String              // Snapshotted at creation (bill-to name)
    /// CKRecord.ID recordName of the client this invoice is billed to.
    /// Persisted so per-client balances stay accurate even if the project's
    /// GC/Sub assignment changes later.
    var billToClientID: String?
    var notes: String
    var attachments: [Attachment]       // Generated PDFs, backup docs
    var recordID: CKRecord.ID?
    var projectRef: CKRecord.Reference?

    enum CodingKeys: String, CodingKey {
        case id, invoiceNumber, type, status, amount, retainageHeld
        case sentDate, dueDate, paidDate, paymentTermsDays
        case linkedPayAppID, projectID, clientName, billToClientID, notes, attachments
    }

    init(
        id: UUID = UUID(),
        invoiceNumber: String = "",
        type: InvoiceType = .payApplication,
        status: InvoiceStatus = .draft,
        amount: Decimal = 0,
        retainageHeld: Decimal = 0,
        sentDate: Date? = nil,
        dueDate: Date? = nil,
        paidDate: Date? = nil,
        paymentTermsDays: Int = 30,
        linkedPayAppID: UUID? = nil,
        projectID: String,
        clientName: String = "",
        billToClientID: String? = nil,
        notes: String = "",
        attachments: [Attachment] = [],
        recordID: CKRecord.ID? = nil,
        projectRef: CKRecord.Reference? = nil
    ) {
        self.id = id
        self.invoiceNumber = invoiceNumber
        self.type = type
        self.status = status
        self.amount = amount
        self.retainageHeld = retainageHeld
        self.sentDate = sentDate
        self.dueDate = dueDate
        self.paidDate = paidDate
        self.paymentTermsDays = paymentTermsDays
        self.linkedPayAppID = linkedPayAppID
        self.projectID = projectID
        self.clientName = clientName
        self.billToClientID = billToClientID
        self.notes = notes
        self.attachments = attachments
        self.recordID = recordID
        self.projectRef = projectRef
    }

    // MARK: - Computed

    /// The amount actually owed by the GC (what's on the invoice face).
    /// = amount - retainageHeld
    var netAmountDue: Decimal {
        amount - retainageHeld
    }

    /// Returns true once sentDate has passed the dueDate and not yet fully paid.
    /// Does NOT fire for drafts or already-paid invoices.
    var isOverdue: Bool {
        guard status != .paid, status != .draft else { return false }
        guard let due = dueDate else { return false }
        return Date() > due
    }

    /// Whole days past due. Negative if not yet due.
    var daysOverdue: Int {
        guard let due = dueDate else { return 0 }
        let comps = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: due),
            to: Calendar.current.startOfDay(for: Date())
        )
        return comps.day ?? 0
    }

    /// Days until due date. Negative if already overdue.
    var daysUntilDue: Int {
        -daysOverdue
    }
}

// MARK: - Invoice Type

enum InvoiceType: String, Codable, CaseIterable, Identifiable {
    case payApplication = "Pay Application"
    case standalone = "Standalone"
    case retainageRelease = "Retainage Release"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .payApplication: return "doc.plaintext.fill"
        case .standalone: return "doc.text.fill"
        case .retainageRelease: return "lock.open.fill"
        }
    }
}

// MARK: - Invoice Status

enum InvoiceStatus: String, Codable, CaseIterable, Identifiable {
    case draft = "Draft"
    case sent = "Sent"
    case pendingPayment = "Pending Payment"
    case partiallyPaid = "Partially Paid"
    case paid = "Paid"
    case overdue = "Overdue"    // Computed display state, not stored directly

    var id: String { rawValue }

    /// Color used for status badges throughout the UI.
    var colorName: String {
        switch self {
        case .draft: return "gray"
        case .sent: return "blue"
        case .pendingPayment: return "orange"
        case .partiallyPaid: return "yellow"
        case .paid: return "green"
        case .overdue: return "red"
        }
    }

    /// Statuses that represent money still owed.
    static var outstandingCases: [InvoiceStatus] {
        [.sent, .pendingPayment, .partiallyPaid, .overdue]
    }
}

// MARK: - Payment Method (used by Payment model)

enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case check = "Check"
    case ach = "ACH"
    case wire = "Wire"
    case cash = "Cash"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .check: return "checkmark.rectangle.fill"
        case .ach: return "building.columns.fill"
        case .wire: return "bolt.fill"
        case .cash: return "banknote.fill"
        case .other: return "questionmark.circle.fill"
        }
    }
}
