import SwiftUI

struct PhoneProjectsView: View {
    @EnvironmentObject var dataStore: DataStore

    @State private var searchText = ""
    @State private var selectedFilter = "All"

    private let filters = ["All", "Active", "Upcoming", "Completed"]

    private var filteredProjects: [Project] {
        let base: [Project]
        switch selectedFilter {
        case "Active": base = dataStore.activeProjects
        case "Upcoming": base = dataStore.upcomingProjects
        case "Completed": base = dataStore.completedProjects
        default: base = dataStore.projects
        }

        if searchText.isEmpty { return base }
        let query = searchText.lowercased()
        return base.filter { project in
            project.title.lowercased().contains(query) ||
            project.location.lowercased().contains(query) ||
            (dataStore.clientName(for: project)?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(filters, id: \.self) { filter in
                            FilterPill(filter, isSelected: selectedFilter == filter, count: countFor(filter)) {
                                selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                if filteredProjects.isEmpty {
                    EmptyStateView(
                        icon: "folder",
                        title: "No Projects",
                        message: searchText.isEmpty ? "No projects match this filter." : "No projects match \"\(searchText)\"."
                    )
                } else {
                    List {
                        ForEach(filteredProjects) { project in
                            NavigationLink(value: project) {
                                ProjectListRow(project: project, clientName: dataStore.clientName(for: project),
                                               hasGanttTasks: dataStore.ganttTasks.contains { $0.projectID == project.id.recordName })
                                    .swipeActions(edge: .trailing) {
                                        if project.computedStatus != "Completed" {
                                            Button("Complete") {
                                                var updated = project
                                                updated.status = "Completed"
                                                updated.actualCompletionDate = Date()
                                                dataStore.updateProject(updated)
                                            }
                                            .tint(.green)
                                        } else {
                                            Button("Reopen") {
                                                var updated = project
                                                updated.status = "Active"
                                                updated.actualCompletionDate = nil
                                                dataStore.updateProject(updated)
                                            }
                                            .tint(.blue)
                                        }
                                    }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: Project.self) { project in
                PhoneProjectDetailView(project: project)
            }
            .searchable(text: $searchText, prompt: "Search projects...")
            .refreshable {
                if dataStore.cloudKitAvailable {
                    await dataStore.pullFromCloud()
                }
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
}

// MARK: - Project List Row

private struct ProjectListRow: View {
    let project: Project
    let clientName: String?
    var hasGanttTasks: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Text(project.title)
                        .font(AppTheme.Typography.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if hasGanttTasks {
                        Image(systemName: "calendar.day.timeline.left")
                            .font(.system(size: 10))
                            .foregroundColor(AppTheme.primaryOrange)
                    }
                }
                Spacer()
                StatusBadge(text: project.computedStatus, color: statusColor(for: project.computedStatus))
            }

            if let name = clientName {
                Text(name)
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(1)
            }

            HStack {
                Text(project.contractAmount.currencyFormatted)
                    .font(AppTheme.Typography.footnote)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.primaryOrange)

                Spacer()

                if !project.location.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 10))
                        Text(project.location)
                            .lineLimit(1)
                    }
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.tertiaryText)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Helpers

private func statusColor(for status: String) -> Color {
    switch status {
    case "Active": return AppTheme.ProjectStatus.active
    case "Upcoming": return AppTheme.ProjectStatus.upcoming
    case "Completed": return AppTheme.ProjectStatus.completed
    default: return AppTheme.ProjectStatus.onHold
    }
}
