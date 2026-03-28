import SwiftUI
import CloudKit

struct ClientsView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedFilter = "All"
    @State private var searchText = ""
    @State private var showAddClient = false
    @State private var selectedClient: Client?

    private let filters = ["All", "GC", "Sub"]

    var filteredClients: [Client] {
        var result = dataStore.clients
        switch selectedFilter {
        case "GC": result = result.filter { $0.preferredRateType == .generalContractor }
        case "Sub": result = result.filter { $0.preferredRateType == .subcontractor }
        default: break
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.contactName.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result.sorted { $0.name < $1.name }
    }

    var body: some View {
        PlatformSplitView {
            // Left: Client list
            VStack(spacing: 0) {
                // Metrics
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        MetricCard(title: "Total Clients", value: "\(dataStore.clients.count)",
                                   icon: "person.2.fill", color: .blue)
                        MetricCard(title: "General Contractors", value: "\(dataStore.gcClients.count)",
                                   icon: "building.2.fill", color: AppTheme.primaryOrange)
                        MetricCard(title: "Subcontractors", value: "\(dataStore.subcontractorClients.count)",
                                   icon: "wrench.and.screwdriver.fill", color: .purple)
                    }
                    .padding(AppTheme.Spacing.md)
                }
                .frame(height: 120)

                // Filters
                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(filters, id: \.self) { filter in
                        FilterPill(filter, isSelected: selectedFilter == filter,
                                   count: countFor(filter: filter)) {
                            selectedFilter = filter
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.sm)

                // Client list
                List(selection: $selectedClient) {
                    ForEach(filteredClients) { client in
                        ClientRow(client: client, projectCount: dataStore.projects(for: client).count)
                            .tag(client)
                            .contextMenu {
                                Button("Edit") { selectedClient = client }
                                Divider()
                                Button("Delete", role: .destructive) { dataStore.deleteClient(client) }
                            }
                    }
                }
                .listStyle(.inset)
                .searchable(text: $searchText, prompt: "Search clients...")
            }
            #if os(macOS)
            .frame(minWidth: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showAddClient = true }) {
                        Label("New Client", systemImage: "plus")
                    }
                }
            }

            // Right: Client detail
            if let client = selectedClient {
                ClientDetailView(client: client)
                    #if os(macOS)
                    .frame(minWidth: 450)
                    #endif
            } else {
                EmptyStateView(icon: "person.2", title: "No Client Selected",
                               message: "Select a client from the list to view details.",
                               buttonTitle: "Add Client") { showAddClient = true }
                #if os(macOS)
                .frame(minWidth: 450)
                #endif
            }
        }
        .sheet(isPresented: $showAddClient) {
            AddClientView()
        }
        .navigationTitle("Clients")
    }

    private func countFor(filter: String) -> Int? {
        switch filter {
        case "All": return dataStore.clients.count
        case "GC": return dataStore.gcClients.count
        case "Sub": return dataStore.subcontractorClients.count
        default: return nil
        }
    }
}

// MARK: - Client Row
struct ClientRow: View {
    let client: Client
    let projectCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text(client.name)
                    .font(.headline)
                Spacer()
                StatusBadge(text: client.preferredRateType.displayName,
                            color: client.preferredRateType == .generalContractor ? AppTheme.primaryOrange : .purple)
            }

            HStack {
                if !client.contactName.isEmpty {
                    Label(client.contactName, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if projectCount > 0 {
                    Label("\(projectCount) project\(projectCount == 1 ? "" : "s")", systemImage: "building.2")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack {
                if !client.phone.isEmpty {
                    Label(client.phone, systemImage: "phone")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !client.email.isEmpty {
                    Label(client.email, systemImage: "envelope")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}

// MARK: - Client Detail
struct ClientDetailView: View {
    let client: Client
    @EnvironmentObject var dataStore: DataStore
    @State private var showEditClient = false

    private var clientProjects: [Project] {
        dataStore.projects(for: client)
    }

    private var clientBids: [BidProject] {
        dataStore.bids(for: client)
    }

    private var clientRevenue: Decimal {
        clientProjects.reduce(0) { $0 + $1.totalRevenue }
    }

    private var clientProfit: Decimal {
        clientProjects.reduce(0) { $0 + $1.profit }
    }

    private var clientCosts: Decimal {
        clientProjects.reduce(0) { $0 + $1.totalCosts }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(client.name)
                            .font(AppTheme.Typography.title2)
                        StatusBadge(text: client.preferredRateType.displayName,
                                    color: client.preferredRateType == .generalContractor ? AppTheme.primaryOrange : .purple)
                    }
                    Spacer()
                    Button("Edit") { showEditClient = true }
                        .buttonStyle(.bordered)
                }

                // Contact Information
                GroupBox("Contact Information") {
                    VStack(spacing: AppTheme.Spacing.sm) {
                        if !client.contactName.isEmpty {
                            InfoRow(label: "Contact", value: client.contactName, icon: "person")
                            Divider()
                        }
                        if !client.email.isEmpty {
                            InfoRow(label: "Email", value: client.email, icon: "envelope")
                            Divider()
                        }
                        if !client.phone.isEmpty {
                            InfoRow(label: "Phone", value: client.phone, icon: "phone")
                            Divider()
                        }
                        if !client.billingAddress.isEmpty {
                            InfoRow(label: "Address", value: client.billingAddress, icon: "mappin")
                            Divider()
                        }
                        InfoRow(label: "Type", value: client.preferredRateType.displayName, icon: "tag")
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // Financial Summary
                if !clientProjects.isEmpty {
                    GroupBox("Financial Summary") {
                        VStack(spacing: AppTheme.Spacing.sm) {
                            InfoRow(label: "Total Revenue", value: clientRevenue.currencyFormatted, icon: "dollarsign.circle")
                            Divider()
                            InfoRow(label: "Total Costs", value: clientCosts.currencyFormatted, icon: "cart")
                            Divider()
                            HStack {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                Text("Profit")
                                    .foregroundColor(AppTheme.secondaryText)
                                Spacer()
                                Text(clientProfit.currencyFormatted)
                                    .fontWeight(.bold)
                                    .foregroundColor(clientProfit >= 0 ? .green : .red)
                            }
                            if clientRevenue > 0 {
                                Divider()
                                let margin = Double(truncating: (clientProfit / clientRevenue * 100) as NSDecimalNumber)
                                InfoRow(label: "Margin", value: String(format: "%.1f%%", margin), icon: "percent")
                            }
                        }
                        .padding(.vertical, AppTheme.Spacing.sm)
                    }
                }

                // Projects
                GroupBox("Projects (\(clientProjects.count))") {
                    if clientProjects.isEmpty {
                        Text("No projects linked to this client.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, AppTheme.Spacing.sm)
                    } else {
                        Table(clientProjects) {
                            TableColumn("Project") { p in Text(p.title).fontWeight(.medium) }
                            TableColumn("Status") { p in
                                StatusBadge(text: p.computedStatus, color: projectStatusColor(p))
                            }.width(min: 80, max: 120)
                            TableColumn("Contract") { p in Text(p.contractAmount.currencyFormatted) }
                                .width(min: 90, max: 120)
                            TableColumn("Profit") { p in
                                Text(p.profit.currencyFormatted)
                                    .foregroundColor(p.profit >= 0 ? .green : .red)
                            }.width(min: 90, max: 120)
                        }
                        .frame(minHeight: 120)
                    }
                }

                // Bids
                GroupBox("Bids (\(clientBids.count))") {
                    if clientBids.isEmpty {
                        Text("No bids linked to this client.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, AppTheme.Spacing.sm)
                    } else {
                        Table(clientBids) {
                            TableColumn("Bid") { b in Text(b.projectName).fontWeight(.medium) }
                            TableColumn("Amount") { b in Text(b.bidAmount.currencyFormatted) }
                                .width(min: 90, max: 120)
                            TableColumn("Status") { b in
                                StatusBadge(text: b.status.rawValue, color: bidStatusColor(b))
                            }.width(min: 90, max: 120)
                            TableColumn("Due") { b in Text(b.bidDueDate.shortDate) }
                                .width(min: 90, max: 120)
                        }
                        .frame(minHeight: 120)
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .sheet(isPresented: $showEditClient) {
            EditClientView(client: client)
        }
    }

    private func projectStatusColor(_ project: Project) -> Color {
        switch project.computedStatus {
        case "Active": return AppTheme.ProjectStatus.active
        case "Upcoming": return AppTheme.ProjectStatus.upcoming
        case "Completed": return AppTheme.ProjectStatus.completed
        default: return AppTheme.ProjectStatus.onHold
        }
    }

    private func bidStatusColor(_ bid: BidProject) -> Color {
        switch bid.status {
        case .pending: return .blue; case .readyToSubmit: return .cyan
        case .submitted: return .purple; case .awarded: return .green; case .lost: return .red
        }
    }
}

// MARK: - Add Client
struct AddClientView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var contactName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var billingAddress = ""
    @State private var rateType: RateType = .generalContractor

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Client")
                    .font(AppTheme.Typography.title2)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
            }
            .padding()

            Divider()

            Form {
                Section("Client Information") {
                    TextField("Company Name", text: $name)
                    Picker("Client Type", selection: $rateType) {
                        ForEach(RateType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section("Contact Details") {
                    TextField("Contact Name", text: $contactName)
                    TextField("Email", text: $email)
                    TextField("Phone", text: $phone)
                    TextField("Billing Address", text: $billingAddress)
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 480, height: 420)
        #endif
    }

    private func save() {
        let client = Client(
            name: name, contactName: contactName,
            email: email, phone: phone,
            billingAddress: billingAddress,
            preferredRateType: rateType
        )
        dataStore.addClient(client)
        dismiss()
    }
}

// MARK: - Edit Client
struct EditClientView: View {
    let client: Client
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var contactName: String
    @State private var email: String
    @State private var phone: String
    @State private var billingAddress: String
    @State private var rateType: RateType

    init(client: Client) {
        self.client = client
        _name = State(initialValue: client.name)
        _contactName = State(initialValue: client.contactName)
        _email = State(initialValue: client.email)
        _phone = State(initialValue: client.phone)
        _billingAddress = State(initialValue: client.billingAddress)
        _rateType = State(initialValue: client.preferredRateType)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Client")
                    .font(AppTheme.Typography.title2)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
            }
            .padding()

            Divider()

            Form {
                Section("Client Information") {
                    TextField("Company Name", text: $name)
                    Picker("Client Type", selection: $rateType) {
                        ForEach(RateType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section("Contact Details") {
                    TextField("Contact Name", text: $contactName)
                    TextField("Email", text: $email)
                    TextField("Phone", text: $phone)
                    TextField("Billing Address", text: $billingAddress)
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 480, height: 420)
        #endif
    }

    private func save() {
        var updated = client
        updated.name = name
        updated.contactName = contactName
        updated.email = email
        updated.phone = phone
        updated.billingAddress = billingAddress
        updated.preferredRateType = rateType
        dataStore.updateClient(updated)
        dismiss()
    }
}
