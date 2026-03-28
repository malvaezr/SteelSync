import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var navigationState: NavigationState
    @State private var showSyncOptions = false

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $navigationState.selectedSection) {
                Section("PROJECT MANAGEMENT") {
                    sidebarRow(.dashboard, badge: dataStore.activeProjects.count)
                    sidebarRow(.clients, badge: dataStore.clients.count)
                    sidebarRow(.bidding, badge: dataStore.pendingBids.count + dataStore.bids.filter { $0.status == .readyToSubmit }.count)
                }

                Section("OPERATIONS") {
                    sidebarRow(.timekeeping, badge: dataStore.activeEmployees.count)
                    sidebarRow(.schedule)
                    sidebarRow(.equipment, badge: dataStore.allActiveRentalCount)
                }

                Section("TRACKING") {
                    sidebarRow(.todo, badge: dataStore.overdueTodos.count)
                    sidebarRow(.reports)
                    sidebarRow(.activity)
                }
            }
            .listStyle(.sidebar)

            Divider()

            syncButton
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .navigationTitle("SteelSync")
        .confirmationDialog("Sync Options", isPresented: $showSyncOptions) {
            Button("Push Local → Cloud") {
                Task { await dataStore.pushToCloud() }
            }
            Button("Pull Cloud → Local") {
                Task { await dataStore.pullFromCloud() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(syncDialogMessage)
        }
    }

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItem, badge: Int = 0) -> some View {
        Label {
            HStack {
                Text(item.rawValue)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.primaryOrange.opacity(0.2))
                        .foregroundColor(AppTheme.primaryOrange)
                        .clipShape(Capsule())
                }
            }
        } icon: {
            Image(systemName: item.icon)
                .foregroundColor(navigationState.selectedSection == item ? AppTheme.primaryOrange : .secondary)
        }
        .tag(item)
    }

    private var syncButton: some View {
        VStack(spacing: 4) {
            Button {
                if !dataStore.isSyncing {
                    showSyncOptions = true
                }
            } label: {
                HStack(spacing: 4) {
                    switch dataStore.syncStatus {
                    case .syncing, .checking:
                        ProgressView()
                            .controlSize(.mini)
                    default:
                        Circle()
                            .fill(syncColor)
                            .frame(width: 8, height: 8)
                    }
                    Text(dataStore.syncStatus.displayText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    if !dataStore.isSyncing {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(dataStore.isSyncing)
            .help(syncTooltip)

            if dataStore.isSyncing {
                ProgressView(value: dataStore.syncProgress)
                    .tint(AppTheme.primaryOrange)
            }
        }
    }

    private var syncDialogMessage: String {
        var msg = "Choose sync direction."
        if let lastSync = dataStore.lastSyncDate {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            msg += "\nLast synced: \(formatter.localizedString(for: lastSync, relativeTo: Date()))"
        }
        if case .error(let err) = dataStore.syncStatus {
            msg += "\nLast error: \(err)"
        }
        return msg
    }

    private var syncTooltip: String {
        switch dataStore.syncStatus {
        case .synced:
            if let d = dataStore.lastSyncDate {
                return "Synced \(d.formatted(date: .abbreviated, time: .shortened)). Click to sync again."
            }
            return "Synced. Click to sync again."
        case .ready: return "iCloud connected. Click to sync."
        case .error(let msg): return "Sync error: \(msg). Click to retry."
        case .local: return "Running locally. iCloud not available."
        case .checking: return "Checking iCloud..."
        case .syncing: return "Syncing..."
        }
    }

    private var syncColor: Color {
        switch dataStore.syncStatus {
        case .local: return .orange
        case .checking, .syncing, .ready: return .blue
        case .synced: return .green
        case .error: return .red
        }
    }
}
