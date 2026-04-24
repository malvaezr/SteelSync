import SwiftUI
import CloudKit

struct EquipmentOverviewView: View {
    @EnvironmentObject var dataStore: DataStore

    // MARK: - Date range filter state
    @State private var rangeStart: Date = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var rangeEnd: Date = Date()
    @State private var rangeExpanded: Bool = true

    private var activeRentals: [(rental: EquipmentRental, projectID: CKRecord.ID, projectName: String)] {
        dataStore.equipmentRentals.flatMap { (projectID, rentals) -> [(EquipmentRental, CKRecord.ID, String)] in
            let name = dataStore.projects.first { $0.id == projectID }?.title ?? "Unknown"
            return rentals.filter { $0.isActive }.map { ($0, projectID, name) }
        }
        .sorted { $0.0.daysSinceStart > $1.0.daysSinceStart }
    }

    private var estimatedTotal: Decimal {
        activeRentals.reduce(0) { $0 + $1.rental.costIfCloseToday }
    }

    private var projectsWithEquipment: Int {
        Set(activeRentals.map { $0.projectID }).count
    }

    // MARK: - Date range filter computations

    /// Projects whose active window overlaps with [rangeStart, rangeEnd].
    /// "Active window" = startDate ... (actualCompletionDate ?? endDate ?? distantFuture).
    /// Projects without a startDate are skipped (no way to date-filter them).
    private var projectsActiveInRange: [Project] {
        let calendar = Calendar.current
        let normStart = calendar.startOfDay(for: rangeStart)
        let normEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: rangeEnd)) ?? rangeEnd
        return dataStore.projects.filter { p in
            guard let pStart = p.startDate else { return false }
            let pEnd = p.actualCompletionDate ?? p.endDate ?? .distantFuture
            return pStart < normEnd && pEnd >= normStart
        }
    }

    /// For each in-range project, sum machinery-category Cost entries whose
    /// date falls within [rangeStart, rangeEnd]. Returns only projects with
    /// non-zero in-range equipment spend, sorted descending by amount.
    private var equipmentCostsByProject: [(project: Project, total: Decimal, count: Int)] {
        let calendar = Calendar.current
        let normStart = calendar.startOfDay(for: rangeStart)
        let normEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: rangeEnd)) ?? rangeEnd
        var result: [(Project, Decimal, Int)] = []
        for p in projectsActiveInRange {
            let machineryInRange = dataStore.costs(for: p.id).filter { c in
                c.category == .machinery && c.date >= normStart && c.date < normEnd
            }
            let total = machineryInRange.reduce(Decimal(0)) { $0 + $1.amount }
            if total > 0 {
                result.append((p, total, machineryInRange.count))
            }
        }
        return result.sorted { $0.1 > $1.1 }
    }

    private var rangeTotalEquipmentCost: Decimal {
        equipmentCostsByProject.reduce(Decimal(0)) { $0 + $1.total }
    }

    private var rangeDayCount: Int {
        let comps = Calendar.current.dateComponents([.day], from: rangeStart, to: rangeEnd)
        return max(1, (comps.day ?? 0) + 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Metrics bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    MetricCard(title: "Active Rentals", value: "\(activeRentals.count)",
                               icon: "shippingbox.fill", color: AppTheme.primaryOrange)
                    MetricCard(title: "Est. Total Cost", value: estimatedTotal.currencyFormatted,
                               icon: "dollarsign.circle.fill", color: .red)
                    MetricCard(title: "Projects w/ Equipment", value: "\(projectsWithEquipment)",
                               icon: "building.2.fill", color: .blue)
                }
                .padding(AppTheme.Spacing.md)
            }
            .frame(height: 120)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    dateRangeSection
                    if activeRentals.isEmpty {
                        EmptyStateView(icon: "shippingbox", title: "No Equipment On Rent",
                                       message: "Add equipment rentals from a project's Equipment tab to track them here.")
                        .frame(height: 200)
                    } else {
                        Text("Currently On Rent")
                            .font(.headline)
                            .padding(.top, 4)
                        ForEach(activeRentals, id: \.rental.id) { item in
                            rentalCard(rental: item.rental, projectName: item.projectName, projectID: item.projectID)
                        }
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
        }
        .navigationTitle("Equipment On Rent")
    }

    // MARK: - Date Range Section

    @ViewBuilder
    private var dateRangeSection: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $rangeExpanded) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    // Date pickers + presets
                    HStack(spacing: AppTheme.Spacing.md) {
                        DatePicker("From", selection: $rangeStart, displayedComponents: .date)
                            .datePickerStyle(.compact)
                        DatePicker("To", selection: $rangeEnd, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }

                    // Quick presets
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            presetButton("This Month") { applyPreset(.thisMonth) }
                            presetButton("Last Month") { applyPreset(.lastMonth) }
                            presetButton("This Quarter") { applyPreset(.thisQuarter) }
                            presetButton("Last Quarter") { applyPreset(.lastQuarter) }
                            presetButton("YTD") { applyPreset(.yearToDate) }
                            presetButton("Last Year") { applyPreset(.lastYear) }
                        }
                    }

                    Divider()

                    // Summary
                    HStack(spacing: AppTheme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Equipment Cost in Range")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(rangeTotalEquipmentCost.currencyFormatted)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(AppTheme.primaryOrange)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("\(equipmentCostsByProject.count) project\(equipmentCostsByProject.count == 1 ? "" : "s") of \(projectsActiveInRange.count) active")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("\(rangeDayCount) day\(rangeDayCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Per-project breakdown
                    if equipmentCostsByProject.isEmpty {
                        Text("No equipment costs recorded for active projects in this date range.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(equipmentCostsByProject, id: \.project.id) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.project.title)
                                            .font(.callout)
                                            .lineLimit(1)
                                        Text("\(entry.count) cost item\(entry.count == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(entry.total.currencyFormatted)
                                        .font(.callout.monospacedDigit())
                                        .fontWeight(.semibold)
                                }
                                .padding(.vertical, 6)
                                Divider()
                            }
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(AppTheme.primaryOrange)
                    Text("Equipment Costs by Date Range")
                        .font(.headline)
                    Spacer()
                    if !rangeExpanded {
                        Text(rangeTotalEquipmentCost.currencyFormatted)
                            .font(.callout.monospacedDigit())
                            .fontWeight(.semibold)
                            .foregroundColor(AppTheme.primaryOrange)
                    }
                }
            }
        }
    }

    private func presetButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
        }
        .buttonStyle(.appSecondary)
        .controlSize(.small)
    }

    private enum DateRangePreset {
        case thisMonth, lastMonth, thisQuarter, lastQuarter, yearToDate, lastYear
    }

    private func applyPreset(_ preset: DateRangePreset) {
        let cal = Calendar.current
        let now = Date()
        switch preset {
        case .thisMonth:
            rangeStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            rangeEnd = now
        case .lastMonth:
            let firstOfThisMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
            let firstOfLastMonth = cal.date(byAdding: .month, value: -1, to: firstOfThisMonth) ?? now
            rangeStart = firstOfLastMonth
            rangeEnd = cal.date(byAdding: .day, value: -1, to: firstOfThisMonth) ?? now
        case .thisQuarter:
            let month = cal.component(.month, from: now)
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var comps = cal.dateComponents([.year], from: now)
            comps.month = quarterStartMonth
            comps.day = 1
            rangeStart = cal.date(from: comps) ?? now
            rangeEnd = now
        case .lastQuarter:
            let month = cal.component(.month, from: now)
            let thisQuarterStartMonth = ((month - 1) / 3) * 3 + 1
            var comps = cal.dateComponents([.year], from: now)
            comps.month = thisQuarterStartMonth
            comps.day = 1
            let thisQuarterStart = cal.date(from: comps) ?? now
            rangeStart = cal.date(byAdding: .month, value: -3, to: thisQuarterStart) ?? now
            rangeEnd = cal.date(byAdding: .day, value: -1, to: thisQuarterStart) ?? now
        case .yearToDate:
            var comps = cal.dateComponents([.year], from: now)
            comps.month = 1
            comps.day = 1
            rangeStart = cal.date(from: comps) ?? now
            rangeEnd = now
        case .lastYear:
            var comps = cal.dateComponents([.year], from: now)
            comps.year = (comps.year ?? 0) - 1
            comps.month = 1
            comps.day = 1
            rangeStart = cal.date(from: comps) ?? now
            comps.month = 12
            comps.day = 31
            rangeEnd = cal.date(from: comps) ?? now
        }
    }

    // MARK: - Rental Card

    @ViewBuilder
    private func rentalCard(rental: EquipmentRental, projectName: String, projectID: CKRecord.ID) -> some View {
        GroupBox {
            VStack(spacing: AppTheme.Spacing.md) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rental.equipmentName)
                            .font(AppTheme.Typography.title3)
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Label(projectName, systemImage: "building.2")
                                .font(.callout)
                                .foregroundColor(.secondary)
                            if rental.isScheduled {
                                Text("Scheduled \(rental.startDate.shortDate)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                            } else {
                                Text("Day \(rental.daysSinceStart)")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(AppTheme.primaryOrange.opacity(0.15))
                                    .foregroundColor(AppTheme.primaryOrange)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Current Cost")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(rental.costIfCloseToday.currencyFormatted)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(AppTheme.primaryOrange)
                    }
                }

                Divider()

                // Billing Period Status
                HStack(spacing: AppTheme.Spacing.lg) {
                    // Weekly period
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "calendar.badge.clock")
                                .foregroundColor(.blue)
                            Text("Weekly Period")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        Text("Week \(rental.currentWeekPeriod)")
                            .font(.callout)
                            .fontWeight(.semibold)
                        HStack(spacing: 4) {
                            if rental.daysUntilWeekCutoff == 0 {
                                Text("Ends today")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .fontWeight(.semibold)
                            } else {
                                Text("\(rental.daysUntilWeekCutoff) day\(rental.daysUntilWeekCutoff == 1 ? "" : "s") left")
                                    .font(.caption)
                                    .foregroundColor(rental.daysUntilWeekCutoff <= 1 ? .red : .green)
                                    .fontWeight(.medium)
                            }
                        }
                        Text("Cutoff: \(rental.weekCutoffDate.shortDate)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 60)

                    // 4-Week period
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.purple)
                            Text("4-Week Period")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                        }
                        Text("Month \(rental.currentMonthPeriod)")
                            .font(.callout)
                            .fontWeight(.semibold)
                        HStack(spacing: 4) {
                            if rental.daysUntilMonthCutoff == 0 {
                                Text("Ends today")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .fontWeight(.semibold)
                            } else {
                                Text("\(rental.daysUntilMonthCutoff) day\(rental.daysUntilMonthCutoff == 1 ? "" : "s") left")
                                    .font(.caption)
                                    .foregroundColor(rental.daysUntilMonthCutoff <= 2 ? .orange : .green)
                                    .fontWeight(.medium)
                            }
                        }
                        Text("Cutoff: \(rental.monthCutoffDate.shortDate)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                // Cost Comparison Table
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack {
                        Image(systemName: "dollarsign.arrow.trianglehead.counterclockwise.rotate.90")
                            .foregroundColor(.green)
                        Text("Cost Analysis")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(rental.currentBreakdown)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 0) {
                        costColumn(
                            label: rental.isScheduled ? "Not Started" : "Close Today",
                            sublabel: rental.isScheduled ? "Starts \(rental.startDate.shortDate)" : "Day \(rental.daysSinceStart)",
                            cost: rental.costIfCloseToday,
                            delta: nil,
                            highlight: true
                        )
                        Divider().frame(height: 50).padding(.horizontal, 4)
                        costColumn(
                            label: "At Week End",
                            sublabel: rental.weekCutoffDate.shortDate,
                            cost: rental.costAtWeekCutoff,
                            delta: rental.weekCutoffDelta,
                            highlight: false
                        )
                        Divider().frame(height: 50).padding(.horizontal, 4)
                        costColumn(
                            label: "At Month End",
                            sublabel: rental.monthCutoffDate.shortDate,
                            cost: rental.costAtMonthCutoff,
                            delta: rental.monthCutoffDelta,
                            highlight: false
                        )
                    }
                }

                // Rates reference
                HStack(spacing: AppTheme.Spacing.lg) {
                    rateRef("Daily", rental.dailyRate)
                    rateRef("Weekly", rental.weeklyRate)
                    rateRef("4-Week", rental.fourWeekRate)
                    Spacer()
                    Text("Started \(rental.startDate.shortDate)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, AppTheme.Spacing.sm)
        }
    }

    // MARK: - Helpers

    private func costColumn(label: String, sublabel: String, cost: Decimal, delta: Decimal?, highlight: Bool) -> some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(cost.currencyFormatted)
                .font(.callout)
                .fontWeight(.bold)
                .foregroundColor(highlight ? AppTheme.primaryOrange : AppTheme.primaryText)
            if let delta = delta {
                if delta == 0 {
                    Text("no change")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Text("+\(delta.currencyFormatted)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }
            } else {
                Text(sublabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rateRef(_ label: String, _ rate: Decimal) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(rate.currencyFormatted).font(.caption2).fontWeight(.medium)
        }
    }
}
