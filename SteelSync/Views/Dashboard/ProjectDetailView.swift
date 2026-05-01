import SwiftUI
import CloudKit

/// Sections within a project detail view, grouped by PM workflow instead of a
/// flat tab bar. Used by the left sidebar in `ProjectDetailView`.
enum ProjectDetailSection: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case changeOrders = "Change Orders"
    case payments = "Payments"
    case payApps = "Pay Apps"
    case costs = "Costs"
    case payroll = "Payroll"
    case equipment = "Equipment"
    case rfis = "RFIs"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .changeOrders: return "arrow.triangle.branch"
        case .payments: return "creditcard.fill"
        case .payApps: return "doc.plaintext.fill"
        case .costs: return "cart.fill"
        case .payroll: return "person.2.fill"
        case .equipment: return "shippingbox.fill"
        case .rfis: return "questionmark.bubble.fill"
        }
    }

    var group: ProjectDetailGroup {
        switch self {
        case .overview: return .overview
        case .payments, .payApps, .costs, .payroll: return .money
        case .equipment, .rfis: return .field
        case .changeOrders: return .changes
        }
    }
}

enum ProjectDetailGroup: String, CaseIterable {
    case overview = "OVERVIEW"
    case money = "MONEY"
    case field = "FIELD OPS"
    case changes = "CHANGES"

    var sections: [ProjectDetailSection] {
        ProjectDetailSection.allCases.filter { $0.group == self }
    }
}

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSection: ProjectDetailSection = .overview
    @State private var showEditProject = false
    @State private var showAddChangeOrder = false
    @State private var editingChangeOrder: ChangeOrder?
    @State private var showAddPayment = false
    @State private var showAddPayroll = false
    @State private var showAddCost = false
    @State private var showAddRental = false
    @State private var rentalToClose: EquipmentRental? = nil
    @State private var showEditProgress = false
    @State private var showQuickEntry = false
    @State private var showAddRFI = false
    @State private var editingRFI: RFI?
    @State private var costToDelete: Cost?
    @State private var editingCost: Cost?
    @State private var paymentToDelete: Payment?
    @State private var rfiToDelete: RFI?
    @State private var changeOrderToDelete: ChangeOrder?
    @State private var payrollEntryToDelete: PayrollEntry?

    var body: some View {
        VStack(spacing: 0) {
            // Header (unchanged — keeps the project-specific status/metrics/progress row)
            projectHeader

            Divider()

            // Measure actual available width so the inner sidebar collapses
            // to a compact tab picker when the parent pane gets squeezed
            // (e.g. iPad landscape with outer sidebar + project list both visible).
            GeometryReader { geo in
                adaptiveBody(availableWidth: geo.size.width)
            }
        }
        .sheet(isPresented: $showEditProject) {
            EditProjectView(project: project)
        }
        .sheet(isPresented: $showAddChangeOrder) {
            AddChangeOrderView(projectID: project.id, nextNumber: (dataStore.changeOrders(for: project.id).count) + 1)
        }
        .sheet(item: $editingChangeOrder) { co in
            EditChangeOrderSheet(changeOrder: co, projectID: project.id)
        }
        .sheet(isPresented: $showAddPayment) {
            AddPaymentView(projectID: project.id)
        }
        .sheet(isPresented: $showAddPayroll) {
            AddPayrollView(projectID: project.id)
        }
        .sheet(isPresented: $showAddCost) {
            AddCostView(projectID: project.id)
        }
        .sheet(isPresented: $showAddRental) {
            AddEquipmentRentalView(projectID: project.id)
        }
        .sheet(item: $rentalToClose) { rental in
            CloseEquipmentRentalView(projectID: project.id, rental: rental)
        }
        .sheet(isPresented: $showQuickEntry) {
            QuickEntrySheet(project: project)
        }
        .sheet(isPresented: $showAddRFI) {
            AddRFISheet(projectID: project.id, nextNumber: dataStore.nextRFINumber(for: project.id))
        }
        .sheet(item: $editingRFI) { rfi in
            EditRFISheet(rfi: rfi, projectID: project.id)
        }
        .confirmationDialog(
            "Delete RFI?",
            isPresented: Binding(
                get: { rfiToDelete != nil },
                set: { if !$0 { rfiToDelete = nil } }
            ),
            presenting: rfiToDelete
        ) { rfi in
            Button("Delete", role: .destructive) {
                dataStore.deleteRFI(rfi, from: project.id)
                rfiToDelete = nil
            }
            Button("Cancel", role: .cancel) { rfiToDelete = nil }
        } message: { rfi in
            Text("RFI #\(rfi.number) — \"\(rfi.subject)\" will be removed along with its attachments. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete change order?",
            isPresented: Binding(
                get: { changeOrderToDelete != nil },
                set: { if !$0 { changeOrderToDelete = nil } }
            ),
            presenting: changeOrderToDelete
        ) { co in
            Button("Delete", role: .destructive) {
                dataStore.deleteChangeOrder(co, from: project.id)
                changeOrderToDelete = nil
            }
            Button("Cancel", role: .cancel) { changeOrderToDelete = nil }
        } message: { co in
            Text("Change Order — \(co.description) (\(co.amount.currencyFormatted)) will be removed and the project balance will recalculate. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete payroll entry?",
            isPresented: Binding(
                get: { payrollEntryToDelete != nil },
                set: { if !$0 { payrollEntryToDelete = nil } }
            ),
            presenting: payrollEntryToDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                dataStore.deletePayrollEntry(entry, from: project.id)
                payrollEntryToDelete = nil
            }
            Button("Cancel", role: .cancel) { payrollEntryToDelete = nil }
        } message: { entry in
            Text("\(entry.weekDateRange) — \(entry.totalHours.decimalFormatted) hrs, \(entry.totalAmount.currencyFormatted) for \(entry.employeeDetails.count) employee\(entry.employeeDetails.count == 1 ? "" : "s") will be removed. This cannot be undone.")
        }
    }

    // MARK: - Adaptive Layout

    /// Picks sidebar vs compact tab layout based on the ACTUAL available width,
    /// not just horizontalSizeClass. On iPad landscape with nested split views,
    /// the size class stays `.regular` even when the inner pane has very little
    /// room, so we have to measure to know.
    @ViewBuilder
    private func adaptiveBody(availableWidth: CGFloat) -> some View {
        // Thresholds:
        //   < 640pt  → compact tab picker (too narrow for 200pt sidebar + content)
        //   640–820  → slim sidebar (160pt)
        //   820–1100 → standard sidebar (200pt)
        //   1100+    → wide sidebar (220pt)
        let isCompact: Bool = {
            if availableWidth > 0 && availableWidth < 640 { return true }
            #if os(iOS)
            if horizontalSizeClass == .compact { return true }
            #endif
            return false
        }()

        if isCompact {
            VStack(spacing: 0) {
                compactSectionPicker
                Divider()
                ScrollView {
                    sectionContent
                        .padding(AppTheme.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                projectSidebar
                    .frame(width: sidebarWidth(for: availableWidth))
                    .background(AppTheme.secondaryBackground)

                Divider()

                ScrollView {
                    sectionContent
                        .padding(AppTheme.Spacing.lg)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// Scales the inner sidebar width to the available pane width so narrow
    /// panes don't swallow content while wide panes get a proper-size sidebar.
    private func sidebarWidth(for availableWidth: CGFloat) -> CGFloat {
        if availableWidth >= 1100 { return 220 }
        if availableWidth >= 820 { return 200 }
        return 160
    }

    /// Kept for backward compatibility with any sibling code still calling it.
    /// The real decision now happens inside `adaptiveBody`.
    private var useCompactLayout: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    // MARK: - Compact Section Picker (used when sidebar is too tight)

    @ViewBuilder
    private var compactSectionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(ProjectDetailSection.allCases) { section in
                        let isSelected = selectedSection == section
                        Button {
                            selectedSection = section
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: section.icon)
                                    .font(.system(size: 11))
                                Text(section.rawValue)
                                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                if let badge = sidebarBadge(for: section), badge > 0 {
                                    Text("\(badge)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(isSelected ? AppTheme.primaryOrange.opacity(0.15) : Color.gray.opacity(0.08))
                            )
                            .foregroundColor(isSelected ? AppTheme.primaryOrange : AppTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, 8)
            }
        }
        .background(AppTheme.secondaryBackground)
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var projectSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(ProjectDetailGroup.allCases, id: \.self) { group in
                if !group.sections.isEmpty {
                    Text(group.rawValue)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 4)

                    ForEach(group.sections) { section in
                        sidebarButton(section)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func sidebarButton(_ section: ProjectDetailSection) -> some View {
        let isSelected = selectedSection == section
        Button {
            selectedSection = section
        } label: {
            HStack(spacing: 6) {
                Image(systemName: section.icon)
                    .font(.system(size: 12))
                    .frame(width: 14)
                    .foregroundColor(isSelected ? AppTheme.primaryOrange : .secondary)
                Text(section.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? AppTheme.primaryText : AppTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if let badge = sidebarBadge(for: section), badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.gray.opacity(0.15)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected
                    ? AppTheme.primaryOrange.opacity(0.12)
                    : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Returns a count to display as a sidebar badge for each section, or nil if
    /// no count is useful. Gives PMs an at-a-glance sense of what's inside each
    /// section before clicking in.
    private func sidebarBadge(for section: ProjectDetailSection) -> Int? {
        switch section {
        case .overview: return nil
        case .changeOrders: return dataStore.changeOrders(for: project.id).count
        case .payments: return dataStore.payments(for: project.id).count
        case .payApps: return dataStore.payApps(for: project.id).count
        case .costs: return dataStore.costs(for: project.id).count
        case .payroll: return dataStore.payrollEntries(for: project.id).count
        case .equipment: return dataStore.rentals(for: project.id).count
        case .rfis:
            let rfis = dataStore.rfis(for: project.id)
            let open = rfis.filter { $0.status != .closed }.count
            return open > 0 ? open : rfis.count
        }
    }

    // MARK: - Section Content

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .overview:
            overviewTab
        case .changeOrders:
            changeOrdersTab
        case .payments:
            paymentsTab
        case .payApps:
            PayAppsTab(project: project)
        case .costs:
            costsTab
        case .payroll:
            payrollTab
        case .equipment:
            equipmentTab
        case .rfis:
            rfiTab
        }
    }

    // MARK: - Header
    private var projectHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.title)
                        .font(AppTheme.Typography.title2)
                    if let gc = dataStore.gcClient(for: project) {
                        HStack(spacing: 4) {
                            Label(gc.name, systemImage: "person.fill")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            StatusBadge(text: "GC", color: AppTheme.primaryOrange)
                        }
                    }
                    if let sub = dataStore.subClient(for: project) {
                        HStack(spacing: 4) {
                            Label(sub.name, systemImage: "person.fill")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            StatusBadge(text: "Sub", color: .purple)
                        }
                    }
                    if !project.location.isEmpty {
                        Label(project.location, systemImage: AppIcons.location)
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                StatusBadge(text: project.computedStatus, color: statusColor)
                Button { showQuickEntry = true } label: {
                    Label("Quick Entry", systemImage: "bolt.fill")
                        .font(.caption)
                }
                .buttonStyle(.appSecondary)
                .tint(.yellow)
                Button("Edit") { showEditProject = true }
                    .buttonStyle(.appSecondary)
            }

            // Financial summary bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.md) {
                    financialMetric("Contract", project.contractAmount.currencyFormatted)
                    financialMetric("Revenue", project.totalRevenue.currencyFormatted)
                    financialMetric("Costs", project.totalCosts.currencyFormatted)
                    financialMetric("Profit", project.profit.currencyFormatted,
                                   color: project.profit >= 0 ? .green : .red)
                    financialMetric("Margin", String(format: "%.1f%%", project.profitMargin),
                                   color: project.profitMargin >= 0 ? .green : .red)

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing) {
                        Text("Progress")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            ProgressBar(value: project.progress)
                                .frame(width: 80)
                            Text("\(Int(project.progress * 100))%")
                                .font(.callout)
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .padding(AppTheme.Spacing.lg)
        .background(AppTheme.secondaryBackground)
    }

    private func financialMetric(_ label: String, _ value: String, color: Color = AppTheme.primaryText) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }

    private var statusColor: Color {
        switch project.computedStatus {
        case "Active": return AppTheme.ProjectStatus.active
        case "Upcoming": return AppTheme.ProjectStatus.upcoming
        case "Completed": return AppTheme.ProjectStatus.completed
        default: return AppTheme.ProjectStatus.onHold
        }
    }

    // MARK: - Overview Tab
    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            GroupBox("Project Details") {
                VStack(spacing: AppTheme.Spacing.sm) {
                    if let gc = dataStore.gcClient(for: project) {
                        InfoRow(label: "General Contractor", value: gc.name, icon: "building.2")
                        Divider()
                    }
                    if let sub = dataStore.subClient(for: project) {
                        InfoRow(label: "Subcontractor", value: sub.name, icon: "wrench.and.screwdriver")
                        Divider()
                    }
                    InfoRow(label: "Contract Amount", value: project.contractAmount.currencyFormatted, icon: "dollarsign.circle")
                    Divider()
                    if let start = project.startDate {
                        InfoRow(label: "Start Date", value: start.shortDate, icon: "calendar")
                        Divider()
                    }
                    if let end = project.endDate {
                        InfoRow(label: "End Date", value: end.shortDate, icon: "calendar.badge.clock")
                        Divider()
                    }
                    InfoRow(label: "Status", value: project.computedStatus, icon: "flag")
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            GroupBox("Financial Summary") {
                VStack(spacing: AppTheme.Spacing.sm) {
                    InfoRow(label: "Contract", value: project.contractAmount.currencyFormatted)
                    InfoRow(label: "Change Orders", value: project.balanceSummary.changeOrderTotal.currencyFormatted)
                    Divider()
                    InfoRow(label: "Total Revenue", value: project.totalRevenue.currencyFormatted)
                    Divider()
                    InfoRow(label: "Labor (Payroll)", value: project.balanceSummary.payrollTotal.currencyFormatted)
                    InfoRow(label: "Other Costs", value: project.balanceSummary.costTotal.currencyFormatted)
                    Divider()
                    InfoRow(label: "Total Costs", value: project.totalCosts.currencyFormatted)
                    Divider()
                    HStack {
                        Text("Profit").fontWeight(.semibold)
                        Spacer()
                        Text(project.profit.currencyFormatted)
                            .fontWeight(.bold)
                            .foregroundColor(project.profit >= 0 ? .green : .red)
                    }
                    HStack {
                        Text("Remaining Balance").fontWeight(.semibold)
                        Spacer()
                        Text(project.remainingBalance.currencyFormatted)
                            .fontWeight(.bold)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            if !project.notes.isEmpty {
                GroupBox("Notes") {
                    Text(project.notes)
                        .padding(.vertical, AppTheme.Spacing.sm)
                }
            }
        }
    }

    // MARK: - Change Orders Tab
    /// Computes the invoicing status for a change order by checking every pay
    /// application's line items. Status is derived, not stored — so adding a CO
    /// to a pay app and sending that pay app updates this automatically.
    private func invoicingStatus(for co: ChangeOrder) -> (label: String, color: Color) {
        let payApps = dataStore.payApps(for: project.id)
        // Find the pay app(s) that include this CO as a line item
        let containingPayApps = payApps.filter { payApp in
            payApp.lineItems.contains { $0.isChangeOrder && $0.changeOrderID == co.id }
        }
        guard let payApp = containingPayApps.first else {
            return ("Not Invoiced", .gray)
        }
        // Check the linked invoice status on the pay app
        guard let invoiceID = payApp.linkedInvoiceID,
              let invoice = dataStore.invoices(for: project.id).first(where: { $0.id == invoiceID }) else {
            return ("Pending Invoice", .orange)
        }
        if invoice.isOverdue { return ("Overdue", .red) }
        switch invoice.status {
        case .draft: return ("Pending Invoice", .orange)
        case .sent: return ("Invoiced", .blue)
        case .pendingPayment: return ("Pending Payment", .orange)
        case .partiallyPaid: return ("Partially Paid", .yellow)
        case .paid: return ("Paid", .green)
        case .overdue: return ("Overdue", .red)
        }
    }

    private var changeOrdersTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeaderView(title: "Change Orders", action: { showAddChangeOrder = true })

            let cos = dataStore.changeOrders(for: project.id)
            if cos.isEmpty {
                EmptyStateView(icon: "doc.badge.plus", title: "No Change Orders",
                               message: "Add change orders to track scope and cost changes.",
                               buttonTitle: "Add Change Order") { showAddChangeOrder = true }
                .frame(height: 200)
            } else {
                let grouped = Dictionary(grouping: cos, by: \.billedTo)
                let sortedKeys = COBilledTo.allCases.filter { grouped[$0] != nil }
                List {
                    ForEach(sortedKeys, id: \.self) { billedTo in
                        Section(header: Text("Billed to: \(billedTo.displayName)")) {
                            let sectionTotal = (grouped[billedTo] ?? []).reduce(0) { $0 + $1.amount }
                            ForEach(grouped[billedTo] ?? []) { co in
                        HStack {
                            Text("#\(co.number)")
                                .fontWeight(.medium)
                                .frame(width: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(co.description.isEmpty ? "Change Order #\(co.number)" : co.description)
                                    .font(.callout)
                                    .lineLimit(1)
                                Text(co.submittedDate.shortDate)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(co.amount.currencyFormatted)
                                .fontWeight(.semibold)
                                .foregroundColor(co.amount >= 0 ? .green : .red)
                            StatusBadge(text: co.isSigned ? "Signed" : "Pending",
                                        color: co.isSigned ? .green : .orange)
                            let invStatus = invoicingStatus(for: co)
                            StatusBadge(text: invStatus.label, color: invStatus.color)
                            Button {
                                PDFExportService.exportWorkOrderInvoice(
                                    changeOrder: co, project: project,
                                    client: dataStore.client(for: project.clientRef))
                            } label: {
                                Image(systemName: "arrow.down.doc.fill")
                                    .foregroundColor(AppTheme.primaryOrange)
                            }
                            .buttonStyle(.borderless)
                        }
                        .contextMenu {
                            Button("Edit") { editingChangeOrder = co }
                            Divider()
                            Button("Delete…", role: .destructive) {
                                changeOrderToDelete = co
                            }
                        }
                    }
                            HStack {
                                Spacer()
                                Text("Section Total: \(sectionTotal.currencyFormatted)")
                                    .font(.caption).fontWeight(.bold).foregroundColor(.green)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 200)

                HStack {
                    Spacer()
                    Text("Total: \(cos.reduce(0) { $0 + $1.amount }.currencyFormatted)")
                        .font(.headline)
                }
            }
        }
    }

    // MARK: - Payments Tab
    private var paymentsTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeaderView(title: "Payments Received", action: { showAddPayment = true })

            let pmts = dataStore.payments(for: project.id)
            if pmts.isEmpty {
                EmptyStateView(icon: "banknote", title: "No Payments",
                               message: "Record payments received from the client.",
                               buttonTitle: "Add Payment") { showAddPayment = true }
                .frame(height: 200)
            } else {
                Table(pmts) {
                    TableColumn("Date") { p in Text(p.date.shortDate) }
                        .width(min: 90, max: 120)
                    TableColumn("Amount") { p in Text(p.amount.currencyFormatted).fontWeight(.medium) }
                        .width(min: 80, max: 120)
                    TableColumn("Notes") { p in Text(p.notes).foregroundColor(.secondary) }
                    TableColumn("") { p in
                        Button {
                            paymentToDelete = p
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Delete this payment (PIN required)")
                    }
                    .width(40)
                }
                .frame(minHeight: 200)

                HStack {
                    Spacer()
                    Text("Total Received: \(pmts.reduce(0) { $0 + $1.amount }.currencyFormatted)")
                        .font(.headline)
                }
            }
        }
        .sheet(item: $paymentToDelete) { payment in
            ConfirmationPinSheet(
                title: "Delete Payment",
                detail: "\(payment.date.shortDate) — \(payment.amount.currencyFormatted)\(payment.notes.isEmpty ? "" : "\n\(payment.notes)")",
                confirmLabel: "Delete",
                onConfirm: {
                    dataStore.deletePayment(payment, from: project.id)
                }
            )
        }
    }

    // MARK: - Payroll Tab
    private var payrollTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Timesheet entries from Crew Management (auto-linked by project)
            let timesheetRows = dataStore.timesheetEntries.filter { $0.projectRef == project.id.recordName }
            if !timesheetRows.isEmpty {
                // Group by week
                let byWeek = Dictionary(grouping: timesheetRows, by: { $0.weekLabel })
                let sortedWeeks = byWeek.keys.sorted()

                SectionHeaderView(title: "Timesheet (from Crew Management)")

                List {
                    ForEach(sortedWeeks, id: \.self) { week in
                        Section(header: Text(week)) {
                            let weekEntries = byWeek[week] ?? []
                            ForEach(weekEntries) { entry in
                                HStack {
                                    Text(entry.displayName)
                                        .font(.callout)
                                    Spacer()
                                    Text("\(entry.totalHours.formatted()) hrs")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(entry.totalPay.currencyFormatted)
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.green)
                                }
                            }
                            HStack {
                                Spacer()
                                let weekHours = weekEntries.reduce(Decimal.zero) { $0 + $1.totalHours }
                                let weekPay = weekEntries.reduce(Decimal.zero) { $0 + $1.totalPay }
                                Text("Week Total: \(weekHours.formatted()) hrs — \(weekPay.currencyFormatted)")
                                    .font(.caption).fontWeight(.bold).foregroundColor(AppTheme.primaryOrange)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 150)

                let tsHours = timesheetRows.reduce(Decimal.zero) { $0 + $1.totalHours }
                let tsPay = timesheetRows.reduce(Decimal.zero) { $0 + $1.totalPay }
                HStack {
                    Text("Timesheet Total: \(tsHours.formatted()) hrs")
                        .font(.callout)
                    Spacer()
                    Text(tsPay.currencyFormatted)
                        .font(.headline).foregroundColor(.green)
                }
            }

            // Manual payroll entries (legacy/additional)
            SectionHeaderView(title: "Manual Payroll Entries", action: { showAddPayroll = true })

            let entries = dataStore.payrollEntries(for: project.id)
            if entries.isEmpty && timesheetRows.isEmpty {
                EmptyStateView(icon: "person.2.fill", title: "No Payroll Data",
                               message: "Add workers in Crew Management or create manual payroll entries.",
                               buttonTitle: "Add Payroll") { showAddPayroll = true }
                .frame(height: 200)
            } else if entries.isEmpty {
                Text("No manual payroll entries. Timesheet data is shown above.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, AppTheme.Spacing.sm)
            } else {
                Table(entries) {
                    TableColumn("Week") { e in Text(e.weekDateRange) }
                    TableColumn("Hours") { e in Text(e.totalHours.decimalFormatted) }
                        .width(min: 60, max: 80)
                    TableColumn("Amount") { e in Text(e.totalAmount.currencyFormatted).fontWeight(.medium) }
                        .width(min: 80, max: 120)
                    TableColumn("Employees") { e in Text("\(e.employeeDetails.count)") }
                        .width(min: 60, max: 80)
                    TableColumn("Notes") { e in Text(e.notes).foregroundColor(.secondary) }
                    TableColumn("") { e in
                        Button {
                            payrollEntryToDelete = e
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                        .help("Delete this payroll entry")
                    }
                    .width(40)
                }
                .frame(minHeight: 150)

                HStack {
                    Text("Manual Total: \(entries.reduce(0) { $0 + $1.totalHours }.decimalFormatted) hrs")
                        .font(.callout)
                    Spacer()
                    Text(entries.reduce(0) { $0 + $1.totalAmount }.currencyFormatted)
                        .font(.headline)
                }
            }
        }
    }

    // MARK: - RFI Tab
    private var rfiTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeaderView(title: "Requests for Information", action: { showAddRFI = true })

            let projectRFIs = dataStore.rfis(for: project.id)
            if projectRFIs.isEmpty {
                EmptyStateView(icon: "doc.text.magnifyingglass", title: "No RFIs",
                               message: "Track Requests for Information submitted to the architect or engineer.",
                               buttonTitle: "Add RFI") { showAddRFI = true }
                .frame(height: 200)
            } else {
                // Summary metrics
                let open = projectRFIs.filter { $0.status != .closed }.count
                let overdue = projectRFIs.filter { $0.isOverdue }.count

                HStack(spacing: AppTheme.Spacing.sm) {
                    MetricCard(title: "Total RFIs", value: "\(projectRFIs.count)", icon: "doc.text.fill", color: .blue)
                    MetricCard(title: "Open", value: "\(open)", icon: "circle", color: .orange)
                    if overdue > 0 {
                        MetricCard(title: "Overdue", value: "\(overdue)", icon: "exclamationmark.triangle.fill", color: .red)
                    }
                }
                .frame(height: 70)

                List {
                    ForEach(projectRFIs) { rfi in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("RFI #\(rfi.number)")
                                        .font(.caption).fontWeight(.bold)
                                    Text(rfi.subject)
                                        .font(.callout).lineLimit(1)
                                    if !rfi.attachments.isEmpty {
                                        Image(systemName: "paperclip")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(rfi.attachments.count)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                HStack(spacing: 8) {
                                    Text("To: \(rfi.submittedTo)")
                                        .font(.caption2).foregroundColor(.secondary)
                                    Text("Due: \(rfi.responseDueDate.shortDate)")
                                        .font(.caption2).foregroundColor(rfi.isOverdue ? .red : .secondary)
                                    if rfi.isOverdue {
                                        Text("OVERDUE").font(.caption2).fontWeight(.bold).foregroundColor(.red)
                                    }
                                }
                            }
                            Spacer()
                            // Open first attachment if available
                            if let firstAtt = rfi.attachments.first {
                                Button { FileStorageService.openFile(firstAtt) } label: {
                                    Image(systemName: "eye.fill").foregroundColor(.blue)
                                }
                                .buttonStyle(.borderless)
                            }
                            StatusBadge(text: rfi.status.rawValue,
                                        color: rfi.status == .closed ? .green :
                                               rfi.status == .responded ? .orange :
                                               rfi.status == .submitted ? .blue : .gray)
                            StatusBadge(text: rfi.priority.rawValue,
                                        color: rfi.priority == .urgent ? .red :
                                               rfi.priority == .high ? .orange : .secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingRFI = rfi }
                        .contextMenu {
                            Button("Edit") { editingRFI = rfi }
                            Divider()
                            Button("Delete…", role: .destructive) { rfiToDelete = rfi }
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 200)
            }
        }
    }

    // MARK: - Costs Tab
    private var costsTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeaderView(title: "Other Costs", action: { showAddCost = true })

            let projectCosts = dataStore.costs(for: project.id)
            if projectCosts.isEmpty {
                EmptyStateView(icon: "cart", title: "No Costs Recorded",
                               message: "Track equipment, materials, and other project costs.",
                               buttonTitle: "Add Cost") { showAddCost = true }
                .frame(height: 200)
            } else {
                // Group by category
                let grouped = Dictionary(grouping: projectCosts, by: { $0.category.categoryGroup })

                ForEach(Cost.CostCategoryGroup.allCases, id: \.self) { group in
                    if let items = grouped[group], !items.isEmpty {
                        GroupBox(group.rawValue) {
                            Table(items) {
                                TableColumn("Category") { c in
                                    Button { editingCost = c } label: {
                                        Text(c.category.displayName)
                                            .foregroundColor(AppTheme.primaryText)
                                    }
                                    .buttonStyle(.plain)
                                }
                                TableColumn("Description") { c in
                                    Button { editingCost = c } label: {
                                        Text(c.description)
                                            .foregroundColor(AppTheme.primaryText)
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)
                                }
                                TableColumn("Amount") { c in
                                    Button { editingCost = c } label: {
                                        Text(c.amount.currencyFormatted)
                                            .foregroundColor(AppTheme.primaryText)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .width(min: 80, max: 120)
                                TableColumn("Date") { c in
                                    Button { editingCost = c } label: {
                                        Text(c.date.shortDate)
                                            .foregroundColor(AppTheme.primaryText)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .width(min: 90, max: 120)
                                TableColumn("") { c in
                                    HStack(spacing: 8) {
                                        Button {
                                            editingCost = c
                                        } label: {
                                            Image(systemName: "pencil")
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Edit this cost")

                                        Button {
                                            costToDelete = c
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(.borderless)
                                        .help("Delete this cost")
                                    }
                                }
                                .width(70)
                            }
                            .frame(minHeight: 100)
                        }
                    }
                }

                let directCosts = projectCosts.reduce(Decimal(0)) { $0 + $1.amount }
                let allocatedOverhead = dataStore.allocateOverhead(
                    in: Date.distantPast...Date.distantFuture
                ).perProject[project.id.recordName] ?? 0

                if allocatedOverhead > 0 {
                    GroupBox("Allocated Overhead") {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: "briefcase.fill")
                                    .foregroundColor(AppTheme.primaryOrange)
                                Text("Pro-rata share of company overhead")
                                    .font(.callout)
                                Spacer()
                                Text(allocatedOverhead.currencyFormatted)
                                    .font(.callout)
                                    .fontWeight(.semibold)
                            }
                            Text("Indirect costs (rent, office, insurance) distributed by contract value. Edit in Overhead module.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Direct Costs: \(directCosts.currencyFormatted)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if allocatedOverhead > 0 {
                            Text("+ Overhead: \(allocatedOverhead.currencyFormatted)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text("Total Costs: \((directCosts + allocatedOverhead).currencyFormatted)")
                            .font(.headline)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this cost?",
            isPresented: Binding(
                get: { costToDelete != nil },
                set: { if !$0 { costToDelete = nil } }
            ),
            presenting: costToDelete
        ) { cost in
            Button("Delete", role: .destructive) {
                dataStore.deleteCost(cost, from: project.id)
                costToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                costToDelete = nil
            }
        } message: { cost in
            Text("\"\(cost.description)\" — \(cost.amount.currencyFormatted)\nThis cannot be undone.")
        }
        .sheet(item: $editingCost) { cost in
            EditCostView(cost: cost, projectID: project.id)
        }
    }

    // MARK: - Equipment Tab
    private var equipmentTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeaderView(title: "Equipment Rentals", action: { showAddRental = true })

            let allRentals = dataStore.rentals(for: project.id)
            let active = dataStore.activeRentals(for: project.id)
            let closed = dataStore.closedRentals(for: project.id)

            if allRentals.isEmpty {
                EmptyStateView(icon: "crane.fill", title: "No Equipment Rentals",
                               message: "Track rented equipment, auto-calculate costs from EDTX rate sheets.",
                               buttonTitle: "Add Rental") { showAddRental = true }
                .frame(height: 200)
            } else {
                // Active Rentals
                if !active.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                            HStack {
                                Label("Active Rentals", systemImage: "clock.fill")
                                    .font(AppTheme.Typography.headline)
                                    .foregroundColor(.green)
                                Spacer()
                            }

                            ForEach(active) { rental in
                                VStack(spacing: AppTheme.Spacing.sm) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(rental.equipmentName)
                                                .fontWeight(.semibold)
                                            Text("Since \(rental.startDate.shortDate) (\(rental.daysSinceStart) days)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text("Est. \(rental.estimatedActiveCost.currencyFormatted)")
                                                .font(.callout)
                                                .fontWeight(.semibold)
                                                .foregroundColor(AppTheme.primaryOrange)
                                            Button("Close Rental") {
                                                rentalToClose = rental
                                            }
                                            .font(.caption)
                                            .buttonStyle(.appSecondary)
                                            .tint(.green)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                if rental.id != active.last?.id {
                                    Divider()
                                }
                            }
                        }
                        .padding(.vertical, AppTheme.Spacing.sm)
                    }
                }

                // Closed Rentals
                if !closed.isEmpty {
                    GroupBox("Closed Rentals") {
                        Table(closed) {
                            TableColumn("Equipment") { r in Text(r.equipmentName).fontWeight(.medium) }
                            TableColumn("Period") { r in
                                Text("\(r.startDate.shortDate) - \(r.endDate?.shortDate ?? "")")
                                    .font(.caption)
                            }
                            TableColumn("Days") { r in Text("\(r.rentalDays ?? 0)") }
                                .width(min: 40, max: 60)
                            TableColumn("Cost") { r in
                                Text(r.totalCost?.currencyFormatted ?? "-")
                                    .fontWeight(.medium)
                            }.width(min: 80, max: 120)
                            TableColumn("Breakdown") { r in
                                Text(r.costBreakdown ?? "-")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(minHeight: 120)
                    }
                }

                // Summary
                HStack {
                    if !active.isEmpty {
                        let estActive = active.reduce(Decimal(0)) { $0 + $1.estimatedActiveCost }
                        Text("Active Est.: \(estActive.currencyFormatted)")
                            .font(.callout)
                            .foregroundColor(.orange)
                    }
                    Spacer()
                    if !closed.isEmpty {
                        let closedTotal = closed.reduce(Decimal(0)) { $0 + ($1.totalCost ?? 0) }
                        Text("Closed Total: \(closedTotal.currencyFormatted)")
                            .font(.headline)
                    }
                }
            }
        }
    }
}
