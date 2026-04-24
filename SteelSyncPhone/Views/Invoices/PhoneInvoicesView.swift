import SwiftUI
import CloudKit

/// Mobile invoice triage — cross-project list with aging buckets and filters.
/// Replaces the need to drill into each project to check billing status.
/// Read-only for the most part; supports "Log Payment" action per row.
struct PhoneInvoicesView: View {
    @EnvironmentObject var dataStore: DataStore

    @State private var statusFilter: InvoiceStatusFilter = .outstanding
    @State private var searchText: String = ""
    @State private var loggingPaymentFor: InvoiceContext?
    @State private var inspectingInvoice: InvoiceContext?

    enum InvoiceStatusFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case outstanding = "Outstanding"
        case overdue = "Overdue"
        case paid = "Paid"
        var id: String { rawValue }
    }

    struct InvoiceContext: Identifiable {
        let invoice: Invoice
        let projectID: CKRecord.ID
        let projectTitle: String
        var id: UUID { invoice.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Metric strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    metricCard("Outstanding", value: totalOutstanding.currencyFormatted, color: .orange, icon: "clock.fill")
                    metricCard("Overdue", value: totalOverdue.currencyFormatted, color: .red, icon: "exclamationmark.triangle.fill")
                    metricCard("Received MTD", value: receivedMTD.currencyFormatted, color: .green, icon: "checkmark.circle.fill")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Aging bucket strip
            agingBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            // Filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(InvoiceStatusFilter.allCases) { filter in
                        Button {
                            statusFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(
                                        statusFilter == filter
                                            ? AppTheme.primaryOrange
                                            : Color.gray.opacity(0.15)
                                    )
                                )
                                .foregroundColor(statusFilter == filter ? .white : AppTheme.primaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)

            // List
            if filteredInvoices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(emptyTitle)
                        .font(.headline)
                    Text(emptyMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredInvoices) { entry in
                        PhoneInvoiceRow(
                            entry: entry,
                            balanceRemaining: dataStore.balanceRemaining(for: entry.invoice)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            inspectingInvoice = entry
                        }
                        .swipeActions(edge: .trailing) {
                            if entry.invoice.status != .paid {
                                Button {
                                    loggingPaymentFor = entry
                                } label: {
                                    Label("Log Payment", systemImage: "creditcard.fill")
                                }
                                .tint(AppTheme.primaryOrange)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search invoice, project, client")
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Invoices")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $loggingPaymentFor) { ctx in
            NavigationStack {
                PhoneLogPaymentView(invoice: ctx.invoice, projectID: ctx.projectID)
                    .environmentObject(dataStore)
            }
        }
        .sheet(item: $inspectingInvoice) { ctx in
            NavigationStack {
                PhoneInvoiceDetailView(
                    invoice: ctx.invoice,
                    projectID: ctx.projectID,
                    projectTitle: ctx.projectTitle
                )
                .environmentObject(dataStore)
            }
        }
    }

    // MARK: - Metric card

    private func metricCard(_ title: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.callout.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
        }
        .padding(12)
        .frame(width: 180, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.secondaryBackground)
        )
    }

    // MARK: - Aging bar

    private var agingBar: some View {
        let buckets = agingBuckets
        return VStack(alignment: .leading, spacing: 6) {
            Text("AGING")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                agingCell("Current", buckets.current, .green)
                agingCell("1–30", buckets.oneToThirty, .yellow)
                agingCell("31–60", buckets.thirtyOneToSixty, .orange)
                agingCell("61–90", buckets.sixtyOneToNinety, .red.opacity(0.7))
                agingCell("90+", buckets.overNinety, .red)
            }
        }
    }

    private func agingCell(_ label: String, _ amount: Decimal, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(amount.currencyFormatted)
                .font(.caption.monospacedDigit())
                .fontWeight(.bold)
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.secondaryBackground)
        )
    }

    // MARK: - Computed slices

    private var allInvoices: [InvoiceContext] {
        dataStore.allInvoices.map {
            InvoiceContext(invoice: $0.invoice, projectID: $0.projectID, projectTitle: $0.projectTitle)
        }
    }

    private var filteredInvoices: [InvoiceContext] {
        var result = allInvoices
        switch statusFilter {
        case .all: break
        case .outstanding:
            result = result.filter {
                InvoiceStatus.outstandingCases.contains($0.invoice.status) || $0.invoice.isOverdue
            }
        case .overdue:
            result = result.filter { $0.invoice.isOverdue }
        case .paid:
            result = result.filter { $0.invoice.status == .paid }
        }

        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter { entry in
                entry.invoice.invoiceNumber.lowercased().contains(q)
                    || entry.invoice.clientName.lowercased().contains(q)
                    || entry.projectTitle.lowercased().contains(q)
            }
        }

        return result.sorted { ($0.invoice.sentDate ?? .distantPast) > ($1.invoice.sentDate ?? .distantPast) }
    }

    private var totalOutstanding: Decimal {
        allInvoices
            .filter { InvoiceStatus.outstandingCases.contains($0.invoice.status) || $0.invoice.isOverdue }
            .reduce(Decimal(0)) { $0 + dataStore.balanceRemaining(for: $1.invoice) }
    }

    private var totalOverdue: Decimal {
        allInvoices
            .filter { $0.invoice.isOverdue }
            .reduce(Decimal(0)) { $0 + dataStore.balanceRemaining(for: $1.invoice) }
    }

    private var receivedMTD: Decimal {
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        var total: Decimal = 0
        for (_, list) in dataStore.payments {
            for p in list where p.date >= monthStart {
                total += p.amount
            }
        }
        return total
    }

    private var agingBuckets: (current: Decimal, oneToThirty: Decimal, thirtyOneToSixty: Decimal, sixtyOneToNinety: Decimal, overNinety: Decimal) {
        var current: Decimal = 0
        var b1: Decimal = 0
        var b2: Decimal = 0
        var b3: Decimal = 0
        var b4: Decimal = 0
        for entry in allInvoices where entry.invoice.status != .paid && entry.invoice.status != .draft {
            let remaining = dataStore.balanceRemaining(for: entry.invoice)
            let days = entry.invoice.daysOverdue
            if days <= 0 { current += remaining }
            else if days <= 30 { b1 += remaining }
            else if days <= 60 { b2 += remaining }
            else if days <= 90 { b3 += remaining }
            else { b4 += remaining }
        }
        return (current, b1, b2, b3, b4)
    }

    private var emptyTitle: String {
        switch statusFilter {
        case .all: return "No invoices yet"
        case .outstanding: return "Nothing outstanding"
        case .overdue: return "Nothing overdue"
        case .paid: return "No paid invoices yet"
        }
    }

    private var emptyMessage: String {
        "Pay apps become invoices when you mark them as sent on Mac or iPad."
    }
}

// MARK: - Row

private struct PhoneInvoiceRow: View {
    let entry: PhoneInvoicesView.InvoiceContext
    let balanceRemaining: Decimal

    private var statusColor: Color {
        if entry.invoice.isOverdue { return .red }
        switch entry.invoice.status {
        case .draft: return .gray
        case .sent: return .blue
        case .pendingPayment: return .orange
        case .partiallyPaid: return .yellow
        case .paid: return .green
        case .overdue: return .red
        }
    }

    private var statusText: String {
        if entry.invoice.isOverdue && entry.invoice.status != .paid {
            return "Overdue"
        }
        return entry.invoice.status.rawValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(entry.invoice.invoiceNumber)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                StatusBadge(text: statusText, color: statusColor)
            }
            Text(entry.projectTitle)
                .font(.callout)
                .fontWeight(.semibold)
                .lineLimit(1)
            HStack {
                if !entry.invoice.clientName.isEmpty {
                    Text(entry.invoice.clientName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let due = entry.invoice.dueDate {
                    Text("· Due \(due.shortDate)")
                        .font(.caption)
                        .foregroundColor(entry.invoice.isOverdue ? .red : .secondary)
                }
                Spacer()
                Text(balanceRemaining.currencyFormatted)
                    .font(.callout.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundColor(balanceRemaining > 0 ? .orange : .green)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Invoice Detail

struct PhoneInvoiceDetailView: View {
    let invoice: Invoice
    let projectID: CKRecord.ID
    let projectTitle: String
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    @State private var showLogPayment = false

    private var payments: [Payment] {
        dataStore.payments(for: invoice.id)
    }

    private var balanceRemaining: Decimal {
        dataStore.balanceRemaining(for: invoice)
    }

    var body: some View {
        List {
            Section {
                InfoRow(label: "Invoice #", value: invoice.invoiceNumber)
                InfoRow(label: "Project", value: projectTitle)
                if !invoice.clientName.isEmpty {
                    InfoRow(label: "Bill To", value: invoice.clientName)
                } else if invoice.billToClientID == nil {
                    InfoRow(label: "Bill To", value: "Not Assigned")
                }
                InfoRow(label: "Status", value: invoice.status.rawValue)
                if let sent = invoice.sentDate {
                    InfoRow(label: "Sent", value: sent.shortDate)
                }
                if let due = invoice.dueDate {
                    InfoRow(label: "Due", value: due.shortDate)
                }
            }

            Section("Balances") {
                InfoRow(label: "Amount Invoiced", value: invoice.netAmountDue.currencyFormatted)
                InfoRow(label: "Retainage Held", value: invoice.retainageHeld.currencyFormatted)
                InfoRow(label: "Paid", value: dataStore.totalPaid(for: invoice.id).currencyFormatted)
                InfoRow(label: "Remaining", value: balanceRemaining.currencyFormatted)
            }

            if !payments.isEmpty {
                Section("Payments Received") {
                    ForEach(payments) { p in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(p.amount.currencyFormatted)
                                    .font(.callout.monospacedDigit())
                                    .fontWeight(.bold)
                                    .foregroundColor(.green)
                                Spacer()
                                Text(p.paymentMethod.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Text(p.date.shortDate)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            if !p.referenceNumber.isEmpty {
                                Text("Ref: \(p.referenceNumber)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if !p.attachments.isEmpty {
                                Label("\(p.attachments.count) attachment\(p.attachments.count == 1 ? "" : "s")", systemImage: "paperclip")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if invoice.status != .paid {
                    Button("Log Payment") { showLogPayment = true }
                        .fontWeight(.semibold)
                }
            }
        }
        .sheet(isPresented: $showLogPayment) {
            NavigationStack {
                PhoneLogPaymentView(invoice: invoice, projectID: projectID)
                    .environmentObject(dataStore)
            }
        }
    }
}
