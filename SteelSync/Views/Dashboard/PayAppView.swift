import SwiftUI
import CloudKit

// MARK: - Pay Apps Tab (AIA G703 Schedule of Values + Invoice Tracking)

struct PayAppsTab: View {
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @State private var showCreatePayApp = false
    @State private var editingPayApp: PayApplication?
    @State private var markingSentPayApp: PayApplication?
    @State private var addingPaymentForInvoice: InvoiceContext?
    @State private var exportingPayApp: PayApplication?
    @State private var showRetainageRelease = false
    @State private var payAppToDelete: PayApplication?

    /// Wrapper so `sheet(item:)` can carry both an Invoice and the project ID
    /// to the payment logging sheet.
    struct InvoiceContext: Identifiable {
        let invoice: Invoice
        var id: UUID { invoice.id }
    }

    private var payApps: [PayApplication] {
        dataStore.payApps(for: project.id)
    }

    private var projectInvoices: [Invoice] {
        dataStore.invoices(for: project.id)
    }

    private var totalInvoiced: Decimal {
        projectInvoices.reduce(Decimal(0)) { $0 + $1.netAmountDue }
    }

    private var totalPaid: Decimal {
        projectInvoices.reduce(Decimal(0)) { $0 + dataStore.totalPaid(for: $1.id) }
    }

    private var totalOutstanding: Decimal {
        totalInvoiced - totalPaid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Header + actions
            HStack {
                Text("Pay Applications & Invoices")
                    .font(AppTheme.Typography.headline)
                Spacer()
                if !payApps.isEmpty {
                    Button {
                        showRetainageRelease = true
                    } label: {
                        Label("Retainage Release", systemImage: "lock.open.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    showCreatePayApp = true
                } label: {
                    Label("New Pay App", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primaryOrange)
            }

            // Invoice summary strip
            if !projectInvoices.isEmpty {
                HStack(spacing: AppTheme.Spacing.sm) {
                    payAppSummaryCard("Total Invoiced", value: totalInvoiced.currencyFormatted, color: .blue, icon: "doc.text.fill")
                    payAppSummaryCard("Total Paid", value: totalPaid.currencyFormatted, color: .green, icon: "checkmark.circle.fill")
                    payAppSummaryCard("Outstanding", value: totalOutstanding.currencyFormatted, color: totalOutstanding > 0 ? .orange : .green, icon: "clock.fill")
                }
            }

            if payApps.isEmpty {
                EmptyStateView(
                    icon: "doc.text.fill",
                    title: "No Pay Applications",
                    message: "Create a schedule of values to track progressive billing.",
                    buttonTitle: "Create Pay App"
                ) { showCreatePayApp = true }
                .frame(height: 200)
            } else {
                VStack(spacing: 4) {
                    ForEach(payApps) { payApp in
                        PayAppRow(
                            payApp: payApp,
                            invoice: dataStore.invoice(for: payApp.id, in: project.id),
                            paid: payApp.linkedInvoiceID.map { dataStore.totalPaid(for: $0) } ?? 0
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(AppTheme.secondaryBackground)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { editingPayApp = payApp }
                        .contextMenu {
                            payAppContextMenu(for: payApp)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCreatePayApp) {
            CreatePayAppSheet(project: project)
        }
        .sheet(item: $editingPayApp) { payApp in
            EditPayAppSheet(payApp: payApp, project: project)
        }
        .sheet(item: $markingSentPayApp) { payApp in
            MarkAsSentSheet(payApp: payApp, project: project)
        }
        .sheet(item: $addingPaymentForInvoice) { ctx in
            LogPaymentSheet(invoice: ctx.invoice, project: project)
        }
        .sheet(item: $exportingPayApp) { payApp in
            ExportPayAppSheet(payApp: payApp, project: project)
        }
        .sheet(isPresented: $showRetainageRelease) {
            RetainageReleaseSheet(project: project)
        }
        .confirmationDialog(
            "Delete pay application?",
            isPresented: Binding(
                get: { payAppToDelete != nil },
                set: { if !$0 { payAppToDelete = nil } }
            ),
            presenting: payAppToDelete
        ) { payApp in
            Button("Delete", role: .destructive) {
                dataStore.deletePayApplication(payApp, from: project.id)
                payAppToDelete = nil
            }
            Button("Cancel", role: .cancel) { payAppToDelete = nil }
        } message: { payApp in
            Text("Application #\(payApp.applicationNumber) will be removed. If a linked invoice exists, it will be removed too. This cannot be undone.")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func payAppContextMenu(for payApp: PayApplication) -> some View {
        Button("Edit SOV") { editingPayApp = payApp }
        Button("Export as PDF…") { exportingPayApp = payApp }
        Divider()
        if payApp.linkedInvoiceID == nil {
            Button("Mark as Sent…") { markingSentPayApp = payApp }
        }
        if let invoice = dataStore.invoice(for: payApp.id, in: project.id),
           invoice.status != .paid {
            Button("Log Payment…") { addingPaymentForInvoice = InvoiceContext(invoice: invoice) }
        }
        Divider()
        Button("Delete…", role: .destructive) { payAppToDelete = payApp }
    }

    private func payAppSummaryCard(_ title: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
            Spacer()
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(AppTheme.secondaryBackground)
        )
    }
}

// MARK: - Pay App Row (now shows invoice status + balances)

private struct PayAppRow: View {
    let payApp: PayApplication
    let invoice: Invoice?
    let paid: Decimal

    private var balanceDue: Decimal {
        guard let invoice = invoice else { return 0 }
        return invoice.netAmountDue - paid
    }

    /// Net amount billed — gross work minus retainage withheld this period.
    /// Matches what an Invoice's netAmountDue would be once sent.
    private var displayInvoicedAmount: Decimal {
        if let invoice = invoice {
            return invoice.netAmountDue
        }
        return payApp.netAmountThisPeriod - payApp.totalRetainage
    }

    private var statusColor: Color {
        if payApp.isRetainageRelease { return .purple }
        guard let invoice = invoice else { return .gray }
        if invoice.isOverdue { return .red }
        switch invoice.status {
        case .draft: return .gray
        case .sent: return .blue
        case .pendingPayment: return .orange
        case .partiallyPaid: return .yellow
        case .paid: return .green
        case .overdue: return .red
        }
    }

    private var statusText: String {
        if payApp.isRetainageRelease { return "Retainage Release" }
        guard let invoice = invoice else { return "Draft" }
        if invoice.isOverdue { return "Overdue" }
        return invoice.status.rawValue
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("App #\(payApp.applicationNumber)")
                        .font(.headline)
                    StatusBadge(text: statusText, color: statusColor)
                    if let invoice = invoice, invoice.isOverdue {
                        Text("\(invoice.daysOverdue)d late")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.12)))
                    }
                }
                if let invoice = invoice {
                    Text("\(invoice.invoiceNumber) · Period to \(payApp.periodTo.shortDate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No invoice yet · Period to \(payApp.periodTo.shortDate)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer(minLength: AppTheme.Spacing.md)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Invoiced")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                // Display NET of retainage. For a linked invoice we use its
                // netAmountDue (which already subtracts retainage). For a draft
                // pay app we compute netAmountThisPeriod - totalRetainage so
                // the shown value matches what the GC will actually be billed.
                // Without this, summing pay apps appears to exceed contract
                // because retainage would be double-counted.
                Text(displayInvoicedAmount.currencyFormatted)
                    .font(.callout.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            .frame(width: 100, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Paid")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(paid.currencyFormatted)
                    .font(.callout.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
            .frame(width: 100, alignment: .trailing)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Remaining")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(balanceDue.currencyFormatted)
                    .font(.callout.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundColor(balanceDue > 0 ? .orange : .green)
            }
            .frame(width: 100, alignment: .trailing)
        }
    }
}

// MARK: - Create Pay App Sheet

struct CreatePayAppSheet: View {
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var periodTo = Date()
    @State private var retainageRate = "10"

    var body: some View {
        NavigationStack {
            Form {
                Section("Application Details") {
                    let nextNum = (dataStore.payApps(for: project.id).map(\.applicationNumber).max() ?? 0) + 1
                    InfoRow(label: "Application #", value: "\(nextNum)")
                    InfoRow(label: "Project", value: project.title)
                    DatePicker("Period To", selection: $periodTo, displayedComponents: .date)
                    HStack {
                        Text("Retainage Rate")
                        Spacer()
                        TextField("10", text: $retainageRate)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("%")
                    }
                }

                Section("What will be included") {
                    let allCOs = dataStore.changeOrders(for: project.id)
                    let eligibleCOs = allCOs.filter { $0.submittedDate <= periodTo }
                    InfoRow(label: "Contract Amount", value: project.contractAmount.currencyFormatted)
                    InfoRow(label: "Change Orders (by \(periodTo.shortDate))", value: "\(eligibleCOs.count) (\(eligibleCOs.reduce(0) { $0 + $1.amount }.currencyFormatted))")
                    InfoRow(label: "Total Scheduled Value", value: (project.contractAmount + eligibleCOs.reduce(0) { $0 + $1.amount }).currencyFormatted)

                    let previousApps = dataStore.payApps(for: project.id)
                    if let last = previousApps.last {
                        InfoRow(label: "Previously Billed", value: last.totalCompletedToDate.currencyFormatted)
                        InfoRow(label: "Remaining", value: (last.totalScheduledValue - last.totalCompletedToDate).currencyFormatted)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Pay Application")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primaryOrange)
                }
            }
        }
        #if os(macOS)
        .frame(width: 500, height: 400)
        #endif
    }

    private func create() {
        let rate = Decimal(string: retainageRate).map { $0 / 100 } ?? Decimal(0.10)
        var payApp = dataStore.buildNewPayApp(for: project.id, periodTo: periodTo, retainageRate: rate)
        payApp.applicationDate = Date()
        dataStore.addPayApplication(payApp, to: project.id)
        dismiss()
    }
}

// MARK: - Edit Pay App Sheet (G703 SOV Editor)

struct EditPayAppSheet: View {
    @State var payApp: PayApplication
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header info
                HStack {
                    VStack(alignment: .leading) {
                        Text("Application #\(payApp.applicationNumber)")
                            .font(.headline)
                        Text("Period to: \(payApp.periodTo.shortDate)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Retainage: \(Int(Double(truncating: payApp.retainageRate * 100 as NSDecimalNumber)))%")
                            .font(.caption).foregroundColor(.secondary)
                        Text("Total: \(payApp.totalCompletedToDate.currencyFormatted)")
                            .font(.callout).fontWeight(.bold).foregroundColor(.green)
                    }
                }
                .padding()

                Divider()

                // G703 Column Headers
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        sovHeaderRow
                        Divider()

                        ForEach(Array(payApp.lineItems.enumerated()), id: \.element.id) { index, item in
                            sovDataRow(index: index, item: item)
                            Divider()
                        }

                        // Grand totals
                        sovTotalRow
                    }
                    .frame(minWidth: 800)
                }
            }
            .navigationTitle("Schedule of Values")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primaryOrange)
                }
            }
        }
        #if os(macOS)
        .frame(width: 900, height: 600)
        #endif
    }

    // MARK: - G703 Header Row

    private var sovHeaderRow: some View {
        HStack(spacing: 0) {
            Text("A").sovHeader(width: 30)
            Text("B - Description").sovHeader(width: 160)
            Text("C - Scheduled\nValue").sovHeader(width: 100)
            Text("D - Previous\nApplication").sovHeader(width: 100)
            Text("E - This\nPeriod").sovHeader(width: 100)
            Text("F - Materials\nStored").sovHeader(width: 90)
            Text("G - Total\nCompleted").sovHeader(width: 100)
            Text("% (G÷C)").sovHeader(width: 60)
            Text("H - Balance\nTo Finish").sovHeader(width: 100)
            Text("I - Retainage").sovHeader(width: 90)
        }
        .background(Color.gray.opacity(0.15))
    }

    // MARK: - G703 Data Row

    private func sovDataRow(index: Int, item: SOVLineItem) -> some View {
        HStack(spacing: 0) {
            // A: Item number
            Text("\(item.itemNumber)")
                .sovCell(width: 30)

            // B: Description
            Text(item.description)
                .sovCell(width: 160, alignment: .leading)
                .lineLimit(2)

            // C: Scheduled value (read-only)
            Text(item.scheduledValue.currencyFormatted)
                .sovCell(width: 100)

            // D: Previous application (read-only, carried forward)
            Text(item.previousCompleted.currencyFormatted)
                .sovCell(width: 100)
                .foregroundColor(.secondary)

            // E: This period (EDITABLE)
            TextField("0", value: $payApp.lineItems[index].thisPeriodCompleted, format: .currency(code: "USD"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 95)
                .padding(.horizontal, 2)
                #if !os(macOS)
                .keyboardType(.decimalPad)
                #endif

            // F: Materials stored (EDITABLE)
            TextField("0", value: $payApp.lineItems[index].materialsStored, format: .currency(code: "USD"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 85)
                .padding(.horizontal, 2)
                #if !os(macOS)
                .keyboardType(.decimalPad)
                #endif

            // G: Total completed (calculated)
            Text(payApp.lineItems[index].totalCompletedToDate.currencyFormatted)
                .sovCell(width: 100)
                .foregroundColor(.green)

            // %: Percent complete (calculated)
            Text(String(format: "%.1f%%", payApp.lineItems[index].percentComplete))
                .sovCell(width: 60)
                .foregroundColor(payApp.lineItems[index].percentComplete >= 100 ? .green : AppTheme.primaryOrange)

            // H: Balance to finish (calculated)
            Text(payApp.lineItems[index].balanceToFinish.currencyFormatted)
                .sovCell(width: 100)

            // I: Retainage (calculated)
            Text(payApp.lineItems[index].retainage(at: payApp.retainageRate).currencyFormatted)
                .sovCell(width: 90)
                .foregroundColor(.orange)
        }
        .font(.caption)
    }

    // MARK: - Grand Total Row

    private var sovTotalRow: some View {
        HStack(spacing: 0) {
            Text("").sovCell(width: 30)
            Text("GRAND TOTALS").sovCell(width: 160, alignment: .leading).fontWeight(.bold)
            Text(payApp.totalScheduledValue.currencyFormatted).sovCell(width: 100).fontWeight(.bold)
            Text(payApp.totalPreviousCompleted.currencyFormatted).sovCell(width: 100)
            Text(payApp.totalThisPeriod.currencyFormatted).sovCell(width: 100).fontWeight(.bold).foregroundColor(AppTheme.primaryOrange)
            Text(payApp.totalMaterialsStored.currencyFormatted).sovCell(width: 90)
            Text(payApp.totalCompletedToDate.currencyFormatted).sovCell(width: 100).fontWeight(.bold).foregroundColor(.green)
            Text(String(format: "%.1f%%", payApp.overallPercentComplete)).sovCell(width: 60).fontWeight(.bold)
            Text(payApp.totalBalanceToFinish.currencyFormatted).sovCell(width: 100)
            Text(payApp.totalRetainage.currencyFormatted).sovCell(width: 90).fontWeight(.bold).foregroundColor(.orange)
        }
        .background(Color.gray.opacity(0.1))
        .font(.caption)
    }

    private func save() {
        dataStore.updatePayApplication(payApp, in: project.id)
        dismiss()
    }
}

// MARK: - SOV Cell Modifiers

extension Text {
    func sovHeader(width: CGFloat) -> some View {
        self.font(.system(size: 9, weight: .bold))
            .multilineTextAlignment(.center)
            .frame(width: width, alignment: .center)
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
    }

    func sovCell(width: CGFloat, alignment: Alignment = .trailing) -> some View {
        self.frame(width: width, alignment: alignment)
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
    }
}

// MARK: - Mark As Sent Sheet

/// Small sheet that asks for the sent date + payment terms + invoice number,
/// then creates a linked Invoice via DataStore.createInvoiceFromPayApp.
struct MarkAsSentSheet: View {
    let payApp: PayApplication
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var sentDate = Date()
    @State private var termsDays = 30
    @State private var invoiceNumber = ""
    @State private var billToClientID: String?

    private var billToCandidates: [Client] {
        dataStore.billToCandidates(for: project)
    }

    private var selectedBillTo: Client? {
        guard let id = billToClientID else { return nil }
        return billToCandidates.first { $0.id.recordName == id }
    }

    private func roleLabel(for client: Client) -> String {
        if client.id == project.subClientRef?.recordID { return "Sub" }
        if client.id == project.gcClientRef?.recordID { return "GC" }
        return client.preferredRateType.displayName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Invoice Details") {
                    HStack {
                        Text("Invoice Number")
                        Spacer()
                        TextField("Auto-suggested", text: $invoiceNumber)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 180)
                    }
                    DatePicker("Sent Date", selection: $sentDate, displayedComponents: .date)
                    Stepper("Payment Terms: Net \(termsDays)", value: $termsDays, in: 7...120, step: 1)
                    HStack {
                        Text("Due Date")
                        Spacer()
                        Text((Calendar.current.date(byAdding: .day, value: termsDays, to: sentDate) ?? sentDate).shortDate)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    if billToCandidates.isEmpty {
                        Text("No client linked to this project. Add a GC or Sub on the project to set a bill-to.")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if billToCandidates.count == 1, let only = billToCandidates.first {
                        InfoRow(label: only.name, value: roleLabel(for: only))
                    } else {
                        Picker("Bill To", selection: Binding(
                            get: { billToClientID ?? billToCandidates.first?.id.recordName ?? "" },
                            set: { billToClientID = $0 }
                        )) {
                            ForEach(billToCandidates, id: \.id.recordName) { c in
                                Text("\(c.name) — \(roleLabel(for: c))").tag(c.id.recordName)
                            }
                        }
                    }
                } header: {
                    Text("Bill To")
                } footer: {
                    if billToCandidates.count > 1 {
                        Text("Defaults to the subcontractor when both a GC and a Sub are linked. Change if billing the GC directly.")
                    }
                }

                Section("Summary") {
                    InfoRow(label: "Application #", value: "\(payApp.applicationNumber)")
                    InfoRow(label: "Amount This Period", value: payApp.netAmountThisPeriod.currencyFormatted)
                    InfoRow(label: "Retainage Withheld", value: payApp.totalRetainage.currencyFormatted)
                    InfoRow(label: "Net Invoice Amount", value: (payApp.netAmountThisPeriod - payApp.totalRetainage).currencyFormatted)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Mark as Sent")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Invoice") { markSent() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primaryOrange)
                }
            }
            .onAppear {
                if invoiceNumber.isEmpty {
                    invoiceNumber = dataStore.suggestedInvoiceNumber(
                        for: project.id,
                        type: payApp.isRetainageRelease ? .retainageRelease : .payApplication
                    )
                }
                if billToClientID == nil {
                    billToClientID = dataStore.defaultBillToClient(for: project)?.id.recordName
                }
            }
        }
        #if os(macOS)
        .frame(width: 500, height: 540)
        #endif
    }

    private func markSent() {
        var invoice = dataStore.createInvoiceFromPayApp(
            payApp,
            in: project.id,
            sentDate: sentDate,
            termsDays: termsDays,
            billToClient: selectedBillTo ?? dataStore.defaultBillToClient(for: project)
        )
        if !invoiceNumber.isEmpty {
            invoice.invoiceNumber = invoiceNumber
            dataStore.updateInvoice(invoice, in: project.id)
        }
        dismiss()
    }
}

// MARK: - Log Payment Sheet

/// Dedicated sheet for logging a payment against a specific invoice.
/// Gates save on `attachment OR proofReason` per user rule #5.
struct LogPaymentSheet: View {
    let invoice: Invoice
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var amount: Decimal = 0
    @State private var date = Date()
    @State private var method: PaymentMethod = .check
    @State private var referenceNumber = ""
    @State private var notes = ""
    @State private var proofReason = ""
    @State private var attachments: [Attachment] = []
    @State private var showFilePicker = false
    @State private var showMissingProofWarning = false

    private var balanceDue: Decimal {
        dataStore.balanceRemaining(for: invoice)
    }

    private var hasProofOrReason: Bool {
        !attachments.isEmpty || !proofReason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSave: Bool {
        amount > 0 && hasProofOrReason
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Payment Details") {
                    InfoRow(label: "Invoice", value: invoice.invoiceNumber)
                    InfoRow(label: "Balance Due", value: balanceDue.currencyFormatted)
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", value: $amount, format: .currency(code: "USD"))
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 140)
                            #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    DatePicker("Date Received", selection: $date, displayedComponents: .date)
                    Picker("Method", selection: $method) {
                        ForEach(PaymentMethod.allCases) { m in
                            Label(m.rawValue, systemImage: m.icon).tag(m)
                        }
                    }
                    TextField("Reference Number", text: $referenceNumber, prompt: Text("Check #, wire confirmation, ACH ref"))
                }

                Section {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        if attachments.isEmpty {
                            // Drop zone + click-to-attach
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("Drag a check image or PDF here")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                Button {
                                    showFilePicker = true
                                } label: {
                                    Label("Or choose a file…", systemImage: "paperclip")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.gray.opacity(0.06))
                            )
                            .fileDrop(folderID: "payment-\(invoice.id.uuidString)") { attachment in
                                attachments.append(attachment)
                            }

                            TextField("", text: $proofReason, prompt: Text("Or explain why no proof is attached (required if no file)"), axis: .vertical)
                                .lineLimit(2...4)
                        } else {
                            ForEach(attachments, id: \.id) { att in
                                HStack {
                                    Image(systemName: "doc.fill")
                                        .foregroundColor(.green)
                                    Text(att.filename)
                                        .font(.callout)
                                    Spacer()
                                    Button(role: .destructive) {
                                        attachments.removeAll { $0.id == att.id }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            Button {
                                showFilePicker = true
                            } label: {
                                Label("Add Another", systemImage: "plus")
                            }
                        }
                    }
                } header: {
                    Text("Proof of Payment")
                } footer: {
                    if !hasProofOrReason {
                        Text("⚠️ Attach a check image or payment receipt, OR type a reason to save without proof.")
                            .foregroundColor(.orange)
                    }
                }

                Section("Notes") {
                    TextField("", text: $notes, prompt: Text("Optional notes"), axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Log Payment")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primaryOrange)
                        .disabled(!canSave)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.image, .pdf],
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
            .onAppear {
                if amount == 0 { amount = balanceDue }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 620)
        #endif
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        // Route payment proofs through the same FileStorageService used for bid
        // attachments. We use a `payment-{invoice.id}` folder identifier to keep
        // them separate from bid docs.
        let folderID = "payment-\(invoice.id.uuidString)"
        switch FileStorageService.importFile(from: url, bidID: folderID) {
        case .success(let attachment):
            attachments.append(attachment)
        case .failure:
            break
        }
    }

    private func save() {
        var payment = Payment(
            amount: amount,
            date: date,
            appliedToInvoiceID: invoice.id,
            paymentMethod: method,
            referenceNumber: referenceNumber,
            proofReason: proofReason,
            notes: notes,
            attachments: attachments
        )
        payment.projectRef = CKRecord.Reference(recordID: project.id, action: .deleteSelf)
        dataStore.addPayment(payment, to: project.id)
        dataStore.refreshInvoiceStatus(invoice, in: project.id)
        dismiss()
    }
}

// MARK: - Export PDF Sheet (placeholder; full implementation in PDF export task)

/// Format picker + export trigger. Falls back to a simple placeholder if the
/// renderer isn't wired in yet.
struct ExportPayAppSheet: View {
    let payApp: PayApplication
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: PDFFormat = .steelSync
    @State private var includeG702Cover: Bool = true
    @State private var exportURL: URL?

    private var billToClient: Client? {
        // Honor the snapshot taken at invoice creation if a linked invoice
        // exists — the user may have explicitly chosen GC vs Sub at that point.
        if let invoice = dataStore.invoice(for: payApp.id, in: project.id),
           let linked = dataStore.billToClient(for: invoice) {
            return linked
        }
        return dataStore.defaultBillToClient(for: project)
    }

    enum PDFFormat: String, CaseIterable, Identifiable {
        case g703 = "AIA G702 / G703"
        case steelSync = "SteelSync Branded"
        var id: String { rawValue }
    }

    private var formatBlurb: String {
        switch selectedFormat {
        case .g703:
            return includeG702Cover
                ? "Two-page PDF: G702 Application for Payment cover + G703 Schedule of Values continuation sheet. The form most GCs expect."
                : "Single-page G703 Schedule of Values only. Useful for subcontractors that don't require the G702 cover."
        case .steelSync:
            return "Clean, modern invoice layout with SteelSync branding. Same data, more readable."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("PDF Format", selection: $selectedFormat) {
                        ForEach(PDFFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    if selectedFormat == .g703 {
                        Toggle("Include G702 cover sheet", isOn: $includeG702Cover)
                    }

                    Text(formatBlurb)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Preview") {
                    InfoRow(label: "Application #", value: "\(payApp.applicationNumber)")
                    InfoRow(label: "Period", value: payApp.periodTo.shortDate)
                    InfoRow(label: "Amount", value: payApp.netAmountThisPeriod.currencyFormatted)
                    InfoRow(label: "Retainage", value: payApp.totalRetainage.currencyFormatted)
                }

                if let url = exportURL {
                    Section("Exported") {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.green)
                        #if !os(macOS)
                        ShareLink(item: url) {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                        #endif
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Export PDF")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { export() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primaryOrange)
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 480)
        #endif
    }

    private func export() {
        let renderer = PayAppPDFRenderer(
            payApp: payApp,
            project: project,
            client: billToClient,
            format: selectedFormat,
            includeG702Cover: includeG702Cover
        )
        if let url = renderer.render() {
            exportURL = url
            #if os(macOS)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            dismiss()
            #endif
        }
    }
}

// MARK: - Retainage Release Sheet

struct RetainageReleaseSheet: View {
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    private var totalRetainageHeld: Decimal {
        dataStore.payApps(for: project.id)
            .filter { !$0.isRetainageRelease }
            .reduce(Decimal(0)) { $0 + $1.totalRetainage }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    InfoRow(label: "Project", value: project.title)
                    InfoRow(label: "Total Retainage Held", value: totalRetainageHeld.currencyFormatted)
                } header: {
                    Text("Closeout Retainage Release")
                } footer: {
                    Text("This creates a new pay application marked as a retainage release. Use this only at project closeout when the GC is releasing withheld retainage.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Retainage Release")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primaryOrange)
                        .disabled(totalRetainageHeld <= 0)
                }
            }
        }
        #if os(macOS)
        .frame(width: 500, height: 350)
        #endif
    }

    private func create() {
        let previousApps = dataStore.payApps(for: project.id)
        let nextNumber = (previousApps.map(\.applicationNumber).max() ?? 0) + 1
        let releaseItem = SOVLineItem(
            itemNumber: 1,
            description: "Retainage Release",
            scheduledValue: totalRetainageHeld,
            previousCompleted: 0,
            thisPeriodCompleted: totalRetainageHeld,
            materialsStored: 0,
            isChangeOrder: false,
            changeOrderID: nil
        )
        let payApp = PayApplication(
            applicationNumber: nextNumber,
            applicationDate: Date(),
            periodTo: Date(),
            projectID: project.id.recordName,
            retainageRate: 0,
            lineItems: [releaseItem],
            notes: "Retainage release pay application",
            isRetainageRelease: true
        )
        dataStore.addPayApplication(payApp, to: project.id)
        dismiss()
    }
}
