import SwiftUI
import CloudKit

// MARK: - Shared Sheet Chrome

private struct SheetHeader: View {
    let title: String
    let saveTitle: String
    var saveDisabled: Bool = false
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)
            Spacer()
            Button("Cancel") { onCancel() }
                .buttonStyle(.appGhost)
                .keyboardShortcut(.cancelAction)
            Button(saveTitle) { onSave() }
                .buttonStyle(.appPrimary)
                .keyboardShortcut(.defaultAction)
                .disabled(saveDisabled)
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
        .background(AppTheme.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(AppTheme.primaryText.opacity(0.08)).frame(height: 0.5)
        }
    }
}

private struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(AppTheme.secondaryText)
            .textCase(.uppercase)
            .tracking(0.5)
            .padding(.bottom, 2)
    }
}

private struct CurrencyInput: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Text("$")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppTheme.secondaryText)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                #if !os(macOS)
                .keyboardType(.decimalPad)
                #endif
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(minHeight: 36)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.secondaryBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(AppTheme.primaryText.opacity(0.08), lineWidth: 0.5)
        )
    }
}

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
            SheetHeader(
                title: "New Bid",
                saveTitle: "Save",
                saveDisabled: projectName.isEmpty || clientName.isEmpty,
                onCancel: { dismiss() },
                onSave: save
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    projectInfoSection
                    metricsSection
                    notesSection
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 560, height: 620)
        #endif
    }

    @ViewBuilder private var projectInfoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Project Information")

            LabeledField(label: "Project Name") {
                TextField("e.g. Downtown Office Tower", text: $projectName)
                    .textFieldStyle(.appField)
            }

            LabeledField(label: "Client") {
                Picker("", selection: $selectedClientID) {
                    Text("Other / New Client").tag(nil as CKRecord.ID?)
                    ForEach(dataStore.clients) { client in
                        Text("\(client.name) (\(client.preferredRateType == .generalContractor ? "GC" : "Sub"))")
                            .tag(client.id as CKRecord.ID?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .appControlSurface()
                .onChange(of: selectedClientID) { _, newValue in
                    if let id = newValue, let c = dataStore.clients.first(where: { $0.id == id }) {
                        clientName = c.name
                    }
                }
            }

            if selectedClientID == nil {
                LabeledField(label: "Client Name") {
                    TextField("Company name", text: $clientName)
                        .textFieldStyle(.appField)
                }
            }

            LabeledField(label: "Address") {
                TextField("Street, City, ST", text: $address)
                    .textFieldStyle(.appField)
            }

            HStack(spacing: AppTheme.Spacing.md) {
                LabeledField(label: "Bid Amount") {
                    CurrencyInput(placeholder: "0.00", text: $bidAmount)
                }
                LabeledField(label: "Bid Due Date") {
                    DatePicker("", selection: $bidDueDate, displayedComponents: .date)
                        .labelsHidden()
                        .appControlSurface()
                }
            }
        }
    }

    @ViewBuilder private var metricsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Construction Metrics")

            HStack(spacing: AppTheme.Spacing.md) {
                LabeledField(label: "Sq Ft") { numberField("0", $squareFeet, decimal: false) }
                LabeledField(label: "Beams") { numberField("0", $beams, decimal: false) }
                LabeledField(label: "Columns") { numberField("0", $columns, decimal: false) }
            }
            HStack(spacing: AppTheme.Spacing.md) {
                LabeledField(label: "Joists") { numberField("0", $joists, decimal: false) }
                LabeledField(label: "Wall Panels") { numberField("0", $wallPanels, decimal: false) }
                LabeledField(label: "Est. Tons") { numberField("0.0", $estimatedTons, decimal: true) }
            }
        }
    }

    @ViewBuilder private var notesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Notes")
            TextEditor(text: $notes)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 80)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.secondaryBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppTheme.primaryText.opacity(0.08), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private func numberField(_ placeholder: String, _ text: Binding<String>, decimal: Bool) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.appField)
            #if !os(macOS)
            .keyboardType(decimal ? .decimalPad : .numberPad)
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
            SheetHeader(
                title: "Edit Bid",
                saveTitle: "Save",
                onCancel: { dismiss() },
                onSave: save
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    projectInfoSection
                    metricsSection
                    notesSection
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 560, height: 620)
        #endif
    }

    @ViewBuilder private var projectInfoSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Project Information")

            LabeledField(label: "Project Name") {
                TextField("Project name", text: $projectName)
                    .textFieldStyle(.appField)
            }

            LabeledField(label: "Client") {
                Picker("", selection: $selectedClientID) {
                    Text("Other / New Client").tag(nil as CKRecord.ID?)
                    ForEach(dataStore.clients) { client in
                        Text("\(client.name) (\(client.preferredRateType == .generalContractor ? "GC" : "Sub"))")
                            .tag(client.id as CKRecord.ID?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .appControlSurface()
                .onChange(of: selectedClientID) { _, newValue in
                    if let id = newValue, let c = dataStore.clients.first(where: { $0.id == id }) {
                        clientName = c.name
                    }
                }
            }

            if selectedClientID == nil {
                LabeledField(label: "Client Name") {
                    TextField("Company name", text: $clientName)
                        .textFieldStyle(.appField)
                }
            }

            LabeledField(label: "Address") {
                TextField("Street, City, ST", text: $address)
                    .textFieldStyle(.appField)
            }

            HStack(spacing: AppTheme.Spacing.md) {
                LabeledField(label: "Bid Amount") {
                    CurrencyInput(placeholder: "0.00", text: $bidAmount)
                }
                LabeledField(label: "Bid Due Date") {
                    DatePicker("", selection: $bidDueDate, displayedComponents: .date)
                        .labelsHidden()
                        .appControlSurface()
                }
            }
        }
    }

    @ViewBuilder private var metricsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Construction Metrics")
            HStack(spacing: AppTheme.Spacing.md) {
                LabeledField(label: "Sq Ft") { numberField("0", $squareFeet, decimal: false) }
                LabeledField(label: "Beams") { numberField("0", $beams, decimal: false) }
                LabeledField(label: "Columns") { numberField("0", $columns, decimal: false) }
            }
            HStack(spacing: AppTheme.Spacing.md) {
                LabeledField(label: "Joists") { numberField("0", $joists, decimal: false) }
                LabeledField(label: "Wall Panels") { numberField("0", $wallPanels, decimal: false) }
                LabeledField(label: "Est. Tons") { numberField("0.0", $estimatedTons, decimal: true) }
            }
        }
    }

    @ViewBuilder private var notesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Notes")
            TextEditor(text: $notes)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 80)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(AppTheme.secondaryBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(AppTheme.primaryText.opacity(0.08), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private func numberField(_ placeholder: String, _ text: Binding<String>, decimal: Bool) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.appField)
            #if !os(macOS)
            .keyboardType(decimal ? .decimalPad : .numberPad)
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
            SheetHeader(
                title: "Log Touchpoint",
                saveTitle: "Save",
                onCancel: { dismiss() },
                onSave: save
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    LabeledField(label: "Type") {
                        Picker("", selection: $type) {
                            ForEach(Touchpoint.TouchpointType.allCases, id: \.self) { t in
                                Label(t.rawValue, systemImage: t.icon).tag(t)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .appControlSurface()
                    }

                    LabeledField(label: "Date") {
                        DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .appControlSurface()
                    }

                    LabeledField(label: "Notes") {
                        TextField("Details...", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.appField)
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 440, height: 360)
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
            SheetHeader(
                title: "Convert to Project",
                saveTitle: "Convert",
                onCancel: { dismiss() },
                onSave: convert
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        SectionTitle(text: "Bid")
                        VStack(spacing: AppTheme.Spacing.sm) {
                            InfoRow(label: "Project", value: bid.projectName)
                            InfoRow(label: "Client", value: bid.clientName)
                            InfoRow(label: "Bid Amount", value: bid.bidAmount.currencyFormatted)
                        }
                        .padding(AppTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppTheme.secondaryBackground)
                        )
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        SectionTitle(text: "Contract Details")
                        LabeledField(label: "Contract Amount") {
                            CurrencyInput(placeholder: "0.00", text: $contractAmount)
                        }
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 440, height: 380)
        #endif
    }

    private func convert() {
        let amount = Decimal(string: contractAmount.replacingOccurrences(of: ",", with: "")) ?? bid.bidAmount
        _ = dataStore.convertBidToProject(bid, contractAmount: amount)
        dismiss()
    }
}
