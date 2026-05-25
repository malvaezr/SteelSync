import SwiftUI
import CloudKit

// MARK: - Change Order Form (shared by Add + Edit)
//
// Both AddChangeOrderView and EditChangeOrderSheet delegate to
// `ChangeOrderFormBody` so they always expose the same set of editable
// fields. The parent owns the @State and the save side-effect; the body
// handles all rendering and per-field bindings.

private struct ChangeOrderFormBody: View {
    let project: Project?
    let client: Client?
    let allowEditingNumber: Bool
    let siblingNumbers: Set<Int>      // Other CO numbers on this project (collision check)
    let originalCONumber: Int?         // nil for Add, existing number for Edit

    @Binding var numberText: String
    @Binding var coDescription: String      // = title
    @Binding var invoiceNumber: String
    @Binding var invoiceDate: Date
    @Binding var workOrderNumber: String
    @Binding var poNumber: String
    @Binding var scope: String
    @Binding var laborLines: [LaborLineItem]
    @Binding var additionalLines: [AdditionalChargeItem]
    @Binding var taxRateString: String
    @Binding var paymentTerms: String
    @Binding var additionalNotes: String
    @Binding var billedTo: COBilledTo
    @Binding var isSigned: Bool
    @Binding var signedDate: Date

    var laborSubtotal: Decimal { laborLines.reduce(0) { $0 + $1.lineTotal } }
    var additionalSubtotal: Decimal { additionalLines.reduce(0) { $0 + $1.lineTotal } }
    var subtotal: Decimal { laborSubtotal + additionalSubtotal }
    var taxRate: Decimal { Decimal(string: taxRateString) ?? 0 }
    var taxAmount: Decimal {
        var result = Decimal(); var val = subtotal * taxRate / 100
        NSDecimalRound(&result, &val, 2, .plain); return result
    }
    var totalDue: Decimal { subtotal + taxAmount }

    var parsedNumber: Int? { Int(numberText.trimmingCharacters(in: .whitespaces)) }
    var numberCollision: Bool {
        guard let n = parsedNumber else { return false }
        if let original = originalCONumber, n == original { return false }
        return siblingNumbers.contains(n)
    }

    private var numberError: String? {
        guard allowEditingNumber else { return nil }
        if numberCollision { return "Another change order on this project already uses #\(parsedNumber ?? 0)." }
        if parsedNumber == nil || (parsedNumber ?? 0) < 1 { return "Number must be a positive integer." }
        return nil
    }

    var body: some View {
        Group {
            EntrySection("Identification", systemImage: "number.square") {
                LabeledField(label: "CO Number") {
                    TextField("e.g. 2", text: $numberText)
                        .textFieldStyle(.appField)
                        .disabled(!allowEditingNumber)
                        #if !os(macOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                if let numberError {
                    Text(numberError).font(.caption).foregroundColor(.red)
                }
                LabeledField(label: "Title") {
                    TextField("Beam relocation, owner request", text: $coDescription)
                        .textFieldStyle(.appField)
                }
                LabeledField(label: "Billed To") {
                    Picker("", selection: $billedTo) {
                        ForEach(COBilledTo.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }
            }

            EntrySection("Invoice Details", systemImage: AppIcons.invoice) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    LabeledField(label: "Invoice #") {
                        TextField("INV-1", text: $invoiceNumber).textFieldStyle(.appField)
                    }
                    LabeledField(label: "Date") {
                        DatePicker("", selection: $invoiceDate, displayedComponents: .date)
                            .labelsHidden().appControlSurface()
                    }
                }
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    LabeledField(label: "Work Order #") {
                        TextField("", text: $workOrderNumber).textFieldStyle(.appField)
                    }
                    LabeledField(label: "PO Number") {
                        TextField("", text: $poNumber).textFieldStyle(.appField)
                    }
                }
            }

            EntrySection("Bill To / Project", systemImage: "person.text.rectangle") {
                if let client = client {
                    InfoRow(label: "Bill To", value: client.name, icon: "person")
                    if !client.billingAddress.isEmpty {
                        Text(client.billingAddress).font(.caption).foregroundColor(AppTheme.secondaryText)
                    }
                } else {
                    Text("No client linked to this project").font(.caption).foregroundColor(AppTheme.secondaryText)
                }
                if let project = project {
                    InfoRow(label: "Project", value: project.title, icon: "building.2")
                    if !project.location.isEmpty {
                        InfoRow(label: "Location", value: project.location, icon: AppIcons.location)
                    }
                }
            }

            EntrySection("Work Description / Scope Performed", systemImage: "text.alignleft") {
                NotesField(text: $scope, minHeight: 80)
            }

            EntrySection("Labor & Equipment Charges", systemImage: AppIcons.tools) {
                laborTable
            }

            EntrySection("Additional Charges / Materials", systemImage: AppIcons.equipment) {
                additionalTable
            }

            EntrySection("Totals", systemImage: AppIcons.money) {
                HStack {
                    Text("Subtotal").foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    Text(subtotal.currencyWithCents).fontWeight(.semibold).foregroundColor(AppTheme.primaryText)
                }
                HStack {
                    Text("Tax Rate (%)").foregroundColor(AppTheme.secondaryText)
                    TextField("0", text: $taxRateString)
                        #if !os(macOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .textFieldStyle(.appField).frame(width: 90)
                    Spacer()
                    if taxAmount > 0 {
                        Text(taxAmount.currencyWithCents).foregroundColor(AppTheme.secondaryText)
                    }
                }
            }

            EntrySection("Payment Terms & Notes", systemImage: "note.text") {
                LabeledField(label: "Payment Terms") {
                    TextField("Net 30 Days", text: $paymentTerms).textFieldStyle(.appField)
                }
                LabeledField(label: "Additional Notes") {
                    NotesField(text: $additionalNotes, minHeight: 60)
                }
            }

            EntrySection("Approval", systemImage: "checkmark.seal") {
                Toggle("Mark as Signed", isOn: $isSigned)
                    .tint(AppTheme.primaryOrange)
                if isSigned {
                    LabeledField(label: "Signed Date") {
                        DatePicker("", selection: $signedDate, displayedComponents: .date)
                            .labelsHidden().appControlSurface()
                    }
                }
            }
        }
    }

    private var laborTable: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Description").font(.caption).fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
                Text("Qty").font(.caption).fontWeight(.bold).frame(width: 46)
                Text("Hours").font(.caption).fontWeight(.bold).frame(width: 50)
                Text("Rate").font(.caption).fontWeight(.bold).frame(width: 64)
                Text("Total").font(.caption).fontWeight(.bold).frame(width: 78, alignment: .trailing)
            }
            ForEach(Array(laborLines.enumerated()), id: \.element.id) { index, line in
                HStack {
                    Text(line.category.displayName)
                        .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                    TextField("0", value: $laborLines[index].quantity, format: .number)
                        #if !os(macOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .textFieldStyle(.roundedBorder).frame(width: 46)
                    TextField("0", value: $laborLines[index].hours, format: .number)
                        #if !os(macOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .textFieldStyle(.roundedBorder).frame(width: 50)
                    TextField("0", value: $laborLines[index].rate, format: .number)
                        #if !os(macOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .textFieldStyle(.roundedBorder).frame(width: 64)
                    Text(line.lineTotal.currencyWithCents)
                        .font(.callout).fontWeight(.medium)
                        .frame(width: 78, alignment: .trailing)
                        .foregroundColor(line.lineTotal > 0 ? AppTheme.primaryOrange : AppTheme.secondaryText)
                }
            }
        }
    }

    private var additionalTable: some View {
        VStack(spacing: 8) {
            ForEach(Array(additionalLines.enumerated()), id: \.element.id) { index, line in
                HStack {
                    TextField("Description", text: $additionalLines[index].description)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 4) {
                        Text("$").foregroundColor(AppTheme.secondaryText)
                        TextField("0", value: $additionalLines[index].rate, format: .number)
                            #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .textFieldStyle(.roundedBorder).frame(width: 90)
                    }
                    Button { additionalLines.remove(at: index) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red.opacity(0.6))
                    }.buttonStyle(.plain)
                }
            }
            Button {
                var item = AdditionalChargeItem()
                item.quantity = 1
                item.hours = 1
                additionalLines.append(item)
            } label: {
                Label("Add Line Item", systemImage: "plus")
                    .font(.callout).foregroundColor(AppTheme.primaryOrange)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Add Change Order / Work Order Invoice
struct AddChangeOrderView: View {
    let projectID: CKRecord.ID
    let nextNumber: Int
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var numberText = ""
    @State private var coDescription = ""
    @State private var invoiceNumber = ""
    @State private var invoiceDate = Date()
    @State private var workOrderNumber = ""
    @State private var poNumber = ""
    @State private var scope = ""
    @State private var laborLines: [LaborLineItem] = LaborLineItem.defaultSet()
    @State private var additionalLines: [AdditionalChargeItem] = []
    @State private var taxRateString = ""
    @State private var paymentTerms = "Net 30 Days"
    @State private var additionalNotes = ""
    @State private var billedTo: COBilledTo = .gc
    @State private var isSigned = false
    @State private var signedDate = Date()

    private var project: Project? {
        dataStore.projects.first { $0.id == projectID }
    }
    private var client: Client? {
        guard let p = project else { return nil }
        return dataStore.client(for: p.clientRef)
    }
    private var siblingNumbers: Set<Int> {
        Set(dataStore.changeOrders(for: projectID).map(\.number))
    }
    private var parsedNumber: Int? { Int(numberText.trimmingCharacters(in: .whitespaces)) }
    private var numberCollision: Bool {
        guard let n = parsedNumber else { return false }
        return siblingNumbers.contains(n)
    }
    private var isSaveDisabled: Bool {
        parsedNumber == nil || (parsedNumber ?? 0) < 1 || numberCollision
    }

    private var footerTotal: Decimal {
        let labor = laborLines.reduce(Decimal(0)) { $0 + $1.lineTotal }
        let additional = additionalLines.reduce(Decimal(0)) { $0 + $1.lineTotal }
        let sub = labor + additional
        let rate = Decimal(string: taxRateString) ?? 0
        var tax = Decimal(); var v = sub * rate / 100
        NSDecimalRound(&tax, &v, 2, .plain)
        return sub + tax
    }

    var body: some View {
        EntryFormScaffold(
            title: "Work Order Invoice",
            badge: "CO #\(numberText.isEmpty ? "\(nextNumber)" : numberText)",
            saveDisabled: isSaveDisabled,
            onCancel: closeForm,
            onSave: save
        ) {
            ChangeOrderFormBody(
                project: project,
                client: client,
                allowEditingNumber: true,
                siblingNumbers: siblingNumbers,
                originalCONumber: nil,
                numberText: $numberText,
                coDescription: $coDescription,
                invoiceNumber: $invoiceNumber,
                invoiceDate: $invoiceDate,
                workOrderNumber: $workOrderNumber,
                poNumber: $poNumber,
                scope: $scope,
                laborLines: $laborLines,
                additionalLines: $additionalLines,
                taxRateString: $taxRateString,
                paymentTerms: $paymentTerms,
                additionalNotes: $additionalNotes,
                billedTo: $billedTo,
                isSigned: $isSigned,
                signedDate: $signedDate
            )
        } footer: {
            HStack {
                Text("TOTAL DUE").font(.headline).foregroundColor(AppTheme.primaryText)
                Spacer()
                Text(footerTotal.currencyWithCents)
                    .font(.title3).fontWeight(.bold).foregroundColor(AppTheme.primaryOrange)
            }
        }
        .onAppear {
            if numberText.isEmpty { numberText = "\(nextNumber)" }
            if invoiceNumber.isEmpty { invoiceNumber = "INV-\(nextNumber)" }
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func save() {
        guard let n = parsedNumber, n > 0, !numberCollision else { return }
        let laborSubtotal = laborLines.reduce(Decimal(0)) { $0 + $1.lineTotal }
        let additionalSubtotal = additionalLines.reduce(Decimal(0)) { $0 + $1.lineTotal }
        let subtotal = laborSubtotal + additionalSubtotal
        let taxRate = Decimal(string: taxRateString) ?? 0
        var taxAmount = Decimal(); var taxVal = subtotal * taxRate / 100
        NSDecimalRound(&taxAmount, &taxVal, 2, .plain)
        let total = subtotal + taxAmount

        let co = ChangeOrder(
            number: n,
            description: coDescription,
            amount: total,
            submittedDate: invoiceDate,
            signedDate: isSigned ? signedDate : nil,
            scope: scope,
            billedTo: billedTo,
            invoiceNumber: invoiceNumber,
            invoiceDate: invoiceDate,
            workOrderNumber: workOrderNumber,
            poNumber: poNumber,
            laborLineItems: laborLines,
            additionalCharges: additionalLines,
            taxRate: taxRate,
            paymentTerms: paymentTerms,
            additionalNotes: additionalNotes
        )
        dataStore.addChangeOrder(co, to: projectID)
        closeForm()
    }
}

// MARK: - Edit Change Order (full Work Order Invoice form)
//
// Mirrors the Add sheet exactly via the shared `ChangeOrderFormBody` so the
// PM can adjust line items, tax rate, payment terms, etc. — not just the
// total. For COs created before line items were tracked (amount > 0 but
// laborLineItems + additionalCharges both empty), we seed a synthetic
// "Existing Total" line so the invoice math still adds up to the saved
// amount and the user can see/edit it.
struct EditChangeOrderSheet: View {
    let changeOrder: ChangeOrder
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var numberText: String
    @State private var coDescription: String
    @State private var invoiceNumber: String
    @State private var invoiceDate: Date
    @State private var workOrderNumber: String
    @State private var poNumber: String
    @State private var scope: String
    @State private var laborLines: [LaborLineItem]
    @State private var additionalLines: [AdditionalChargeItem]
    @State private var taxRateString: String
    @State private var paymentTerms: String
    @State private var additionalNotes: String
    @State private var billedTo: COBilledTo
    @State private var isSigned: Bool
    @State private var signedDate: Date

    init(changeOrder: ChangeOrder, projectID: CKRecord.ID) {
        self.changeOrder = changeOrder
        self.projectID = projectID
        _numberText = State(initialValue: "\(changeOrder.number)")
        _coDescription = State(initialValue: changeOrder.description)
        _invoiceNumber = State(initialValue: changeOrder.invoiceNumber)
        _invoiceDate = State(initialValue: changeOrder.invoiceDate)
        _workOrderNumber = State(initialValue: changeOrder.workOrderNumber)
        _poNumber = State(initialValue: changeOrder.poNumber)
        _scope = State(initialValue: changeOrder.scope)

        // Backward-compat: legacy COs only stored `amount` with no line
        // breakdown. Seed an "Existing Total" line so the unified form's
        // computed total matches what was saved.
        let labor = changeOrder.laborLineItems
        var additional = changeOrder.additionalCharges
        let hasLineItems = labor.contains { $0.lineTotal > 0 } || additional.contains { $0.lineTotal > 0 }
        if !hasLineItems && changeOrder.amount > 0 {
            additional.append(AdditionalChargeItem(
                description: "Existing Total",
                quantity: 1, hours: 1,
                rate: changeOrder.amount
            ))
        }
        _laborLines = State(initialValue: labor.isEmpty ? LaborLineItem.defaultSet() : labor)
        _additionalLines = State(initialValue: additional)

        _taxRateString = State(initialValue: changeOrder.taxRate > 0
            ? NSDecimalNumber(decimal: changeOrder.taxRate).stringValue
            : "")
        _paymentTerms = State(initialValue: changeOrder.paymentTerms.isEmpty ? "Net 30 Days" : changeOrder.paymentTerms)
        _additionalNotes = State(initialValue: changeOrder.additionalNotes)
        _billedTo = State(initialValue: changeOrder.billedTo)
        _isSigned = State(initialValue: changeOrder.isSigned)
        _signedDate = State(initialValue: changeOrder.signedDate ?? Date())
    }

    private var project: Project? {
        dataStore.projects.first { $0.id == projectID }
    }
    private var client: Client? {
        guard let p = project else { return nil }
        return dataStore.client(for: p.clientRef)
    }
    private var siblingNumbers: Set<Int> {
        Set(dataStore.changeOrders(for: projectID)
            .filter { $0.id != changeOrder.id }
            .map(\.number))
    }
    private var parsedNumber: Int? { Int(numberText.trimmingCharacters(in: .whitespaces)) }
    private var numberCollision: Bool {
        guard let n = parsedNumber else { return false }
        if n == changeOrder.number { return false }
        return siblingNumbers.contains(n)
    }
    private var isSaveDisabled: Bool {
        parsedNumber == nil || (parsedNumber ?? 0) < 1 || numberCollision
    }

    private var footerTotal: Decimal {
        let labor = laborLines.reduce(Decimal(0)) { $0 + $1.lineTotal }
        let additional = additionalLines.reduce(Decimal(0)) { $0 + $1.lineTotal }
        let sub = labor + additional
        let rate = Decimal(string: taxRateString) ?? 0
        var tax = Decimal(); var v = sub * rate / 100
        NSDecimalRound(&tax, &v, 2, .plain)
        return sub + tax
    }

    var body: some View {
        EntryFormScaffold(
            title: "Edit Work Order Invoice",
            badge: "CO #\(numberText)",
            saveDisabled: isSaveDisabled,
            onCancel: closeForm,
            onSave: save
        ) {
            ChangeOrderFormBody(
                project: project,
                client: client,
                allowEditingNumber: true,
                siblingNumbers: siblingNumbers,
                originalCONumber: changeOrder.number,
                numberText: $numberText,
                coDescription: $coDescription,
                invoiceNumber: $invoiceNumber,
                invoiceDate: $invoiceDate,
                workOrderNumber: $workOrderNumber,
                poNumber: $poNumber,
                scope: $scope,
                laborLines: $laborLines,
                additionalLines: $additionalLines,
                taxRateString: $taxRateString,
                paymentTerms: $paymentTerms,
                additionalNotes: $additionalNotes,
                billedTo: $billedTo,
                isSigned: $isSigned,
                signedDate: $signedDate
            )
        } footer: {
            HStack {
                Text("TOTAL DUE").font(.headline).foregroundColor(AppTheme.primaryText)
                Spacer()
                Text(footerTotal.currencyWithCents)
                    .font(.title3).fontWeight(.bold).foregroundColor(AppTheme.primaryOrange)
            }
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func save() {
        guard let n = parsedNumber, n > 0, !numberCollision else { return }
        let laborSubtotal = laborLines.reduce(Decimal(0)) { $0 + $1.lineTotal }
        let additionalSubtotal = additionalLines.reduce(Decimal(0)) { $0 + $1.lineTotal }
        let subtotal = laborSubtotal + additionalSubtotal
        let taxRate = Decimal(string: taxRateString) ?? 0
        var taxAmount = Decimal(); var taxVal = subtotal * taxRate / 100
        NSDecimalRound(&taxAmount, &taxVal, 2, .plain)
        let total = subtotal + taxAmount

        var updated = changeOrder
        updated.number = n
        updated.description = coDescription
        updated.amount = total
        updated.submittedDate = invoiceDate
        updated.signedDate = isSigned ? signedDate : nil
        updated.scope = scope
        updated.billedTo = billedTo
        updated.invoiceNumber = invoiceNumber
        updated.invoiceDate = invoiceDate
        updated.workOrderNumber = workOrderNumber
        updated.poNumber = poNumber
        updated.laborLineItems = laborLines
        updated.additionalCharges = additionalLines
        updated.taxRate = taxRate
        updated.paymentTerms = paymentTerms
        updated.additionalNotes = additionalNotes
        dataStore.updateChangeOrder(updated, in: projectID)
        closeForm()
    }
}

// MARK: - Add Payment
struct AddPaymentView: View {
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var amount = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var appliedToCO: UUID?
    @State private var appliedToInvoiceID: UUID?
    @State private var paymentMethod: PaymentMethod = .check
    @State private var referenceNumber = ""
    @State private var proofReason = ""
    @State private var attachments: [Attachment] = []
    @State private var showFilePicker = false

    private var project: Project? {
        dataStore.projects.first { $0.id == projectID }
    }

    private var changeOrders: [ChangeOrder] {
        dataStore.changeOrders(for: projectID)
    }

    private var outstandingInvoices: [Invoice] {
        dataStore.invoices(for: projectID)
            .filter { $0.status != .paid && $0.status != .draft }
            .sorted { ($0.sentDate ?? .distantPast) > ($1.sentDate ?? .distantPast) }
    }

    private var parsedAmount: Decimal {
        Decimal(string: amount.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private var hasProofOrReason: Bool {
        !attachments.isEmpty || !proofReason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSave: Bool {
        parsedAmount > 0 && hasProofOrReason
    }

    var body: some View {
        EntryFormScaffold(
            title: "Record Payment",
            icon: AppIcons.money,
            saveDisabled: !canSave,
            onCancel: closeForm,
            onSave: save
        ) {
            // Collection Progress
            if let project = project {
                EntrySection("Collection Progress", systemImage: "chart.bar.fill") {
                    let revenue = project.totalRevenue
                    let collected = project.totalPayments
                    let remaining = project.remainingBalance
                    let progress = revenue > 0 ? Double(truncating: (collected / revenue) as NSDecimalNumber) : 0
                    let afterCollected = collected + parsedAmount
                    let afterProgress = revenue > 0 ? Double(truncating: (afterCollected / revenue) as NSDecimalNumber) : 0

                    VStack(spacing: AppTheme.Spacing.sm) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Revenue").font(.caption).foregroundColor(AppTheme.secondaryText)
                                Text(revenue.currencyFormatted).fontWeight(.semibold)
                            }
                            Spacer()
                            VStack(alignment: .center) {
                                Text("Collected").font(.caption).foregroundColor(AppTheme.secondaryText)
                                Text(collected.currencyFormatted).fontWeight(.semibold).foregroundColor(.green)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Remaining").font(.caption).foregroundColor(AppTheme.secondaryText)
                                Text(remaining.currencyFormatted).fontWeight(.semibold).foregroundColor(.orange)
                            }
                        }

                        ProgressBar(value: progress, color: .green)

                        if parsedAmount > 0 {
                            HStack {
                                Text("After this payment:")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.secondaryText)
                                Spacer()
                                Text(afterCollected.currencyFormatted)
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                                Text("(\(Int(afterProgress * 100))%)")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.secondaryText)
                            }

                            ProgressBar(value: afterProgress, color: .green.opacity(0.6), height: 4)
                        }
                    }
                }
            }

            // Payment Details
            EntrySection("Payment Details", systemImage: "banknote") {
                LabeledField(label: "Amount") {
                    CurrencyInput(placeholder: "0.00", text: $amount)
                }
                LabeledField(label: "Date Received") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
                LabeledField(label: "Method") {
                    Picker("", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases) { m in
                            Label(m.rawValue, systemImage: m.icon).tag(m)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }
                LabeledField(label: "Reference Number") {
                    TextField("Check #, wire confirmation, ACH ref", text: $referenceNumber)
                        .textFieldStyle(.appField)
                }

                if !outstandingInvoices.isEmpty {
                    LabeledField(label: "Apply to Invoice") {
                        Picker("", selection: $appliedToInvoiceID) {
                            Text("None (contract payment)").tag(nil as UUID?)
                            Divider()
                            ForEach(outstandingInvoices) { invoice in
                                let remaining = dataStore.balanceRemaining(for: invoice)
                                Text("\(invoice.invoiceNumber) — \(remaining.currencyFormatted) due")
                                    .tag(invoice.id as UUID?)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).appControlSurface()
                    }
                }

                LabeledField(label: "Apply to Change Order") {
                    Picker("", selection: $appliedToCO) {
                        Text("None").tag(nil as UUID?)
                        if !changeOrders.isEmpty {
                            Divider()
                            ForEach(changeOrders) { co in
                                Text("CO #\(co.number) - \(co.description) (\(co.amount.currencyFormatted))")
                                    .tag(co.id as UUID?)
                            }
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }
            }

            // Proof of Payment (required — image or reason)
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
                    .fileDrop(folderID: "payment-\(projectID.recordName)") { attachment in
                        attachments.append(attachment)
                    }

                    NotesField(text: $proofReason, minHeight: 60)
                    Text("Or explain why no proof is attached (required if no file)")
                        .font(.caption2).foregroundColor(AppTheme.tertiaryText)
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
                    .buttonStyle(.appSecondary)
                    .controlSize(.small)
                }

                if !hasProofOrReason {
                    Text("⚠️ Attach a check image/receipt, OR type a reason to save without proof.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // Notes
            EntrySection("Notes", systemImage: "note.text") {
                NotesField(text: $notes, minHeight: 60)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFilePick(result)
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        let folderID = "payment-\(UUID().uuidString)"
        switch FileStorageService.importFile(from: url, bidID: folderID) {
        case .success(let attachment):
            attachments.append(attachment)
        case .failure:
            break
        }
    }

    private func save() {
        let payment = Payment(
            amount: parsedAmount,
            date: date,
            appliedToChangeOrder: appliedToCO,
            appliedToInvoiceID: appliedToInvoiceID,
            paymentMethod: paymentMethod,
            referenceNumber: referenceNumber,
            proofReason: proofReason,
            notes: notes,
            attachments: attachments
        )
        dataStore.addPayment(payment, to: projectID)
        // If this payment satisfies an invoice, refresh its status
        if let invoiceID = appliedToInvoiceID,
           let invoice = dataStore.invoices(for: projectID).first(where: { $0.id == invoiceID }) {
            dataStore.refreshInvoiceStatus(invoice, in: projectID)
        }
        closeForm()
    }
}

// MARK: - Payroll Employee Line
private struct PayrollLine: Identifiable {
    let id = UUID()
    var employeeUUID: UUID?
    var employeeName: String = ""
    var hourlyRate: Decimal = 0
    /// Single-total hours entry (used when useDailyBreakdown == false)
    var hoursWorked: String = ""
    /// Per-day hours (7 entries, week-start-first) used when useDailyBreakdown == true
    var dailyHours: [String] = Array(repeating: "", count: 7)
    /// Per diem paid for the week (flat dollar amount)
    var perDiem: String = ""
    /// UI toggle between total-hours entry and per-day grid
    var useDailyBreakdown: Bool = false

    var parsedHours: Decimal {
        if useDailyBreakdown {
            return dailyHours.reduce(Decimal(0)) { $0 + (Decimal(string: $1) ?? 0) }
        }
        return Decimal(string: hoursWorked) ?? 0
    }

    var parsedPerDiem: Decimal {
        Decimal(string: perDiem) ?? 0
    }

    var dailyHoursDecimal: [Decimal]? {
        guard useDailyBreakdown else { return nil }
        return dailyHours.map { Decimal(string: $0) ?? 0 }
    }

    var pay: Decimal {
        hourlyRate * parsedHours + parsedPerDiem
    }
}

// MARK: - Add Payroll Entry
struct AddPayrollView: View {
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var weekStart = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
    @State private var notes = ""
    @State private var crewLines: [PayrollLine] = []
    @State private var showEmployeePicker = false

    private var project: Project? {
        dataStore.projects.first { $0.id == projectID }
    }

    private var totalHours: Decimal {
        crewLines.reduce(0) { $0 + $1.parsedHours }
    }

    private var totalAmount: Decimal {
        crewLines.reduce(0) { $0 + $1.pay }
    }

    private var availableEmployees: [Employee] {
        let usedIDs = Set(crewLines.compactMap { $0.employeeUUID })
        return dataStore.activeEmployees.filter { !usedIDs.contains($0.id) }
    }

    var body: some View {
        EntryFormScaffold(
            title: "Add Payroll Entry",
            icon: AppIcons.crew,
            saveDisabled: crewLines.isEmpty || totalHours == 0,
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Work Week", systemImage: AppIcons.calendar) {
                LabeledField(label: "Week Starting") {
                    DatePicker("", selection: $weekStart, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
                if let project = project {
                    InfoRow(label: "Project", value: project.title, icon: "building.2")
                }
            }

            EntrySection("Crew (\(crewLines.count))", systemImage: AppIcons.people) {
                if crewLines.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "person.badge.plus")
                                .font(.title2)
                                .foregroundColor(AppTheme.secondaryText)
                            Text("Add crew members to this payroll entry")
                                .font(.caption)
                                .foregroundColor(AppTheme.secondaryText)
                        }
                        .padding(.vertical, AppTheme.Spacing.md)
                        Spacer()
                    }
                }

                ForEach(Array(crewLines.enumerated()), id: \.element.id) { index, line in
                    crewLineRow(index: index, line: line)
                        .padding(.vertical, 6)
                    if index < crewLines.count - 1 {
                        Divider()
                    }
                }

                if !availableEmployees.isEmpty {
                    Menu {
                        ForEach(availableEmployees) { emp in
                            Button {
                                addEmployee(emp)
                            } label: {
                                HStack {
                                    Text(emp.fullName)
                                    Text("(\(emp.employeeType.displayName))")
                                    Spacer()
                                    Text(emp.defaultHourlyRate.currencyFormatted + "/hr")
                                }
                            }
                        }
                    } label: {
                        Label("Add Crew Member", systemImage: "person.badge.plus")
                            .font(.callout)
                            .foregroundColor(AppTheme.primaryOrange)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            EntrySection("Notes", systemImage: "note.text") {
                TextField("Notes", text: $notes).textFieldStyle(.appField)
            }
        } footer: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Hours")
                        .font(.caption).foregroundColor(AppTheme.secondaryText)
                    Text(totalHours.decimalFormatted)
                        .font(.title3).fontWeight(.bold).foregroundColor(AppTheme.primaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total Labor Cost")
                        .font(.caption).foregroundColor(AppTheme.secondaryText)
                    Text(totalAmount.currencyFormatted)
                        .font(.title3).fontWeight(.bold).foregroundColor(AppTheme.primaryOrange)
                }
            }
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func addEmployee(_ employee: Employee) {
        crewLines.append(PayrollLine(
            employeeUUID: employee.id,
            employeeName: employee.fullName,
            hourlyRate: employee.defaultHourlyRate
        ))
    }

    /// Seven short day labels + numeric day-of-month based on the picked week
    /// start. Updates when `weekStart` changes so the header always matches
    /// the actual dates of the pay week.
    private var dayHeaders: [(short: String, dayNumber: String)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"  // single-letter day (M, T, W…)
        let calendar = Calendar.current
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let day = calendar.component(.day, from: date)
            return (short: formatter.string(from: date), dayNumber: "\(day)")
        }
    }

    // MARK: - Crew row UI

    @ViewBuilder
    private func crewLineRow(index: Int, line: PayrollLine) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Header row: name + rate + mode toggle + remove button
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.employeeName)
                        .fontWeight(.medium)
                    Text("\(line.hourlyRate.currencyFormatted)/hr")
                        .font(.caption)
                        .foregroundColor(AppTheme.primaryOrange)
                }
                Spacer()
                // Toggle between total-hours and per-day entry
                Picker("", selection: $crewLines[index].useDailyBreakdown) {
                    Text("Total").tag(false)
                    Text("By Day").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
                Button { crewLines.remove(at: index) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red.opacity(0.6))
                }
                .buttonStyle(.plain)
            }

            // Hours entry (switches based on mode)
            if line.useDailyBreakdown {
                // Per-day grid: 7 small textfields with short day labels
                HStack(spacing: 4) {
                    ForEach(Array(dayHeaders.enumerated()), id: \.offset) { dayIndex, header in
                        VStack(spacing: 2) {
                            Text(header.short)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(header.dayNumber)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            TextField("0", text: $crewLines[index].dailyHours[dayIndex])
                                #if !os(macOS)
                                .keyboardType(.decimalPad)
                                #endif
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                HStack {
                    Text("Total:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(line.parsedHours.decimalFormatted)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("hrs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                HStack {
                    Text("Hours:")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    TextField("0", text: $crewLines[index].hoursWorked)
                        #if !os(macOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Spacer()
                }
            }

            // Per diem + pay display
            HStack {
                Text("Per Diem:")
                    .font(.callout)
                    .foregroundColor(.secondary)
                TextField("0", text: $crewLines[index].perDiem)
                    #if !os(macOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                Spacer()
                Text("Pay:")
                    .font(.callout)
                    .foregroundColor(.secondary)
                Text(line.pay.currencyFormatted)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
        }
    }

    private func save() {
        let weekNum = Calendar.current.component(.weekOfYear, from: weekStart)
        let year = Calendar.current.component(.yearForWeekOfYear, from: weekStart)
        let projectName = project?.title ?? ""

        let details = crewLines.map { line in
            EmployeePayrollDetail(
                employeeName: line.employeeName,
                hourlyRate: line.hourlyRate,
                hoursWorked: line.parsedHours,
                projectName: projectName,
                dailyHours: line.dailyHoursDecimal,
                perDiem: line.parsedPerDiem
            )
        }

        let entry = PayrollEntry(
            weekNumber: weekNum,
            year: year,
            totalHours: totalHours,
            totalAmount: totalAmount,
            notes: notes,
            employeeDetails: details
        )
        dataStore.addPayrollEntry(entry, to: projectID)
        closeForm()
    }
}

// MARK: - Add Cost
struct AddCostView: View {
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var category: Cost.CostCategory = .machinery
    @State private var coDescription = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var useQuantity = false
    @State private var quantity = ""
    @State private var unitPrice = ""

    private var parsedAmount: Decimal {
        if useQuantity {
            let qty = Decimal(string: quantity) ?? 0
            let price = Decimal(string: unitPrice.replacingOccurrences(of: ",", with: "")) ?? 0
            return qty * price
        }
        return Decimal(string: amount.replacingOccurrences(of: ",", with: "")) ?? 0
    }

    private var project: Project? {
        dataStore.projects.first { $0.id == projectID }
    }

    var body: some View {
        EntryFormScaffold(
            title: "Add Cost",
            icon: "dollarsign.circle",
            saveDisabled: coDescription.isEmpty,
            onCancel: closeForm,
            onSave: save
        ) {
            // Category
            EntrySection("Category", systemImage: "tag") {
                LabeledField(label: "Category") {
                    Picker("", selection: $category) {
                        ForEach(Cost.CostCategoryGroup.allCases, id: \.self) { group in
                            Section(group.rawValue) {
                                ForEach(group.categories, id: \.self) { cat in
                                    Label(cat.displayName, systemImage: categoryIcon(cat))
                                        .tag(cat)
                                }
                            }
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: categoryIcon(category))
                        .foregroundColor(categoryColor(category))
                        .frame(width: 24)
                    Text(category.categoryGroup.rawValue)
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    StatusBadge(text: category.displayName, color: categoryColor(category))
                }
            }

            // Details
            EntrySection("Details", systemImage: "text.alignleft") {
                LabeledField(label: "Description") {
                    NotesField(text: $coDescription, minHeight: 50)
                }
                LabeledField(label: "Date") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
            }

            // Amount
            EntrySection("Amount", systemImage: "dollarsign.circle") {
                Picker("Entry Mode", selection: $useQuantity) {
                    Text("Direct Amount").tag(false)
                    Text("Qty x Unit Price").tag(true)
                }
                .pickerStyle(.segmented)

                if useQuantity {
                    HStack(alignment: .bottom, spacing: AppTheme.Spacing.md) {
                        LabeledField(label: "Qty") {
                            TextField("0", text: $quantity)
                                #if !os(macOS)
                                .keyboardType(.numberPad)
                                #endif
                                .textFieldStyle(.appField)
                        }
                        Text("x")
                            .foregroundColor(AppTheme.secondaryText)
                            .fontWeight(.semibold)
                            .padding(.bottom, 10)
                        LabeledField(label: "Unit Price") {
                            CurrencyInput(placeholder: "0.00", text: $unitPrice)
                        }
                    }

                    if parsedAmount > 0 {
                        HStack {
                            Text("Total:")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(parsedAmount.currencyFormatted)
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(AppTheme.primaryOrange)
                        }
                    }
                } else {
                    LabeledField(label: "Amount") {
                        CurrencyInput(placeholder: "0.00", text: $amount)
                    }
                }
            }

            // Running Context
            if let project = project, parsedAmount > 0 {
                EntrySection("Impact Preview", systemImage: "chart.line.downtrend.xyaxis") {
                    let currentCosts = project.totalCosts
                    let afterCosts = currentCosts + parsedAmount
                    let afterProfit = project.totalRevenue - afterCosts

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Current Costs").font(.caption).foregroundColor(AppTheme.secondaryText)
                            Text(currentCosts.currencyFormatted).fontWeight(.semibold)
                        }
                        Spacer()
                        Image(systemName: "arrow.right").foregroundColor(AppTheme.secondaryText)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("After This Cost").font(.caption).foregroundColor(AppTheme.secondaryText)
                            Text(afterCosts.currencyFormatted).fontWeight(.semibold).foregroundColor(.red)
                        }
                    }
                    HStack {
                        Text("Profit Impact:").font(.caption).foregroundColor(AppTheme.secondaryText)
                        Spacer()
                        Text(afterProfit.currencyFormatted)
                            .fontWeight(.semibold)
                            .foregroundColor(afterProfit >= 0 ? .green : .red)
                    }
                }
            }
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func save() {
        let cost = Cost(category: category, description: coDescription, amount: parsedAmount, date: date)
        dataStore.addCost(cost, to: projectID)
        closeForm()
    }

    private func categoryIcon(_ cat: Cost.CostCategory) -> String { costCategoryIcon(cat) }
    private func categoryColor(_ cat: Cost.CostCategory) -> Color { costCategoryColor(cat) }
}

// MARK: - Cost category helpers (shared by AddCostView + EditCostView)

fileprivate func costCategoryIcon(_ cat: Cost.CostCategory) -> String {
    switch cat {
    case .machinery: return "gearshape.2.fill"
    case .hotel: return "bed.double.fill"
    case .gas: return "fuelpump.fill"
    case .diesel: return "fuelpump.fill"
    case .insurance: return "shield.checkered"
    case .materialsAndTools: return "wrench.and.screwdriver.fill"
    case .subcontractor: return "person.2.fill"
    case .permits: return "doc.text.fill"
    case .other: return "ellipsis.circle.fill"
    }
}

fileprivate func costCategoryColor(_ cat: Cost.CostCategory) -> Color {
    switch cat.categoryGroup {
    case .machinery: return .blue
    case .overhead: return .orange
    case .other: return .purple
    }
}

// MARK: - Edit Cost

struct EditCostView: View {
    let cost: Cost
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var category: Cost.CostCategory
    @State private var coDescription: String
    @State private var amount: String
    @State private var date: Date

    init(cost: Cost, projectID: CKRecord.ID) {
        self.cost = cost
        self.projectID = projectID
        _category = State(initialValue: cost.category)
        _coDescription = State(initialValue: cost.description)
        _amount = State(initialValue: NSDecimalNumber(decimal: cost.amount).stringValue)
        _date = State(initialValue: cost.date)
    }

    private var parsedAmount: Decimal {
        Decimal(string: amount.replacingOccurrences(of: ",", with: "")) ?? cost.amount
    }

    var body: some View {
        EntryFormScaffold(
            title: "Edit Cost",
            icon: "dollarsign.circle",
            saveDisabled: coDescription.isEmpty || parsedAmount <= 0,
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Category", systemImage: "tag") {
                LabeledField(label: "Category") {
                    Picker("", selection: $category) {
                        ForEach(Cost.CostCategoryGroup.allCases, id: \.self) { group in
                            Section(group.rawValue) {
                                ForEach(group.categories, id: \.self) { cat in
                                    Label(cat.displayName, systemImage: costCategoryIcon(cat))
                                        .tag(cat)
                                }
                            }
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: costCategoryIcon(category))
                        .foregroundColor(costCategoryColor(category))
                        .frame(width: 24)
                    Text(category.categoryGroup.rawValue)
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    StatusBadge(text: category.displayName, color: costCategoryColor(category))
                }
            }

            EntrySection("Details", systemImage: "text.alignleft") {
                LabeledField(label: "Description") {
                    NotesField(text: $coDescription, minHeight: 60)
                }
                LabeledField(label: "Date") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
            }

            EntrySection("Amount", systemImage: "dollarsign.circle") {
                LabeledField(label: "Amount") {
                    CurrencyInput(placeholder: "0.00", text: $amount)
                }
            }
        }
        #if os(macOS)
        .frame(width: 560, height: 560)
        #endif
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func save() {
        var updated = cost
        updated.category = category
        updated.description = coDescription
        updated.amount = parsedAmount
        updated.date = date
        dataStore.updateCost(updated, in: projectID)
        closeForm()
    }
}

// MARK: - Add Equipment Rental
struct AddEquipmentRentalView: View {
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var selectedRateIndex = 0
    @State private var startDate = Date()
    @State private var includeDelivery = true
    @State private var includePickup = true
    @State private var notes = ""

    private var catalog: [EquipmentRate] { EquipmentRate.edtxCatalog }
    private var selectedRate: EquipmentRate { catalog[selectedRateIndex] }

    private var deliveryTotal: Decimal {
        (includeDelivery ? EquipmentRate.edtxDeliveryCharge : 0) +
        (includePickup ? EquipmentRate.edtxDeliveryCharge : 0)
    }

    var body: some View {
        EntryFormScaffold(
            title: "Add Equipment Rental",
            icon: "crane.fill",
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Equipment Selection", systemImage: AppIcons.equipment) {
                LabeledField(label: "Equipment") {
                    Picker("", selection: $selectedRateIndex) {
                        ForEach(Array(catalog.enumerated()), id: \.offset) { index, rate in
                            Text(rate.name).tag(index)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }
                HStack(spacing: AppTheme.Spacing.lg) {
                    rateDisplay("Daily", selectedRate.dailyRate)
                    Divider().frame(height: 36)
                    rateDisplay("Weekly", selectedRate.weeklyRate)
                    Divider().frame(height: 36)
                    rateDisplay("4-Week", selectedRate.fourWeekRate)
                    Spacer()
                }
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.secondaryBackground)
                )
            }

            EntrySection("Rental Details", systemImage: AppIcons.calendar) {
                LabeledField(label: "Start Date") {
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
            }

            EntrySection("Transport", systemImage: "truck.box.fill") {
                Toggle(isOn: $includeDelivery) {
                    HStack {
                        Text("Delivery")
                        Spacer()
                        if includeDelivery {
                            Text(EquipmentRate.edtxDeliveryCharge.currencyFormatted)
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }
                }
                .tint(AppTheme.primaryOrange)
                Toggle(isOn: $includePickup) {
                    HStack {
                        Text("Return Pickup")
                        Spacer()
                        if includePickup {
                            Text(EquipmentRate.edtxDeliveryCharge.currencyFormatted)
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }
                }
                .tint(AppTheme.primaryOrange)
            }

            EntrySection("Notes", systemImage: "note.text") {
                TextField("PO number, unit ID, notes...", text: $notes)
                    .textFieldStyle(.appField)
            }

            EntrySection("Vendor", systemImage: "building.2") {
                InfoRow(label: "Vendor", value: selectedRate.vendor)
            }
        } footer: {
            HStack {
                Text("Transport Total")
                    .fontWeight(.medium).foregroundColor(AppTheme.primaryText)
                Spacer()
                Text(deliveryTotal.currencyFormatted)
                    .font(.title3).fontWeight(.bold).foregroundColor(AppTheme.primaryOrange)
            }
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func rateDisplay(_ label: String, _ rate: Decimal) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(rate.currencyFormatted)
                .font(.callout)
                .fontWeight(.bold)
                .foregroundColor(AppTheme.primaryOrange)
        }
    }

    private func save() {
        let rental = EquipmentRental(
            equipmentRateID: selectedRate.id,
            equipmentName: selectedRate.name,
            dailyRate: selectedRate.dailyRate,
            weeklyRate: selectedRate.weeklyRate,
            fourWeekRate: selectedRate.fourWeekRate,
            startDate: startDate,
            includeDelivery: includeDelivery,
            includePickup: includePickup,
            notes: notes
        )
        dataStore.addRental(rental, to: projectID)
        closeForm()
    }
}

// MARK: - Close Equipment Rental
struct CloseEquipmentRentalView: View {
    let projectID: CKRecord.ID
    let rental: EquipmentRental
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var endDate = Date()
    @State private var fuelGallons = ""
    @State private var fuelPrice = "9.95"

    private var project: Project? {
        dataStore.projects.first { $0.id == projectID }
    }

    private var rentalDays: Int {
        let days = Calendar.current.dateComponents([.day], from: rental.startDate.startOfDay, to: endDate.startOfDay).day ?? 0
        return max(days + 1, 1)
    }

    private var parsedFuelGal: Decimal { Decimal(string: fuelGallons) ?? 0 }
    private var parsedFuelPrice: Decimal { Decimal(string: fuelPrice) ?? 0 }

    private var detail: RentalCostDetail {
        rental.detailedCost(forDays: rentalDays, fuelGal: parsedFuelGal, fuelPrice: parsedFuelPrice)
    }

    var body: some View {
        EntryFormScaffold(
            title: "Close Rental",
            icon: "checkmark.circle.fill",
            saveTitle: "Close Rental",
            onCancel: closeForm,
            onSave: save
        ) {
            // Rental Info
            EntrySection("Rental Summary", systemImage: "info.circle") {
                InfoRow(label: "Equipment", value: rental.equipmentName, icon: "crane.fill")
                Divider()
                InfoRow(label: "Start Date", value: rental.startDate.shortDate, icon: "calendar")
                if !rental.unitInfo.isEmpty {
                    Divider()
                    InfoRow(label: "Unit", value: rental.unitInfo, icon: "number")
                }
                Divider()
                HStack(spacing: AppTheme.Spacing.lg) {
                    rateInfo("Daily", rental.dailyRate)
                    Divider().frame(height: 30)
                    rateInfo("Weekly", rental.weeklyRate)
                    Divider().frame(height: 30)
                    rateInfo("4-Week", rental.fourWeekRate)
                }
                .padding(.vertical, 2)
            }

            // Close Date
            EntrySection("Close Date", systemImage: "calendar.badge.checkmark") {
                LabeledField(label: "End Date") {
                    DatePicker("", selection: $endDate,
                               in: rental.startDate...,
                               displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
                HStack {
                    Text("Duration").foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    Text("\(rentalDays) day\(rentalDays == 1 ? "" : "s")")
                        .fontWeight(.semibold)
                }
            }

            // Fuel On Return
            EntrySection("Fuel On Return", systemImage: "fuelpump.fill") {
                HStack {
                    Text("Gallons")
                    TextField("0", text: $fuelGallons)
                        #if !os(macOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("x").foregroundColor(AppTheme.secondaryText)
                    Text("$").foregroundColor(AppTheme.secondaryText)
                    TextField("9.95", text: $fuelPrice)
                        #if !os(macOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                    Text("/gal").foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    if parsedFuelGal > 0 {
                        Text("= \(detail.fuelCharge.currencyFormatted)")
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.primaryOrange)
                    }
                }
            }

            // Invoice Breakdown
            EntrySection("Invoice Breakdown", systemImage: "doc.text") {
                Text(detail.breakdown)
                    .font(.caption)
                    .foregroundColor(AppTheme.primaryOrange)
                    .fontWeight(.medium)

                Divider()

                invoiceLine("Equipment Rental", detail.equipmentCost)
                invoiceLine("Environmental Fee (2.4%)", detail.environmentalFee)
                invoiceLine("Dealer Inventory Tax (0.23%)", detail.dealerInventoryTax)
                if detail.deliveryCharges > 0 {
                    invoiceLine("Delivery + Pickup", detail.deliveryCharges)
                }
                if detail.fuelCharge > 0 {
                    invoiceLine("Fuel On Return (\(fuelGallons) gal)", detail.fuelCharge)
                }

                Divider()

                HStack {
                    Text("Subtotal").font(.subheadline).foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    Text(detail.preTaxSubtotal.currencyFormatted)
                        .font(.subheadline)
                        .foregroundColor(AppTheme.secondaryText)
                }
                invoiceLine("Sales Tax (8.25%)", detail.salesTax)
            }

            // Impact Preview
            if let project = project {
                EntrySection("Impact Preview", systemImage: "chart.line.downtrend.xyaxis") {
                    let currentCosts = project.totalCosts
                    let afterCosts = currentCosts + detail.subtotal
                    let afterProfit = project.totalRevenue - afterCosts

                    HStack {
                        VStack(alignment: .leading) {
                            Text("Current Costs").font(.caption).foregroundColor(AppTheme.secondaryText)
                            Text(currentCosts.currencyFormatted).fontWeight(.semibold)
                        }
                        Spacer()
                        Image(systemName: "arrow.right").foregroundColor(AppTheme.secondaryText)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("After Close").font(.caption).foregroundColor(AppTheme.secondaryText)
                            Text(afterCosts.currencyFormatted).fontWeight(.semibold).foregroundColor(.red)
                        }
                    }
                    HStack {
                        Text("Profit Impact").font(.caption).foregroundColor(AppTheme.secondaryText)
                        Spacer()
                        Text(afterProfit.currencyFormatted)
                            .fontWeight(.semibold)
                            .foregroundColor(afterProfit >= 0 ? .green : .red)
                    }
                }
            }
        } footer: {
            HStack {
                Text("Total").font(.headline).foregroundColor(AppTheme.primaryText)
                Spacer()
                Text(detail.subtotal.currencyFormatted)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.primaryOrange)
            }
        }
        #if os(macOS)
        .frame(width: 580, height: 700)
        #endif
    }

    private func invoiceLine(_ label: String, _ amount: Decimal) -> some View {
        HStack {
            Text(label).font(.callout).foregroundColor(AppTheme.secondaryText)
            Spacer()
            Text(amount.currencyFormatted).font(.callout).fontWeight(.medium)
        }
    }

    private func rateInfo(_ label: String, _ rate: Decimal) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.caption2).foregroundColor(AppTheme.secondaryText)
            Text(rate.currencyFormatted).font(.caption).fontWeight(.semibold)
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func save() {
        dataStore.closeRental(rental, endDate: endDate,
                              fuelGallons: parsedFuelGal,
                              fuelPricePerGallon: parsedFuelPrice,
                              in: projectID)
        closeForm()
    }
}

// MARK: - Quick Entry (Lump Sum Backfill)

struct QuickEntrySheet: View {
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    enum EntryCategory: String, CaseIterable {
        case payment = "Payment"
        case changeOrder = "Change Order"
        case payroll = "Payroll"
        case equipment = "Equipment"
        case cost = "Misc. Cost"

        var icon: String {
            switch self {
            case .payment: return "dollarsign.circle.fill"
            case .changeOrder: return "doc.badge.plus"
            case .payroll: return "person.2.fill"
            case .equipment: return "shippingbox.fill"
            case .cost: return "cart.fill"
            }
        }

        var color: Color {
            switch self {
            case .payment: return .green
            case .changeOrder: return .blue
            case .payroll: return .purple
            case .equipment: return .orange
            case .cost: return .red
            }
        }
    }

    @State private var category: EntryCategory = .payment
    @State private var amount = ""
    @State private var description = ""
    @State private var date = Date()

    // Category-specific optional fields
    @State private var costSubcategory: Cost.CostCategory = .other
    @State private var coBilledTo: COBilledTo = .gc
    @State private var attachments: [Attachment] = []
    @State private var showFileImporter = false

    private var parsedAmount: Decimal {
        Decimal(string: amount) ?? 0
    }

    var body: some View {
        EntryFormScaffold(
            title: "Quick Entry",
            icon: "bolt.fill",
            saveDisabled: parsedAmount == 0,
            onCancel: closeForm,
            onSave: save
        ) {
            // Header warning
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                Text("Quick Entry — Lump Sum")
                    .font(.caption)
                    .fontWeight(.bold)
                Spacer()
                Text("For backfill only. Use detailed forms when possible.")
                    .font(.caption2)
                    .foregroundColor(AppTheme.secondaryText)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.yellow.opacity(0.08))
            )

            // Category picker
            EntrySection("Category", systemImage: "square.grid.2x2") {
                Picker("Type", selection: $category) {
                    ForEach(EntryCategory.allCases, id: \.self) { cat in
                        Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            // Amount + date
            EntrySection("Amount", systemImage: "dollarsign.circle") {
                LabeledField(label: "Amount") {
                    CurrencyInput(placeholder: "0.00", text: $amount)
                }
                LabeledField(label: "Date") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
            }

            // Description
            EntrySection("Description", systemImage: "text.alignleft") {
                TextField(descriptionPlaceholder, text: $description)
                    .textFieldStyle(.appField)
            }

            // Attachments (PDFs, images, etc.) — attached to the created record
            EntrySection("Attachments", systemImage: AppIcons.attachment) {
                if attachments.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.title2).foregroundColor(AppTheme.secondaryText)
                        Text("Drag a PDF or image here")
                            .font(.callout).foregroundColor(AppTheme.secondaryText)
                        Button { showFileImporter = true } label: {
                            Label("Or choose a file…", systemImage: "paperclip")
                        }
                        .buttonStyle(.appSecondary).controlSize(.small)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.06)))
                    .fileDrop(folderID: "quickentry-\(project.id.recordName)") { attachment in
                        attachments.append(attachment)
                    }
                } else {
                    ForEach(attachments, id: \.id) { att in
                        HStack {
                            Image(systemName: "doc.fill").foregroundColor(.green)
                            Text(att.filename).font(.callout)
                            Spacer()
                            Button(role: .destructive) {
                                attachments.removeAll { $0.id == att.id }
                            } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                        }
                    }
                    Button { showFileImporter = true } label: {
                        Label("Add Another", systemImage: "plus").foregroundColor(AppTheme.primaryOrange)
                    }
                    .buttonStyle(.plain)
                }
                if category == .payroll && !attachments.isEmpty {
                    Text("Note: payroll entries don't store attachments — these will be ignored. Use Payment, Change Order, or Cost.")
                        .font(.caption2).foregroundColor(.orange)
                }
            }

            // Category-specific fields
            switch category {
            case .cost:
                EntrySection("Cost Category", systemImage: "tag") {
                    Picker("", selection: $costSubcategory) {
                        ForEach(Cost.CostCategory.allCases, id: \.self) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }
            case .changeOrder:
                EntrySection("Billed To", systemImage: "person.text.rectangle") {
                    Picker("", selection: $coBilledTo) {
                        ForEach(COBilledTo.allCases, id: \.self) { bt in
                            Text(bt.displayName).tag(bt)
                        }
                    }
                    .labelsHidden().pickerStyle(.segmented)
                }
            default:
                EmptyView()
            }

            // Summary
            if parsedAmount > 0 {
                EntrySection("Summary", systemImage: "checklist") {
                    HStack {
                        Image(systemName: category.icon)
                            .foregroundColor(category.color)
                        Text(category.rawValue)
                            .fontWeight(.medium)
                        Spacer()
                        Text(parsedAmount.currencyFormatted)
                            .font(.headline)
                            .foregroundColor(category.color)
                    }
                    InfoRow(label: "Project", value: project.title)
                    InfoRow(label: "Date", value: date.shortDate)
                    if !description.isEmpty {
                        InfoRow(label: "Note", value: description)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .image, .data],
            allowsMultipleSelection: true
        ) { result in
            handleFilePick(result)
        }
    }

    private func handleFilePick(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let folderID = "quickentry-\(project.id.recordName)"
        for url in urls {
            if case .success(let att) = FileStorageService.importFile(from: url, bidID: folderID) {
                attachments.append(att)
            }
        }
    }

    private var descriptionPlaceholder: String {
        switch category {
        case .payment: return "e.g., Check #1234"
        case .changeOrder: return "e.g., Added steel for mezzanine"
        case .payroll: return "e.g., Week of 3/10 labor"
        case .equipment: return "e.g., Crane rental March"
        case .cost: return "e.g., Hotel stays for crew"
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func save() {
        let note = description.isEmpty ? "Quick entry (lump sum)" : "\(description) [Quick entry]"

        switch category {
        case .payment:
            var payment = Payment(amount: parsedAmount, date: date, notes: note)
            payment.attachments = attachments
            dataStore.addPayment(payment, to: project.id)

        case .changeOrder:
            let nextNum = (dataStore.changeOrders(for: project.id).count) + 1
            var co = ChangeOrder(
                number: nextNum,
                description: description.isEmpty ? "Quick entry CO" : description,
                amount: parsedAmount,
                submittedDate: date,
                signedDate: date,
                billedTo: coBilledTo
            )
            co.attachments = attachments
            dataStore.addChangeOrder(co, to: project.id)

        case .payroll:
            let cal = Calendar.current
            let weekNum = cal.component(.weekOfYear, from: date)
            let year = cal.component(.yearForWeekOfYear, from: date)
            let entry = PayrollEntry(
                weekNumber: weekNum,
                year: year,
                totalHours: 0,
                totalAmount: parsedAmount,
                notes: note
            )
            dataStore.addPayrollEntry(entry, to: project.id)   // PayrollEntry has no attachments

        case .equipment:
            var cost = Cost(category: .machinery, description: note, amount: parsedAmount, date: date)
            cost.attachments = attachments
            dataStore.addCost(cost, to: project.id)

        case .cost:
            var cost = Cost(category: costSubcategory, description: note, amount: parsedAmount, date: date)
            cost.attachments = attachments
            dataStore.addCost(cost, to: project.id)
        }

        closeForm()
    }
}

// MARK: - Add RFI

struct AddRFISheet: View {
    let projectID: CKRecord.ID
    let nextNumber: Int
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var subject = ""
    @State private var submittedTo = ""
    @State private var submittedDate = Date()
    @State private var responseDueDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var priority: RFIPriority = .medium
    @State private var notes = ""
    @State private var showFileImporter = false
    @State private var uploadedAttachments: [Attachment] = []

    var body: some View {
        EntryFormScaffold(
            title: "New RFI",
            badge: "RFI #\(nextNumber)",
            saveTitle: "Create",
            saveDisabled: subject.isEmpty,
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Request", systemImage: "questionmark.circle") {
                LabeledField(label: "Subject") {
                    TextField("e.g. Beam connection at grid B-4", text: $subject)
                        .textFieldStyle(.appField)
                }
                LabeledField(label: "Submitted To") {
                    TextField("e.g. Architect", text: $submittedTo)
                        .textFieldStyle(.appField)
                }
                LabeledField(label: "Priority") {
                    Picker("", selection: $priority) {
                        ForEach(RFIPriority.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }
            }

            EntrySection("Dates", systemImage: AppIcons.calendar) {
                LabeledField(label: "Submitted") {
                    DatePicker("", selection: $submittedDate, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
                LabeledField(label: "Response Due") {
                    DatePicker("", selection: $responseDueDate, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
            }

            EntrySection("RFI Document", systemImage: "doc.text") {
                if uploadedAttachments.isEmpty {
                    Button { showFileImporter = true } label: {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                                .font(.title2)
                                .foregroundColor(AppTheme.primaryOrange)
                            VStack(alignment: .leading) {
                                Text("Upload RFI Sheet")
                                    .fontWeight(.medium)
                                Text("PDF, image, or drawing file")
                                    .font(.caption)
                                    .foregroundColor(AppTheme.secondaryText)
                            }
                            Spacer()
                        }
                        .padding(AppTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(AppTheme.secondaryBackground)
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    ForEach(uploadedAttachments) { att in
                        HStack {
                            Image(systemName: FileStorageService.iconName(for: att.filename))
                                .foregroundColor(AppTheme.primaryOrange)
                            VStack(alignment: .leading) {
                                Text(att.filename).font(.callout).lineLimit(1)
                                Text(att.fileSizeFormatted).font(.caption2).foregroundColor(AppTheme.secondaryText)
                            }
                            Spacer()
                            Button { uploadedAttachments.removeAll { $0.id == att.id } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button { showFileImporter = true } label: {
                        Label("Add More Files", systemImage: "plus").font(.caption)
                    }
                    .buttonStyle(.appSecondary)
                    .controlSize(.small)
                }
            }

            EntrySection("Notes (optional)", systemImage: "note.text") {
                TextField("Internal notes", text: $notes)
                    .textFieldStyle(.appField)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .png, .jpeg, .tiff, .data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let rfiFolder = "RFI_\(projectID.recordName)"
                    if case .success(let att) = FileStorageService.importFile(from: url, bidID: rfiFolder) {
                        uploadedAttachments.append(att)
                    }
                }
            }
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func save() {
        let rfi = RFI(
            number: nextNumber,
            subject: subject,
            submittedTo: submittedTo,
            submittedDate: submittedDate,
            responseDueDate: responseDueDate,
            status: submittedTo.isEmpty ? .draft : .submitted,
            priority: priority,
            notes: notes,
            attachments: uploadedAttachments
        )
        dataStore.addRFI(rfi, to: projectID)
        closeForm()
    }
}

// MARK: - Edit RFI

struct EditRFISheet: View {
    @State var rfi: RFI
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss
    @State private var showFileImporter = false

    var body: some View {
        EntryFormScaffold(
            title: "Edit RFI",
            badge: "RFI #\(rfi.number)",
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Request", systemImage: "questionmark.circle") {
                LabeledField(label: "Subject") {
                    TextField("Subject", text: $rfi.subject)
                        .textFieldStyle(.appField)
                }
                LabeledField(label: "Submitted To") {
                    TextField("Submitted To", text: $rfi.submittedTo)
                        .textFieldStyle(.appField)
                }
                LabeledField(label: "Status") {
                    Picker("", selection: $rfi.status) {
                        ForEach(RFIStatus.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }
                LabeledField(label: "Priority") {
                    Picker("", selection: $rfi.priority) {
                        ForEach(RFIPriority.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }
            }

            EntrySection("Dates", systemImage: AppIcons.calendar) {
                LabeledField(label: "Submitted") {
                    DatePicker("", selection: $rfi.submittedDate, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
                LabeledField(label: "Response Due") {
                    DatePicker("", selection: $rfi.responseDueDate, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
                if rfi.status == .responded || rfi.status == .closed {
                    LabeledField(label: "Response Received") {
                        DatePicker("", selection: Binding(
                            get: { rfi.responseReceivedDate ?? Date() },
                            set: { rfi.responseReceivedDate = $0 }
                        ), displayedComponents: .date)
                            .labelsHidden().appControlSurface()
                    }
                }
            }

            EntrySection("Documents (\(rfi.attachments.count) file\(rfi.attachments.count == 1 ? "" : "s"))", systemImage: "doc.text") {
                ForEach(rfi.attachments) { att in
                    HStack {
                        Image(systemName: FileStorageService.iconName(for: att.filename))
                            .foregroundColor(AppTheme.primaryOrange)
                        Text(att.filename).font(.callout).lineLimit(1)
                        Spacer()
                        Text(att.fileSizeFormatted).font(.caption2).foregroundColor(AppTheme.secondaryText)
                        Button { rfi.attachments.removeAll { $0.id == att.id } } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button { showFileImporter = true } label: {
                    Label("Upload Document", systemImage: "doc.badge.plus").font(.callout)
                }
                .buttonStyle(.appSecondary)
                .controlSize(.small)
            }

            EntrySection("Notes", systemImage: "note.text") {
                TextField("Internal notes", text: $rfi.notes)
                    .textFieldStyle(.appField)
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .png, .jpeg, .tiff, .data], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    let rfiFolder = "RFI_\(projectID.recordName)"
                    if case .success(let att) = FileStorageService.importFile(from: url, bidID: rfiFolder) {
                        rfi.attachments.append(att)
                    }
                }
            }
        }
        #if os(macOS)
        .frame(width: 540, height: 600)
        #endif
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func save() {
        dataStore.updateRFI(rfi, in: projectID)
        closeForm()
    }
}
