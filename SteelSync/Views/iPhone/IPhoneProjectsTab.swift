#if STEELSYNC_IPHONE
import SwiftUI

struct IPhoneProjectsTab: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var searchText = ""
    @State private var selectedFilter = "All"

    private let filters = ["All", "Active", "Upcoming", "Completed"]

    private var filteredProjects: [Project] {
        let byStatus: [Project]
        switch selectedFilter {
        case "Active": byStatus = dataStore.activeProjects
        case "Upcoming": byStatus = dataStore.upcomingProjects
        case "Completed": byStatus = dataStore.completedProjects
        default: byStatus = dataStore.projects
        }
        if searchText.isEmpty { return byStatus }
        return byStatus.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.location.localizedCaseInsensitiveContains(searchText) ||
            (dataStore.clientName(for: $0) ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "Active": return AppTheme.ProjectStatus.active
        case "Upcoming": return AppTheme.ProjectStatus.upcoming
        case "Completed": return AppTheme.ProjectStatus.completed
        default: return AppTheme.ProjectStatus.onHold
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(filters, id: \.self) { filter in
                            FilterPill(filter, isSelected: selectedFilter == filter,
                                       count: countFor(filter)) {
                                selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                if filteredProjects.isEmpty {
                    EmptyStateView(
                        icon: "building.2",
                        title: "No Projects",
                        message: "No projects match your current filter."
                    )
                } else {
                    List {
                        ForEach(filteredProjects) { project in
                            NavigationLink(value: project) {
                                ProjectRowView(project: project)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Projects")
            .searchable(text: $searchText, prompt: "Search projects")
            .refreshable {
                await dataStore.pullFromCloud()
            }
            .navigationDestination(for: Project.self) { project in
                IPhoneProjectDetailView(project: project)
            }
        }
    }

    private func countFor(_ filter: String) -> Int? {
        switch filter {
        case "Active": return dataStore.activeProjects.count
        case "Upcoming": return dataStore.upcomingProjects.count
        case "Completed": return dataStore.completedProjects.count
        case "All": return dataStore.projects.count
        default: return nil
        }
    }

    // MARK: - Project Row
    @ViewBuilder
    private func ProjectRowView(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(project.title)
                    .font(.headline)
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                StatusBadge(
                    text: project.computedStatus,
                    color: statusColor(for: project.computedStatus)
                )
            }

            if let clientName = dataStore.clientName(for: project) {
                Text(clientName)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(1)
            }

            HStack {
                if !project.location.isEmpty {
                    Label(project.location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundColor(AppTheme.tertiaryText)
                        .lineLimit(1)
                }
                Spacer()
                Text(project.contractAmount.currencyFormatted)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.primaryOrange)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
