import SwiftUI
import CloudKit

struct AddProjectView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var location = ""
    @State private var contractAmount = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(86400 * 90)
    @State private var status = "Active"
    @State private var notes = ""
    @State private var hasEndDate = false
    @State private var selectedGCID: CKRecord.ID?
    @State private var selectedSubID: CKRecord.ID?

    private let statuses = ["Active", "Upcoming", "On Hold"]

    private var gcClients: [Client] { dataStore.clients.filter { $0.preferredRateType == .generalContractor } }
    private var subClients: [Client] { dataStore.clients.filter { $0.preferredRateType == .subcontractor } }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "New Project",
                saveTitle: "Save",
                saveDisabled: title.isEmpty,
                onCancel: { dismiss() },
                onSave: save
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    ProjectClientsSection(
                        gcClients: gcClients, subClients: subClients,
                        selectedGCID: $selectedGCID, selectedSubID: $selectedSubID
                    )
                    ProjectInfoSection(
                        title: $title, location: $location, contractAmount: $contractAmount,
                        status: $status, statuses: statuses
                    )
                    ProjectDatesSection(
                        startDate: $startDate, endDate: $endDate, hasEndDate: $hasEndDate
                    )
                    ProjectNotesSection(notes: $notes)
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 560, height: 640)
        #endif
    }

    private func save() {
        let amount = Decimal(string: contractAmount.replacingOccurrences(of: ",", with: "")) ?? 0
        let gcRef = selectedGCID.map { CKRecord.Reference(recordID: $0, action: .none) }
        let subRef = selectedSubID.map { CKRecord.Reference(recordID: $0, action: .none) }
        let primaryRef = gcRef ?? subRef
        let project = Project(
            clientRef: primaryRef,
            gcClientRef: gcRef,
            subClientRef: subRef,
            title: title, location: location, contractAmount: amount,
            startDate: startDate, endDate: hasEndDate ? endDate : nil,
            status: status, notes: notes,
            balanceSummary: ProjectBalanceSummary(contractAmount: amount)
        )
        dataStore.addProject(project)
        dismiss()
    }
}

struct EditProjectView: View {
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var location: String
    @State private var contractAmount: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var status: String
    @State private var notes: String
    @State private var hasEndDate: Bool
    @State private var selectedGCID: CKRecord.ID?
    @State private var selectedSubID: CKRecord.ID?

    private let statuses = ["Active", "Upcoming", "Completed", "On Hold"]

    private var gcClients: [Client] { dataStore.clients.filter { $0.preferredRateType == .generalContractor } }
    private var subClients: [Client] { dataStore.clients.filter { $0.preferredRateType == .subcontractor } }

    init(project: Project) {
        self.project = project
        _title = State(initialValue: project.title)
        _location = State(initialValue: project.location)
        _contractAmount = State(initialValue: "\(project.contractAmount)")
        _startDate = State(initialValue: project.startDate ?? Date())
        _endDate = State(initialValue: project.endDate ?? Date().addingTimeInterval(86400 * 90))
        _status = State(initialValue: project.status)
        _notes = State(initialValue: project.notes)
        _hasEndDate = State(initialValue: project.endDate != nil)
        _selectedGCID = State(initialValue: project.gcClientRef?.recordID ?? (project.clientRef?.recordID))
        _selectedSubID = State(initialValue: project.subClientRef?.recordID)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Edit Project",
                saveTitle: "Save",
                saveDisabled: title.isEmpty,
                onCancel: { dismiss() },
                onSave: save
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    ProjectClientsSection(
                        gcClients: gcClients, subClients: subClients,
                        selectedGCID: $selectedGCID, selectedSubID: $selectedSubID
                    )
                    ProjectInfoSection(
                        title: $title, location: $location, contractAmount: $contractAmount,
                        status: $status, statuses: statuses
                    )
                    ProjectDatesSection(
                        startDate: $startDate, endDate: $endDate, hasEndDate: $hasEndDate
                    )
                    ProjectNotesSection(notes: $notes)
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 560, height: 640)
        #endif
    }

    private func save() {
        let amount = Decimal(string: contractAmount.replacingOccurrences(of: ",", with: "")) ?? 0
        let gcRef = selectedGCID.map { CKRecord.Reference(recordID: $0, action: .none) }
        let subRef = selectedSubID.map { CKRecord.Reference(recordID: $0, action: .none) }
        var updated = project
        updated.gcClientRef = gcRef
        updated.subClientRef = subRef
        updated.clientRef = gcRef ?? subRef
        updated.title = title
        updated.location = location
        updated.contractAmount = amount
        updated.startDate = startDate
        updated.endDate = hasEndDate ? endDate : nil
        updated.status = status
        updated.notes = notes
        dataStore.updateProject(updated)
        dismiss()
    }
}

// MARK: - Shared field sections

private struct ProjectClientsSection: View {
    let gcClients: [Client]
    let subClients: [Client]
    @Binding var selectedGCID: CKRecord.ID?
    @Binding var selectedSubID: CKRecord.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Clients")
            LabeledField(label: "General Contractor") {
                Picker("", selection: $selectedGCID) {
                    Text("None").tag(nil as CKRecord.ID?)
                    ForEach(gcClients) { client in
                        Text(client.name).tag(client.id as CKRecord.ID?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .appControlSurface()
            }
            LabeledField(label: "Subcontractor") {
                Picker("", selection: $selectedSubID) {
                    Text("None").tag(nil as CKRecord.ID?)
                    ForEach(subClients) { client in
                        Text(client.name).tag(client.id as CKRecord.ID?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .appControlSurface()
            }
        }
    }
}

private struct ProjectInfoSection: View {
    @Binding var title: String
    @Binding var location: String
    @Binding var contractAmount: String
    @Binding var status: String
    let statuses: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Project Information")
            LabeledField(label: "Project Title") {
                TextField("e.g. Downtown Tower", text: $title)
                    .textFieldStyle(.appField)
            }
            LabeledField(label: "Location") {
                TextField("City, ST", text: $location)
                    .textFieldStyle(.appField)
            }
            HStack(spacing: AppTheme.Spacing.md) {
                LabeledField(label: "Contract Amount") {
                    CurrencyInput(placeholder: "0.00", text: $contractAmount)
                }
                LabeledField(label: "Status") {
                    Picker("", selection: $status) {
                        ForEach(statuses, id: \.self) { Text($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .appControlSurface()
                }
            }
        }
    }
}

private struct ProjectDatesSection: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    @Binding var hasEndDate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Dates")
            LabeledField(label: "Start Date") {
                DatePicker("", selection: $startDate, displayedComponents: .date)
                    .labelsHidden()
                    .appControlSurface()
            }
            Toggle("Set End Date", isOn: $hasEndDate)
                .toggleStyle(.switch)
            if hasEndDate {
                LabeledField(label: "End Date") {
                    DatePicker("", selection: $endDate, displayedComponents: .date)
                        .labelsHidden()
                        .appControlSurface()
                }
            }
        }
    }
}

private struct ProjectNotesSection: View {
    @Binding var notes: String

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Notes")
            NotesField(text: $notes, minHeight: 90)
        }
    }
}
