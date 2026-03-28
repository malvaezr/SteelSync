import SwiftUI

struct PhoneContentView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            PhoneDashboardView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            PhoneTimeClockView()
                .tabItem {
                    Label("Time Clock", systemImage: "clock.fill")
                }
                .tag(1)

            PhoneProjectsView()
                .tabItem {
                    Label("Projects", systemImage: "building.2.fill")
                }
                .tag(2)

            PhoneTasksView()
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }
                .tag(3)

            PhoneMoreView()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tag(4)
        }
        .tint(AppTheme.primaryOrange)
        .task {
            await dataStore.pullFromCloud()
        }
    }
}
