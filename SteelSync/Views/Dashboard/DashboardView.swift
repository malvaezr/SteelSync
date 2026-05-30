import SwiftUI
import CloudKit

struct DashboardView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var navigationState: NavigationState
    @State private var selectedFilter = "All"
    @State private var searchText = ""
    @State private var showAddProject = false
    @State private var selectedProject: Project?
    @State private var projectToDelete: Project?
    @State private var sortMode: ProjectSortMode = .startDate

    private let filters = ["All", "Active", "Upcoming", "Completed"]

    enum ProjectSortMode: String, CaseIterable, Identifiable {
        case startDate = "Start Date"
        case alphabetical = "Alphabetical"
        case completion = "Completion"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .startDate: return "calendar"
            case .alphabetical: return "textformat.abc"
            case .completion: return "chart.bar.fill"
            }
        }
    }

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
        switch sortMode {
        case .startDate:
            return result.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        case .alphabetical:
            return result.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .completion:
            return result.sorted { $0.progress > $1.progress }
        }
    }

    var body: some View {
        Group {
            #if os(iOS)
            // Compact iPad (portrait full-screen, Slide Over, narrow Stage
            // Manager) is too narrow for a side-by-side list+detail — drop
            // to a list-only view that opens detail in a full-screen cover.
            // Regular width keeps the existing two-pane HStack.
            GeometryReader { proxy in
                if proxy.size.width < 800 {
                    projectListPane
                        .fullScreenCover(item: $selectedProject) { project in
                            NavigationStack {
                                ProjectDetailView(project: project)
                                    .navigationTitle(project.title)
                                    .navigationBarTitleDisplayMode(.inline)
                                    .toolbar {
                                        ToolbarItem(placement: .cancellationAction) {
                                            Button("Done") { selectedProject = nil }
                                        }
                                    }
                            }
                        }
                } else {
                    PlatformSplitView {
                        projectListPane
                        projectDetailPane
                    }
                }
            }
            #else
            PlatformSplitView {
                projectListPane
                projectDetailPane
            }
            #endif
        }
        .inlineForm(isPresented: $showAddProject) {
            AddProjectView()
        }
        .onAppear { applyRequestedProjectIfAny() }
        .onChange(of: navigationState.requestedProjectID) { _, _ in
            applyRequestedProjectIfAny()
        }
        .sheet(item: $projectToDelete) { project in
            ConfirmationPinSheet(
                title: "Delete Project",
                detail: "\(project.title)\n\nAll costs, payments, payroll, RFIs, change orders, and equipment rentals on this project will be removed. This cannot be undone.",
                confirmLabel: "Delete",
                onConfirm: {
                    dataStore.deleteProject(project)
                    if selectedProject?.id == project.id { selectedProject = nil }
                }
            )
        }
        .navigationTitle("Projects")
    }

    // MARK: - Panes (factored so the body can branch on width)

    @ViewBuilder
    private var projectListPane: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Active Projects",
                subtitle: "\(dataStore.activeProjects.count) active · \(dataStore.upcomingProjects.count) upcoming",
                icon: AppIcons.building
            ) {
                Button {
                    showAddProject = true
                } label: {
                    Label("New Project", systemImage: AppIcons.add)
                }
                .buttonStyle(.appPrimary)
            }

            // Metrics row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    MetricCard(title: "Active Projects", value: "\(dataStore.activeProjects.count)",
                               icon: "hammer.fill", color: AppTheme.ProjectStatus.active)
                    MetricCard(title: "Total Revenue", value: dataStore.totalRevenue.currencyFormatted,
                               icon: AppIcons.money, color: .green)
                    MetricCard(title: "Total Profit", value: dataStore.totalProfit.currencyFormatted,
                               icon: "chart.line.uptrend.xyaxis", color: AppTheme.primaryOrange)
                    MetricCard(title: "Remaining Balance", value: dataStore.totalRemainingBalance.currencyFormatted,
                               icon: AppIcons.money, color: .blue)
                }
                .padding(AppTheme.Spacing.md)
            }
            .frame(height: 120)

            // Filters + sort
            HStack(spacing: AppTheme.Spacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(filters, id: \.self) { filter in
                            FilterPill(filter, isSelected: selectedFilter == filter,
                                       count: countFor(filter: filter)) {
                                selectedFilter = filter
                            }
                        }
                    }
                }
                sortMenu
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.sm)

            // Project list
            let ganttProjectIDs = Set(dataStore.ganttTasks.map(\.projectID))
            List(selection: $selectedProject) {
                ForEach(filteredProjects) { project in
                    ProjectRow(project: project, clientName: dataStore.clientName(for: project),
                               hasGanttTasks: ganttProjectIDs.contains(project.id.recordName))
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
                            Button(navigationState.isPinned(projectID: project.id.recordName)
                                   ? "Unpin from Sidebar"
                                   : "Pin to Sidebar") {
                                navigationState.togglePin(projectID: project.id.recordName)
                            }
                            Divider()
                            Button("Delete…", role: .destructive) { projectToDelete = project }
                        }
                }
            }
            .listStyle(.inset)
            .searchable(text: $searchText, prompt: "Search projects...")
        }
        #if os(macOS)
        .frame(minWidth: 250, idealWidth: 500)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showAddProject = true }) {
                    Label("New Project", systemImage: "plus")
                }
            }
        }
    }

    @ViewBuilder
    private var projectDetailPane: some View {
        if let project = selectedProject {
            ProjectDetailView(project: project)
                #if os(macOS)
                .frame(minWidth: 250, idealWidth: 400)
                #endif
        } else {
            EmptyStateView(icon: "building.2", title: "No Project Selected",
                           message: "Select a project from the list to view details.",
                           buttonTitle: "Add Project") { showAddProject = true }
            #if os(macOS)
            .frame(minWidth: 250, idealWidth: 400)
            #endif
        }
    }

    /// Honors a navigation request from a Pinned project tap. Picks the
    /// project as the detail and clears the pending intent so the same
    /// click doesn't fire repeatedly.
    private func applyRequestedProjectIfAny() {
        guard let id = navigationState.requestedProjectID,
              let project = dataStore.projects.first(where: { $0.id.recordName == id }) else { return }
        selectedProject = project
        navigationState.requestedProjectID = nil
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

    /// Dropdown to arrange the project list by start date, name, or completion.
    private var sortMenu: some View {
        Menu {
            ForEach(ProjectSortMode.allCases) { mode in
                Button {
                    sortMode = mode
                } label: {
                    if sortMode == mode {
                        Label(mode.rawValue, systemImage: "checkmark")
                    } else {
                        Label(mode.rawValue, systemImage: mode.icon)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Text(sortMode.rawValue)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9))
            }
            .font(.caption)
            .foregroundColor(AppTheme.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppTheme.primaryText.opacity(0.1), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort projects")
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
                    Label(project.location, systemImage: AppIcons.location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(project.contractAmount.currencyFormatted)
                    .font(.callout)
                    .fontWeight(.semibold)
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                Text(project.totalRevenue.currencyFormatted)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .fixedSize()
                Text(project.profit.currencyFormatted)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(project.profit >= 0 ? .green : .red)
                    .lineLimit(1)
                    .fixedSize()
                Spacer()
                ProgressBar(value: project.progress, color: statusColor)
                    .frame(width: 60)
                Text("\(Int(project.progress * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}
