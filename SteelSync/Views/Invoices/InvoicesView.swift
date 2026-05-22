import SwiftUI
import CloudKit

/// Top-level cross-project invoice log. Mirrors the RFI Log pattern from Phase 2.
/// Lets a PM triage invoices across every active project in one place.
struct InvoicesView: View {
    @EnvironmentObject var dataStore: DataStore

    @State private var statusFilter: InvoiceStatusFilter = .outstanding
    @State private var projectFilter: String = "All"
    @State private var searchText: String = ""
    @State private var payingInvoice: InvoiceContext?
    @State private var deletingInvoice: InvoiceContext?

    enum InvoiceStatusFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case outstanding = "Outstanding"
        case overdue = "Overdue"
        case paid = "Paid"
        case draft = "Draft"
        var id: String { rawValue }
    }

    /// Wrapper for sheet(item:)
    struct InvoiceContext: Identifiable {
        let invoice: Invoice
        let projectID: CKRecord.ID
        var id: UUID { invoice.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Invoices",
                subtitle: subtitle,
                icon: AppIcons.invoice
            ) {
                EmptyView()
            }

            // Metric strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    MetricCard(title: "Outstanding", value: totalOutstanding.currencyFormatted,
                               icon: "clock.fill", color: .orange)
                    MetricCard(title: "Overdue", value: totalOverdue.currencyFormatted,
                               icon: AppIcons.warning, color: .red)
                    MetricCard(title: "Received MTD", value: receivedMTD.currencyFormatted,
                               icon: AppIcons.success, color: .green)
                    MetricCard(title: "Avg Days to Paid", value: averageDaysToPaid,
                               icon: "speedometer", color: .blue)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.sm)
            }
            .frame(height: 110)

            Divider()

            // Filter bar
            HStack(spacing: AppTheme.Spacing.md) {
                Picker("Status", selection: $statusFilter) {
                    ForEach(InvoiceStatusFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 500)

                Spacer()

                Picker("Project", selection: $projectFilter) {
                    Text("All Projects").tag("All")
                    ForEach(dataStore.projects) { project in
                        Text(project.title).tag(project.id.recordName)
                    }
                }
                .frame(width: 220)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.sm)

            Divider()

            // Aging bucket summary (only when All or Outstanding)
            if statusFilter == .all || statusFilter == .outstanding || statusFilter == .overdue {
                agingSummary
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.top, AppTheme.Spacing.sm)
            }

            // List
            if filteredInvoices.isEmpty {
                EmptyStateView(
                    icon: "doc.text",
                    title: emptyStateTitle,
                    message: emptyStateMessage
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredInvoices) { entry in
                        InvoiceLogRow(
                            entry: entry,
                            balanceRemaining: dataStore.balanceRemaining(for: entry.invoice)
                        )
                        .contentShape(Rectangle())
                        .contextMenu {
                            if entry.invoice.status != .paid {
                                Button("Log Payment…") {
                                    payingInvoice = InvoiceContext(invoice: entry.invoice, projectID: entry.projectID)
                                }
                            }
                            Divider()
                            Button("Delete Invoice…", role: .destructive) {
                                deletingInvoice = entry
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deletingInvoice = entry
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .searchable(text: $searchText, prompt: "Search by invoice number, project, client")
            }
        }
        .background(AppTheme.background)
        .sheet(item: $payingInvoice) { ctx in
            if let project = dataStore.projects.first(where: { $0.id == ctx.projectID }) {
                LogPaymentSheet(invoice: ctx.invoice, project: project)
            }
        }
        .confirmationDialog(
            "Delete Invoice?",
            isPresented: Binding(get: { deletingInvoice != nil }, set: { if !$0 { deletingInvoice = nil } }),
            presenting: deletingInvoice
        ) { ctx in
            Button("Delete \(ctx.invoice.invoiceNumber)", role: .destructive) {
                dataStore.deleteInvoice(ctx.invoice, from: ctx.projectID)
                deletingInvoice = nil
            }
            Button("Cancel", role: .cancel) { deletingInvoice = nil }
        } message: { ctx in
            Text("Permanently deletes invoice \(ctx.invoice.invoiceNumber) and any payments logged against it. If it came from a pay application, that app will be unlinked so you can re-invoice it.")
        }
    }

    // MARK: - Aging summary

    @ViewBuilder
    private var agingSummary: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            agingCard("Current", amount: agingBuckets.current, color: .green)
            agingCard("1–30 days", amount: agingBuckets.oneToThirty, color: .yellow)
            agingCard("31–60 days", amount: agingBuckets.thirtyOneToSixty, color: .orange)
            agingCard("61–90 days", amount: agingBuckets.sixtyOneToNinety, color: .red.opacity(0.7))
            agingCard("90+ days", amount: agingBuckets.overNinety, color: .red)
        }
    }

    private func agingCard(_ label: String, amount: Decimal, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(amount.currencyFormatted)
                .font(.callout.monospacedDigit())
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(AppTheme.secondaryBackground)
        )
    }

    // MARK: - Computed data

    private var allInvoices: [InvoiceContext] {
        dataStore.allInvoices.map { tuple in
            InvoiceContext(invoice: tuple.invoice, projectID: tuple.projectID)
        }
    }

    private var filteredInvoices: [InvoiceContext] {
        var result = allInvoices

        switch statusFilter {
        case .all: break
        case .outstanding:
            result = result.filter { InvoiceStatus.outstandingCases.contains($0.invoice.status) || $0.invoice.isOverdue }
        case .overdue:
            result = result.filter { $0.invoice.isOverdue }
        case .paid:
            result = result.filter { $0.invoice.status == .paid }
        case .draft:
            result = result.filter { $0.invoice.status == .draft }
        }

        if projectFilter != "All" {
            result = result.filter { $0.projectID.recordName == projectFilter }
        }

        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter { entry in
                entry.invoice.invoiceNumber.lowercased().contains(q)
                    || entry.invoice.clientName.lowercased().contains(q)
                    || projectTitle(for: entry.projectID).lowercased().contains(q)
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

    private var averageDaysToPaid: String {
        let paid = allInvoices.compactMap { entry -> Int? in
            guard entry.invoice.status == .paid,
                  let sent = entry.invoice.sentDate,
                  let paid = entry.invoice.paidDate else { return nil }
            return Calendar.current.dateComponents([.day], from: sent, to: paid).day
        }
        guard !paid.isEmpty else { return "—" }
        let avg = paid.reduce(0, +) / paid.count
        return "\(avg)d"
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
            if days <= 0 {
                current += remaining
            } else if days <= 30 {
                b1 += remaining
            } else if days <= 60 {
                b2 += remaining
            } else if days <= 90 {
                b3 += remaining
            } else {
                b4 += remaining
            }
        }
        return (current, b1, b2, b3, b4)
    }

    private var subtitle: String {
        let out = allInvoices.filter { InvoiceStatus.outstandingCases.contains($0.invoice.status) }.count
        let overdueCount = allInvoices.filter { $0.invoice.isOverdue }.count
        return "\(out) outstanding · \(overdueCount) overdue"
    }

    private func projectTitle(for projectID: CKRecord.ID) -> String {
        dataStore.projects.first { $0.id == projectID }?.title ?? "Unknown"
    }

    private var emptyStateTitle: String {
        switch statusFilter {
        case .all: return "No invoices yet"
        case .outstanding: return "Nothing outstanding"
        case .overdue: return "Nothing overdue"
        case .paid: return "No paid invoices yet"
        case .draft: return "No draft invoices"
        }
    }

    private var emptyStateMessage: String {
        "Open a project's Pay Apps tab and click 'Mark as Sent' on a pay app to create an invoice."
    }
}

// MARK: - Row

private struct InvoiceLogRow: View {
    let entry: InvoicesView.InvoiceContext
    let balanceRemaining: Decimal
    @EnvironmentObject var dataStore: DataStore

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
        HStack(spacing: AppTheme.Spacing.md) {
            Text(entry.invoice.invoiceNumber)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .frame(width: 140, alignment: .leading)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(projectTitle)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if entry.invoice.isOverdue {
                        Image(systemName: AppIcons.warning)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                HStack(spacing: 6) {
                    if !entry.invoice.clientName.isEmpty {
                        Text(entry.invoice.clientName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("·").foregroundColor(.secondary).font(.caption)
                    }
                    if let sent = entry.invoice.sentDate {
                        Text("Sent \(sent.shortDate)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Draft")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let due = entry.invoice.dueDate {
                        Text("·").foregroundColor(.secondary).font(.caption)
                        Text("Due \(due.shortDate)")
                            .font(.caption)
                            .foregroundColor(entry.invoice.isOverdue ? .red : .secondary)
                    }
                }
            }

            Spacer(minLength: AppTheme.Spacing.md)

            VStack(alignment: .trailing, spacing: 2) {
                Text("Invoiced")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(entry.invoice.netAmountDue.currencyFormatted)
                    .font(.callout.monospacedDigit())
                    .fontWeight(.medium)
            }
            .frame(width: 100, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 2) {
                Text("Remaining")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(balanceRemaining.currencyFormatted)
                    .font(.callout.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundColor(balanceRemaining > 0 ? .orange : .green)
            }
            .frame(width: 100, alignment: .trailing)

            StatusBadge(text: statusText, color: statusColor)
                .frame(width: 100)
        }
        .padding(.vertical, 6)
    }

    private var projectTitle: String {
        dataStore.projects.first { $0.id == entry.projectID }?.title ?? "Unknown"
    }
}
