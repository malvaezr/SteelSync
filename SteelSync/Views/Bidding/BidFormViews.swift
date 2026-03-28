import SwiftUI
import CloudKit

// MARK: - Add Bid
struct AddBidView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var projectName = ""
    @State private var selectedClientID: CKRecord.ID?
    @State private var clientName = ""
    @State private var address = ""
    @State private var bidAmount = ""
    @State private var bidDueDate = Date().addingTimeInterval(86400 * 14)
    @State private var squareFeet = ""
    @State private var beams = ""
    @State private var columns = ""
    @State private var joists = ""
    @State private var wallPanels = ""
    @State private var estimatedTons = ""
    @State private var notes = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Bid")
                    .font(AppTheme.Typography.title2)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(projectName.isEmpty || clientName.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
            }
            .padding()
            Divider()

            Form {
                Section("Project Information") {
                    TextField("Project Name", text: $projectName)
                    Picker("Client", selection: $selectedClientID) {
                        Text("Other / New Client").tag(nil as CKRecord.ID?)
                        ForEach(dataStore.clients) { client in
                            HStack {
                                Text(client.name)
                                Text(client.preferredRateType == .generalContractor ? "(GC)" : "(Sub)")
                                    .foregroundColor(.secondary)
                            }
                            .tag(client.id as CKRecord.ID?)
                        }
                    }
                    .onChange(of: selectedClientID) { _, newValue in
                        if let id = newValue, let c = dataStore.clients.first(where: { $0.id == id }) {
                            clientName = c.name
                        }
                    }
                    if selectedClientID == nil {
                        TextField("Client Name", text: $clientName)
                    }
                    TextField("Address", text: $address)
                    HStack { Text("$"); TextField("Bid Amount", text: $bidAmount) }
                    DatePicker("Bid Due Date", selection: $bidDueDate, displayedComponents: .date)
                }

                Section("Construction Metrics") {
                    HStack {
                        TextField("Sq Ft", text: $squareFeet)
                        TextField("Beams", text: $beams)
                        TextField("Columns", text: $columns)
                    }
                    HStack {
                        TextField("Joists", text: $joists)
                        TextField("Wall Panels", text: $wallPanels)
                        TextField("Est. Tons", text: $estimatedTons)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(height: 60)
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 550, height: 580)
        #endif
    }

    private func save() {
        let clientRef = selectedClientID.map { CKRecord.Reference(recordID: $0, action: .none) }
        let bid = BidProject(
            projectName: projectName, clientName: clientName, clientRef: clientRef, address: address,
            bidAmount: Decimal(string: bidAmount.replacingOccurrences(of: ",", with: "")) ?? 0,
            bidDueDate: bidDueDate,
            squareFeet: Int(squareFeet) ?? 0, numberOfBeams: Int(beams) ?? 0,
            numberOfColumns: Int(columns) ?? 0, numberOfJoists: Int(joists) ?? 0,
            numberOfWallPanels: Int(wallPanels) ?? 0,
            estimatedTons: Double(estimatedTons) ?? 0, notes: notes
        )
        dataStore.addBid(bid)
        dismiss()
    }
}

// MARK: - Edit Bid
struct EditBidView: View {
    let bid: BidProject
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var projectName: String
    @State private var selectedClientID: CKRecord.ID?
    @State private var clientName: String
    @State private var address: String
    @State private var bidAmount: String
    @State private var bidDueDate: Date
    @State private var squareFeet: String
    @State private var beams: String
    @State private var columns: String
    @State private var joists: String
    @State private var wallPanels: String
    @State private var estimatedTons: String
    @State private var notes: String

    init(bid: BidProject) {
        self.bid = bid
        _projectName = State(initialValue: bid.projectName)
        _selectedClientID = State(initialValue: bid.clientRef?.recordID)
        _clientName = State(initialValue: bid.clientName)
        _address = State(initialValue: bid.address)
        _bidAmount = State(initialValue: "\(bid.bidAmount)")
        _bidDueDate = State(initialValue: bid.bidDueDate)
        _squareFeet = State(initialValue: bid.squareFeet > 0 ? "\(bid.squareFeet)" : "")
        _beams = State(initialValue: bid.numberOfBeams > 0 ? "\(bid.numberOfBeams)" : "")
        _columns = State(initialValue: bid.numberOfColumns > 0 ? "\(bid.numberOfColumns)" : "")
        _joists = State(initialValue: bid.numberOfJoists > 0 ? "\(bid.numberOfJoists)" : "")
        _wallPanels = State(initialValue: bid.numberOfWallPanels > 0 ? "\(bid.numberOfWallPanels)" : "")
        _estimatedTons = State(initialValue: bid.estimatedTons > 0 ? "\(bid.estimatedTons)" : "")
        _notes = State(initialValue: bid.notes)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Bid").font(AppTheme.Typography.title2)
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
                Section("Project Information") {
                    TextField("Project Name", text: $projectName)
                    Picker("Client", selection: $selectedClientID) {
                        Text("Other / New Client").tag(nil as CKRecord.ID?)
                        ForEach(dataStore.clients) { client in
                            HStack {
                                Text(client.name)
                                Text(client.preferredRateType == .generalContractor ? "(GC)" : "(Sub)")
                                    .foregroundColor(.secondary)
                            }
                            .tag(client.id as CKRecord.ID?)
                        }
                    }
                    .onChange(of: selectedClientID) { _, newValue in
                        if let id = newValue, let c = dataStore.clients.first(where: { $0.id == id }) {
                            clientName = c.name
                        }
                    }
                    if selectedClientID == nil {
                        TextField("Client Name", text: $clientName)
                    }
                    TextField("Address", text: $address)
                    HStack { Text("$"); TextField("Bid Amount", text: $bidAmount) }
                    DatePicker("Bid Due Date", selection: $bidDueDate, displayedComponents: .date)
                }
                Section("Construction Metrics") {
                    HStack {
                        TextField("Sq Ft", text: $squareFeet)
                        TextField("Beams", text: $beams)
                        TextField("Columns", text: $columns)
                    }
                    HStack {
                        TextField("Joists", text: $joists)
                        TextField("Wall Panels", text: $wallPanels)
                        TextField("Est. Tons", text: $estimatedTons)
                    }
                }
                Section("Notes") {
                    TextEditor(text: $notes).frame(height: 60)
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 550, height: 580)
        #endif
    }

    private func save() {
        var updated = bid
        updated.projectName = projectName
        updated.clientRef = selectedClientID.map { CKRecord.Reference(recordID: $0, action: .none) }
        updated.clientName = clientName
        updated.address = address
        updated.bidAmount = Decimal(string: bidAmount.replacingOccurrences(of: ",", with: "")) ?? 0
        updated.bidDueDate = bidDueDate
        updated.squareFeet = Int(squareFeet) ?? 0; updated.numberOfBeams = Int(beams) ?? 0
        updated.numberOfColumns = Int(columns) ?? 0; updated.numberOfJoists = Int(joists) ?? 0
        updated.numberOfWallPanels = Int(wallPanels) ?? 0
        updated.estimatedTons = Double(estimatedTons) ?? 0; updated.notes = notes
        dataStore.updateBid(updated)
        dismiss()
    }
}

// MARK: - Add Touchpoint
struct AddTouchpointView: View {
    let bid: BidProject
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var type: Touchpoint.TouchpointType = .call
    @State private var date = Date()
    @State private var notes = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Log Touchpoint").font(AppTheme.Typography.title3)
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
                Picker("Type", selection: $type) {
                    ForEach(Touchpoint.TouchpointType.allCases, id: \.self) { t in
                        Label(t.rawValue, systemImage: t.icon).tag(t)
                    }
                }
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 420, height: 300)
        #endif
    }

    private func save() {
        var updated = bid
        updated.touchpoints.append(Touchpoint(type: type, date: date, notes: notes))
        dataStore.updateBid(updated)
        dismiss()
    }
}

// MARK: - Convert Bid to Project
struct ConvertBidToProjectView: View {
    let bid: BidProject
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var contractAmount: String

    init(bid: BidProject) {
        self.bid = bid
        _contractAmount = State(initialValue: "\(bid.bidAmount)")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Convert to Project").font(AppTheme.Typography.title3)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Convert") { convert() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
            }
            .padding()
            Divider()
            Form {
                Section {
                    InfoRow(label: "Project", value: bid.projectName)
                    InfoRow(label: "Client", value: bid.clientName)
                    InfoRow(label: "Bid Amount", value: bid.bidAmount.currencyFormatted)
                }
                Section("Contract Details") {
                    HStack { Text("$"); TextField("Contract Amount", text: $contractAmount) }
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 420, height: 300)
        #endif
    }

    private func convert() {
        let amount = Decimal(string: contractAmount.replacingOccurrences(of: ",", with: "")) ?? bid.bidAmount
        _ = dataStore.convertBidToProject(bid, contractAmount: amount)
        dismiss()
    }
}
