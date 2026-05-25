import SwiftUI
import CloudKit
import UniformTypeIdentifiers

// MARK: - Pay Apps Tab (AIA G703 Schedule of Values + Invoice Tracking)

struct PayAppsTab: View {
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Binding var showCreatePayApp: Bool
    @Binding var editingPayApp: PayApplication?
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
                    .buttonStyle(.appSecondary)
                }
                Button {
                    showCreatePayApp = true
                } label: {
                    Label("New Pay App", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.appPrimary)
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
        // Pay-app create/edit are presented INLINE at the ProjectDetailView
        // root (so the overlay fills the whole pane). See ProjectDetailView.
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
    @Environment(\.inlineDismiss) private var inlineDismiss
    @State private var periodTo = Date()
    @State private var retainageRate = "10"

    private var nextNum: Int {
        (dataStore.payApps(for: project.id).map(\.applicationNumber).max() ?? 0) + 1
    }

    var body: some View {
        EntryFormScaffold(
            title: "New Pay Application",
            icon: AppIcons.invoice,
            saveTitle: "Create",
            onCancel: closeForm,
            onSave: create
        ) {
            detailsSection
            inclusionSection
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    @ViewBuilder private var detailsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Application Details")
            VStack(spacing: AppTheme.Spacing.sm) {
                InfoRow(label: "Application #", value: "\(nextNum)")
                InfoRow(label: "Project", value: project.title)
            }
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.secondaryBackground)
            )

            HStack(spacing: AppTheme.Spacing.md) {
                LabeledField(label: "Period To") {
                    DatePicker("", selection: $periodTo, displayedComponents: .date)
                        .labelsHidden()
                        .appControlSurface()
                }
                LabeledField(label: "Retainage Rate (%)",
                             helpText: "Typical AIA G702 default is 10%.") {
                    TextField("10", text: $retainageRate)
                        .textFieldStyle(.appField)
                        #if !os(macOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
            }
        }
    }

    @ViewBuilder private var inclusionSection: some View {
        let allCOs = dataStore.changeOrders(for: project.id)
        let eligibleCOs = allCOs.filter { $0.submittedDate <= periodTo }
        let coTotal = eligibleCOs.reduce(Decimal(0)) { $0 + $1.amount }
        let scheduledValue = project.contractAmount + coTotal
        let previousApps = dataStore.payApps(for: project.id)

        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "What Will Be Included")
            VStack(spacing: AppTheme.Spacing.sm) {
                InfoRow(label: "Contract Amount",
                        value: project.contractAmount.currencyFormatted,
                        icon: "doc.text.fill")
                InfoRow(label: "Change Orders (by \(periodTo.shortDate))",
                        value: "\(eligibleCOs.count) · \(coTotal.currencyFormatted)",
                        icon: "arrow.triangle.branch")
                InfoRow(label: "Total Scheduled Value",
                        value: scheduledValue.currencyFormatted,
                        icon: "sum")
                if let last = previousApps.last {
                    Divider().padding(.vertical, 2)
                    InfoRow(label: "Previously Billed",
                            value: last.totalCompletedToDate.currencyFormatted,
                            icon: "checkmark.circle")
                    InfoRow(label: "Remaining",
                            value: (last.totalScheduledValue - last.totalCompletedToDate).currencyFormatted,
                            icon: "circle")
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.secondaryBackground)
            )
        }
    }

    private func create() {
        let rate = Decimal(string: retainageRate).map { $0 / 100 } ?? Decimal(0.10)
        var payApp = dataStore.buildNewPayApp(for: project.id, periodTo: periodTo, retainageRate: rate)
        payApp.applicationDate = Date()
        dataStore.addPayApplication(payApp, to: project.id)
        closeForm()
    }
}

// MARK: - Edit Pay App Sheet (G703 SOV Editor)

struct EditPayAppSheet: View {
    @State var payApp: PayApplication
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss
    @State private var draggingLineItemID: UUID?

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Schedule of Values — App #\(payApp.applicationNumber)",
                saveTitle: "Save",
                onCancel: closeForm,
                onSave: save
            )

            // Summary header card — application metadata that doesn't belong
            // in the table itself (period, retainage rate, running total).
            HStack(spacing: AppTheme.Spacing.md) {
                summaryStat(
                    label: "Period To",
                    value: payApp.periodTo.shortDate,
                    icon: "calendar"
                )
                summaryStat(
                    label: "Retainage",
                    value: "\(Int(Double(truncating: payApp.retainageRate * 100 as NSDecimalNumber)))%",
                    icon: "lock.fill"
                )
                summaryStat(
                    label: "Total Completed",
                    value: payApp.totalCompletedToDate.currencyFormatted,
                    icon: "sum",
                    accent: .green
                )
                summaryStat(
                    label: "This Period",
                    value: payApp.totalThisPeriod.currencyFormatted,
                    icon: "arrow.up.right",
                    accent: AppTheme.primaryOrange
                )
                Spacer()
                changeOrderMenu
                Button {
                    addLineItem()
                } label: {
                    Label("Add Line Item", systemImage: "plus")
                }
                .buttonStyle(.appSecondary)
                .controlSize(.small)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.md)

            Divider()

            // G703 table — kept on a horizontal scroll because the column
            // count is fixed by the form (A through I). On large screens
            // the whole table fits without scrolling.
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    sovHeaderRow
                    Divider()

                    ForEach(Array(payApp.lineItems.enumerated()), id: \.element.id) { index, item in
                        sovDataRow(index: index, item: item)
                        Divider()
                    }

                    sovTotalRow
                }
                .frame(minWidth: 878)
            }
        }
        // Cap the G703 worksheet to a document width and center it at the top,
        // so on wide displays it reads as a focused document rather than a
        // stretched table with empty canvas to the right/below.
        .frame(maxWidth: 1000)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func summaryStat(label: String, value: String, icon: String, accent: Color = .primary) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(accent == .primary ? AppTheme.secondaryText : accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText)
                    .tracking(0.4)
                Text(value)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundColor(accent)
            }
        }
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
            Text("").sovHeader(width: 78)
        }
        .background(Color.gray.opacity(0.15))
    }

    // MARK: - G703 Data Row

    private func sovDataRow(index: Int, item: SOVLineItem) -> some View {
        HStack(spacing: 0) {
            // A: Item number
            Text("\(item.itemNumber)")
                .sovCell(width: 30)

            // B: Description (EDITABLE)
            TextField("Description", text: $payApp.lineItems[index].description)
                .textFieldStyle(.plain)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(width: 150, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(AppTheme.primaryOrange.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(AppTheme.primaryOrange.opacity(0.25), lineWidth: 0.5)
                )

            // C: Scheduled value (EDITABLE)
            TextField("0", value: $payApp.lineItems[index].scheduledValue, format: .currency(code: "USD"))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(width: 90)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(AppTheme.primaryOrange.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(AppTheme.primaryOrange.opacity(0.25), lineWidth: 0.5)
                )
                #if !os(macOS)
                .keyboardType(.decimalPad)
                #endif

            // D: Previous application (read-only, carried forward)
            Text(item.previousCompleted.currencyFormatted)
                .sovCell(width: 100)
                .foregroundColor(.secondary)

            // E: This period (EDITABLE) — slightly highlighted so the
            // editable cells stand out from the read-only ones.
            TextField("0", value: $payApp.lineItems[index].thisPeriodCompleted, format: .currency(code: "USD"))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(width: 95)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(AppTheme.primaryOrange.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(AppTheme.primaryOrange.opacity(0.25), lineWidth: 0.5)
                )
                #if !os(macOS)
                .keyboardType(.decimalPad)
                #endif

            // F: Materials stored (EDITABLE)
            TextField("0", value: $payApp.lineItems[index].materialsStored, format: .currency(code: "USD"))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(width: 85)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(AppTheme.primaryOrange.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(AppTheme.primaryOrange.opacity(0.25), lineWidth: 0.5)
                )
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

            // Row controls: drag handle to reorder + delete
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                    .contentShape(Rectangle())
                    .help("Drag to reorder")
                    .onDrag {
                        draggingLineItemID = item.id
                        return NSItemProvider(object: item.id.uuidString as NSString)
                    }

                Button(role: .destructive) {
                    deleteLineItem(at: index)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.red.opacity(0.75))
                .help("Delete this line item")
            }
            .font(.caption)
            .frame(width: 78)
        }
        .font(.caption)
        .opacity(draggingLineItemID == item.id ? 0.5 : 1)
        .onDrop(of: [.text], delegate: RowReorderDropDelegate(
            targetID: item.id,
            draggingID: $draggingLineItemID,
            onReorder: { from, to in moveLineItem(from: from, to: to) }
        ))
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
            Text("").sovCell(width: 78)
        }
        .background(Color.gray.opacity(0.1))
        .font(.caption)
    }

    // MARK: - Change Orders

    /// Menu of every change order on the project. Checked entries are already
    /// in the SOV; toggling adds or removes the matching line item. New pay
    /// apps still auto-import COs (see DataStore.buildNewPayApp) — this just
    /// lets the user override that selection per application.
    private var changeOrderMenu: some View {
        Menu {
            let cos = dataStore.changeOrders(for: project.id)
            if cos.isEmpty {
                Text("No change orders for this project")
            } else {
                ForEach(cos) { co in
                    Button {
                        toggleChangeOrder(co)
                    } label: {
                        let title = "CO #\(co.number): \(co.description) · \(co.amount.currencyFormatted)"
                        if isChangeOrderIncluded(co) {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            }
        } label: {
            Label("Change Orders", systemImage: "plus.forwardslash.minus")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .fixedSize()
        .help("Add or remove change orders in this Schedule of Values")
    }

    private func isChangeOrderIncluded(_ co: ChangeOrder) -> Bool {
        payApp.lineItems.contains { $0.changeOrderID == co.id }
    }

    private func toggleChangeOrder(_ co: ChangeOrder) {
        if let idx = payApp.lineItems.firstIndex(where: { $0.changeOrderID == co.id }) {
            payApp.lineItems.remove(at: idx)
        } else {
            let nextNumber = (payApp.lineItems.map(\.itemNumber).max() ?? 0) + 1
            payApp.lineItems.append(SOVLineItem(
                itemNumber: nextNumber,
                description: "CO #\(co.number): \(co.description)",
                scheduledValue: co.amount,
                isChangeOrder: true,
                changeOrderID: co.id
            ))
        }
        renumberLineItems()
    }

    // MARK: - Line Item Mutations

    private func addLineItem() {
        let nextNumber = (payApp.lineItems.map(\.itemNumber).max() ?? 0) + 1
        payApp.lineItems.append(
            SOVLineItem(itemNumber: nextNumber, description: "", scheduledValue: 0)
        )
    }

    private func deleteLineItem(at index: Int) {
        guard payApp.lineItems.indices.contains(index) else { return }
        payApp.lineItems.remove(at: index)
        renumberLineItems()
    }

    /// Drag-reorder: move the line item with id `from` to the position of `to`.
    private func moveLineItem(from: UUID, to: UUID) {
        guard let f = payApp.lineItems.firstIndex(where: { $0.id == from }),
              let t = payApp.lineItems.firstIndex(where: { $0.id == to }), f != t else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            payApp.lineItems.move(fromOffsets: IndexSet(integer: f), toOffset: t > f ? t + 1 : t)
        }
        renumberLineItems()
    }

    /// Keep column A (item number) sequential after a reorder or delete.
    private func renumberLineItems() {
        for i in payApp.lineItems.indices {
            payApp.lineItems[i].itemNumber = i + 1
        }
    }

    private func save() {
        dataStore.updatePayApplication(payApp, in: project.id)
        closeForm()
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
    @Environment(\.inlineDismiss) private var inlineDismiss

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
        EntryFormScaffold(
            title: "Mark as Sent",
            icon: AppIcons.invoice,
            saveTitle: "Create Invoice",
            onCancel: closeForm,
            onSave: markSent
        ) {
            EntrySection("Invoice Details", systemImage: AppIcons.invoice) {
                LabeledField(label: "Invoice Number") {
                    TextField("Auto-suggested", text: $invoiceNumber).textFieldStyle(.appField)
                }
                LabeledField(label: "Sent Date") {
                    DatePicker("", selection: $sentDate, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
                Stepper("Payment Terms: Net \(termsDays)", value: $termsDays, in: 7...120, step: 1)
                InfoRow(label: "Due Date", value: (Calendar.current.date(byAdding: .day, value: termsDays, to: sentDate) ?? sentDate).shortDate)
            }

            EntrySection("Bill To", systemImage: AppIcons.person) {
                if billToCandidates.isEmpty {
                    Text("No client linked to this project. Add a GC or Sub on the project to set a bill-to.")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if billToCandidates.count == 1, let only = billToCandidates.first {
                    InfoRow(label: only.name, value: roleLabel(for: only))
                } else {
                    LabeledField(label: "Bill To") {
                        Picker("", selection: Binding(
                            get: { billToClientID ?? billToCandidates.first?.id.recordName ?? "" },
                            set: { billToClientID = $0 }
                        )) {
                            ForEach(billToCandidates, id: \.id.recordName) { c in
                                Text("\(c.name) — \(roleLabel(for: c))").tag(c.id.recordName)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).appControlSurface()
                    }
                    Text("Defaults to the subcontractor when both a GC and a Sub are linked. Change if billing the GC directly.")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                }
            }

            EntrySection("Summary", systemImage: AppIcons.money) {
                InfoRow(label: "Application #", value: "\(payApp.applicationNumber)")
                InfoRow(label: "Amount This Period", value: payApp.netAmountThisPeriod.currencyFormatted)
                InfoRow(label: "Retainage Withheld", value: payApp.totalRetainage.currencyFormatted)
                InfoRow(label: "Net Invoice Amount", value: (payApp.netAmountThisPeriod - payApp.totalRetainage).currencyFormatted)
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
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

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

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
        closeForm()
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
    @Environment(\.inlineDismiss) private var inlineDismiss

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
        EntryFormScaffold(
            title: "Log Payment",
            icon: AppIcons.payment,
            saveDisabled: !canSave,
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Payment Details", systemImage: AppIcons.payment) {
                InfoRow(label: "Invoice", value: invoice.invoiceNumber)
                InfoRow(label: "Balance Due", value: balanceDue.currencyFormatted)
                LabeledField(label: "Amount") {
                    TextField("0", value: $amount, format: .currency(code: "USD"))
                        .textFieldStyle(.appField)
                        #if !os(macOS)
                        .keyboardType(.decimalPad)
                        #endif
                }
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    LabeledField(label: "Date Received") {
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden().appControlSurface()
                    }
                    LabeledField(label: "Method") {
                        Picker("", selection: $method) {
                            ForEach(PaymentMethod.allCases) { m in
                                Label(m.rawValue, systemImage: m.icon).tag(m)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).appControlSurface()
                    }
                }
                LabeledField(label: "Reference Number") {
                    TextField("Check #, wire confirmation, ACH ref", text: $referenceNumber)
                        .textFieldStyle(.appField)
                }
            }

            EntrySection("Proof of Payment", systemImage: "checkmark.shield") {
                if attachments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.title2)
                            .foregroundColor(AppTheme.secondaryText)
                        Text("Drag a check image or PDF here")
                            .font(.callout)
                            .foregroundColor(AppTheme.secondaryText)
                        Button {
                            showFilePicker = true
                        } label: {
                            Label("Or choose a file…", systemImage: "paperclip")
                        }
                        .buttonStyle(.appSecondary)
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
                        .textFieldStyle(.appField)
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
                            .foregroundColor(AppTheme.primaryOrange)
                    }
                    .buttonStyle(.plain)
                }
                if !hasProofOrReason {
                    Text("⚠️ Attach a check image or payment receipt, OR type a reason to save without proof.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            EntrySection("Notes", systemImage: "note.text") {
                NotesField(text: $notes, minHeight: 60)
            }
        }
        #if os(macOS)
        .frame(width: 540, height: 640)
        #endif
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

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

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
        closeForm()
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
        case g703 = "AIA G702 / G703 (PDF)"
        case steelSync = "SteelSync Branded (PDF)"
        case subcontractorAIA = "Carrillo Submittal format (PDF)"
        case subcontractorXLSX = "Carrillo Submittal format (Excel .xlsx)"
        case subcontractorFullRelease = "Full w/ Release Lien (PDF)"
        var id: String { rawValue }

        var isExcel: Bool { self == .subcontractorXLSX }
    }

    private var formatBlurb: String {
        switch selectedFormat {
        case .g703:
            return includeG702Cover
                ? "Two-page PDF: G702 Application for Payment cover + G703 Schedule of Values continuation sheet. The form most GCs expect."
                : "Single-page G703 Schedule of Values only. Useful for subcontractors that don't require the G702 cover."
        case .steelSync:
            return "Clean, modern invoice layout with SteelSync branding. Same data, more readable."
        case .subcontractorAIA:
            return "Two-page subcontractor pay application matching the Carrillo Steel submittal template — application certificate page + schedule of values continuation with subtotals, change-order section, and summary block."
        case .subcontractorXLSX:
            return "Editable Excel workbook (.xlsx) with two sheets matching the Carrillo Steel submittal template — Application sheet (lines 1–9, lien release & notary block, change order summary) + Schedule of Values sheet. All numbers are real Excel currency cells you can edit for next month's app."
        case .subcontractorFullRelease:
            return "Same two-page Carrillo Submittal format, but the right-hand certification column is replaced with a full WAIVER & RELEASE OF LIEN block — McGregor / Miller Act language, blank notary fields, and a PM / DATE PAID / CHECK # / AMOUNT footer for back-office bookkeeping."
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
                        PDFShareButton.payApp(url: url, payApp: payApp, project: project, client: billToClient)
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
                        .buttonStyle(.appPrimary)
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 480)
        #endif
    }

    private func export() {
        let url: URL?
        if selectedFormat.isExcel {
            url = PayAppXLSXRenderer(
                payApp: payApp,
                project: project,
                client: billToClient
            ).render()
        } else {
            url = PayAppPDFRenderer(
                payApp: payApp,
                project: project,
                client: billToClient,
                format: selectedFormat,
                includeG702Cover: includeG702Cover
            ).render()
        }
        if let url {
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
    @Environment(\.inlineDismiss) private var inlineDismiss

    private var totalRetainageHeld: Decimal {
        dataStore.payApps(for: project.id)
            .filter { !$0.isRetainageRelease }
            .reduce(Decimal(0)) { $0 + $1.totalRetainage }
    }

    var body: some View {
        EntryFormScaffold(
            title: "Retainage Release",
            icon: AppIcons.money,
            saveTitle: "Create",
            saveDisabled: totalRetainageHeld <= 0,
            onCancel: closeForm,
            onSave: create
        ) {
            EntrySection("Closeout Retainage Release", systemImage: "lock.open.fill") {
                InfoRow(label: "Project", value: project.title)
                InfoRow(label: "Total Retainage Held", value: totalRetainageHeld.currencyFormatted)
                Text("This creates a new pay application marked as a retainage release. Use this only at project closeout when the GC is releasing withheld retainage.")
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 380)
        #endif
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

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
        closeForm()
    }
}
