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
    @State private var description = ""
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
                    .disabled(description.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
            }
            .padding()
            Divider()

            ScrollView {
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
                                InfoRow(label: "Location", value: project.location, icon: "mappin")
                            }
                        }
                    } header: {
                        Label("Bill To / Project", systemImage: "person.text.rectangle")
                    }

                    // Scope
                    Section {
                        TextField("Brief Description", text: $description)
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
                                    .textFieldStyle(.roundedBorder).frame(width: 50)
                                TextField("0", value: $laborLines[index].hours, format: .number)
                                    .textFieldStyle(.roundedBorder).frame(width: 55)
                                Text(line.rate.currencyWithCents)
                                    .font(.caption).frame(width: 70)
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
                        if !additionalLines.isEmpty {
                            HStack {
                                Text("Description").font(.caption).fontWeight(.bold).frame(minWidth: 120, alignment: .leading)
                                Text("Qty").font(.caption).fontWeight(.bold).frame(width: 50)
                                Text("Hours").font(.caption).fontWeight(.bold).frame(width: 55)
                                Text("Rate").font(.caption).fontWeight(.bold).frame(width: 70)
                                Text("Total").font(.caption).fontWeight(.bold).frame(width: 70, alignment: .trailing)
                                Spacer().frame(width: 24)
                            }
                            .padding(.vertical, 2)
                        }

                        ForEach(Array(additionalLines.enumerated()), id: \.element.id) { index, line in
                            HStack {
                                TextField("Description", text: $additionalLines[index].description)
                                    .textFieldStyle(.roundedBorder).frame(minWidth: 120)
                                TextField("0", value: $additionalLines[index].quantity, format: .number)
                                    .textFieldStyle(.roundedBorder).frame(width: 50)
                                TextField("0", value: $additionalLines[index].hours, format: .number)
                                    .textFieldStyle(.roundedBorder).frame(width: 55)
                                TextField("$0", value: $additionalLines[index].rate, format: .number)
                                    .textFieldStyle(.roundedBorder).frame(width: 70)
                                Text(line.lineTotal.currencyWithCents)
                                    .font(.callout).fontWeight(.medium)
                                    .frame(width: 70, alignment: .trailing)
                                Button { additionalLines.remove(at: index) } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.red.opacity(0.6))
                                }.buttonStyle(.plain).frame(width: 24)
                            }
                        }

                        Button {
                            additionalLines.append(AdditionalChargeItem())
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
            description: description,
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

// MARK: - Add Payment
struct AddPaymentView: View {
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var amount = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var appliedToCO: UUID?

    private var project: Project? {
        dataStore.projects.first { $0.id == projectID }
    }

    private var changeOrders: [ChangeOrder] {
        dataStore.changeOrders(for: projectID)
    }

    private var parsedAmount: Decimal {
        Decimal(string: amount.replacingOccurrences(of: ",", with: "")) ?? 0
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
                    .disabled(parsedAmount == 0)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
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
                            .textFieldStyle(.plain)
                            .font(.title3)
                    }

                    DatePicker("Date Received", selection: $date, displayedComponents: .date)

                    Picker("Applied To", selection: $appliedToCO) {
                        Text("Contract").tag(nil as UUID?)
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

                // Notes
                Section {
                    TextEditor(text: $notes)
                        .frame(height: 60)
                        .overlay(
                            Group {
                                if notes.isEmpty {
                                    Text("Check number, wire reference, notes...")
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
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
    }

    private func save() {
        let payment = Payment(
            amount: parsedAmount,
            date: date,
            appliedToChangeOrder: appliedToCO,
            notes: notes
        )
        dataStore.addPayment(payment, to: projectID)
        dismiss()
    }
}

// MARK: - Payroll Employee Line
private struct PayrollLine: Identifiable {
    let id = UUID()
    var employeeUUID: UUID?
    var employeeName: String = ""
    var hourlyRate: Decimal = 0
    var hoursWorked: String = ""

    var parsedHours: Decimal {
        Decimal(string: hoursWorked) ?? 0
    }

    var pay: Decimal {
        hourlyRate * parsedHours
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
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
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
                        VStack(spacing: AppTheme.Spacing.sm) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.employeeName)
                                        .fontWeight(.medium)
                                    Text("\(line.hourlyRate.currencyFormatted)/hr")
                                        .font(.caption)
                                        .foregroundColor(AppTheme.primaryOrange)
                                }
                                Spacer()
                                Button { crewLines.remove(at: index) } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }

                            HStack {
                                Text("Hours:")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                TextField("0", text: $crewLines[index].hoursWorked)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                Spacer()
                                Text("Pay:")
                                    .font(.callout)
                                    .foregroundColor(.secondary)
                                Text(line.pay.currencyFormatted)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.green)
                            }
                        }
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

    private func save() {
        let weekNum = Calendar.current.component(.weekOfYear, from: weekStart)
        let year = Calendar.current.component(.yearForWeekOfYear, from: weekStart)
        let projectName = project?.title ?? ""

        let details = crewLines.map { line in
            EmployeePayrollDetail(
                employeeName: line.employeeName,
                hourlyRate: line.hourlyRate,
                hoursWorked: line.parsedHours,
                projectName: projectName
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
    @State private var description = ""
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
                    .disabled(description.isEmpty || parsedAmount == 0)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
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
                    TextEditor(text: $description)
                        .frame(height: 50)
                        .overlay(
                            Group {
                                if description.isEmpty {
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
        let cost = Cost(category: category, description: description, amount: parsedAmount, date: date)
        dataStore.addCost(cost, to: projectID)
        dismiss()
    }

    private func categoryIcon(_ cat: Cost.CostCategory) -> String {
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

    private func categoryColor(_ cat: Cost.CostCategory) -> Color {
        switch cat.categoryGroup {
        case .machinery: return .blue
        case .overhead: return .orange
        case .other: return .purple
        }
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
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
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
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
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
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 70)
                        Text("x").foregroundColor(.secondary)
                        Text("$").foregroundColor(.secondary)
                        TextField("9.95", text: $fuelPrice)
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
