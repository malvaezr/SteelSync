import SwiftUI
import CloudKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SidebarView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var navigationState: NavigationState
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showSyncOptions = false
    @State private var pendingShare: CKShare?
    @State private var shareError: String?
    @State private var isPreparingShare = false
    /// Spike scaffolding: holds the timesheets-zone share URL after it's copied
    /// to the clipboard, to surface it in a confirmation alert.
    @State private var timesheetsShareURL: String?

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
            logoHeader

            List(selection: $navigationState.selectedSection) {
                if !pinnedProjects.isEmpty {
                    Section {
                        ForEach(pinnedProjects) { project in
                            pinnedProjectRow(project)
                        }
                    } header: { glassSectionLabel("Pinned") }
                }

                Section {
                    sidebarRow(.today, badge: todayBadgeCount)
                    sidebarRow(.schedule)
                    sidebarRow(.todo, badge: dataStore.overdueTodos.count)
                } header: { glassSectionLabel("Today") }

                Section {
                    sidebarRow(.dashboard, badge: dataStore.activeProjects.count)
                    sidebarRow(.rfis, badge: openRFICount)
                    sidebarRow(.invoices, badge: outstandingInvoiceCount)
                    sidebarRow(.reports)
                } header: { glassSectionLabel("Projects") }

                Section {
                    sidebarRow(.timekeeping, badge: dataStore.activeEmployees.count)
                    sidebarRow(.equipment, badge: dataStore.allActiveRentalCount)
                    sidebarRow(.calendar)
                    sidebarRow(.overhead, badge: dataStore.overheadRecurringTemplates.count)
                    #if os(iOS)
                    if UIDevice.current.userInterfaceIdiom == .pad {
                        sidebarRow(.planningPad)
                    }
                    #endif
                } header: { glassSectionLabel("Operations") }

                Section {
                    sidebarRow(.bidding, badge: dataStore.pendingBids.count + dataStore.bids.filter { $0.status == .readyToSubmit }.count)
                    sidebarRow(.clients, badge: dataStore.clients.count)
                } header: { glassSectionLabel("Pipeline") }

                Section {
                    sidebarRow(.assistant)
                    sidebarRow(.activity)
                    sidebarRow(.settings)
                } header: { glassSectionLabel("Tools") }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(themeManager.glassEnabled ? .hidden : .automatic)

            Divider()

            syncButton
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .background {
            // Frosted glass chrome: the regular material blurs the graphite
            // wallpaper behind it (§3 — sidebar gets blur). Legacy themes keep
            // the system sidebar appearance.
            if themeManager.glassEnabled {
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
            }
        }
        .navigationTitle("SteelSync")
        .confirmationDialog("Sync Options", isPresented: $showSyncOptions) {
            Button("Push Local → Cloud") {
                Task { await dataStore.pushToCloud() }
            }
            Button("Pull Cloud → Local") {
                Task { await dataStore.pullFromCloud() }
            }
            if !dataStore.cloudKit.isParticipant {
                Button("Share Data…") {
                    Task { await prepareShare() }
                }
                Button("Share Timesheets Zone…") {
                    Task { await prepareTimesheetsShare() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(syncDialogMessage)
        }
        .sheet(isPresented: Binding(get: { pendingShare != nil }, set: { if !$0 { pendingShare = nil } })) {
            if let share = pendingShare, let container = dataStore.cloudKit.ckContainer {
                CloudShareSheet(share: share, container: container) {
                    pendingShare = nil
                }
            }
        }
        .alert("Couldn't create share", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("OK", role: .cancel) { shareError = nil }
        } message: {
            Text(shareError ?? "")
        }
        .alert("Timesheets share link copied", isPresented: Binding(get: { timesheetsShareURL != nil }, set: { if !$0 { timesheetsShareURL = nil } })) {
            Button("OK", role: .cancel) { timesheetsShareURL = nil }
        } message: {
            Text("Copied to your clipboard — send it to a foreman to invite them to the timesheets zone:\n\n\(timesheetsShareURL ?? "")")
        }
    }

    private func prepareShare() async {
        isPreparingShare = true
        defer { isPreparingShare = false }
        do {
            let share = try await dataStore.cloudKit.ensureZoneShare()
            pendingShare = share
        } catch {
            shareError = error.localizedDescription
        }
    }

    /// Spike scaffolding: create/return the timesheets-zone share, copy its URL
    /// to the clipboard, and surface it in an alert so it can be sent to a
    /// foreman. Replace with the production invite UI once the spike is proven.
    private func prepareTimesheetsShare() async {
        isPreparingShare = true
        defer { isPreparingShare = false }
        do {
            let share = try await dataStore.cloudKit.ensureTimesheetsZoneShare()
            // Publish the minimal crew/project roster into the timesheets zone so
            // invited foremen get pickers (no financials are exposed).
            await dataStore.cloudKit.publishRosterToTimesheetsZone(
                employees: dataStore.activeEmployees, projects: dataStore.activeProjects)
            guard let url = share.url else {
                shareError = "Share created but no URL yet — tap “Share Timesheets Zone…” again in a moment."
                return
            }
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            #else
            UIPasteboard.general.string = url.absoluteString
            #endif
            timesheetsShareURL = url.absoluteString
        } catch {
            shareError = error.localizedDescription
        }
    }

    /// Brand banner at the top of the sidebar. The PNG already contains the
    /// "Steel Sync" wordmark, so no extra Text is needed alongside.
    private var logoHeader: some View {
        VStack(spacing: 0) {
            Image("SteelSyncLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 64)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
            Divider()
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

    /// Section label per the Glass spec (§4): 11/600, tertiary, sentence case —
    /// never the system's auto-uppercased sidebar header. `.textCase(nil)`
    /// suppresses that uppercasing.
    @ViewBuilder
    private func glassSectionLabel(_ text: String) -> some View {
        if themeManager.glassEnabled {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppTheme.tertiaryText)
                .textCase(nil)
                .tracking(0.4)
        } else {
            Text(text.uppercased())
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
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(AppTheme.primaryOrange.opacity(0.18))
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
            if dataStore.cloudKit.isParticipant {
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 9))
                    Text("Shared mode")
                        .font(.system(size: 10, weight: .medium))
                    Spacer()
                }
                .foregroundColor(AppTheme.primaryOrange)
            }

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
                    Text(syncPrimaryLabel)
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
                if dataStore.syncBytesTotal > 0 {
                    HStack {
                        Text("~\(formatBytes(dataStore.syncBytesDone)) of \(formatBytes(dataStore.syncBytesTotal))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary.opacity(0.8))
                        Spacer()
                    }
                }
                ProgressView(value: dataStore.syncProgress)
                    .tint(AppTheme.primaryOrange)
            }
        }
    }

    private var syncPrimaryLabel: String {
        let base = dataStore.syncStatus.displayText
        if dataStore.isSyncing && dataStore.syncItemsTotal > 0 {
            return "\(base) \(dataStore.syncItemsDone) of \(dataStore.syncItemsTotal) items"
        }
        return base
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
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
