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
            HStack {
                Text("New Project")
                    .font(AppTheme.Typography.title2)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
            }
            .padding()

            Divider()

            Form {
                Section("Clients") {
                    Picker("General Contractor", selection: $selectedGCID) {
                        Text("None").tag(nil as CKRecord.ID?)
                        ForEach(gcClients) { client in
                            Text(client.name).tag(client.id as CKRecord.ID?)
                        }
                    }
                    Picker("Subcontractor", selection: $selectedSubID) {
                        Text("None").tag(nil as CKRecord.ID?)
                        ForEach(subClients) { client in
                            Text(client.name).tag(client.id as CKRecord.ID?)
                        }
                    }
                }

                Section("Project Information") {
                    TextField("Project Title", text: $title)
                    TextField("Location", text: $location)
                    HStack {
                        Text("$")
                        TextField("Contract Amount", text: $contractAmount)
                    }
                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { Text($0) }
                    }
                }

                Section("Dates") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    Toggle("Set End Date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 80)
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 500, height: 580)
        #endif
    }

    private func save() {
        let amount = Decimal(string: contractAmount.replacingOccurrences(of: ",", with: "")) ?? 0
        let gcRef = selectedGCID.map { CKRecord.Reference(recordID: $0, action: .none) }
        let subRef = selectedSubID.map { CKRecord.Reference(recordID: $0, action: .none) }
        // Set primary clientRef to GC if available, otherwise Sub
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
            HStack {
                Text("Edit Project")
                    .font(AppTheme.Typography.title2)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
            }
            .padding()

            Divider()

            Form {
                Section("Clients") {
                    Picker("General Contractor", selection: $selectedGCID) {
                        Text("None").tag(nil as CKRecord.ID?)
                        ForEach(gcClients) { client in
                            Text(client.name).tag(client.id as CKRecord.ID?)
                        }
                    }
                    Picker("Subcontractor", selection: $selectedSubID) {
                        Text("None").tag(nil as CKRecord.ID?)
                        ForEach(subClients) { client in
                            Text(client.name).tag(client.id as CKRecord.ID?)
                        }
                    }
                }

                Section("Project Information") {
                    TextField("Project Title", text: $title)
                    TextField("Location", text: $location)
                    HStack {
                        Text("$")
                        TextField("Contract Amount", text: $contractAmount)
                    }
                    Picker("Status", selection: $status) {
                        ForEach(statuses, id: \.self) { Text($0) }
                    }
                }

                Section("Dates") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    Toggle("Set End Date", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 80)
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 500, height: 580)
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
