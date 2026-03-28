#if STEELSYNC_IPHONE
import SwiftUI
import CloudKit

struct IPhoneMoreTab: View {
    @EnvironmentObject var dataStore: DataStore

    private var allActiveRentals: [(rental: EquipmentRental, projectID: CKRecord.ID)] {
        var result: [(EquipmentRental, CKRecord.ID)] = []
        for (projectID, rentals) in dataStore.equipmentRentals {
            for rental in rentals where rental.isActive {
                result.append((rental, projectID))
            }
        }
        return result
    }

    private var totalEstimatedRentalCost: Decimal {
        allActiveRentals.reduce(0) { $0 + $1.rental.estimatedActiveCost }
    }

    private func projectTitle(for projectID: CKRecord.ID) -> String {
        dataStore.projects.first { $0.id == projectID }?.title ?? "Unknown Project"
    }

    private var syncStatusText: String {
        switch dataStore.syncStatus {
        case .local: return "Local Only"
        case .checking: return "Checking..."
        case .ready: return "Ready"
        case .syncing: return "Syncing..."
        case .synced: return "Synced"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var syncStatusColor: Color {
        switch dataStore.syncStatus {
        case .synced: return .green
        case .error: return .red
        case .syncing, .checking: return .orange
        default: return .secondary
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Reports
                Section("Reports") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        MetricCard(
                            title: "Pipeline Value",
                            value: dataStore.totalBidPipeline.currencyFormatted,
                            icon: "chart.bar.fill",
                            color: .blue
                        )
                        MetricCard(
                            title: "Win Rate",
                            value: String(format: "%.0f%%", dataStore.bidWinRate),
                            icon: "trophy.fill",
                            color: .green
                        )
                        MetricCard(
                            title: "Active Projects",
                            value: "\(dataStore.activeProjects.count)",
                            icon: "building.2.fill",
                            color: AppTheme.primaryOrange
                        )
                        MetricCard(
                            title: "Total Revenue",
                            value: dataStore.totalRevenue.currencyFormatted,
                            icon: "dollarsign.circle.fill",
                            color: .purple
                        )
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // MARK: - Equipment
                Section("Equipment") {
                    InfoRow(
                        label: "Active Rentals",
                        value: "\(allActiveRentals.count)",
                        icon: "wrench.and.screwdriver"
                    )
                    InfoRow(
                        label: "Est. Total Cost",
                        value: totalEstimatedRentalCost.currencyFormatted,
                        icon: "dollarsign.circle"
                    )

                    if !allActiveRentals.isEmpty {
                        ForEach(allActiveRentals, id: \.rental.id) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.rental.equipmentName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                    Text(projectTitle(for: item.projectID))
                                        .font(.caption)
                                        .foregroundColor(AppTheme.secondaryText)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("Day \(item.rental.daysSinceStart)")
                                        .font(.caption)
                                        .foregroundColor(AppTheme.tertiaryText)
                                    Text(item.rental.estimatedActiveCost.currencyFormatted)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(AppTheme.primaryOrange)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // MARK: - Sync
                Section("Sync") {
                    HStack {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundColor(syncStatusColor)
                        Text("Status")
                            .foregroundColor(AppTheme.secondaryText)
                        Spacer()
                        Text(syncStatusText)
                            .fontWeight(.medium)
                            .foregroundColor(syncStatusColor)
                    }

                    if let lastSync = dataStore.lastSyncDate {
                        InfoRow(label: "Last Sync", value: lastSync.timeAgo, icon: "clock")
                    }

                    Button {
                        Task {
                            await dataStore.pullFromCloud()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Refresh Data", systemImage: "arrow.clockwise")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(dataStore.isSyncing)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
            .refreshable {
                await dataStore.pullFromCloud()
            }
        }
    }
}
#endif
