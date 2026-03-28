import SwiftUI
import CloudKit

struct DashboardView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedFilter = "All"
    @State private var searchText = ""
    @State private var showAddProject = false
    @State private var selectedProject: Project?

    private let filters = ["All", "Active", "Upcoming", "Completed"]

    var filteredProjects: [Project] {
        var result = dataStore.projects
        if selectedFilter != "All" {
            result = result.filter { $0.computedStatus == selectedFilter }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.location.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    var body: some View {
        PlatformSplitView {
            // Left: Project list
            VStack(spacing: 0) {
                // Metrics row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        MetricCard(title: "Active Projects", value: "\(dataStore.activeProjects.count)",
                                   icon: "hammer.fill", color: AppTheme.ProjectStatus.active)
                        MetricCard(title: "Total Revenue", value: dataStore.totalRevenue.currencyFormatted,
                                   icon: "dollarsign.circle.fill", color: .green)
                        MetricCard(title: "Total Profit", value: dataStore.totalProfit.currencyFormatted,
                                   icon: "chart.line.uptrend.xyaxis", color: AppTheme.primaryOrange)
                        MetricCard(title: "Remaining Balance", value: dataStore.totalRemainingBalance.currencyFormatted,
                                   icon: "banknote.fill", color: .blue)
                    }
                    .padding(AppTheme.Spacing.md)
                }
                .frame(height: 120)

                // Filters
                HStack(spacing: AppTheme.Spacing.sm) {
                    ForEach(filters, id: \.self) { filter in
                        FilterPill(filter, isSelected: selectedFilter == filter,
                                   count: countFor(filter: filter)) {
                            selectedFilter = filter
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.sm)

                // Project list
                List(selection: $selectedProject) {
                    ForEach(filteredProjects) { project in
                        ProjectRow(project: project, clientName: dataStore.clientName(for: project),
                                   hasGanttTasks: dataStore.ganttTasks.contains { $0.projectID == project.id.recordName })
                            .tag(project)
                            .contextMenu {
                                Button("Edit") { selectedProject = project }
                                Divider()
                                if project.computedStatus != "Completed" {
                                    Button("Mark as Completed") {
                                        var updated = project
                                        updated.status = "Completed"
                                        updated.actualCompletionDate = Date()
                                        dataStore.updateProject(updated)
                                    }
                                }
                                if project.computedStatus == "Completed" {
                                    Button("Reopen Project") {
                                        var updated = project
                                        updated.status = "Active"
                                        updated.actualCompletionDate = nil
                                        dataStore.updateProject(updated)
                                    }
                                }
                                Divider()
                                Button("Delete", role: .destructive) { dataStore.deleteProject(project) }
                            }
                    }
                }
                .listStyle(.inset)
                .searchable(text: $searchText, prompt: "Search projects...")
            }
            #if os(macOS)
            .frame(minWidth: 400, idealWidth: 500)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showAddProject = true }) {
                        Label("New Project", systemImage: "plus")
                    }
                }
            }

            // Right: Project detail
            if let project = selectedProject {
                ProjectDetailView(project: project)
                    #if os(macOS)
                    .frame(minWidth: 350)
                    #endif
            } else {
                EmptyStateView(icon: "building.2", title: "No Project Selected",
                               message: "Select a project from the list to view details.",
                               buttonTitle: "Add Project") { showAddProject = true }
                #if os(macOS)
                .frame(minWidth: 350)
                #endif
            }
        }
        .sheet(isPresented: $showAddProject) {
            AddProjectView()
        }
        .navigationTitle("Projects")
    }

    private func countFor(filter: String) -> Int? {
        switch filter {
        case "All": return dataStore.projects.count
        case "Active": return dataStore.activeProjects.count
        case "Upcoming": return dataStore.upcomingProjects.count
        case "Completed": return dataStore.completedProjects.count
        default: return nil
        }
    }
}

// MARK: - Project Row
struct ProjectRow: View {
    let project: Project
    var clientName: String? = nil
    var hasGanttTasks: Bool = false

    var statusColor: Color {
        switch project.computedStatus {
        case "Active": return AppTheme.ProjectStatus.active
        case "Upcoming": return AppTheme.ProjectStatus.upcoming
        case "Completed": return AppTheme.ProjectStatus.completed
        default: return AppTheme.ProjectStatus.onHold
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(project.title)
                            .font(.headline)
                        if hasGanttTasks {
                            Image(systemName: "calendar.day.timeline.left")
                                .font(.caption2)
                                .foregroundColor(AppTheme.primaryOrange)
                                .help("Has Gantt schedule")
                        }
                    }
                    if let clientName = clientName {
                        Text(clientName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                StatusBadge(text: project.computedStatus, color: statusColor)
            }

            HStack {
                if !project.location.isEmpty {
                    Label(project.location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(project.contractAmount.currencyFormatted)
                    .font(.callout)
                    .fontWeight(.semibold)
            }

            HStack(spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading) {
                    Text("Revenue")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(project.totalRevenue.currencyFormatted)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                VStack(alignment: .leading) {
                    Text("Profit")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(project.profit.currencyFormatted)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(project.profit >= 0 ? .green : .red)
                }
                Spacer()
                ProgressBar(value: project.progress, color: statusColor)
                    .frame(width: 80)
                Text("\(Int(project.progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}
