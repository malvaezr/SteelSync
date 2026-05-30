import SwiftUI

/// Phone-side editor for a single weekly `TimesheetEntry` row. Lets the
/// foreman fix a forgotten clock-out, correct hours, change the notes, or
/// delete the row entirely. Saves through `DataStore.updateTimesheetEntry`
/// so the desk view and CloudKit see the same change.
struct EditTimesheetEntrySheet: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: TimesheetEntry
    @State private var showDeleteConfirm = false

    init(entry: TimesheetEntry) {
        _draft = State(initialValue: entry)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Employee", value: draft.employeeName.isEmpty ? "—" : draft.employeeName)
                    LabeledContent("Project", value: draft.projectName.isEmpty ? "—" : draft.projectName)
                    LabeledContent("Week of", value: weekStartLabel)
                } header: {
                    Text("Entry")
                }

                Section {
                    hoursRow(label: "Monday",    value: $draft.mondayHours)
                    hoursRow(label: "Tuesday",   value: $draft.tuesdayHours)
                    hoursRow(label: "Wednesday", value: $draft.wednesdayHours)
                    hoursRow(label: "Thursday",  value: $draft.thursdayHours)
                    hoursRow(label: "Friday",    value: $draft.fridayHours)
                    hoursRow(label: "Saturday",  value: $draft.saturdayHours)
                    hoursRow(label: "Sunday",    value: $draft.sundayHours)
                } header: {
                    Text("Hours")
                } footer: {
                    HStack {
                        Text("Week total")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.2fh", NSDecimalNumber(decimal: draft.totalHours).doubleValue))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundColor(AppTheme.primaryOrange)
                    }
                }

                Section {
                    decimalRow(label: "Per Diem ($)", value: $draft.perDiem)
                    decimalRow(label: "Hourly Rate ($)", value: $draft.hourlyRate)
                } header: {
                    Text("Rates")
                }

                Section {
                    TextField("Notes", text: $draft.notes, axis: .vertical)
                        .lineLimit(2...6)
                } header: {
                    Text("Notes")
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Entry", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        dataStore.updateTimesheetEntry(draft)
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete this entry?",
                                isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    dataStore.deleteTimesheetEntry(draft)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Removes the row from the timesheet — including hours and per diem. Can be undone with a new entry but the original is gone.")
            }
        }
    }

    private var weekStartLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE MMM d, yyyy"
        return f.string(from: draft.weekStartDate)
    }

    @ViewBuilder
    private func hoursRow(label: String, value: Binding<Decimal>) -> some View {
        HStack {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("0.0", value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
                .monospacedDigit()
            Text("h")
                .foregroundColor(.secondary)
                .frame(width: 14)
        }
    }

    @ViewBuilder
    private func decimalRow(label: String, value: Binding<Decimal>) -> some View {
        HStack {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("0.00", value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
                .monospacedDigit()
        }
    }
}
