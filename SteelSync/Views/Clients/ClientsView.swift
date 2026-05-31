import SwiftUI
import CloudKit

struct ClientsView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedFilter = "All"
    @State private var searchText = ""
    @State private var showAddClient = false
    @State private var selectedClient: Client?
    @State private var clientToDelete: Client?
    @State private var showUnassigned: Bool = false

    private let filters = ["All", "GC", "Sub"]

    /// What the detail pane is showing. Derived from the two selection
    /// states (`selectedClient` / `showUnassigned`) so the compact
    /// full-screen cover and the regular detail pane render identically.
    private enum ClientDetail: Identifiable {
        case client(Client)
        case unassigned
        var id: String {
            switch self {
            case .client(let c): return "client-\(c.id.recordName)"
            case .unassigned: return "unassigned"
            }
        }
    }

    /// Current detail selection, computed from the two underlying states.
    /// Setting it back-fills both states; clearing (nil) clears both.
    private var detailSelection: Binding<ClientDetail?> {
        Binding(
            get: {
                if showUnassigned { return .unassigned }
                if let client = selectedClient { return .client(client) }
                return nil
            },
            set: { newValue in
                switch newValue {
                case .client(let c):
                    selectedClient = c
                    showUnassigned = false
                case .unassigned:
                    selectedClient = nil
                    showUnassigned = true
                case nil:
                    selectedClient = nil
                    showUnassigned = false
                }
            }
        )
    }

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
        Group {
            #if os(iOS)
            // Compact iPad (portrait full-screen, Slide Over, narrow Stage
            // Manager) is too narrow for a side-by-side list+detail — drop
            // to a list-only view that opens detail in a full-screen cover.
            // Regular width keeps the existing two-pane HStack.
            GeometryReader { proxy in
                if proxy.size.width < 800 {
                    clientListPane
                        .fullScreenCover(item: detailSelection) { detail in
                            NavigationStack {
                                clientDetailContent(for: detail)
                                    .navigationTitle(detailTitle(for: detail))
                                    .navigationBarTitleDisplayMode(.inline)
                                    .toolbar {
                                        ToolbarItem(placement: .cancellationAction) {
                                            Button("Done") { detailSelection.wrappedValue = nil }
                                        }
                                    }
                            }
                        }
                } else {
                    PlatformSplitView {
                        clientListPane
                        clientDetailPane
                    }
                }
            }
            #else
            PlatformSplitView {
                clientListPane
                clientDetailPane
            }
            #endif
        }
        .inlineForm(isPresented: $showAddClient) {
            AddClientView()
        }
        .confirmationDialog(
            "Delete client?",
            isPresented: Binding(
                get: { clientToDelete != nil },
                set: { if !$0 { clientToDelete = nil } }
            ),
            presenting: clientToDelete
        ) { client in
            Button("Delete", role: .destructive) {
                dataStore.deleteClient(client)
                if selectedClient?.id == client.id { selectedClient = nil }
                clientToDelete = nil
            }
            Button("Cancel", role: .cancel) { clientToDelete = nil }
        } message: { client in
            Text("\"\(client.name)\" will be removed. Linked projects will keep their references but may show as missing client. This cannot be undone.")
        }
        .navigationTitle("Clients")
    }

    // MARK: - Panes (factored so the body can branch on width)

    @ViewBuilder
    private var clientListPane: some View {
            // Left: Client list
            VStack(spacing: 0) {
                ScreenHeader(
                    title: "Clients",
                    subtitle: "\(dataStore.clients.count) total · \(dataStore.gcClients.count) GC · \(dataStore.subcontractorClients.count) Sub",
                    icon: AppIcons.people
                ) {
                    Button { showAddClient = true } label: {
                        Label("New Client", systemImage: AppIcons.add)
                    }
                    .buttonStyle(.appPrimary)
                }

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
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(filters, id: \.self) { filter in
                            FilterPill(filter, isSelected: selectedFilter == filter,
                                       count: countFor(filter: filter)) {
                                selectedFilter = filter
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.sm)

                // Client list
                List(selection: $selectedClient) {
                    let unassignedCount = dataStore.unassignedInvoices().count
                    if unassignedCount > 0 {
                        Section {
                            UnassignedInvoicesRow(
                                count: unassignedCount,
                                outstanding: dataStore.unassignedOutstandingBalance(),
                                isSelected: showUnassigned
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showUnassigned = true
                                selectedClient = nil
                            }
                        }
                    }

                    Section {
                        ForEach(filteredClients) { client in
                            ClientRow(client: client, projectCount: dataStore.projects(for: client).count)
                                .tag(client)
                                .contextMenu {
                                    Button("Edit") { selectedClient = client }
                                    Divider()
                                    Button("Delete…", role: .destructive) { clientToDelete = client }
                                }
                        }
                    }
                }
                .listStyle(.inset)
                .searchable(text: $searchText, prompt: "Search clients...")
                .onChange(of: selectedClient) { _, newValue in
                    if newValue != nil { showUnassigned = false }
                }
            }
            #if os(macOS)
            .frame(minWidth: 220, idealWidth: 450)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showAddClient = true }) {
                        Label("New Client", systemImage: "plus")
                    }
                }
            }
    }

    @ViewBuilder
    private var clientDetailPane: some View {
        // Right: Client detail (or unassigned invoices)
        if showUnassigned {
            UnassignedInvoicesDetailView()
                #if os(macOS)
                .frame(minWidth: 220, idealWidth: 450)
                #endif
        } else if let client = selectedClient {
            ClientDetailView(client: client)
                #if os(macOS)
                .frame(minWidth: 220, idealWidth: 450)
                #endif
        } else {
            EmptyStateView(icon: "person.2", title: "No Client Selected",
                           message: "Select a client from the list to view details.",
                           buttonTitle: "Add Client") { showAddClient = true }
            #if os(macOS)
            .frame(minWidth: 220, idealWidth: 450)
            #endif
        }
    }

    /// Detail body used inside the compact full-screen cover. Mirrors
    /// `clientDetailPane` minus the empty state (the cover only opens when
    /// something is selected).
    @ViewBuilder
    private func clientDetailContent(for detail: ClientDetail) -> some View {
        switch detail {
        case .client(let client):
            ClientDetailView(client: client)
        case .unassigned:
            UnassignedInvoicesDetailView()
        }
    }

    private func detailTitle(for detail: ClientDetail) -> String {
        switch detail {
        case .client(let client): return client.name
        case .unassigned: return "Not Assigned"
        }
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

    private var billedInvoices: [(invoice: Invoice, projectID: CKRecord.ID, projectTitle: String)] {
        dataStore.invoices(billedTo: client)
    }

    private var totalInvoicedToClient: Decimal {
        dataStore.totalInvoiced(billedTo: client)
    }

    private var totalPaidByClient: Decimal {
        dataStore.totalPaid(billedTo: client)
    }

    private var outstandingFromClient: Decimal {
        dataStore.outstandingBalance(billedTo: client)
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
                        .buttonStyle(.appSecondary)
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
                            InfoRow(label: "Address", value: client.billingAddress, icon: AppIcons.location)
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

                // Invoicing (per-client AR)
                if !billedInvoices.isEmpty {
                    GroupBox("Invoicing") {
                        VStack(spacing: AppTheme.Spacing.sm) {
                            InfoRow(label: "Invoices Billed", value: "\(billedInvoices.count)", icon: "doc.text")
                            Divider()
                            InfoRow(label: "Total Invoiced", value: totalInvoicedToClient.currencyFormatted, icon: "dollarsign.circle")
                            Divider()
                            InfoRow(label: "Paid", value: totalPaidByClient.currencyFormatted, icon: "checkmark.circle")
                            Divider()
                            HStack {
                                Image(systemName: "clock")
                                    .foregroundColor(.secondary)
                                    .frame(width: 20)
                                Text("Outstanding")
                                    .foregroundColor(AppTheme.secondaryText)
                                Spacer()
                                Text(outstandingFromClient.currencyFormatted)
                                    .fontWeight(.bold)
                                    .foregroundColor(outstandingFromClient > 0 ? .orange : .green)
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
        case .pending: return .blue; case .workingOn: return .yellow; case .readyToSubmit: return .cyan
        case .submitted: return .purple; case .awarded: return .green; case .lost: return .red
        }
    }
}

// MARK: - Add Client
struct AddClientView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var name = ""
    @State private var contactName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var billingAddress = ""
    @State private var rateType: RateType = .generalContractor

    var body: some View {
        EntryFormScaffold(
            title: "New Client",
            icon: AppIcons.people,
            saveDisabled: name.isEmpty,
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Client Information", systemImage: AppIcons.building) {
                LabeledField(label: "Company Name") {
                    TextField("Company name", text: $name)
                        .textFieldStyle(.appField)
                }
                LabeledField(label: "Client Type") {
                    Picker("", selection: $rateType) {
                        ForEach(RateType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .appControlSurface()
                }
            }

            EntrySection("Contact Details", systemImage: AppIcons.person) {
                LabeledField(label: "Contact Name") {
                    TextField("Primary contact", text: $contactName)
                        .textFieldStyle(.appField)
                }
                LabeledField(label: "Email") {
                    TextField("name@example.com", text: $email)
                        .textFieldStyle(.appField)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                }
                LabeledField(label: "Phone") {
                    TextField("(555) 555-5555", text: $phone)
                        .textFieldStyle(.appField)
                        #if !os(macOS)
                        .keyboardType(.phonePad)
                        #endif
                }
                LabeledField(label: "Billing Address") {
                    TextField("Street, City, ST", text: $billingAddress)
                        .textFieldStyle(.appField)
                }
            }
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func save() {
        let client = Client(
            name: name, contactName: contactName,
            email: email, phone: phone,
            billingAddress: billingAddress,
            preferredRateType: rateType
        )
        dataStore.addClient(client)
        closeForm()
    }
}

// MARK: - Edit Client
struct EditClientView: View {
    let client: Client
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

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
        EntryFormScaffold(
            title: "Edit Client",
            icon: AppIcons.people,
            saveDisabled: name.isEmpty,
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Client Information", systemImage: AppIcons.building) {
                LabeledField(label: "Company Name") {
                    TextField("Company name", text: $name)
                        .textFieldStyle(.appField)
                }
                LabeledField(label: "Client Type") {
                    Picker("", selection: $rateType) {
                        ForEach(RateType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .appControlSurface()
                }
            }

            EntrySection("Contact Details", systemImage: AppIcons.person) {
                LabeledField(label: "Contact Name") {
                    TextField("Primary contact", text: $contactName)
                        .textFieldStyle(.appField)
                }
                LabeledField(label: "Email") {
                    TextField("name@example.com", text: $email)
                        .textFieldStyle(.appField)
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                }
                LabeledField(label: "Phone") {
                    TextField("(555) 555-5555", text: $phone)
                        .textFieldStyle(.appField)
                        #if !os(macOS)
                        .keyboardType(.phonePad)
                        #endif
                }
                LabeledField(label: "Billing Address") {
                    TextField("Street, City, ST", text: $billingAddress)
                        .textFieldStyle(.appField)
                }
            }
        }
        #if os(macOS)
        .frame(width: 580, height: 620)
        #endif
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func save() {
        var updated = client
        updated.name = name
        updated.contactName = contactName
        updated.email = email
        updated.phone = phone
        updated.billingAddress = billingAddress
        updated.preferredRateType = rateType
        dataStore.updateClient(updated)
        closeForm()
    }
}

// MARK: - Unassigned Invoices Row (pinned at top of client list)

struct UnassignedInvoicesRow: View {
    let count: Int
    let outstanding: Decimal
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Image(systemName: "questionmark.folder")
                .font(.title3)
                .foregroundColor(.orange)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Not Assigned")
                    .font(.headline)
                Text("\(count) invoice\(count == 1 ? "" : "s") with no client linked")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Outstanding")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(outstanding.currencyFormatted)
                    .font(.callout.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundColor(outstanding > 0 ? .orange : .green)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? AppTheme.primaryOrange.opacity(0.12) : Color.clear)
        )
    }
}

// MARK: - Unassigned Invoices Detail

struct UnassignedInvoicesDetailView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var assigningEntry: AssignmentContext?

    struct AssignmentContext: Identifiable {
        let invoice: Invoice
        let projectID: CKRecord.ID
        var id: UUID { invoice.id }
    }

    private var entries: [(invoice: Invoice, projectID: CKRecord.ID, projectTitle: String)] {
        dataStore.unassignedInvoices()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not Assigned")
                            .font(AppTheme.Typography.title2)
                        StatusBadge(text: "Legacy / Unmapped", color: .orange)
                    }
                    Spacer()
                }

                Text("These invoices were created before per-client billing tracking was added, or had no client linked at the time. Assign each to a client to include it in that client's balance.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                GroupBox("Totals") {
                    VStack(spacing: AppTheme.Spacing.sm) {
                        InfoRow(label: "Invoices", value: "\(entries.count)", icon: "doc.text")
                        Divider()
                        InfoRow(label: "Total Invoiced", value: dataStore.totalUnassignedInvoiced().currencyFormatted, icon: "dollarsign.circle")
                        Divider()
                        InfoRow(label: "Paid", value: dataStore.totalUnassignedPaid().currencyFormatted, icon: "checkmark.circle")
                        Divider()
                        HStack {
                            Image(systemName: "clock")
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            Text("Outstanding")
                                .foregroundColor(AppTheme.secondaryText)
                            Spacer()
                            Text(dataStore.unassignedOutstandingBalance().currencyFormatted)
                                .fontWeight(.bold)
                                .foregroundColor(dataStore.unassignedOutstandingBalance() > 0 ? .orange : .green)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                GroupBox("Invoices (\(entries.count))") {
                    if entries.isEmpty {
                        Text("Nothing here — every invoice has a client.")
                            .foregroundColor(.secondary)
                            .padding(.vertical, AppTheme.Spacing.sm)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.invoice.id) { index, entry in
                                HStack(spacing: AppTheme.Spacing.md) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.invoice.invoiceNumber)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        Text(entry.projectTitle)
                                            .font(.callout)
                                            .fontWeight(.semibold)
                                            .lineLimit(1)
                                        if let sent = entry.invoice.sentDate {
                                            Text("Sent \(sent.shortDate)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text("Net Due")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text(entry.invoice.netAmountDue.currencyFormatted)
                                            .font(.callout.monospacedDigit())
                                            .fontWeight(.medium)
                                    }
                                    Button("Assign…") {
                                        assigningEntry = AssignmentContext(invoice: entry.invoice, projectID: entry.projectID)
                                    }
                                    .buttonStyle(.appSecondary)
                                }
                                .padding(.vertical, AppTheme.Spacing.sm)
                                if index < entries.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .sheet(item: $assigningEntry) { ctx in
            AssignBillToSheet(invoice: ctx.invoice, projectID: ctx.projectID)
        }
    }
}

// MARK: - Assign Bill-To Sheet

struct AssignBillToSheet: View {
    let invoice: Invoice
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClientID: String = ""

    private var project: Project? {
        dataStore.projects.first { $0.id == projectID }
    }

    private var candidates: [Client] {
        if let project = project {
            let projectCandidates = dataStore.billToCandidates(for: project)
            if !projectCandidates.isEmpty { return projectCandidates }
        }
        return dataStore.clients.sorted { $0.name < $1.name }
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Assign Bill-To",
                saveTitle: "Save",
                saveDisabled: selectedClientID.isEmpty,
                onCancel: { dismiss() },
                onSave: save
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        SectionTitle(text: "Invoice")
                        VStack(spacing: AppTheme.Spacing.sm) {
                            InfoRow(label: "Number", value: invoice.invoiceNumber)
                            InfoRow(label: "Project", value: project?.title ?? "Unknown")
                            InfoRow(label: "Net Due", value: invoice.netAmountDue.currencyFormatted)
                        }
                        .padding(AppTheme.Spacing.md)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppTheme.secondaryBackground)
                        )
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        SectionTitle(text: "Assign To")
                        if candidates.isEmpty {
                            Text("No clients exist yet. Add a client first.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            LabeledField(label: "Bill To") {
                                Picker("", selection: $selectedClientID) {
                                    Text("— Select —").tag("")
                                    ForEach(candidates, id: \.id.recordName) { c in
                                        Text(c.name).tag(c.id.recordName)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .appControlSurface()
                            }
                        }
                        Text("Linked clients on the invoice's project appear first. Pick any client to attribute this invoice to them in AR.")
                            .font(.caption)
                            .foregroundColor(AppTheme.tertiaryText)
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 500, height: 480)
        #endif
    }

    private func save() {
        guard let chosen = candidates.first(where: { $0.id.recordName == selectedClientID }) else { return }
        var updated = invoice
        updated.billToClientID = chosen.id.recordName
        if updated.clientName.isEmpty { updated.clientName = chosen.name }
        dataStore.updateInvoice(updated, in: projectID)
        dismiss()
    }
}
