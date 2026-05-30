import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ReportsView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedReport = "Overview"

    private let reports = ["Overview", "Projects", "Bidding", "Clients", "Financial", "Job Costing", "Bonuses", "Overhead", "1099 Summary"]
    @State private var selectedJobCostProject: Project?
    @State private var selected1099Year: Int = Calendar.current.component(.year, from: Date())
    @State private var overheadRangePreset: OverheadRangePreset = .thisYear

    // Bonus-report state.
    @State private var bonusYear: Int = Calendar.current.component(.year, from: Date())
    @State private var bonusBasis: BonusBasis = .revenue
    @State private var bonusMultiplier: Double = 2.0  // percent

    var body: some View {
        VStack(spacing: 0) {
            // Report selector
            HStack(spacing: AppTheme.Spacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(reports, id: \.self) { report in
                            FilterPill(report, isSelected: selectedReport == report) {
                                selectedReport = report
                            }
                        }
                    }
                }
                Spacer()

                Button(action: exportCSV) {
                    Label("Export CSV", systemImage: "tablecells")
                }
                .buttonStyle(.appSecondary)

                Button(action: exportPDF) {
                    Label("Export PDF", systemImage: "doc.richtext")
                }
                .buttonStyle(.appSecondary)
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.secondaryBackground)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    switch selectedReport {
                    case "Overview":
                        overviewReport
                    case "Projects":
                        projectsReport
                    case "Bidding":
                        biddingReport
                    case "Clients":
                        clientsReport
                    case "Financial":
                        financialReport
                    case "Job Costing":
                        jobCostingReport
                    case "Bonuses":
                        bonusesReport
                    case "Overhead":
                        overheadReport
                    case "1099 Summary":
                        contractor1099Report
                    default:
                        EmptyView()
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
        }
        .navigationTitle("Reports")
    }

    // MARK: - Overview
    private var overviewReport: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Business Overview")
                .font(AppTheme.Typography.title2)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: AppTheme.Spacing.md) {
                MetricCard(title: "Bid Pipeline", value: dataStore.totalBidPipeline.currencyFormatted, icon: "chart.bar.fill", color: .blue)
                MetricCard(title: "Win Rate", value: String(format: "%.0f%%", dataStore.bidWinRate), icon: "trophy.fill", color: .green)
                MetricCard(title: "Active Projects", value: "\(dataStore.activeProjects.count)", icon: "hammer.fill", color: AppTheme.primaryOrange)
                MetricCard(title: "Total Contract Value", value: dataStore.totalContractValue.currencyFormatted, icon: "building.2.fill", color: .purple)
                MetricCard(title: "Total Revenue", value: dataStore.totalRevenue.currencyFormatted, icon: "dollarsign.circle.fill", color: .green)
                MetricCard(title: "Total Profit", value: dataStore.totalProfit.currencyFormatted, icon: "chart.line.uptrend.xyaxis",
                           color: dataStore.totalProfit >= 0 ? .green : .red)
                MetricCard(title: "Total Costs", value: dataStore.totalCosts.currencyFormatted, icon: "cart.fill", color: .orange)
                MetricCard(title: "Remaining Balance", value: dataStore.totalRemainingBalance.currencyFormatted, icon: "banknote.fill", color: .blue)
            }

            GroupBox("Workforce") {
                HStack(spacing: AppTheme.Spacing.xl) {
                    InfoRow(label: "Total Employees", value: "\(dataStore.employees.count)", icon: "person.2.fill")
                    InfoRow(label: "Active", value: "\(dataStore.activeEmployees.count)", icon: "checkmark.circle")
                    InfoRow(label: "Foremen", value: "\(dataStore.foremen.count)", icon: "person.fill.checkmark")
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            GroupBox("Clients") {
                HStack(spacing: AppTheme.Spacing.xl) {
                    InfoRow(label: "Total Clients", value: "\(dataStore.clients.count)", icon: "person.2.fill")
                    InfoRow(label: "General Contractors", value: "\(dataStore.gcClients.count)", icon: "building.2.fill")
                    InfoRow(label: "Subcontractors", value: "\(dataStore.subcontractorClients.count)", icon: "wrench.and.screwdriver.fill")
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            GroupBox("Tasks") {
                HStack(spacing: AppTheme.Spacing.xl) {
                    InfoRow(label: "Active Tasks", value: "\(dataStore.activeTodos.count)", icon: "checklist")
                    InfoRow(label: "Overdue", value: "\(dataStore.overdueTodos.count)", icon: "exclamationmark.triangle")
                    InfoRow(label: "Upcoming Events", value: "\(dataStore.upcomingEvents.count)", icon: "calendar")
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }
        }
    }

    // MARK: - Projects Report
    private var projectsReport: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Project Performance")
                .font(AppTheme.Typography.title2)

            Table(dataStore.projects) {
                TableColumn("Project") { p in Text(p.title).fontWeight(.medium) }
                TableColumn("Client") { p in
                    Text(dataStore.clientName(for: p) ?? "-")
                        .foregroundColor(.secondary)
                }
                TableColumn("Type") { p in
                    if let client = dataStore.client(for: p.clientRef) {
                        StatusBadge(text: client.preferredRateType == .generalContractor ? "GC" : "Sub",
                                    color: client.preferredRateType == .generalContractor ? AppTheme.primaryOrange : .purple)
                    } else {
                        Text("-").foregroundColor(.secondary)
                    }
                }.width(min: 50, max: 70)
                TableColumn("Status") { p in StatusBadge(text: p.computedStatus, color: statusColor(p)) }
                    .width(min: 80, max: 120)
                TableColumn("Contract") { p in Text(p.contractAmount.currencyFormatted) }
                    .width(min: 90, max: 120)
                TableColumn("Revenue") { p in Text(p.totalRevenue.currencyFormatted) }
                    .width(min: 90, max: 120)
                TableColumn("Profit") { p in
                    Text(p.profit.currencyFormatted)
                        .foregroundColor(p.profit >= 0 ? .green : .red)
                }.width(min: 90, max: 120)
                TableColumn("Margin") { p in Text(String(format: "%.1f%%", p.profitMargin)) }
                    .width(min: 60, max: 80)
            }
            .frame(minHeight: 300)
        }
    }

    // MARK: - Bidding Report
    private var biddingReport: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Bid Pipeline Analysis")
                .font(AppTheme.Typography.title2)

            HStack(spacing: AppTheme.Spacing.md) {
                MetricCard(title: "Total Bids", value: "\(dataStore.bids.count)", icon: "doc.text.fill", color: .blue)
                MetricCard(title: "Pipeline Value", value: dataStore.totalBidPipeline.currencyFormatted, icon: "chart.bar.fill", color: AppTheme.primaryOrange)
                MetricCard(title: "Win Rate", value: String(format: "%.0f%%", dataStore.bidWinRate), icon: "trophy.fill", color: .green)
                MetricCard(title: "Avg Bid Size", value: {
                    let avg = dataStore.bids.isEmpty ? Decimal(0) : dataStore.bids.reduce(0) { $0 + $1.bidAmount } / Decimal(dataStore.bids.count)
                    return avg.currencyFormatted
                }(), icon: "equal.circle.fill", color: .purple)
            }

            Table(dataStore.bids.sorted { $0.bidDueDate < $1.bidDueDate }) {
                TableColumn("Project") { b in Text(b.projectName).fontWeight(.medium) }
                TableColumn("Client") { b in Text(b.clientName) }
                TableColumn("Type") { b in
                    if let client = dataStore.client(for: b.clientRef) {
                        StatusBadge(text: client.preferredRateType == .generalContractor ? "GC" : "Sub",
                                    color: client.preferredRateType == .generalContractor ? AppTheme.primaryOrange : .purple)
                    } else {
                        Text("-").foregroundColor(.secondary)
                    }
                }.width(min: 50, max: 70)
                TableColumn("Amount") { b in Text(b.bidAmount.currencyFormatted) }
                    .width(min: 90, max: 120)
                TableColumn("Due") { b in Text(b.bidDueDate.shortDate) }
                    .width(min: 90, max: 120)
                TableColumn("Status") { b in
                    StatusBadge(text: b.status.rawValue, color: bidStatusColor(b))
                }.width(min: 90, max: 120)
            }
            .frame(minHeight: 250)
        }
    }

    // MARK: - Clients Report
    private var clientsReport: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Client Analysis")
                .font(AppTheme.Typography.title2)

            HStack(spacing: AppTheme.Spacing.md) {
                MetricCard(title: "General Contractors", value: "\(dataStore.gcClients.count)",
                           icon: "building.2.fill", color: AppTheme.primaryOrange)
                MetricCard(title: "Subcontractors", value: "\(dataStore.subcontractorClients.count)",
                           icon: "wrench.and.screwdriver.fill", color: .purple)
                MetricCard(title: "Total Clients", value: "\(dataStore.clients.count)",
                           icon: "person.2.fill", color: .blue)
            }

            GroupBox("Revenue by Client Type") {
                VStack(spacing: AppTheme.Spacing.md) {
                    clientTypeRow(.generalContractor)
                    Divider()
                    clientTypeRow(.subcontractor)
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            GroupBox("Client Performance") {
                Table(dataStore.clients.sorted { $0.name < $1.name }) {
                    TableColumn("Client") { c in Text(c.name).fontWeight(.medium) }
                    TableColumn("Type") { c in
                        StatusBadge(text: c.preferredRateType == .generalContractor ? "GC" : "Sub",
                                    color: c.preferredRateType == .generalContractor ? AppTheme.primaryOrange : .purple)
                    }.width(min: 60, max: 80)
                    TableColumn("Projects") { c in Text("\(dataStore.projects(for: c).count)") }
                        .width(min: 60, max: 80)
                    TableColumn("Bids") { c in Text("\(dataStore.bids(for: c).count)") }
                        .width(min: 50, max: 70)
                    TableColumn("Revenue") { c in
                        Text(dataStore.projects(for: c).reduce(Decimal(0)) { $0 + $1.totalRevenue }.currencyFormatted)
                    }.width(min: 90, max: 120)
                    TableColumn("Profit") { c in
                        let profit = dataStore.projects(for: c).reduce(Decimal(0)) { $0 + $1.profit }
                        Text(profit.currencyFormatted).foregroundColor(profit >= 0 ? .green : .red)
                    }.width(min: 90, max: 120)
                    TableColumn("Margin") { c in
                        let projects = dataStore.projects(for: c)
                        let rev = projects.reduce(Decimal(0)) { $0 + $1.totalRevenue }
                        let prof = projects.reduce(Decimal(0)) { $0 + $1.profit }
                        let margin = rev > 0 ? Double(truncating: (prof / rev * 100) as NSDecimalNumber) : 0
                        Text(String(format: "%.1f%%", margin))
                    }.width(min: 60, max: 80)
                }
                .frame(minHeight: 250)
            }
        }
    }

    private func clientTypeRow(_ type: RateType) -> some View {
        let typeClients = dataStore.clients.filter { $0.preferredRateType == type }
        let typeProjects = typeClients.flatMap { dataStore.projects(for: $0) }
        let revenue = typeProjects.reduce(Decimal(0)) { $0 + $1.totalRevenue }
        let profit = typeProjects.reduce(Decimal(0)) { $0 + $1.profit }
        let costs = typeProjects.reduce(Decimal(0)) { $0 + $1.totalCosts }

        return HStack {
            StatusBadge(text: type.displayName,
                        color: type == .generalContractor ? AppTheme.primaryOrange : .purple)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Revenue: \(revenue.currencyFormatted)").font(.callout).fontWeight(.medium)
                HStack(spacing: AppTheme.Spacing.md) {
                    Text("Costs: \(costs.currencyFormatted)").font(.caption).foregroundColor(.secondary)
                    Text("Profit: \(profit.currencyFormatted)").font(.caption)
                        .foregroundColor(profit >= 0 ? .green : .red)
                }
            }
            Text("\(typeProjects.count) projects")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
    }

    // MARK: - Financial Report
    private var financialReport: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Financial Summary")
                .font(AppTheme.Typography.title2)

            let summary = dataStore.financialSummary

            GroupBox("Profit & Loss") {
                VStack(spacing: AppTheme.Spacing.md) {
                    HStack {
                        Text("Total Revenue").font(.headline)
                        Spacer()
                        Text(summary.revenue.currencyFormatted).font(.title3).fontWeight(.bold).foregroundColor(.green)
                    }
                    Divider()
                    HStack {
                        Text("Total Costs").font(.headline)
                        Spacer()
                        Text(summary.costs.currencyFormatted).font(.title3).fontWeight(.bold).foregroundColor(.red)
                    }
                    Divider()
                    HStack {
                        Text("Net Profit").font(.title3).fontWeight(.bold)
                        Spacer()
                        Text(summary.profit.currencyFormatted)
                            .font(.title2).fontWeight(.bold)
                            .foregroundColor(summary.profit >= 0 ? .green : .red)
                    }
                    HStack {
                        Text("Overall Margin")
                        Spacer()
                        Text(String(format: "%.1f%%", summary.margin))
                            .fontWeight(.semibold)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            GroupBox("Per-Project Breakdown") {
                Table(dataStore.projects.filter { $0.computedStatus == "Active" || $0.computedStatus == "Completed" }) {
                    TableColumn("Project") { p in Text(p.title) }
                    TableColumn("Client") { p in
                        Text(dataStore.clientName(for: p) ?? "-").foregroundColor(.secondary)
                    }
                    TableColumn("Revenue") { p in Text(p.totalRevenue.currencyFormatted) }.width(min: 90, max: 120)
                    TableColumn("Costs") { p in Text(p.totalCosts.currencyFormatted) }.width(min: 90, max: 120)
                    TableColumn("Profit") { p in
                        Text(p.profit.currencyFormatted).foregroundColor(p.profit >= 0 ? .green : .red)
                    }.width(min: 90, max: 120)
                    TableColumn("Margin") { p in Text(String(format: "%.1f%%", p.profitMargin)) }.width(min: 60, max: 80)
                }
                .frame(minHeight: 200)
            }
        }
    }

    // MARK: - Job Costing Report

    private var jobCostingReport: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text("Job Costing Report").font(AppTheme.Typography.headline)
                Spacer()
                Picker("Project", selection: $selectedJobCostProject) {
                    Text("All Projects").tag(nil as Project?)
                    ForEach(dataStore.projects) { p in
                        Text(p.title).tag(p as Project?)
                    }
                }
                .frame(maxWidth: 250)
            }

            let projectsToShow = selectedJobCostProject.map { [$0] } ?? dataStore.projects
            // Allocate overhead once across all time — each project picks up
            // its own pro-rata share for expenses that happened while it was
            // active. Hoisted out of the ForEach so we don't recompute per row.
            let overheadAllocation = dataStore.allocateOverhead(in: Date.distantPast...Date.distantFuture).perProject

            ForEach(projectsToShow) { project in
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text(project.title).font(.headline)

                        let costs = dataStore.costs(for: project.id)
                        let payroll = dataStore.payrollEntries(for: project.id)
                        let timesheets = dataStore.timesheetEntries.filter { $0.projectRef == project.id.recordName }

                        let payrollTotal = payroll.reduce(Decimal.zero) { $0 + $1.totalAmount }
                        let timesheetTotal = timesheets.reduce(Decimal.zero) { $0 + $1.totalPay }
                        let costTotal = costs.reduce(Decimal.zero) { $0 + $1.amount }
                        let projectOverhead = overheadAllocation[project.id.recordName] ?? 0
                        let grandTotal = payrollTotal + timesheetTotal + costTotal + projectOverhead

                        // Labor section
                        if payrollTotal + timesheetTotal > 0 {
                            jobCostRow("Labor (Payroll)", code: Cost.LaborCostCode.payroll, amount: payrollTotal, total: grandTotal)
                            jobCostRow("Labor (Timesheet)", code: Cost.LaborCostCode.timesheet, amount: timesheetTotal, total: grandTotal)
                        }

                        // Costs by category
                        ForEach(Cost.CostCategory.allCases, id: \.self) { cat in
                            let catCosts = costs.filter { $0.category == cat }
                            let catTotal = catCosts.reduce(Decimal.zero) { $0 + $1.amount }
                            if catTotal > 0 {
                                jobCostRow(cat.displayName, code: cat.costCode, amount: catTotal, total: grandTotal)
                            }
                        }

                        if projectOverhead > 0 {
                            jobCostRow("Allocated Overhead", code: "OVHD",
                                       amount: projectOverhead, total: grandTotal)
                        }

                        Divider()
                        HStack {
                            Text("TOTAL COSTS").font(.caption).fontWeight(.bold)
                            Spacer()
                            Text(grandTotal.currencyFormatted).font(.caption).fontWeight(.bold)
                        }
                        HStack {
                            Text("Revenue").font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text(project.totalRevenue.currencyFormatted).font(.caption)
                        }
                        HStack {
                            Text("Profit (after overhead)").font(.caption).fontWeight(.bold)
                            Spacer()
                            Text((project.totalRevenue - grandTotal).currencyFormatted)
                                .font(.caption).fontWeight(.bold)
                                .foregroundColor((project.totalRevenue - grandTotal) >= 0 ? .green : .red)
                        }
                    }
                }
            }

            if projectsToShow.isEmpty {
                EmptyStateView(icon: "chart.bar.doc.horizontal", title: "No Projects",
                               message: "Select a project or add costs to see the job costing breakdown.")
            }
        }
    }

    // MARK: - Overhead

    private var overheadReport: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text("Overhead / Company P&L").font(AppTheme.Typography.headline)
                Spacer()
                Picker("Range", selection: $overheadRangePreset) {
                    ForEach(OverheadRangePreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .frame(maxWidth: 180)
            }

            let range = overheadRangePreset.range()
            let allocation = dataStore.allocateOverhead(in: range)
            let byCategory = dataStore.overheadByCategory(in: range)
            let entries = dataStore.overheadEntries(in: range)

            // Summary metrics
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: AppTheme.Spacing.md) {
                MetricCard(
                    title: "\(overheadRangePreset.rawValue) Total",
                    value: allocation.total.currencyFormatted,
                    icon: "sum", color: AppTheme.primaryOrange
                )
                MetricCard(
                    title: "Entries",
                    value: "\(entries.count)",
                    icon: "list.bullet.rectangle", color: .blue
                )
                MetricCard(
                    title: "Recurring Templates",
                    value: "\(dataStore.overheadRecurringTemplates.count)",
                    icon: "repeat", color: .purple
                )
                MetricCard(
                    title: "Distributed to Projects",
                    value: allocation.perProject.values.reduce(Decimal.zero, +).currencyFormatted,
                    icon: "arrow.triangle.branch", color: .green
                )
            }

            // Category breakdown
            GroupBox {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Breakdown by Category")
                        .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                    if byCategory.isEmpty {
                        Text("No overhead entries in this range.")
                            .font(.caption).foregroundColor(.secondary)
                            .padding(.vertical, AppTheme.Spacing.sm)
                    } else {
                        ForEach(byCategory, id: \.0) { cat, amount in
                            HStack {
                                Image(systemName: cat.icon)
                                    .font(.caption)
                                    .foregroundColor(AppTheme.primaryOrange)
                                    .frame(width: 18)
                                Text(cat.rawValue).font(.caption)
                                Spacer()
                                Text(pct(amount, of: allocation.total))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 55, alignment: .trailing)
                                Text(amount.currencyFormatted)
                                    .font(.caption).fontWeight(.medium)
                                    .frame(width: 100, alignment: .trailing)
                            }
                        }
                    }
                }
            }

            // Per-project allocation
            GroupBox {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Distributed to Projects (Pro-Rata by Contract)")
                        .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                    if allocation.perProject.isEmpty {
                        Text("No project distributions in this range.")
                            .font(.caption).foregroundColor(.secondary)
                            .padding(.vertical, AppTheme.Spacing.sm)
                    } else {
                        let sorted = allocation.perProject.sorted { $0.value > $1.value }
                        ForEach(sorted, id: \.key) { recordName, amount in
                            HStack {
                                Text(projectTitle(for: recordName))
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(pct(amount, of: allocation.perProject.values.reduce(Decimal.zero, +)))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .frame(width: 55, alignment: .trailing)
                                Text(amount.currencyFormatted)
                                    .font(.caption).fontWeight(.medium)
                                    .frame(width: 100, alignment: .trailing)
                            }
                        }
                        Divider()
                        HStack {
                            Text("Company-only (not distributed)")
                                .font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            Text((allocation.total - allocation.perProject.values.reduce(Decimal.zero, +)).currencyFormatted)
                                .font(.caption2).foregroundColor(.secondary)
                                .frame(width: 100, alignment: .trailing)
                        }
                    }
                }
            }

            // Company P&L roll-up
            companyPnLCard(range: range, overheadTotal: allocation.total)
        }
    }

    @ViewBuilder
    private func companyPnLCard(range: ClosedRange<Date>, overheadTotal: Decimal) -> some View {
        let revenue = dataStore.projects.reduce(Decimal.zero) { $0 + $1.totalRevenue }
        let projectCosts = dataStore.projects.reduce(Decimal.zero) { $0 + $1.totalCosts }
        let grossProfit = revenue - projectCosts
        let netProfit = grossProfit - overheadTotal
        let netMargin = revenue > 0 ? Double(truncating: (netProfit / revenue * 100) as NSDecimalNumber) : 0

        GroupBox {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Company P&L — \(overheadRangePreset.rawValue)")
                    .font(.caption).fontWeight(.bold).foregroundColor(.secondary)
                Text("Lifetime project revenue/costs; overhead scoped to selected range.")
                    .font(.caption2).foregroundColor(AppTheme.tertiaryText)

                pnLRow(label: "Revenue (all projects)", value: revenue)
                pnLRow(label: "Project costs", value: -projectCosts)
                Divider()
                pnLRow(label: "Gross profit", value: grossProfit, emphasize: true)
                pnLRow(label: "Overhead (\(overheadRangePreset.rawValue.lowercased()))", value: -overheadTotal)
                Divider()
                pnLRow(label: "Net profit", value: netProfit, emphasize: true,
                       tint: netProfit >= 0 ? .green : .red)
                HStack {
                    Text("Net margin").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", netMargin))
                        .font(.caption).fontWeight(.medium)
                        .foregroundColor(netMargin >= 0 ? .green : .red)
                }
            }
        }
    }

    private func pnLRow(label: String, value: Decimal, emphasize: Bool = false, tint: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .fontWeight(emphasize ? .bold : .regular)
                .foregroundColor(emphasize ? .primary : .secondary)
            Spacer()
            Text(value.currencyFormatted)
                .font(.caption)
                .fontWeight(emphasize ? .bold : .medium)
                .foregroundColor(tint ?? (emphasize ? .primary : .primary))
        }
    }

    private func projectTitle(for recordName: String) -> String {
        dataStore.projects.first { $0.id.recordName == recordName }?.title ?? recordName
    }

    private func jobCostRow(_ label: String, code: String, amount: Decimal, total: Decimal) -> some View {
        let pct = total > 0 ? Double(truncating: (amount / total * 100) as NSDecimalNumber) : 0
        return HStack {
            Text(code).font(.caption2).fontWeight(.medium).foregroundColor(.secondary).frame(width: 50, alignment: .leading)
            Text(label).font(.caption)
            Spacer()
            Text(String(format: "%.1f%%", pct)).font(.caption2).foregroundColor(.secondary).frame(width: 45, alignment: .trailing)
            Text(amount.currencyFormatted).font(.caption).fontWeight(.medium).frame(width: 90, alignment: .trailing)
        }
    }

    // MARK: - 1099 Contractor Summary

    private var contractor1099Report: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                Text("1099-NEC Contractor Summary").font(AppTheme.Typography.headline)
                Spacer()
                Picker("Tax Year", selection: $selected1099Year) {
                    ForEach((2024...Calendar.current.component(.year, from: Date())).reversed(), id: \.self) { year in
                        Text(String(year)).tag(year)
                    }
                }
                .frame(maxWidth: 120)
            }

            let payments = contractorPayments(for: selected1099Year)

            if payments.isEmpty {
                EmptyStateView(icon: "doc.text", title: "No 1099 Data",
                               message: "No contractor payments found for \(selected1099Year). Add timesheet entries for 1099 contractors.")
                .frame(height: 200)
            } else {
                // Summary metrics
                let totalPaid = payments.reduce(Decimal.zero) { $0 + $1.total }
                let meetsThreshold = payments.filter { $0.total >= 600 }.count

                HStack(spacing: AppTheme.Spacing.md) {
                    MetricCard(title: "Contractors", value: "\(payments.count)", icon: "person.2.fill", color: .blue)
                    MetricCard(title: "Total Paid", value: totalPaid.currencyFormatted, icon: "dollarsign.circle.fill", color: .green)
                    MetricCard(title: "Meets $600", value: "\(meetsThreshold)", icon: "exclamationmark.triangle.fill", color: .orange)
                }
                .frame(height: 80)

                // Table
                GroupBox {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Contractor").font(.caption).fontWeight(.bold).frame(maxWidth: .infinity, alignment: .leading)
                            Text("Employee ID").font(.caption).fontWeight(.bold).frame(width: 80)
                            Text("Total Paid").font(.caption).fontWeight(.bold).frame(width: 100, alignment: .trailing)
                            Text("1099?").font(.caption).fontWeight(.bold).frame(width: 60)
                        }
                        .padding(.vertical, 4)
                        .background(AppTheme.primaryOrange.opacity(0.1))

                        ForEach(payments, id: \.name) { contractor in
                            Divider()
                            HStack {
                                Text(contractor.name).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                                Text(contractor.employeeID).font(.caption).foregroundColor(.secondary).frame(width: 80)
                                Text(contractor.total.currencyFormatted).font(.callout).fontWeight(.medium).frame(width: 100, alignment: .trailing)
                                if contractor.total >= 600 {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.orange).frame(width: 60)
                                } else {
                                    Image(systemName: "minus.circle").foregroundColor(.secondary).frame(width: 60)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                Text("Contractors paid $600 or more require IRS Form 1099-NEC.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Aggregate all payments to 1099 contractors for a given tax year
    private func contractorPayments(for year: Int) -> [(name: String, employeeID: String, total: Decimal)] {
        let cal = Calendar.current
        var totals: [String: (name: String, employeeID: String, total: Decimal)] = [:]

        // From timesheet entries
        for entry in dataStore.timesheetEntries {
            guard cal.component(.year, from: entry.weekStartDate) == year else { continue }
            guard entry.employeeType.lowercased().contains("contractor") || entry.employeeType == "1099" else { continue }
            let key = entry.employeeRef.isEmpty ? entry.employeeName : entry.employeeRef
            var existing = totals[key] ?? (name: entry.employeeName, employeeID: entry.employeeRef, total: 0)
            existing.total += entry.totalPay
            totals[key] = existing
        }

        // From manual payroll entries
        for (_, entries) in dataStore.payrollEntries {
            for entry in entries {
                guard cal.component(.year, from: entry.weekStartDate) == year else { continue }
                for detail in entry.employeeDetails {
                    // Match against employees to check if contractor
                    if let emp = dataStore.employees.first(where: { $0.fullName == detail.employeeName }),
                       emp.employeeType == .contractor {
                        let key = emp.id.uuidString
                        var existing = totals[key] ?? (name: emp.fullName, employeeID: emp.employeeID, total: 0)
                        existing.total += detail.totalPay
                        totals[key] = existing
                    }
                }
            }
        }

        return totals.values.sorted { $0.total > $1.total }
    }

    // MARK: - Helpers
    private func statusColor(_ project: Project) -> Color {
        switch project.computedStatus {
        case "Active": return AppTheme.ProjectStatus.active
        case "Upcoming": return AppTheme.ProjectStatus.upcoming
        case "Completed": return AppTheme.ProjectStatus.completed
        default: return AppTheme.ProjectStatus.onHold
        }
    }

    private func pct(_ value: Decimal, of total: Decimal) -> String {
        total > 0 ? String(format: "%.1f%%", Double(truncating: (value / total * 100) as NSDecimalNumber)) : "0%"
    }

    private func bidStatusColor(_ bid: BidProject) -> Color {
        switch bid.status {
        case .pending: return .blue; case .workingOn: return .yellow; case .readyToSubmit: return .cyan
        case .submitted: return .purple; case .awarded: return .green; case .lost: return .red
        }
    }

    // MARK: - CSV Generation (shared between CSV and PDF export)

    private func buildCSVString() -> String {
        var csv = ""
        switch selectedReport {
        case "Clients":
            csv = "Client,Type,Projects,Bids,Revenue,Costs,Profit,Margin\n"
            for c in dataStore.clients.sorted(by: { $0.name < $1.name }) {
                let projects = dataStore.projects(for: c)
                let bids = dataStore.bids(for: c)
                let rev = projects.reduce(Decimal(0)) { $0 + $1.totalRevenue }
                let costs = projects.reduce(Decimal(0)) { $0 + $1.totalCosts }
                let prof = projects.reduce(Decimal(0)) { $0 + $1.profit }
                let margin = rev > 0 ? Double(truncating: (prof / rev * 100) as NSDecimalNumber) : 0
                csv += "\"\(c.name)\",\(c.preferredRateType.displayName),\(projects.count),\(bids.count),\(rev),\(costs),\(prof),\(String(format: "%.1f", margin))%\n"
            }
        case "Job Costing":
            csv = "Project,Cost Code,Category,Amount,% of Total\n"
            let projects = selectedJobCostProject.map { [$0] } ?? dataStore.projects
            let overheadAllocation = dataStore.allocateOverhead(in: Date.distantPast...Date.distantFuture).perProject
            for p in projects {
                let costs = dataStore.costs(for: p.id)
                let payrollTotal = dataStore.payrollEntries(for: p.id).reduce(Decimal.zero) { $0 + $1.totalAmount }
                let tsTotal = dataStore.timesheetEntries.filter { $0.projectRef == p.id.recordName }.reduce(Decimal.zero) { $0 + $1.totalPay }
                let ohTotal = overheadAllocation[p.id.recordName] ?? 0
                let grand = costs.reduce(Decimal.zero) { $0 + $1.amount } + payrollTotal + tsTotal + ohTotal
                if payrollTotal > 0 { csv += "\"\(p.title)\",\(Cost.LaborCostCode.payroll),Labor (Payroll),\(payrollTotal),\(pct(payrollTotal, of: grand))\n" }
                if tsTotal > 0 { csv += "\"\(p.title)\",\(Cost.LaborCostCode.timesheet),Labor (Timesheet),\(tsTotal),\(pct(tsTotal, of: grand))\n" }
                for cat in Cost.CostCategory.allCases {
                    let amt = costs.filter { $0.category == cat }.reduce(Decimal.zero) { $0 + $1.amount }
                    if amt > 0 { csv += "\"\(p.title)\",\(cat.costCode),\(cat.displayName),\(amt),\(pct(amt, of: grand))\n" }
                }
                if ohTotal > 0 {
                    csv += "\"\(p.title)\",OVHD,Allocated Overhead,\(ohTotal),\(pct(ohTotal, of: grand))\n"
                }
            }
        case "Overhead":
            let range = overheadRangePreset.range()
            let allocation = dataStore.allocateOverhead(in: range)
            let entries = dataStore.overheadEntries(in: range).sorted { $0.date > $1.date }
            csv = "# Overhead — \(overheadRangePreset.rawValue)\n"
            csv += "Date,Category,Vendor,Description,Amount,Distribution,Recurrence\n"
            for e in entries {
                let desc = e.expenseDescription.replacingOccurrences(of: "\"", with: "'")
                let vendor = e.vendor.replacingOccurrences(of: "\"", with: "'")
                csv += "\(e.date.shortDate),\(e.category.rawValue),\"\(vendor)\",\"\(desc)\",\(e.amount),\(e.distributionMode.shortLabel),\(e.recurrence.rawValue)\n"
            }
            csv += "\n# By Category\n"
            csv += "Category,Amount,% of Total\n"
            for (cat, amt) in dataStore.overheadByCategory(in: range) {
                csv += "\(cat.rawValue),\(amt),\(pct(amt, of: allocation.total))\n"
            }
            csv += "\n# Distributed to Projects (Pro-Rata)\n"
            csv += "Project,Allocated,% of Distributed\n"
            let distributed = allocation.perProject.values.reduce(Decimal.zero, +)
            for (recordName, amt) in allocation.perProject.sorted(by: { $0.value > $1.value }) {
                csv += "\"\(projectTitle(for: recordName))\",\(amt),\(pct(amt, of: distributed))\n"
            }
            csv += "\n# Summary\n"
            csv += "Metric,Value\n"
            csv += "Range Total,\(allocation.total)\n"
            csv += "Distributed to Projects,\(distributed)\n"
            csv += "Company-only (not distributed),\(allocation.total - distributed)\n"
        case "1099 Summary":
            csv = "Contractor,Employee ID,Total Paid,Meets $600 Threshold\n"
            for c in contractorPayments(for: selected1099Year) {
                csv += "\"\(c.name)\",\(c.employeeID),\(c.total),\(c.total >= 600 ? "Yes" : "No")\n"
            }
        default:
            csv = "Project,Client,Client Type,Status,Contract,Revenue,Costs,Profit,Margin\n"
            for p in dataStore.projects {
                let client = dataStore.client(for: p.clientRef)
                let clientName = client?.name ?? ""
                let clientType = client?.preferredRateType.displayName ?? ""
                csv += "\"\(p.title)\",\"\(clientName)\",\(clientType),\(p.computedStatus),\(p.contractAmount),\(p.totalRevenue),\(p.totalCosts),\(p.profit),\(String(format: "%.1f", p.profitMargin))%\n"
            }
        }
        return csv
    }

    // MARK: - Export CSV

    private func exportCSV() {
        let csv = buildCSVString()
        let csvData = csv.data(using: .utf8) ?? Data()
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "SteelSync_\(selectedReport)_Report.csv"
        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? csvData.write(to: url)
            }
        }
        #else
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteelSync_\(selectedReport)_Report.csv")
        try? csvData.write(to: tempURL)
        PlatformService.shareItems([tempURL])
        #endif
    }

    // MARK: - Export PDF (CSV → PDF table)

    private func exportPDF() {
        let csv = buildCSVString()
        let rows = parseCSV(csv)
        guard !rows.isEmpty else { return }

        let pdfData = renderCSVToPDF(rows: rows, title: "SteelSync \(selectedReport) Report")

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "SteelSync_\(selectedReport)_Report.pdf"
        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? pdfData.write(to: url)
            }
        }
        #else
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteelSync_\(selectedReport)_Report.pdf")
        try? pdfData.write(to: tempURL)
        PlatformService.shareItems([tempURL])
        #endif
    }

    /// Parse CSV string into [[String]] rows, handling quoted fields
    private func parseCSV(_ csv: String) -> [[String]] {
        csv.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                var fields: [String] = []
                var current = ""
                var inQuotes = false
                for char in line {
                    if char == "\"" { inQuotes.toggle() }
                    else if char == "," && !inQuotes { fields.append(current); current = "" }
                    else { current.append(char) }
                }
                fields.append(current)
                return fields
            }
    }

    /// Renders CSV rows as a formatted PDF table using Core Graphics (cross-platform)
    private func renderCSVToPDF(rows: [[String]], title: String) -> Data {
        let pageWidth: CGFloat = 792  // US Letter landscape
        let pageHeight: CGFloat = 612
        let margin: CGFloat = 40
        let usableWidth = pageWidth - margin * 2
        let titleAreaHeight: CGFloat = 50
        let rowHeight: CGFloat = 20
        let fontSize: CGFloat = 9
        let headerFontSize: CGFloat = 14

        let colCount = rows.first?.count ?? 1
        let colWidth = usableWidth / CGFloat(colCount)
        let maxRowsPerPage = Int((pageHeight - margin * 2 - titleAreaHeight) / rowHeight)

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData),
              let cgContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        // On macOS, NSString.draw() requires NSGraphicsContext.current to be set
        #if os(macOS)
        let nsContext = NSGraphicsContext(cgContext: cgContext, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        #endif

        #if os(macOS)
        let titleFont = NSFont.boldSystemFont(ofSize: headerFontSize)
        let bodyFontReg = NSFont.systemFont(ofSize: fontSize)
        let bodyFontBold = NSFont.boldSystemFont(ofSize: fontSize)
        let dateFont = NSFont.systemFont(ofSize: 8)
        let textColor = NSColor.black
        let headerBg = NSColor.systemOrange.withAlphaComponent(0.15).cgColor
        let separatorColor = NSColor.gray.withAlphaComponent(0.3).cgColor
        #else
        let titleFont = UIFont.boldSystemFont(ofSize: headerFontSize)
        let bodyFontReg = UIFont.systemFont(ofSize: fontSize)
        let bodyFontBold = UIFont.boldSystemFont(ofSize: fontSize)
        let dateFont = UIFont.systemFont(ofSize: 8)
        let textColor = UIColor.black
        let headerBg = UIColor.systemOrange.withAlphaComponent(0.15).cgColor
        let separatorColor = UIColor.separator.cgColor
        #endif

        var y: CGFloat = 0

        for (rowIdx, row) in rows.enumerated() {
            if rowIdx % maxRowsPerPage == 0 {
                if rowIdx > 0 { cgContext.endPDFPage() }
                cgContext.beginPDFPage(nil)

                // Flip coordinate system for text drawing
                cgContext.textMatrix = .identity
                cgContext.translateBy(x: 0, y: pageHeight)
                cgContext.scaleBy(x: 1, y: -1)

                #if os(macOS)
                // Re-set NSGraphicsContext after new page
                NSGraphicsContext.current = NSGraphicsContext(cgContext: cgContext, flipped: true)
                #endif

                y = margin

                // Title
                let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: textColor]
                (title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)

                let dateStr = "Generated: \(Date().shortDate)"
                let dateAttrs: [NSAttributedString.Key: Any] = [.font: dateFont, .foregroundColor: textColor]
                (dateStr as NSString).draw(at: CGPoint(x: pageWidth - margin - 120, y: y + 4), withAttributes: dateAttrs)

                y += titleAreaHeight

                // Redraw column headers on subsequent pages
                if rowIdx > 0, let header = rows.first {
                    drawPDFRow(header, at: &y, x: margin, colWidth: colWidth, isHeader: true,
                               fontReg: bodyFontReg, fontBold: bodyFontBold, textColor: textColor,
                               headerBg: headerBg, separatorColor: separatorColor,
                               context: cgContext, pageWidth: pageWidth, margin: margin)
                }
            }

            drawPDFRow(row, at: &y, x: margin, colWidth: colWidth, isHeader: (rowIdx == 0),
                       fontReg: bodyFontReg, fontBold: bodyFontBold, textColor: textColor,
                       headerBg: headerBg, separatorColor: separatorColor,
                       context: cgContext, pageWidth: pageWidth, margin: margin)
        }

        cgContext.endPDFPage()
        cgContext.closePDF()

        #if os(macOS)
        NSGraphicsContext.restoreGraphicsState()
        #endif

        return pdfData as Data
    }

    #if os(macOS)
    private typealias PlatformFont = NSFont
    private typealias PlatformColor = NSColor
    #else
    private typealias PlatformFont = UIFont
    private typealias PlatformColor = UIColor
    #endif

    private func drawPDFRow(_ fields: [String], at y: inout CGFloat, x: CGFloat, colWidth: CGFloat,
                            isHeader: Bool, fontReg: PlatformFont, fontBold: PlatformFont,
                            textColor: PlatformColor, headerBg: CGColor, separatorColor: CGColor,
                            context: CGContext, pageWidth: CGFloat, margin: CGFloat) {
        let rowHeight: CGFloat = 20

        if isHeader {
            context.setFillColor(headerBg)
            context.fill(CGRect(x: x, y: y, width: pageWidth - margin * 2, height: rowHeight))
        }

        context.setStrokeColor(separatorColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: x, y: y + rowHeight))
        context.addLine(to: CGPoint(x: pageWidth - margin, y: y + rowHeight))
        context.strokePath()

        let font = isHeader ? fontBold : fontReg
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]

        for (colIdx, field) in fields.enumerated() {
            let cellX = x + CGFloat(colIdx) * colWidth + 4
            let cellRect = CGRect(x: cellX, y: y + 3, width: colWidth - 8, height: rowHeight - 6)
            let text = field.trimmingCharacters(in: .whitespaces)
            (text as NSString).draw(in: cellRect, withAttributes: attrs)
        }
        y += rowHeight
    }

    // MARK: - Bonuses Report

    /// Estimates each foreman's bonus from the Gantt tasks they completed
    /// in the selected year. Pct = foreman's completed-and-ended-in-year
    /// task-days for the project ÷ that project's total task-days
    /// (all tasks, all-time). Bonus = basis × pct × (multiplier / 100).
    /// Profit basis is clamped at zero so a losing job doesn't pay a
    /// negative bonus.
    private var bonusesReport: some View {
        let breakdowns = dataStore.computeBonuses(year: bonusYear, basis: bonusBasis, multiplierPct: bonusMultiplier)
        let totalPool = breakdowns.reduce(Decimal.zero) { $0 + $1.total }
        let touchedProjects = Set(breakdowns.flatMap { $0.perProject.map(\.project.id.recordName) }).count

        return VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Foreman Bonus Estimate")
                .font(AppTheme.Typography.title2)

            Text("Per-foreman bonus estimate from the Gantt schedule. Percentage = the foreman's completed task-days this year on a project ÷ that project's total task-days (all tasks, all-time). Bonus = basis × percentage × multiplier. Profit basis is clamped at zero so losing projects pay no bonus.")
                .font(.caption)
                .foregroundColor(AppTheme.secondaryText)

            GroupBox("Parameters") {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    HStack(spacing: AppTheme.Spacing.md) {
                        Text("Year")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .leading)
                        Picker("Year", selection: $bonusYear) {
                            ForEach(dataStore.availableBonusYears, id: \.self) { yr in
                                Text(verbatim: "\(yr)").tag(yr)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        Spacer()
                    }
                    HStack(spacing: AppTheme.Spacing.md) {
                        Text("Basis")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .leading)
                        Picker("Basis", selection: $bonusBasis) {
                            ForEach(BonusBasis.allCases, id: \.self) { b in
                                Text(b.rawValue).tag(b)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    HStack(spacing: AppTheme.Spacing.md) {
                        Text("Multiplier")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 90, alignment: .leading)
                        HStack(spacing: 6) {
                            TextField("0.0", value: $bonusMultiplier, format: .number)
                                .textFieldStyle(.appField)
                                .frame(maxWidth: 90)
                                #if !os(macOS)
                                .keyboardType(.decimalPad)
                                #endif
                            Text("% of \(bonusBasis.rawValue.lowercased())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: AppTheme.Spacing.md) {
                MetricCard(title: "Estimated Bonus Pool",
                           value: totalPool.currencyFormatted,
                           icon: "dollarsign.circle.fill",
                           color: AppTheme.primaryOrange)
                MetricCard(title: "Foremen With Bonus",
                           value: "\(breakdowns.filter { $0.total > 0 }.count)",
                           icon: "person.fill.checkmark",
                           color: .green)
                MetricCard(title: "Projects Touched",
                           value: "\(touchedProjects)",
                           icon: "building.2.fill",
                           color: .blue)
            }

            if breakdowns.isEmpty {
                Text("No foremen on file. Add crew in Operations → Crew & Timesheets, then mark them as Foreman.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, AppTheme.Spacing.lg)
            } else {
                ForEach(breakdowns) { b in
                    GroupBox {
                        DisclosureGroup {
                            if b.perProject.isEmpty {
                                Text("No completed tasks ended in \(String(bonusYear)).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 6)
                            } else {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(b.perProject) { item in
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack {
                                                Text(item.project.title)
                                                    .font(.callout)
                                                    .lineLimit(1)
                                                Spacer()
                                                Text(item.contribution.currencyFormatted)
                                                    .font(.callout.monospacedDigit())
                                                    .foregroundColor(AppTheme.primaryText)
                                            }
                                            HStack(spacing: 6) {
                                                Text("\(Int(item.completionPct * 100))% completed")
                                                Text("·")
                                                Text("\(item.foremanDays.formatted(.number.precision(.fractionLength(0...1)))) / \(item.projectTotalDays) d")
                                                Text("·")
                                                Text("\(bonusBasis.rawValue) \(item.basis.currencyFormatted)")
                                            }
                                            .font(.caption2.monospacedDigit())
                                            .foregroundColor(.secondary)
                                        }
                                        .padding(.vertical, 6)
                                        if item.id != b.perProject.last?.id {
                                            Divider()
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.foreman.fullName)
                                        .font(AppTheme.Typography.headline)
                                    Text("\(b.perProject.count) project\(b.perProject.count == 1 ? "" : "s") · \(b.totalCompletionDays.formatted(.number.precision(.fractionLength(0...1)))) days")
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Text(b.total.currencyFormatted)
                                    .font(.title3.monospacedDigit())
                                    .fontWeight(.semibold)
                                    .foregroundColor(AppTheme.primaryOrange)
                            }
                        }
                    }
                }
            }
        }
    }

    // `availableBonusYears` and `computeBonuses(...)` were hoisted onto
    // `DataStore` so the iPhone `PhoneBonusesView` and the Foreman Bonus
    // widget share the same source-of-truth math. See `DataStore.swift`.

}

// MARK: - Bonus report types

enum BonusBasis: String, CaseIterable, Hashable {
    case revenue = "Revenue"
    case profit = "Profit"
}

struct BonusBreakdown: Identifiable {
    let foreman: Employee
    let perProject: [BonusBreakdownItem]
    var total: Decimal { perProject.reduce(Decimal.zero) { $0 + $1.contribution } }
    var totalCompletionDays: Decimal { perProject.reduce(Decimal.zero) { $0 + $1.foremanDays } }
    var id: UUID { foreman.id }
}

struct BonusBreakdownItem: Identifiable {
    let project: Project
    let projectTotalDays: Int
    /// Decimal because multi-foreman tasks split their duration evenly — a
    /// 41-day task with two foremen contributes 20.5 to each.
    let foremanDays: Decimal
    let basis: Decimal
    let contribution: Decimal
    var completionPct: Double {
        guard projectTotalDays > 0 else { return 0 }
        return Double(truncating: (foremanDays / Decimal(projectTotalDays)) as NSDecimalNumber)
    }
    var id: String { project.id.recordName }
}
