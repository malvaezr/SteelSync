import SwiftUI
import CloudKit

// MARK: - Add

struct AddOverheadExpenseView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var amount = ""
    @State private var category: OverheadCategory = .other
    @State private var vendor = ""
    @State private var expenseDescription = ""
    @State private var notes = ""
    @State private var recurrence: RecurrenceInterval = .none
    @State private var distributionMode: OverheadDistributionMode = .allActive
    @State private var selectedProjectIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "New Overhead Expense",
                saveTitle: "Save",
                saveDisabled: parsedAmount == nil,
                onCancel: { dismiss() },
                onSave: save
            )

            ScrollView {
                OverheadFormBody(
                    date: $date, amount: $amount, category: $category,
                    vendor: $vendor, expenseDescription: $expenseDescription,
                    notes: $notes, recurrence: $recurrence,
                    distributionMode: $distributionMode,
                    selectedProjectIDs: $selectedProjectIDs,
                    availableProjects: dataStore.projects
                )
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 580, height: 680)
        #endif
    }

    private var parsedAmount: Decimal? {
        let cleaned = amount.replacingOccurrences(of: ",", with: "")
        guard let d = Decimal(string: cleaned), d > 0 else { return nil }
        return d
    }

    private func save() {
        guard let amt = parsedAmount else { return }
        let entry = OverheadExpense(
            date: date,
            amount: amt,
            category: category,
            vendor: vendor,
            expenseDescription: expenseDescription,
            notes: notes,
            recurrence: recurrence,
            parentRecurringID: nil,
            distributionMode: distributionMode,
            distributionProjectIDs: distributionMode == .specificProjects
                ? Array(selectedProjectIDs)
                : []
        )
        dataStore.addOverhead(entry)
        dismiss()
    }
}

// MARK: - Edit

struct EditOverheadExpenseView: View {
    let expense: OverheadExpense
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var amount: String
    @State private var category: OverheadCategory
    @State private var vendor: String
    @State private var expenseDescription: String
    @State private var notes: String
    @State private var recurrence: RecurrenceInterval
    @State private var distributionMode: OverheadDistributionMode
    @State private var selectedProjectIDs: Set<String>

    init(expense: OverheadExpense) {
        self.expense = expense
        _date = State(initialValue: expense.date)
        _amount = State(initialValue: "\(expense.amount)")
        _category = State(initialValue: expense.category)
        _vendor = State(initialValue: expense.vendor)
        _expenseDescription = State(initialValue: expense.expenseDescription)
        _notes = State(initialValue: expense.notes)
        _recurrence = State(initialValue: expense.recurrence)
        _distributionMode = State(initialValue: expense.distributionMode)
        _selectedProjectIDs = State(initialValue: Set(expense.distributionProjectIDs))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Edit Overhead Expense",
                saveTitle: "Save",
                saveDisabled: parsedAmount == nil,
                onCancel: { dismiss() },
                onSave: save
            )

            ScrollView {
                OverheadFormBody(
                    date: $date, amount: $amount, category: $category,
                    vendor: $vendor, expenseDescription: $expenseDescription,
                    notes: $notes, recurrence: $recurrence,
                    distributionMode: $distributionMode,
                    selectedProjectIDs: $selectedProjectIDs,
                    availableProjects: dataStore.projects,
                    isChildInstance: expense.parentRecurringID != nil
                )
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 580, height: 680)
        #endif
    }

    private var parsedAmount: Decimal? {
        let cleaned = amount.replacingOccurrences(of: ",", with: "")
        guard let d = Decimal(string: cleaned), d > 0 else { return nil }
        return d
    }

    private func save() {
        guard let amt = parsedAmount else { return }
        var updated = expense
        updated.date = date
        updated.amount = amt
        updated.category = category
        updated.vendor = vendor
        updated.expenseDescription = expenseDescription
        updated.notes = notes
        updated.recurrence = recurrence
        updated.distributionMode = distributionMode
        updated.distributionProjectIDs = distributionMode == .specificProjects
            ? Array(selectedProjectIDs)
            : []
        dataStore.updateOverhead(updated)
        dismiss()
    }
}

// MARK: - Shared form body

private struct OverheadFormBody: View {
    @Binding var date: Date
    @Binding var amount: String
    @Binding var category: OverheadCategory
    @Binding var vendor: String
    @Binding var expenseDescription: String
    @Binding var notes: String
    @Binding var recurrence: RecurrenceInterval
    @Binding var distributionMode: OverheadDistributionMode
    @Binding var selectedProjectIDs: Set<String>
    let availableProjects: [Project]
    var isChildInstance: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            basicsSection
            recurrenceSection
            allocationSection
            notesSection
        }
    }

    @ViewBuilder private var basicsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Expense")
            HStack(spacing: AppTheme.Spacing.md) {
                LabeledField(label: "Date") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .appControlSurface()
                }
                LabeledField(label: "Amount") {
                    CurrencyInput(placeholder: "0.00", text: $amount)
                }
            }
            LabeledField(label: "Category") {
                Picker("", selection: $category) {
                    ForEach(OverheadCategory.allCases, id: \.self) { cat in
                        Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .appControlSurface()
            }
            LabeledField(label: "Description") {
                TextField("e.g. April office rent", text: $expenseDescription)
                    .textFieldStyle(.appField)
            }
            LabeledField(label: "Vendor") {
                TextField("Who got paid?", text: $vendor)
                    .textFieldStyle(.appField)
            }
        }
    }

    @ViewBuilder private var recurrenceSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Recurrence")
            if isChildInstance {
                Text("This is a generated instance of a recurring template. Edit the template directly to change the schedule.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(AppTheme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(AppTheme.secondaryBackground)
                    )
            } else {
                LabeledField(label: "Interval",
                             helpText: recurrence == .none
                                ? "One-time expense."
                                : "Re-creates this expense automatically on every \(recurrence.rawValue.lowercased()) schedule.") {
                    Picker("", selection: $recurrence) {
                        ForEach(RecurrenceInterval.allCases, id: \.self) { r in
                            Text(r.rawValue).tag(r)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .appControlSurface()
                }
            }
        }
    }

    @ViewBuilder private var allocationSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Allocation")
            LabeledField(
                label: "Distribution",
                helpText: allocationHelp
            ) {
                Picker("", selection: $distributionMode) {
                    ForEach(OverheadDistributionMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .appControlSurface()
            }

            if distributionMode == .specificProjects {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Select projects")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                        .textCase(.uppercase)
                        .tracking(0.4)
                    ForEach(availableProjects) { project in
                        Toggle(isOn: Binding(
                            get: { selectedProjectIDs.contains(project.id.recordName) },
                            set: { isOn in
                                if isOn { selectedProjectIDs.insert(project.id.recordName) }
                                else { selectedProjectIDs.remove(project.id.recordName) }
                            }
                        )) {
                            HStack {
                                Text(project.title).lineLimit(1)
                                Spacer()
                                Text(project.contractAmount.currencyFormatted)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    if availableProjects.isEmpty {
                        Text("No projects available.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.secondaryBackground)
                )
            }
        }
    }

    @ViewBuilder private var notesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Notes")
            NotesField(text: $notes, minHeight: 80)
        }
    }

    private var allocationHelp: String {
        switch distributionMode {
        case .allActive:
            return "Split pro-rata by contract value across every project active on the expense date."
        case .specificProjects:
            return "Pick which projects share this cost. Pro-rata by their contract amounts."
        case .companyOnly:
            return "Never charged to projects — only appears in company-level totals."
        }
    }
}
