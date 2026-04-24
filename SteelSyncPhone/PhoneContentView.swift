import SwiftUI

/// Root container for SteelSync Field (iPhone). 4-tab layout focused on mobile
/// workflows: Today briefing, Projects, Tasks, and More (secondary actions).
/// Handles deep-link URLs from widgets to jump to a specific tab/filter.
struct PhoneContentView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedTab: Tab = .today
    @State private var tasksFilter: String? = nil
    @State private var morePath: MoreDestination? = nil

    enum Tab: Hashable {
        case today, projects, tasks, more
    }

    enum MoreDestination: Hashable {
        case invoices, rfis, timeClock, equipment, reports, employees
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            PhoneTodayView(selectedTab: $selectedTab, moreDestination: $morePath)
                .tabItem {
                    Label("Today", systemImage: "sun.max.fill")
                }
                .tag(Tab.today)

            PhoneProjectsView()
                .tabItem {
                    Label("Projects", systemImage: "building.2.fill")
                }
                .tag(Tab.projects)

            PhoneTasksView(initialFilter: tasksFilter)
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }
                .tag(Tab.tasks)

            PhoneMoreView(destination: $morePath)
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
                .tag(Tab.more)
        }
        .tint(AppTheme.primaryOrange)
        .task {
            await dataStore.pullFromCloud()
        }
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }

    /// Handles widget deep-links of the form steelsync://<section>?filter=<value>
    /// Widgets use widgetURL() with these URLs to jump the user directly to the
    /// relevant tab + filter.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "steelsync" else { return }
        let host = url.host ?? ""
        let filter = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "filter" })?.value

        switch host {
        case "today":
            selectedTab = .today
        case "projects":
            selectedTab = .projects
        case "tasks":
            tasksFilter = filter
            selectedTab = .tasks
        case "invoices":
            morePath = .invoices
            selectedTab = .more
        case "rfis":
            morePath = .rfis
            selectedTab = .more
        case "timeclock":
            morePath = .timeClock
            selectedTab = .more
        default:
            break
        }
    }
}
