import SwiftUI

struct PhoneSyncStatusView: View {
    @EnvironmentObject var dataStore: DataStore

    private var statusColor: Color {
        switch dataStore.syncStatus {
        case .synced: return AppTheme.success
        case .syncing, .checking: return AppTheme.warning
        case .error: return AppTheme.error
        case .ready: return AppTheme.info
        case .local: return AppTheme.secondaryText
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: AppTheme.Spacing.md) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 14, height: 14)
                    Text(dataStore.syncStatus.displayText)
                        .font(AppTheme.Typography.headline)
                        
                    Spacer()
                }
                .padding(.vertical, AppTheme.Spacing.xs)

                if let lastSync = dataStore.lastSyncDate {
                    HStack {
                        Image(systemName: "clock")
                            .foregroundColor(AppTheme.secondaryText)
                        Text("Last sync: \(lastSync.timeAgo)")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundColor(AppTheme.secondaryText)
                        Spacer()
                    }
                }
            } header: {
                Text("Status")
                    .foregroundColor(AppTheme.secondaryText)
            }
            .listRowBackground(AppTheme.secondaryBackground)

            if dataStore.isSyncing {
                Section {
                    VStack(spacing: AppTheme.Spacing.sm) {
                        ProgressBar(value: dataStore.syncProgress, color: AppTheme.primaryOrange)
                        Text("\(Int(dataStore.syncProgress * 100))% complete")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    .padding(.vertical, AppTheme.Spacing.xs)
                }
                .listRowBackground(AppTheme.secondaryBackground)
            }

            Section {
                Button {
                    Task {
                        await dataStore.pullFromCloud()
                    }
                } label: {
                    HStack {
                        Spacer()
                        Label("Refresh Data", systemImage: "arrow.clockwise")
                            .font(AppTheme.Typography.headline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }
                .listRowBackground(AppTheme.primaryOrange)
                .disabled(dataStore.isSyncing)
                .opacity(dataStore.isSyncing ? 0.5 : 1.0)
            }

            Section {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(AppTheme.secondaryText)
                    Text("Changes to tasks sync automatically when iCloud is available.")
                        .font(AppTheme.Typography.footnote)
                        .foregroundColor(AppTheme.secondaryText)
                }
                .padding(.vertical, AppTheme.Spacing.xs)
            }
            .listRowBackground(AppTheme.secondaryBackground)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Sync")
        .navigationBarTitleDisplayMode(.inline)
    }
}
