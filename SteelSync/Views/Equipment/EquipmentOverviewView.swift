import SwiftUI
import CloudKit

struct EquipmentOverviewView: View {
    @EnvironmentObject var dataStore: DataStore

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

            if activeRentals.isEmpty {
                EmptyStateView(icon: "shippingbox", title: "No Equipment On Rent",
                               message: "Add equipment rentals from a project's Equipment tab to track them here.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        // Active Equipment Cards
                        ForEach(activeRentals, id: \.rental.id) { item in
                            rentalCard(rental: item.rental, projectName: item.projectName, projectID: item.projectID)
                        }
                    }
                    .padding(AppTheme.Spacing.lg)
                }
            }
        }
        .navigationTitle("Equipment On Rent")
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
                            label: "Close Today",
                            sublabel: "Day \(rental.daysSinceStart)",
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
