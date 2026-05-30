import SwiftUI

// MARK: - Compact-width iPad navigation (Glass spec §6.1)
//
// When the iPad is in compact horizontal width (portrait, Slide Over, narrow
// Stage Manager) the sidebar collapses and the destinations surface through a
// bottom tab bar instead. Regular width (landscape full-screen, wide Stage
// Manager) keeps the existing `NavigationSplitView` in `ContentView`.
//
// Routes/destinations are identical to the sidebar — only the chrome differs,
// which §0 explicitly allows. Capture is a presentation action (sheet), not a
// new destination.
//
// File-gated on `!STEELSYNC_PHONE` because the "More" tab surfaces
// `AssistantView` / `SettingsView`, both excluded from the phone target.

#if os(iOS) && !STEELSYNC_PHONE

struct iPadCompactRoot: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var navigationState: NavigationState

    @State private var selectedTab: Tab = .today
    @State private var showCapture = false
    @State private var lastNonCaptureTab: Tab = .today

    enum Tab: Hashable { case today, schedule, capture, projects, more }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "sun.max.fill") }
                .tag(Tab.today)

            NavigationStack { GanttChartView() }
                .tabItem { Label("Schedule", systemImage: "calendar.day.timeline.left") }
                .tag(Tab.schedule)

            // Capture is a presentation action (§6.1), not a destination.
            // Selecting the tab surfaces the capture sheet and snaps the
            // selection back so the user lands on their previous tab when
            // they dismiss the sheet.
            Color.clear
                .tabItem { Label("Capture", systemImage: "plus.app.fill") }
                .tag(Tab.capture)

            NavigationStack { DashboardView() }
                .tabItem { Label("Projects", systemImage: "building.2.fill") }
                .tag(Tab.projects)

            NavigationStack { MoreListView() }
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(Tab.more)
        }
        .tint(AppTheme.primaryOrange)
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .capture {
                showCapture = true
                selectedTab = lastNonCaptureTab
            } else {
                lastNonCaptureTab = newTab
            }
        }
        .sheet(isPresented: $showCapture) {
            CaptureSheet()
                .environmentObject(dataStore)
                .environmentObject(navigationState)
        }
        .sheet(isPresented: $navigationState.showGlobalSearch) {
            GlobalSearchSheet()
                .environmentObject(dataStore)
                .environmentObject(navigationState)
        }
    }
}

// MARK: - Capture sheet
//
// Phase 3 baseline — wraps existing entry actions. The Pencil markup / photo
// / scanner tiles ship disabled here; Phase 4 wires them up per spec §6.5.

private struct CaptureSheet: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var navigationState: NavigationState
    @Environment(\.dismiss) var dismiss

    @State private var pickingForQuickEntry = false
    @State private var quickEntryProject: Project?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: 14)],
                    spacing: 14
                ) {
                    tile("Quick Entry",
                         subtitle: "Payroll · costs · change orders",
                         icon: "bolt.fill",
                         color: AppTheme.primaryOrange) {
                        pickingForQuickEntry = true
                    }
                    tile("Find Anything",
                         subtitle: "Global search",
                         icon: "magnifyingglass",
                         color: Glass.sub) {
                        dismiss()
                        // Wait for the sheet to finish dismissing before the
                        // next sheet animates in — avoids a presentation race.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            navigationState.showGlobalSearch = true
                        }
                    }
                    tile("Photo / Scan",
                         subtitle: "Coming with Pencil markup",
                         icon: "camera.fill",
                         color: AppTheme.tertiaryText,
                         disabled: true) { }
                    tile("Pencil Markup",
                         subtitle: "Coming in Phase 4",
                         icon: "pencil.tip",
                         color: AppTheme.tertiaryText,
                         disabled: true) { }
                }
                .padding(20)
            }
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $pickingForQuickEntry) {
                CaptureProjectPicker { picked in
                    pickingForQuickEntry = false
                    quickEntryProject = picked
                }
                .environmentObject(dataStore)
            }
            .sheet(item: $quickEntryProject) { project in
                QuickEntrySheet(project: project)
                    .environmentObject(dataStore)
            }
        }
    }

    @ViewBuilder
    private func tile(_ title: String,
                      subtitle: String,
                      icon: String,
                      color: Color,
                      disabled: Bool = false,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(color)
                    )
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .appPanel(cornerRadius: 16)
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Capture → Quick Entry project picker

private struct CaptureProjectPicker: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    let onPick: (Project) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Choose a project") {
                    ForEach(dataStore.activeProjects) { project in
                        Button {
                            onPick(project)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.title)
                                        .font(.callout)
                                        .foregroundColor(.primary)
                                    if !project.location.isEmpty {
                                        Text(project.location)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Quick Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - "More" tab — remaining destinations (mirrors the sidebar's IA)

private struct MoreListView: View {
    var body: some View {
        List {
            Section("Today") {
                moreLink("Tasks", icon: SidebarItem.todo.icon) { TodoView() }
            }
            Section("Projects") {
                moreLink("RFIs", icon: SidebarItem.rfis.icon) { RFILogView() }
                moreLink("Invoices", icon: SidebarItem.invoices.icon) { InvoicesView() }
                moreLink("Reports", icon: SidebarItem.reports.icon) { ReportsView() }
            }
            Section("Operations") {
                moreLink("Crew & Timesheets", icon: SidebarItem.timekeeping.icon) { TimekeepingView() }
                moreLink("Equipment", icon: SidebarItem.equipment.icon) { EquipmentOverviewView() }
                moreLink("Calendar", icon: SidebarItem.calendar.icon) { CalendarMainView() }
                moreLink("Overhead", icon: SidebarItem.overhead.icon) { OverheadView() }
                moreLink("Planning Pad", icon: SidebarItem.planningPad.icon) { PlanningPadView() }
            }
            Section("Pipeline") {
                moreLink("Bidding", icon: SidebarItem.bidding.icon) { BiddingView() }
                moreLink("Clients", icon: SidebarItem.clients.icon) { ClientsView() }
            }
            Section("Tools") {
                moreLink("Assistant", icon: SidebarItem.assistant.icon) { AssistantView() }
                moreLink("Activity", icon: SidebarItem.activity.icon) { ActivityView() }
                moreLink("Settings", icon: SidebarItem.settings.icon) { SettingsView() }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("More")
    }

    @ViewBuilder
    private func moreLink<V: View>(
        _ title: String,
        icon: String,
        @ViewBuilder destination: @escaping () -> V
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label(title, systemImage: icon)
        }
    }
}

#endif
