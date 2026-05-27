import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var navigationState: NavigationState

    var body: some View {
        NavigationSplitView(columnVisibility: $navigationState.columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detailView
                // Hybrid wallpaper policy: the detail area defaults to flat
                // graphite so dense data screens stay legible; overview screens
                // (e.g. Today) opt into the gradient via .glassScreenBackground(true).
                .background(AppTheme.background)
                .modifier(IPadMenuCollapseToolbar(visibility: $navigationState.columnVisibility))
        }
        .navigationSplitViewStyle(.balanced)
        .glassGroupBoxes()
        .sheet(isPresented: $navigationState.showGlobalSearch) {
            GlobalSearchSheet()
                .environmentObject(dataStore)
                .environmentObject(navigationState)
        }
        #if os(iOS)
        // On iPad, picking a section auto-hides the sidebar so the inner
        // list+detail (which is itself two panes) gets the full screen. The
        // user complained that 3 panes (sidebar + list + detail) feels too
        // dense; this brings it back to 2.
        .onChange(of: navigationState.selectedSection) { _, newValue in
            guard newValue != nil,
                  UIDevice.current.userInterfaceIdiom == .pad else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                navigationState.columnVisibility = .detailOnly
            }
        }
        #endif
    }

    @ViewBuilder
    private var detailView: some View {
        switch navigationState.selectedSection {
        case .today:
            TodayView()
        case .dashboard:
            DashboardView()
        case .rfis:
            RFILogView()
        case .invoices:
            InvoicesView()
        case .clients:
            ClientsView()
        case .bidding:
            BiddingView()
        case .timekeeping:
            TimekeepingView()
        case .schedule:
            GanttChartView()
        case .equipment:
            EquipmentOverviewView()
        case .todo:
            TodoView()
        case .calendar:
            CalendarMainView()
        case .overhead:
            OverheadView()
        case .reports:
            ReportsView()
        case .activity:
            ActivityView()
        case .planningPad:
            #if os(macOS)
            WelcomeView()
            #else
            PlanningPadView()
            #endif
        case .assistant:
            AssistantView()
        case .settings:
            SettingsView()
        case .none:
            TodayView()
        }
    }
}

/// On iPad, surfaces a "Menu" button in the leading toolbar of the detail
/// column whenever the sidebar is hidden — giving the user an explicit way
/// back to the first menu without hunting for the system sidebar toggle.
/// No-op on macOS and iPhone (where there's no NavigationSplitView sidebar
/// to collapse in the first place).
struct IPadMenuCollapseToolbar: ViewModifier {
    @Binding var visibility: NavigationSplitViewVisibility

    func body(content: Content) -> some View {
        #if os(iOS)
        content.toolbar {
            if UIDevice.current.userInterfaceIdiom == .pad,
               visibility != .all {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            visibility = .all
                        }
                    } label: {
                        Label("Menu", systemImage: "sidebar.left")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityLabel("Back to main menu")
                }
            }
        }
        #else
        content
        #endif
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "building.2.fill")
                .font(.system(size: 64))
                .foregroundColor(AppTheme.primaryOrange)
            Text("SteelSync")
                .font(AppTheme.Typography.largeTitle)
            Text("Steel Erection Project Management")
                .font(AppTheme.Typography.title3)
                .foregroundColor(AppTheme.secondaryText)
            Text("Select a section from the sidebar to get started.")
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
