import SwiftUI
import CloudKit

struct PhoneEquipmentView: View {
    @EnvironmentObject var dataStore: DataStore

    private var allActiveRentals: [(project: Project, rentals: [EquipmentRental])] {
        dataStore.projects.compactMap { project in
            let active = dataStore.activeRentals(for: project.id)
            guard !active.isEmpty else { return nil }
            return (project: project, rentals: active)
        }
    }

    private var activeCount: Int {
        dataStore.allActiveRentalCount
    }

    private var totalEstimatedCost: Decimal {
        dataStore.projects.reduce(Decimal.zero) { total, project in
            total + dataStore.activeRentals(for: project.id).reduce(Decimal.zero) { $0 + $1.estimatedActiveCost }
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: AppTheme.Spacing.lg) {
                    metricItem(
                        icon: "shippingbox.fill",
                        value: "\(activeCount)",
                        label: "Active Rentals"
                    )
                    Spacer()
                    metricItem(
                        icon: "dollarsign.circle.fill",
                        value: totalEstimatedCost.currencyFormatted,
                        label: "Est. Running Cost"
                    )
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }
            .listRowBackground(AppTheme.secondaryBackground)

            if allActiveRentals.isEmpty {
                Section {
                    VStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 40))
                            .foregroundColor(AppTheme.tertiaryText)
                        Text("No active rentals")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundColor(AppTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.xl)
                }
                .listRowBackground(AppTheme.secondaryBackground)
            } else {
                ForEach(allActiveRentals, id: \.project.id) { group in
                    Section {
                        ForEach(group.rentals, id: \.id) { rental in
                            rentalRow(rental)
                        }
                    } header: {
                        Text(group.project.title)
                            .foregroundColor(AppTheme.primaryOrange)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Equipment")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Subviews

    private func metricItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: AppTheme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(AppTheme.primaryOrange)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                
            Text(label)
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.secondaryText)
        }
    }

    private func rentalRow(_ rental: EquipmentRental) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text(rental.equipmentName)
                .font(AppTheme.Typography.headline)
                

            HStack {
                Label(rental.startDate.shortDate, systemImage: "calendar")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.secondaryText)

                Spacer()

                Text("\(rental.daysSinceStart) days")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.warning)

                Spacer()

                Text(rental.estimatedActiveCost.currencyFormatted)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(AppTheme.primaryOrange)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .listRowBackground(AppTheme.secondaryBackground)
    }
}
