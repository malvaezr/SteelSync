import SwiftUI

struct ContentView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var navigationState: NavigationState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var detailView: some View {
        switch navigationState.selectedSection {
        case .dashboard:
            DashboardView()
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
        case .reports:
            ReportsView()
        case .activity:
            ActivityView()
        case .none:
            WelcomeView()
        }
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
