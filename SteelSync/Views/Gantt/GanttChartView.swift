import SwiftUI
import CloudKit

struct GanttChartView: View {
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var vm = GanttViewModel()
    @State private var showAddTask = false
    @State private var editingTask: GanttTask?
    @State private var selectedProjectFilter: String? = nil

    // Distinct colors for each project
    private let projectPalette: [Color] = [
        .orange, .cyan, .green, .pink, .yellow, .purple, .mint, .indigo, .teal, .red,
        .blue, Color(red: 1, green: 0.6, blue: 0.2), Color(red: 0.4, green: 0.8, blue: 0.4),
        Color(red: 0.8, green: 0.4, blue: 0.8), Color(red: 0.3, green: 0.7, blue: 0.9)
    ]

    func projectColor(for projectID: String) -> Color {
        guard let idx = dataStore.projects.firstIndex(where: { $0.id.recordName == projectID }) else {
            return AppTheme.primaryOrange
        }
        return projectPalette[idx % projectPalette.count]
    }

    var allTasks: [GanttTask] { dataStore.ganttTasks }

    var filteredTasks: [GanttTask] {
        if let filter = selectedProjectFilter {
            return allTasks.filter { $0.projectID == filter }.sorted { $0.sortOrder < $1.sortOrder }
        }
        return allTasks.sorted { $0.sortOrder < $1.sortOrder }
    }

    // Group tasks by project for the master view
    var projectGroups: [(project: Project, tasks: [GanttTask])] {
        var groups: [(Project, [GanttTask])] = []
        for project in dataStore.projects {
            let tasks = allTasks.filter { $0.projectID == project.id.recordName }
                .sorted { $0.sortOrder < $1.sortOrder }
            if !tasks.isEmpty || selectedProjectFilter == project.id.recordName {
                groups.append((project, tasks))
            }
        }
        return groups
    }

    // Build flat row list for rendering
    enum GanttRow: Identifiable {
        case projectHeader(Project)
        case task(GanttTask)

        var id: String {
            switch self {
            case .projectHeader(let p): return "header-\(p.id.recordName)"
            case .task(let t): return "task-\(t.id.uuidString)"
            }
        }
    }

    var rows: [GanttRow] {
        if selectedProjectFilter != nil {
            return filteredTasks.map { .task($0) }
        }
        var result: [GanttRow] = []
        for (project, tasks) in projectGroups {
            result.append(.projectHeader(project))
            result += tasks.map { .task($0) }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            GeometryReader { geo in
                let availHeight = geo.size.height
                let contentTimelineHeight = max(timelineHeight, availHeight)

                HStack(spacing: 0) {
                    // Left panel: task list
                    taskListPanel
                        .frame(width: vm.taskListWidth, height: availHeight)

                    Divider()

                    // Right panel: timeline
                    ScrollView([.horizontal, .vertical]) {
                        ZStack(alignment: .topLeading) {
                            // Layer 1: Grid background (Canvas)
                            GanttTimelineGridView(vm: vm, tasks: filteredTasks)
                                .frame(width: max(vm.totalWidth(tasks: filteredTasks), geo.size.width - vm.taskListWidth),
                                       height: contentTimelineHeight)

                            // Layer 2: Task bars
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                if case .task(let task) = row {
                                    GanttTaskBarView(
                                        task: task, vm: vm, allTasks: filteredTasks,
                                        projectColor: projectColor(for: task.projectID),
                                        onEdit: { editingTask = task },
                                        onUpdate: { updated in dataStore.updateGanttTask(updated) }
                                    )
                                    .position(
                                        x: vm.xPosition(for: task.startDate, tasks: filteredTasks) + vm.barWidth(for: task) / 2,
                                        y: yOffset(for: index) + (isHeader(row) ? vm.projectHeaderHeight : vm.rowHeight) / 2
                                    )
                                } else if case .projectHeader(let project) = row {
                                    projectHeaderBar(project: project, yPos: yOffset(for: index))
                                }
                            }

                            // Layer 3: Today marker
                            GanttTodayMarkerView(vm: vm, tasks: filteredTasks, height: contentTimelineHeight)
                        }
                    }
                    .frame(height: availHeight)
                    #if !os(macOS)
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                vm.applyPinchScale(value.magnification)
                            }
                            .onEnded { _ in
                                vm.dayWidthBeforePinch = vm.dayWidth
                            }
                    )
                    #endif
                }
                .onAppear {
                    if allTasks.isEmpty { dataStore.generateSampleGanttTasks() }
                    vm.fitToWindow(tasks: filteredTasks,
                                   availableWidth: geo.size.width - vm.taskListWidth)
                }
            }
        }
        .sheet(isPresented: $showAddTask) {
            GanttTaskEditSheet(projects: dataStore.projects, selectedProjectID: selectedProjectFilter) { newTask in
                dataStore.addGanttTask(newTask)
            }
        }
        .sheet(item: $editingTask) { task in
            GanttTaskEditSheet(projects: dataStore.projects, editingTask: task) { updated in
                dataStore.updateGanttTask(updated)
            } onDelete: {
                dataStore.deleteGanttTask(task)
            }
        }
        .navigationTitle("Schedule")
    }

    // MARK: - Toolbar
    private var toolbar: some View {
        #if os(macOS)
        HStack(spacing: AppTheme.Spacing.md) {
            // Project filter
            Picker("Project", selection: $selectedProjectFilter) {
                Text("All Projects").tag(String?.none)
                ForEach(dataStore.projects) { project in
                    Text(project.title).tag(Optional(project.id.recordName))
                }
            }
            .frame(width: 220)

            Spacer()

            // Category legend
            HStack(spacing: 6) {
                ForEach(TaskCategory.allCases) { cat in
                    HStack(spacing: 3) {
                        Circle().fill(cat.color).frame(width: 8, height: 8)
                        Text(cat.rawValue).font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Zoom controls
            HStack(spacing: 4) {
                Button(action: vm.zoomOut) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Text("\(Int(vm.dayWidth))px")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 30)

                Button(action: vm.zoomIn) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Button("Fit") {
                    // Will be called in onAppear with proper geo
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(action: { showAddTask = true }) {
                Label("Add Task", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.primaryOrange)
            .controlSize(.small)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.secondaryBackground)
        #else
        VStack(spacing: 4) {
            // Row 1: Project picker + zoom controls + Add Task
            HStack(spacing: AppTheme.Spacing.md) {
                Picker("Project", selection: $selectedProjectFilter) {
                    Text("All Projects").tag(String?.none)
                    ForEach(dataStore.projects) { project in
                        Text(project.title).tag(Optional(project.id.recordName))
                    }
                }
                .frame(width: 220)

                Spacer()

                // Zoom controls
                HStack(spacing: 4) {
                    Button(action: vm.zoomOut) {
                        Image(systemName: "minus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)

                    Text("\(Int(vm.dayWidth))px")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 30)

                    Button(action: vm.zoomIn) {
                        Image(systemName: "plus.magnifyingglass")
                    }
                    .buttonStyle(.borderless)

                    Button("Fit") {
                        // Will be called in onAppear with proper geo
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button(action: { showAddTask = true }) {
                    Label("Add Task", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primaryOrange)
                .controlSize(.small)
            }

            // Row 2: Category legend in a horizontal scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TaskCategory.allCases) { cat in
                        HStack(spacing: 4) {
                            Circle().fill(cat.color).frame(width: 8, height: 8)
                            Text(cat.rawValue).font(.system(size: 11)).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.secondaryBackground)
        #endif
    }

    // MARK: - Task List Panel
    private var taskListPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Task").font(.caption).fontWeight(.semibold)
                Spacer()
                Text("Days").font(.caption).fontWeight(.semibold).frame(width: 35)
                Text("Status").font(.caption).fontWeight(.semibold).frame(width: 20)
            }
            .padding(.horizontal, 8)
            .frame(height: vm.headerHeight)
            .background(AppTheme.secondaryBackground)

            Divider()

            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        switch row {
                        case .projectHeader(let project):
                            HStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(projectColor(for: project.id.recordName))
                                    .frame(width: 4, height: 16)
                                Text(project.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .frame(height: vm.projectHeaderHeight)
                            .background(Color.gray.opacity(0.08))

                        case .task(let task):
                            GanttTaskListRow(task: task, isSelected: vm.selectedTaskID == task.id)
                                .frame(height: vm.rowHeight)
                                .onTapGesture { vm.selectedTaskID = task.id }
                                .contextMenu {
                                    Button("Edit") { editingTask = task }
                                    Divider()
                                    Button("Delete", role: .destructive) { dataStore.deleteGanttTask(task) }
                                }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var timelineHeight: CGFloat {
        var height = vm.headerHeight
        for row in rows {
            height += isHeader(row) ? vm.projectHeaderHeight : vm.rowHeight
        }
        return max(height, 400)
    }

    private func yOffset(for index: Int) -> CGFloat {
        var y = vm.headerHeight
        for i in 0..<index {
            y += isHeader(rows[i]) ? vm.projectHeaderHeight : vm.rowHeight
        }
        return y
    }

    private func isHeader(_ row: GanttRow) -> Bool {
        if case .projectHeader = row { return true }
        return false
    }

    private func projectHeaderBar(project: Project, yPos: CGFloat) -> some View {
        Rectangle()
            .fill(projectColor(for: project.id.recordName).opacity(0.08))
            .frame(width: vm.totalWidth(tasks: filteredTasks), height: vm.projectHeaderHeight)
            .position(x: vm.totalWidth(tasks: filteredTasks) / 2, y: yPos + vm.projectHeaderHeight / 2)
    }
}

// MARK: - Task List Row
struct GanttTaskListRow: View {
    let task: GanttTask
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(task.barColor)
                .frame(width: 4)
                .padding(.vertical, 4)

            Text(task.name)
                .font(.system(size: 11))
                .lineLimit(1)

            Spacer()

            Text("\(task.durationDays)d")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 35, alignment: .trailing)

            Image(systemName: task.status.icon)
                .font(.system(size: 10))
                .foregroundColor(task.statusColor)
                .frame(width: 20)
        }
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }
}
