import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var navigationState: NavigationState
    @State private var showSyncOptions = false

    /// Projects the user has pinned, resolved to live `Project` objects.
    /// Filters out IDs that no longer exist (project deleted) so stale
    /// pins disappear automatically.
    private var pinnedProjects: [Project] {
        navigationState.pinnedProjectIDs.compactMap { id in
            dataStore.projects.first { $0.id.recordName == id }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $navigationState.selectedSection) {
                if !pinnedProjects.isEmpty {
                    Section("PINNED") {
                        ForEach(pinnedProjects) { project in
                            pinnedProjectRow(project)
                        }
                    }
                }

                Section("TODAY") {
                    sidebarRow(.today, badge: todayBadgeCount)
                    sidebarRow(.schedule)
                    sidebarRow(.todo, badge: dataStore.overdueTodos.count)
                }

                Section("PROJECTS") {
                    sidebarRow(.dashboard, badge: dataStore.activeProjects.count)
                    sidebarRow(.rfis, badge: openRFICount)
                    sidebarRow(.invoices, badge: outstandingInvoiceCount)
                    sidebarRow(.reports)
                }

                Section("OPERATIONS") {
                    sidebarRow(.timekeeping, badge: dataStore.activeEmployees.count)
                    sidebarRow(.equipment, badge: dataStore.allActiveRentalCount)
                    sidebarRow(.calendar)
                    sidebarRow(.overhead, badge: dataStore.overheadRecurringTemplates.count)
                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        sidebarRow(.planningPad)
                    }
                    #endif
                }

                Section("PIPELINE") {
                    sidebarRow(.bidding, badge: dataStore.pendingBids.count + dataStore.bids.filter { $0.status == .readyToSubmit }.count)
                    sidebarRow(.clients, badge: dataStore.clients.count)
                }

                Section("TOOLS") {
                    sidebarRow(.assistant)
                    sidebarRow(.activity)
                    sidebarRow(.settings)
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

    /// Quick-access row for a pinned project. Tapping navigates straight to
    /// the project's detail in the Projects section. Right-click → unpin
    /// for fast cleanup.
    @ViewBuilder
    private func pinnedProjectRow(_ project: Project) -> some View {
        Button {
            navigationState.navigate(toProjectID: project.id.recordName)
        } label: {
            Label {
                HStack {
                    Text(project.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                    StatusBadge(text: project.computedStatus,
                                color: project.computedStatus == "Active" ? .green : .secondary)
                        .opacity(0.85)
                }
            } icon: {
                Image(systemName: "pin.fill")
                    .foregroundColor(AppTheme.primaryOrange)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") {
                navigationState.navigate(toProjectID: project.id.recordName)
            }
            Divider()
            Button("Unpin", role: .destructive) {
                navigationState.togglePin(projectID: project.id.recordName)
            }
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

    /// Aggregate count of items needing attention today: overdue todos + overdue
    /// gantt tasks + overdue RFIs across all projects. Drives the Today badge.
    private var todayBadgeCount: Int {
        let overdueTasks = dataStore.overdueTodos.count
        let now = Date()
        let overdueGantt = dataStore.ganttTasks.filter { $0.endDate < now && $0.status != .completed }.count
        var overdueRFIs = 0
        for project in dataStore.projects {
            overdueRFIs += dataStore.rfis(for: project.id).filter { $0.isOverdue }.count
        }
        return overdueTasks + overdueGantt + overdueRFIs
    }

    /// Count of open (non-closed) RFIs across all projects for the RFI sidebar badge.
    private var openRFICount: Int {
        var count = 0
        for project in dataStore.projects {
            count += dataStore.rfis(for: project.id).filter { $0.status != .closed }.count
        }
        return count
    }

    /// Count of invoices currently outstanding (sent/pendingPayment/partiallyPaid/overdue).
    /// Drives the Invoices sidebar badge.
    private var outstandingInvoiceCount: Int {
        dataStore.allInvoices
            .filter { InvoiceStatus.outstandingCases.contains($0.invoice.status) || $0.invoice.isOverdue }
            .count
    }
}
