import SwiftUI
import CloudKit

// MARK: - Add Change Order / Work Order Invoice
struct AddChangeOrderView: View {
    let projectID: CKRecord.ID
    let nextNumber: Int
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    // Invoice details
    @State private var invoiceNumber = ""
    @State private var invoiceDate = Date()
    @State private var workOrderNumber = ""
    @State private var poNumber = ""
    @State private var coDescription = ""
    @State private var scope = ""

    // Line items
    @State private var laborLines: [LaborLineItem] = LaborLineItem.defaultSet()
    @State private var additionalLines: [AdditionalChargeItem] = []

    // Totals & terms
    @State private var taxRateString = ""
    @State private var paymentTerms = "Net 30 Days"
    @State private var additionalNotes = ""

    // Approval
    @State private var isSigned = false
    @State private var signedDate = Date()

    private var project: Project? {
        dataStore.projects.first { $0.id == projectID }
    }

    private var client: Client? {
        guard let p = project else { return nil }
        return dataStore.client(for: p.clientRef)
    }

    private var laborSubtotal: Decimal { laborLines.reduce(0) { $0 + $1.lineTotal } }
    private var additionalSubtotal: Decimal { additionalLines.reduce(0) { $0 + $1.lineTotal } }
    private var subtotal: Decimal { laborSubtotal + additionalSubtotal }
    private var taxRate: Decimal { Decimal(string: taxRateString) ?? 0 }
    private var taxAmount: Decimal {
        var result = Decimal(); var val = subtotal * taxRate / 100
        NSDecimalRound(&result, &val, 2, .plain); return result
    }
    private var totalDue: Decimal { subtotal + taxAmount }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text("CO #\(nextNumber)")
                        .font(.caption).fontWeight(.bold)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(AppTheme.primaryOrange)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text("Work Order Invoice")
                        .font(AppTheme.Typography.title3)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.appPrimary)
            }
            .padding()
            Divider()

            Form {
                    // Invoice Details
                    Section {
                        HStack {
                            TextField("Invoice #", text: $invoiceNumber)
                            DatePicker("Date", selection: $invoiceDate, displayedComponents: .date)
                        }
                        HStack {
                            TextField("Work Order #", text: $workOrderNumber)
                            TextField("PO Number", text: $poNumber)
                        }
                    } header: {
                        Label("Invoice Details", systemImage: "doc.text")
                    }

                    // Bill To & Project (auto-populated)
                    Section {
                        if let client = client {
                            InfoRow(label: "Bill To", value: client.name, icon: "person")
                            if !client.billingAddress.isEmpty {
                                Text(client.billingAddress)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        } else {
                            Text("No client linked to this project")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        if let project = project {
                            Divider()
                            InfoRow(label: "Project", value: project.title, icon: "building.2")
                            if !project.location.isEmpty {
                                InfoRow(label: "Location", value: project.location, icon: AppIcons.location)
                            }
                        }
                    } header: {
                        Label("Bill To / Project", systemImage: "person.text.rectangle")
                    }

                    // Scope
                    Section {
                        TextField("Brief Description", text: $coDescription)
                        TextEditor(text: $scope)
                            .frame(height: 60)
                            .overlay(
                                Group {
                                    if scope.isEmpty {
                                        Text("Describe work performed...")
                                            .foregroundColor(AppTheme.tertiaryText)
                                            .padding(.leading, 4).padding(.top, 8)
                                            .allowsHitTesting(false)
                                    }
                                }, alignment: .topLeading
                            )
                    } header: {
                        Label("Work Description / Scope Performed", systemImage: "text.alignleft")
                    }

                    // Labor & Equipment Charges
                    Section {
                        // Header row
                        HStack {
                            Text("Description").font(.caption).fontWeight(.bold).frame(width: 140, alignment: .leading)
                            Text("Qty").font(.caption).fontWeight(.bold).frame(width: 50)
                            Text("Hours").font(.caption).fontWeight(.bold).frame(width: 55)
                            Text("Rate").font(.caption).fontWeight(.bold).frame(width: 70)
                            Text("Total").font(.caption).fontWeight(.bold).frame(width: 80, alignment: .trailing)
                        }
                        .padding(.vertical, 2)

                        ForEach(Array(laborLines.enumerated()), id: \.element.id) { index, line in
                            HStack {
                                Text(line.category.displayName)
                                    .font(.callout)
                                    .frame(width: 140, alignment: .leading)
                                TextField("0", value: $laborLines[index].quantity, format: .number)
                                    #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                                    .textFieldStyle(.roundedBorder).frame(width: 50)
                                TextField("0", value: $laborLines[index].hours, format: .number)
                                    #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                                    .textFieldStyle(.roundedBorder).frame(width: 55)
                                TextField("0", value: $laborLines[index].rate, format: .number)
                                    #if !os(macOS)
                                    .keyboardType(.decimalPad)
                                    #endif
                                    .textFieldStyle(.roundedBorder).frame(width: 70)
                                Text(line.lineTotal.currencyWithCents)
                                    .font(.callout).fontWeight(.medium)
                                    .frame(width: 80, alignment: .trailing)
                                    .foregroundColor(line.lineTotal > 0 ? AppTheme.primaryOrange : .secondary)
                            }
                        }

                        if laborSubtotal > 0 {
                            HStack {
                                Spacer()
                                Text("Labor Subtotal: \(laborSubtotal.currencyWithCents)")
                                    .font(.callout).fontWeight(.semibold)
                            }
                        }
                    } header: {
                        Label("Labor & Equipment Charges", systemImage: "wrench.and.screwdriver")
                    }

                    // Additional Charges / Materials
                    Section {
                        ForEach(Array(additionalLines.enumerated()), id: \.element.id) { index, line in
                            HStack {
                                TextField("Description", text: $additionalLines[index].description)
                                    .textFieldStyle(.roundedBorder)
                                HStack(spacing: 4) {
                                    Text("$")
                                        .foregroundColor(.secondary)
                                    TextField("0", value: $additionalLines[index].rate, format: .number)
                                        #if !os(macOS)
                                        .keyboardType(.decimalPad)
                                        #endif
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 90)
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
                    } header: {
                        Label("Additional Charges / Materials", systemImage: "shippingbox")
                    }

                    // Totals
                    Section {
                        HStack {
                            Text("Subtotal").fontWeight(.medium)
                            Spacer()
                            Text(subtotal.currencyWithCents).fontWeight(.semibold)
                        }
                        HStack {
                            Text("Tax Rate (%)").foregroundColor(.secondary)
                            TextField("0", text: $taxRateString)
                                #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                                .textFieldStyle(.roundedBorder).frame(width: 60)
                            Spacer()
                            if taxAmount > 0 {
                                Text(taxAmount.currencyWithCents).foregroundColor(.secondary)
                            }
                        }
                        Divider()
                        HStack {
                            Text("TOTAL DUE").font(.headline)
                            Spacer()
                            Text(totalDue.currencyWithCents)
                                .font(.title3).fontWeight(.bold)
                                .foregroundColor(AppTheme.primaryOrange)
                        }
                    } header: {
                        Label("Totals", systemImage: "dollarsign.circle")
                    }

                    // Payment Terms & Notes
                    Section {
                        TextField("Payment Terms", text: $paymentTerms)
                        TextEditor(text: $additionalNotes)
                            .frame(height: 50)
                            .overlay(
                                Group {
                                    if additionalNotes.isEmpty {
                                        Text("Additional notes...")
                                            .foregroundColor(AppTheme.tertiaryText)
                                            .padding(.leading, 4).padding(.top, 8)
                                            .allowsHitTesting(false)
                                    }
                                }, alignment: .topLeading
                            )
                    } header: {
                        Label("Payment Terms & Notes", systemImage: "note.text")
                    }

                    // Approval
                    Section {
                        Toggle("Mark as Signed", isOn: $isSigned)
                        if isSigned {
                            DatePicker("Signed Date", selection: $signedDate, displayedComponents: .date)
                        }
                    } header: {
                        Label("Approval", systemImage: "checkmark.seal")
                    }
                }
                .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 700, height: 800)
        #endif
        .onAppear {
            invoiceNumber = "INV-\(nextNumber)"
        }
    }

    private func save() {
        let co = ChangeOrder(
            number: nextNumber,
            description: coDescription,
            amount: totalDue,
            submittedDate: invoiceDate,
            signedDate: isSigned ? signedDate : nil,
            scope: scope,
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
        dismiss()
    }
}

// MARK: - Edit Change Order (Simple Total Input)
struct EditChangeOrderSheet: View {
    let changeOrder: ChangeOrder
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var numberText: String
    @State private var title: String
    @State private var amount: String
    @State private var scope: String
    @State private var isSigned: Bool
    @State private var signedDate: Date
    @State private var submittedDate: Date
    @State private var billedTo: COBilledTo

    init(changeOrder: ChangeOrder, projectID: CKRecord.ID) {
        self.changeOrder = changeOrder
        self.projectID = projectID
        _numberText = State(initialValue: "\(changeOrder.number)")
        _title = State(initialValue: changeOrder.description)
        _amount = State(initialValue: NSDecimalNumber(decimal: changeOrder.amount).stringValue)
        _scope = State(initialValue: changeOrder.scope)
        _isSigned = State(initialValue: changeOrder.isSigned)
        _signedDate = State(initialValue: changeOrder.signedDate ?? Date())
        _submittedDate = State(initialValue: changeOrder.submittedDate)
        _billedTo = State(initialValue: changeOrder.billedTo)
    }

    /// Other change orders on the same project (for collision check).
    private var siblingNumbers: Set<Int> {
        Set(dataStore.changeOrders(for: projectID)
            .filter { $0.id != changeOrder.id }
            .map(\.number))
    }

    private var parsedNumber: Int? { Int(numberText.trimmingCharacters(in: .whitespaces)) }

    private var numberCollision: Bool {
        guard let n = parsedNumber else { return false }
        return siblingNumbers.contains(n)
    }

    private var isSaveDisabled: Bool {
        parsedNumber == nil || (parsedNumber ?? 0) < 1 || numberCollision
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identification") {
                    HStack {
                        Text("CO Number")
                        Spacer()
                        TextField("e.g. 2", text: $numberText)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            #if !os(macOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                    if numberCollision {
                        Text("Another change order on this project already uses #\(parsedNumber ?? 0).")
                            .font(.caption)
                            .foregroundColor(.red)
                    } else if parsedNumber == nil || (parsedNumber ?? 0) < 1 {
                        Text("Number must be a positive integer.")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    TextField("Title (e.g. Beam relocation, owner request)", text: $title)
                }
                Section("Details") {
                    HStack {
                        Text("$")
                        TextField("Total Amount", text: $amount)
                            #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                    }
                    DatePicker("Date", selection: $submittedDate, displayedComponents: .date)
                    Picker("Billed To", selection: $billedTo) {
                        ForEach(COBilledTo.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }
                Section("Scope / Details") {
                    TextEditor(text: $scope)
                        .frame(height: 80)
                }
                Section("Approval") {
                    Toggle("Signed / Approved", isOn: $isSigned)
                    if isSigned {
                        DatePicker("Signed Date", selection: $signedDate, displayedComponents: .date)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit CO #\(changeOrder.number)")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .buttonStyle(.appPrimary)
                        .disabled(isSaveDisabled)
                }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 480)
        #endif
    }

    private func save() {
        guard let n = parsedNumber, n > 0, !numberCollision else { return }
        var updated = changeOrder
        updated.number = n
        updated.description = title
        updated.amount = Decimal(string: amount) ?? changeOrder.amount
        updated.scope = scope
        updated.submittedDate = submittedDate
        updated.signedDate = isSigned ? signedDate : nil
        updated.billedTo = billedTo
        dataStore.updateChangeOrder(updated, in: projectID)
        dismiss()
    }
}

// MARK: - Add Payment
struct AddPaymentView: View {
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

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
        VStack(spacing: 0) {
            HStack {
                Text("Record Payment")
                    .font(AppTheme.Typography.title3)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                    .buttonStyle(.appPrimary)
            }
            .padding()
            Divider()

            Form {
                // Collection Progress
                if let project = project {
                    Section {
                        let revenue = project.totalRevenue
                        let collected = project.totalPayments
                        let remaining = project.remainingBalance
                        let progress = revenue > 0 ? Double(truncating: (collected / revenue) as NSDecimalNumber) : 0
                        let afterCollected = collected + parsedAmount
                        let afterProgress = revenue > 0 ? Double(truncating: (afterCollected / revenue) as NSDecimalNumber) : 0

                        VStack(spacing: AppTheme.Spacing.sm) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Revenue").font(.caption).foregroundColor(.secondary)
                                    Text(revenue.currencyFormatted).fontWeight(.semibold)
                                }
                                Spacer()
                                VStack(alignment: .center) {
                                    Text("Collected").font(.caption).foregroundColor(.secondary)
                                    Text(collected.currencyFormatted).fontWeight(.semibold).foregroundColor(.green)
                                }
                                Spacer()
                                VStack(alignment: .trailing) {
                                    Text("Remaining").font(.caption).foregroundColor(.secondary)
                                    Text(remaining.currencyFormatted).fontWeight(.semibold).foregroundColor(.orange)
                                }
                            }

                            ProgressBar(value: progress, color: .green)

                            if parsedAmount > 0 {
                                HStack {
                                    Text("After this payment:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(afterCollected.currencyFormatted)
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.green)
                                    Text("(\(Int(afterProgress * 100))%)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                ProgressBar(value: afterProgress, color: .green.opacity(0.6), height: 4)
                            }
                        }
                    } header: {
                        Label("Collection Progress", systemImage: "chart.bar.fill")
                    }
                }

                // Payment Details
                Section {
                    HStack {
                        Text("$")
                            .foregroundColor(.green)
                            .fontWeight(.semibold)
                        TextField("Amount", text: $amount)
                            #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .textFieldStyle(.plain)
                            .font(.title3)
                    }

                    DatePicker("Date Received", selection: $date, displayedComponents: .date)

                    Picker("Method", selection: $paymentMethod) {
                        ForEach(PaymentMethod.allCases) { m in
                            Label(m.rawValue, systemImage: m.icon).tag(m)
                        }
                    }

                    TextField("Reference Number", text: $referenceNumber, prompt: Text("Check #, wire confirmation, ACH ref"))

                    if !outstandingInvoices.isEmpty {
                        Picker("Apply to Invoice", selection: $appliedToInvoiceID) {
                            Text("None (contract payment)").tag(nil as UUID?)
                            Divider()
                            ForEach(outstandingInvoices) { invoice in
                                let remaining = dataStore.balanceRemaining(for: invoice)
                                Text("\(invoice.invoiceNumber) — \(remaining.currencyFormatted) due")
                                    .tag(invoice.id as UUID?)
                            }
                        }
                    }

                    Picker("Apply to Change Order", selection: $appliedToCO) {
                        Text("None").tag(nil as UUID?)
                        if !changeOrders.isEmpty {
                            Divider()
                            ForEach(changeOrders) { co in
                                Text("CO #\(co.number) - \(co.description) (\(co.amount.currencyFormatted))")
                                    .tag(co.id as UUID?)
                            }
                        }
                    }
                } header: {
                    Label("Payment Details", systemImage: "banknote")
                }

                // Proof of Payment (required — image or reason)
                Section {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        if attachments.isEmpty {
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

                            TextField(
                                "",
                                text: $proofReason,
                                prompt: Text("Or explain why no proof is attached (required if no file)"),
                                axis: .vertical
                            )
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
                    Label("Proof of Payment", systemImage: "checkmark.shield")
                } footer: {
                    if !hasProofOrReason {
                        Text("⚠️ Attach a check image/receipt, OR type a reason to save without proof.")
                            .foregroundColor(.orange)
                    }
                }

                // Notes
                Section {
                    TextEditor(text: $notes)
                        .frame(height: 60)
                        .overlay(
                            Group {
                                if notes.isEmpty {
                                    Text("Optional notes...")
                                        .foregroundColor(AppTheme.tertiaryText)
                                        .padding(.leading, 4)
                                        .padding(.top, 8)
                                        .allowsHitTesting(false)
                                }
                            }, alignment: .topLeading
                        )
                } header: {
                    Label("Notes", systemImage: "note.text")
                }
            }
            .formStyle(.grouped)
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.image, .pdf],
                allowsMultipleSelection: false
            ) { result in
                handleFilePick(result)
            }
        }
        #if os(macOS)
        .frame(width: 560, height: 720)
        #endif
    }

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
        dismiss()
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
        VStack(spacing: 0) {
            HStack {
                Text("Add Payroll Entry")
                    .font(AppTheme.Typography.title3)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(crewLines.isEmpty || totalHours == 0)
                    .buttonStyle(.appPrimary)
            }
            .padding()
            Divider()

            Form {
                // Work Week
                Section {
                    DatePicker("Week Starting", selection: $weekStart,
                               displayedComponents: .date)
                    if let project = project {
                        InfoRow(label: "Project", value: project.title, icon: "building.2")
                    }
                } header: {
                    Label("Work Week", systemImage: "calendar")
                }

                // Crew
                Section {
                    if crewLines.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "person.badge.plus")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("Add crew members to this payroll entry")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, AppTheme.Spacing.md)
                            Spacer()
                        }
                    }

                    ForEach(Array(crewLines.enumerated()), id: \.element.id) { index, line in
                        crewLineRow(index: index, line: line)
                            .padding(.vertical, 4)
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
                    }
                } header: {
                    HStack {
                        Label("Crew (\(crewLines.count))", systemImage: "person.2.fill")
                        Spacer()
                    }
                }

                // Running Totals
                if !crewLines.isEmpty {
                    Section {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Total Hours")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(totalHours.decimalFormatted)
                                    .font(.title3)
                                    .fontWeight(.bold)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Total Labor Cost")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(totalAmount.currencyFormatted)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(AppTheme.primaryOrange)
                            }
                        }
                    } header: {
                        Label("Summary", systemImage: "sum")
                    }
                }

                // Notes
                Section {
                    TextField("Notes", text: $notes)
                } header: {
                    Label("Notes", systemImage: "note.text")
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 560, height: 600)
        #endif
    }

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
        dismiss()
    }
}

// MARK: - Add Cost
struct AddCostView: View {
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

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
        VStack(spacing: 0) {
            HStack {
                Text("Add Cost")
                    .font(AppTheme.Typography.title3)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(coDescription.isEmpty)
                    .buttonStyle(.appPrimary)
            }
            .padding()
            Divider()

            Form {
                // Category
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(Cost.CostCategoryGroup.allCases, id: \.self) { group in
                            Section(group.rawValue) {
                                ForEach(group.categories, id: \.self) { cat in
                                    Label(cat.displayName, systemImage: categoryIcon(cat))
                                        .tag(cat)
                                }
                            }
                        }
                    }

                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: categoryIcon(category))
                            .foregroundColor(categoryColor(category))
                            .frame(width: 24)
                        Text(category.categoryGroup.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        StatusBadge(text: category.displayName, color: categoryColor(category))
                    }
                } header: {
                    Label("Category", systemImage: "tag")
                }

                // Details
                Section {
                    TextEditor(text: $coDescription)
                        .frame(height: 50)
                        .overlay(
                            Group {
                                if coDescription.isEmpty {
                                    Text("What was this cost for...")
                                        .foregroundColor(AppTheme.tertiaryText)
                                        .padding(.leading, 4)
                                        .padding(.top, 8)
                                        .allowsHitTesting(false)
                                }
                            }, alignment: .topLeading
                        )
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } header: {
                    Label("Details", systemImage: "text.alignleft")
                }

                // Amount
                Section {
                    Picker("Entry Mode", selection: $useQuantity) {
                        Text("Direct Amount").tag(false)
                        Text("Qty x Unit Price").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if useQuantity {
                        HStack(spacing: AppTheme.Spacing.md) {
                            VStack(alignment: .leading) {
                                Text("Qty").font(.caption).foregroundColor(.secondary)
                                TextField("0", text: $quantity)
                                    #if !os(macOS)
                            .keyboardType(.numberPad)
                            #endif
                                    .textFieldStyle(.roundedBorder)
                            }
                            Text("x")
                                .foregroundColor(.secondary)
                                .fontWeight(.semibold)
                            VStack(alignment: .leading) {
                                Text("Unit Price").font(.caption).foregroundColor(.secondary)
                                HStack {
                                    Text("$").foregroundColor(.secondary)
                                    TextField("0.00", text: $unitPrice)
                                        #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                                        .textFieldStyle(.plain)
                                }
                                .padding(6)
                                .background(AppTheme.secondaryBackground)
                                .cornerRadius(6)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3)))
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
                        HStack {
                            Text("$")
                                .foregroundColor(.secondary)
                                .fontWeight(.semibold)
                            TextField("Amount", text: $amount)
                            #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                                .textFieldStyle(.plain)
                                .font(.title3)
                        }
                    }
                } header: {
                    Label("Amount", systemImage: "dollarsign.circle")
                }

                // Running Context
                if let project = project, parsedAmount > 0 {
                    Section {
                        let currentCosts = project.totalCosts
                        let afterCosts = currentCosts + parsedAmount
                        let afterProfit = project.totalRevenue - afterCosts

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Current Costs").font(.caption).foregroundColor(.secondary)
                                Text(currentCosts.currencyFormatted).fontWeight(.semibold)
                            }
                            Spacer()
                            Image(systemName: "arrow.right").foregroundColor(.secondary)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("After This Cost").font(.caption).foregroundColor(.secondary)
                                Text(afterCosts.currencyFormatted).fontWeight(.semibold).foregroundColor(.red)
                            }
                        }
                        HStack {
                            Text("Profit Impact:").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(afterProfit.currencyFormatted)
                                .fontWeight(.semibold)
                                .foregroundColor(afterProfit >= 0 ? .green : .red)
                        }
                    } header: {
                        Label("Impact Preview", systemImage: "chart.line.downtrend.xyaxis")
                    }
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 520, height: useQuantity ? 650 : 600)
        #endif
    }

    private func save() {
        let cost = Cost(category: category, description: coDescription, amount: parsedAmount, date: date)
        dataStore.addCost(cost, to: projectID)
        dismiss()
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
        VStack(spacing: 0) {
            HStack {
                Text("Edit Cost")
                    .font(AppTheme.Typography.title3)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(coDescription.isEmpty || parsedAmount <= 0)
                    .buttonStyle(.appPrimary)
            }
            .padding()
            Divider()

            Form {
                Section {
                    Picker("Category", selection: $category) {
                        ForEach(Cost.CostCategoryGroup.allCases, id: \.self) { group in
                            Section(group.rawValue) {
                                ForEach(group.categories, id: \.self) { cat in
                                    Label(cat.displayName, systemImage: costCategoryIcon(cat))
                                        .tag(cat)
                                }
                            }
                        }
                    }

                    HStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: costCategoryIcon(category))
                            .foregroundColor(costCategoryColor(category))
                            .frame(width: 24)
                        Text(category.categoryGroup.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        StatusBadge(text: category.displayName, color: costCategoryColor(category))
                    }
                } header: {
                    Label("Category", systemImage: "tag")
                }

                Section {
                    TextEditor(text: $coDescription)
                        .frame(height: 60)
                        .overlay(
                            Group {
                                if coDescription.isEmpty {
                                    Text("What was this cost for...")
                                        .foregroundColor(AppTheme.tertiaryText)
                                        .padding(.leading, 4)
                                        .padding(.top, 8)
                                        .allowsHitTesting(false)
                                }
                            }, alignment: .topLeading
                        )
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                } header: {
                    Label("Details", systemImage: "text.alignleft")
                }

                Section {
                    HStack {
                        Text("$")
                            .foregroundColor(.secondary)
                            .fontWeight(.semibold)
                        TextField("Amount", text: $amount)
                            #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .textFieldStyle(.plain)
                            .font(.title3)
                    }
                } header: {
                    Label("Amount", systemImage: "dollarsign.circle")
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 520, height: 540)
        #endif
    }

    private func save() {
        var updated = cost
        updated.category = category
        updated.description = coDescription
        updated.amount = parsedAmount
        updated.date = date
        dataStore.updateCost(updated, in: projectID)
        dismiss()
    }
}

// MARK: - Add Equipment Rental
struct AddEquipmentRentalView: View {
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

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
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "crane.fill")
                        .foregroundColor(AppTheme.primaryOrange)
                    Text("Add Equipment Rental")
                        .font(AppTheme.Typography.title3)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.appPrimary)
            }
            .padding()
            Divider()

            Form {
                // Equipment Selection
                Section {
                    Picker("Equipment", selection: $selectedRateIndex) {
                        ForEach(Array(catalog.enumerated()), id: \.offset) { index, rate in
                            Text(rate.name).tag(index)
                        }
                    }

                    // Rate card
                    HStack(spacing: AppTheme.Spacing.lg) {
                        rateDisplay("Daily", selectedRate.dailyRate)
                        Divider().frame(height: 36)
                        rateDisplay("Weekly", selectedRate.weeklyRate)
                        Divider().frame(height: 36)
                        rateDisplay("4-Week", selectedRate.fourWeekRate)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Label("Equipment Selection", systemImage: "shippingbox.fill")
                }

                // Rental Details
                Section {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                } header: {
                    Label("Rental Details", systemImage: "calendar")
                }

                // Delivery
                Section {
                    Toggle(isOn: $includeDelivery) {
                        HStack {
                            Text("Delivery")
                            Spacer()
                            if includeDelivery {
                                Text(EquipmentRate.edtxDeliveryCharge.currencyFormatted)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Toggle(isOn: $includePickup) {
                        HStack {
                            Text("Return Pickup")
                            Spacer()
                            if includePickup {
                                Text(EquipmentRate.edtxDeliveryCharge.currencyFormatted)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if deliveryTotal > 0 {
                        HStack {
                            Text("Transport Total")
                                .fontWeight(.medium)
                            Spacer()
                            Text(deliveryTotal.currencyFormatted)
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.primaryOrange)
                        }
                    }
                } header: {
                    Label("Transport", systemImage: "truck.box.fill")
                }

                // Notes
                Section {
                    TextField("PO number, unit ID, notes...", text: $notes)
                } header: {
                    Label("Notes", systemImage: "note.text")
                }

                // Vendor Info
                Section {
                    HStack {
                        Text("Vendor").foregroundColor(.secondary)
                        Spacer()
                        Text(selectedRate.vendor).fontWeight(.medium)
                    }
                } header: {
                    Label("Vendor", systemImage: "building.2")
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
    }

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
        dismiss()
    }
}

// MARK: - Close Equipment Rental
struct CloseEquipmentRentalView: View {
    let projectID: CKRecord.ID
    let rental: EquipmentRental
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

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
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Close Rental")
                        .font(AppTheme.Typography.title3)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Close Rental") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.appPrimary)
            }
            .padding()
            Divider()

            Form {
                // Rental Info
                Section {
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
                } header: {
                    Label("Rental Summary", systemImage: "info.circle")
                }

                // Close Date
                Section {
                    DatePicker("End Date", selection: $endDate,
                               in: rental.startDate...,
                               displayedComponents: .date)
                    HStack {
                        Text("Duration").foregroundColor(.secondary)
                        Spacer()
                        Text("\(rentalDays) day\(rentalDays == 1 ? "" : "s")")
                            .fontWeight(.semibold)
                    }
                } header: {
                    Label("Close Date", systemImage: "calendar.badge.checkmark")
                }

                // Fuel On Return
                Section {
                    HStack {
                        Text("Gallons")
                        TextField("0", text: $fuelGallons)
                            #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Text("x").foregroundColor(.secondary)
                        Text("$").foregroundColor(.secondary)
                        TextField("9.95", text: $fuelPrice)
                            #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Text("/gal").foregroundColor(.secondary)
                        Spacer()
                        if parsedFuelGal > 0 {
                            Text("= \(detail.fuelCharge.currencyFormatted)")
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.primaryOrange)
                        }
                    }
                } header: {
                    Label("Fuel On Return", systemImage: "fuelpump.fill")
                }

                // Invoice Breakdown
                Section {
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
                        Text("Subtotal")
                            .font(.headline)
                        Spacer()
                        Text(detail.subtotal.currencyFormatted)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(AppTheme.primaryOrange)
                    }
                } header: {
                    Label("Invoice Breakdown", systemImage: "doc.text")
                }

                // Impact Preview
                if let project = project {
                    Section {
                        let currentCosts = project.totalCosts
                        let afterCosts = currentCosts + detail.subtotal
                        let afterProfit = project.totalRevenue - afterCosts

                        HStack {
                            VStack(alignment: .leading) {
                                Text("Current Costs").font(.caption).foregroundColor(.secondary)
                                Text(currentCosts.currencyFormatted).fontWeight(.semibold)
                            }
                            Spacer()
                            Image(systemName: "arrow.right").foregroundColor(.secondary)
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("After Close").font(.caption).foregroundColor(.secondary)
                                Text(afterCosts.currencyFormatted).fontWeight(.semibold).foregroundColor(.red)
                            }
                        }
                        HStack {
                            Text("Profit Impact").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(afterProfit.currencyFormatted)
                                .fontWeight(.semibold)
                                .foregroundColor(afterProfit >= 0 ? .green : .red)
                        }
                    } header: {
                        Label("Impact Preview", systemImage: "chart.line.downtrend.xyaxis")
                    }
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 560, height: 720)
        #endif
    }

    private func invoiceLine(_ label: String, _ amount: Decimal) -> some View {
        HStack {
            Text(label).font(.callout).foregroundColor(.secondary)
            Spacer()
            Text(amount.currencyFormatted).font(.callout).fontWeight(.medium)
        }
    }

    private func rateInfo(_ label: String, _ rate: Decimal) -> some View {
        VStack(spacing: 1) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(rate.currencyFormatted).font(.caption).fontWeight(.semibold)
        }
    }

    private func save() {
        dataStore.closeRental(rental, endDate: endDate,
                              fuelGallons: parsedFuelGal,
                              fuelPricePerGallon: parsedFuelPrice,
                              in: projectID)
        dismiss()
    }
}

// MARK: - Quick Entry (Lump Sum Backfill)

struct QuickEntrySheet: View {
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

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

    private var parsedAmount: Decimal {
        Decimal(string: amount) ?? 0
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.yellow.opacity(0.08))

                Form {
                    // Category picker
                    Section("Category") {
                        Picker("Type", selection: $category) {
                            ForEach(EntryCategory.allCases, id: \.self) { cat in
                                Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Amount + date
                    Section("Amount") {
                        HStack {
                            Text("$").font(.title2).foregroundColor(.green).fontWeight(.bold)
                            TextField("0.00", text: $amount)
                                .font(.title2)
                                #if !os(macOS)
                                .keyboardType(.decimalPad)
                                #endif
                        }
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }

                    // Description
                    Section("Description") {
                        TextField(descriptionPlaceholder, text: $description)
                    }

                    // Category-specific fields
                    switch category {
                    case .cost:
                        Section("Cost Category") {
                            Picker("Subcategory", selection: $costSubcategory) {
                                ForEach(Cost.CostCategory.allCases, id: \.self) { cat in
                                    Text(cat.rawValue).tag(cat)
                                }
                            }
                        }
                    case .changeOrder:
                        Section("Billed To") {
                            Picker("Billed To", selection: $coBilledTo) {
                                ForEach(COBilledTo.allCases, id: \.self) { bt in
                                    Text(bt.displayName).tag(bt)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    default:
                        EmptyView()
                    }

                    // Summary
                    if parsedAmount > 0 {
                        Section("Summary") {
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
                .formStyle(.grouped)
            }
            .navigationTitle("Quick Entry")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(parsedAmount == 0)
                        .buttonStyle(.appPrimary)
                }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 520)
        #endif
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

    private func save() {
        let note = description.isEmpty ? "Quick entry (lump sum)" : "\(description) [Quick entry]"

        switch category {
        case .payment:
            let payment = Payment(amount: parsedAmount, date: date, notes: note)
            dataStore.addPayment(payment, to: project.id)

        case .changeOrder:
            let nextNum = (dataStore.changeOrders(for: project.id).count) + 1
            let co = ChangeOrder(
                number: nextNum,
                description: description.isEmpty ? "Quick entry CO" : description,
                amount: parsedAmount,
                submittedDate: date,
                signedDate: date,
                billedTo: coBilledTo
            )
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
            dataStore.addPayrollEntry(entry, to: project.id)

        case .equipment:
            let cost = Cost(category: .machinery, description: note, amount: parsedAmount, date: date)
            dataStore.addCost(cost, to: project.id)

        case .cost:
            let cost = Cost(category: costSubcategory, description: note, amount: parsedAmount, date: date)
            dataStore.addCost(cost, to: project.id)
        }

        dismiss()
    }
}

// MARK: - Add RFI

struct AddRFISheet: View {
    let projectID: CKRecord.ID
    let nextNumber: Int
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var subject = ""
    @State private var submittedTo = ""
    @State private var submittedDate = Date()
    @State private var responseDueDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var priority: RFIPriority = .medium
    @State private var notes = ""
    @State private var showFileImporter = false
    @State private var uploadedAttachments: [Attachment] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("RFI #\(nextNumber)") {
                    TextField("Subject (e.g. Beam connection at grid B-4)", text: $subject)
                    TextField("Submitted To (e.g. Architect)", text: $submittedTo)
                    Picker("Priority", selection: $priority) {
                        ForEach(RFIPriority.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                }
                Section("Dates") {
                    DatePicker("Submitted", selection: $submittedDate, displayedComponents: .date)
                    DatePicker("Response Due", selection: $responseDueDate, displayedComponents: .date)
                }
                Section("RFI Document") {
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
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        ForEach(uploadedAttachments) { att in
                            HStack {
                                Image(systemName: FileStorageService.iconName(for: att.filename))
                                    .foregroundColor(AppTheme.primaryOrange)
                                VStack(alignment: .leading) {
                                    Text(att.filename).font(.callout).lineLimit(1)
                                    Text(att.fileSizeFormatted).font(.caption2).foregroundColor(.secondary)
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
                        .buttonStyle(.borderless)
                    }
                }
                Section("Notes (optional)") {
                    TextField("Internal notes", text: $notes)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New RFI")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }
                        .disabled(subject.isEmpty)
                        .buttonStyle(.appPrimary)
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
        #if os(macOS)
        .frame(width: 500, height: 520)
        #endif
    }

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
        dismiss()
    }
}

// MARK: - Edit RFI

struct EditRFISheet: View {
    @State var rfi: RFI
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var showFileImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("RFI #\(rfi.number)") {
                    TextField("Subject", text: $rfi.subject)
                    TextField("Submitted To", text: $rfi.submittedTo)
                    Picker("Status", selection: $rfi.status) {
                        ForEach(RFIStatus.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    Picker("Priority", selection: $rfi.priority) {
                        ForEach(RFIPriority.allCases, id: \.self) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                }
                Section("Dates") {
                    DatePicker("Submitted", selection: $rfi.submittedDate, displayedComponents: .date)
                    DatePicker("Response Due", selection: $rfi.responseDueDate, displayedComponents: .date)
                    if rfi.status == .responded || rfi.status == .closed {
                        DatePicker("Response Received", selection: Binding(
                            get: { rfi.responseReceivedDate ?? Date() },
                            set: { rfi.responseReceivedDate = $0 }
                        ), displayedComponents: .date)
                    }
                }
                Section("Documents (\(rfi.attachments.count) file\(rfi.attachments.count == 1 ? "" : "s"))") {
                    ForEach(rfi.attachments) { att in
                        HStack {
                            Image(systemName: FileStorageService.iconName(for: att.filename))
                                .foregroundColor(AppTheme.primaryOrange)
                            Text(att.filename).font(.callout).lineLimit(1)
                            Spacer()
                            Text(att.fileSizeFormatted).font(.caption2).foregroundColor(.secondary)
                            Button { rfi.attachments.removeAll { $0.id == att.id } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundColor(.red.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button { showFileImporter = true } label: {
                        Label("Upload Document", systemImage: "doc.badge.plus").font(.callout)
                    }
                    .buttonStyle(.borderless)
                }
                Section("Notes") {
                    TextField("Internal notes", text: $rfi.notes)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit RFI #\(rfi.number)")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        dataStore.updateRFI(rfi, in: projectID)
                        dismiss()
                    }
                    .buttonStyle(.appPrimary)
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
        }
        #if os(macOS)
        .frame(width: 500, height: 550)
        #endif
    }
}
