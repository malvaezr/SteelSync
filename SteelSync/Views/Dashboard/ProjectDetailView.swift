import SwiftUI
import CloudKit

struct ProjectDetailView: View {
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedTab = "Overview"
    @State private var showEditProject = false
    @State private var showAddChangeOrder = false
    @State private var showAddPayment = false
    @State private var showAddPayroll = false
    @State private var showAddCost = false
    @State private var showAddRental = false
    @State private var rentalToClose: EquipmentRental? = nil
    @State private var showEditProgress = false

    private let tabs = ["Overview", "Change Orders", "Payments", "Payroll", "Equipment", "Costs"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            projectHeader

            Divider()

            // Tab bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabs, id: \.self) { tab in
                        Button(action: { selectedTab = tab }) {
                            Text(tab)
                                .fixedSize()
                                .font(.callout)
                                .fontWeight(selectedTab == tab ? .semibold : .regular)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedTab == tab ? AppTheme.primaryOrange.opacity(0.1) : Color.clear)
                                .foregroundColor(selectedTab == tab ? AppTheme.primaryOrange : AppTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal)
            }
            .background(AppTheme.secondaryBackground)

            Divider()

            // Tab content
            // Overview uses ScrollView; tabs with Table use direct layout
            // to avoid ScrollView/Table layout recursion on macOS
            Group {
                switch selectedTab {
                case "Overview":
                    ScrollView {
                        overviewTab
                            .padding(AppTheme.Spacing.lg)
                    }
                default:
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        switch selectedTab {
                        case "Change Orders":
                            changeOrdersTab
                        case "Payments":
                            paymentsTab
                        case "Payroll":
                            payrollTab
                        case "Equipment":
                            equipmentTab
                        case "Costs":
                            costsTab
                        default:
                            EmptyView()
                        }
                    }
                    .padding(AppTheme.Spacing.lg)
                }
            }
        }
        .sheet(isPresented: $showEditProject) {
            EditProjectView(project: project)
        }
        .sheet(isPresented: $showAddChangeOrder) {
            AddChangeOrderView(projectID: project.id, nextNumber: (dataStore.changeOrders(for: project.id).count) + 1)
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
                        Label(project.location, systemImage: "mappin.circle.fill")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                StatusBadge(text: project.computedStatus, color: statusColor)
                Button("Edit") { showEditProject = true }
                    .buttonStyle(.bordered)
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
                Table(cos) {
                    TableColumn("CO #") { co in Text("#\(co.number)").fontWeight(.medium) }
                        .width(min: 50, max: 60)
                    TableColumn("Description") { co in Text(co.description) }
                    TableColumn("Amount") { co in
                        Text(co.amount.currencyFormatted)
                            .foregroundColor(co.amount >= 0 ? .green : .red)
                    }.width(min: 80, max: 120)
                    TableColumn("Date") { co in Text(co.submittedDate.shortDate) }
                        .width(min: 90, max: 120)
                    TableColumn("Status") { co in
                        StatusBadge(text: co.isSigned ? "Signed" : "Pending",
                                    color: co.isSigned ? .green : .orange)
                    }.width(min: 80, max: 100)
                    TableColumn("PDF") { co in
                        Button {
                            PDFExportService.exportWorkOrderInvoice(
                                changeOrder: co,
                                project: project,
                                client: dataStore.client(for: project.clientRef)
                            )
                        } label: {
                            Image(systemName: "arrow.down.doc.fill")
                                .foregroundColor(AppTheme.primaryOrange)
                        }
                        .buttonStyle(.borderless)
                    }.width(min: 36, max: 40)
                }
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
                }
                .frame(minHeight: 200)

                HStack {
                    Spacer()
                    Text("Total Received: \(pmts.reduce(0) { $0 + $1.amount }.currencyFormatted)")
                        .font(.headline)
                }
            }
        }
    }

    // MARK: - Payroll Tab
    private var payrollTab: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeaderView(title: "Payroll Entries", action: { showAddPayroll = true })

            let entries = dataStore.payrollEntries(for: project.id)
            if entries.isEmpty {
                EmptyStateView(icon: "person.2.fill", title: "No Payroll Entries",
                               message: "Track labor costs by adding payroll entries.",
                               buttonTitle: "Add Payroll") { showAddPayroll = true }
                .frame(height: 200)
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
                }
                .frame(minHeight: 200)

                HStack {
                    Text("Total Hours: \(entries.reduce(0) { $0 + $1.totalHours }.decimalFormatted)")
                        .font(.callout)
                    Spacer()
                    Text("Total Labor: \(entries.reduce(0) { $0 + $1.totalAmount }.currencyFormatted)")
                        .font(.headline)
                }
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
                                TableColumn("Category") { c in Text(c.category.displayName) }
                                TableColumn("Description") { c in Text(c.description) }
                                TableColumn("Amount") { c in Text(c.amount.currencyFormatted) }
                                    .width(min: 80, max: 120)
                                TableColumn("Date") { c in Text(c.date.shortDate) }
                                    .width(min: 90, max: 120)
                            }
                            .frame(minHeight: 100)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Text("Total Costs: \(projectCosts.reduce(0) { $0 + $1.amount }.currencyFormatted)")
                        .font(.headline)
                }
            }
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
                                            .buttonStyle(.bordered)
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
