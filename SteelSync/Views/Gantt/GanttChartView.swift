import SwiftUI
import CloudKit

struct GanttChartView: View {
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var vm = GanttViewModel()
    @State private var showAddTask = false
    @State private var editingTask: GanttTask?
    @State private var selectedProjectFilter: String? = nil
    @State private var currentDate = Date()
    @State private var isVisible = false

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

    /// Tasks that pass the current project + search + status filters.
    /// Search matches name, assignee, or category (case-insensitive).
    var filteredTasks: [GanttTask] {
        var result = allTasks
        if let filter = selectedProjectFilter {
            result = result.filter { $0.projectID == filter }
        }
        let q = vm.searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter { t in
                t.name.lowercased().contains(q)
                    || t.assignedTo.lowercased().contains(q)
                    || t.category.rawValue.lowercased().contains(q)
                    || t.notes.lowercased().contains(q)
            }
        }
        if let sf = vm.statusFilter {
            result = result.filter { $0.status == sf }
        }
        if vm.showCriticalPathOnly {
            let critical = vm.criticalPathTaskIDs(tasks: allTasks)
            result = result.filter { critical.contains($0.id) }
        }
        return result.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Set of IDs that lie on the project critical path. Computed from the full
    /// task list (not the filtered one) so dependencies across filtered-out
    /// tasks still count.
    var criticalPathIDs: Set<UUID> {
        vm.criticalPathTaskIDs(tasks: allTasks)
    }

    /// Set of IDs that are double-booked by assignee across overlapping dates.
    var crewConflictIDs: Set<UUID> {
        vm.crewConflictTaskIDs(tasks: allTasks)
    }

    // Group tasks by project for the master view
    var projectGroups: [(project: Project, tasks: [GanttTask])] {
        var groups: [(project: Project, tasks: [GanttTask])] = []
        let visibleTasks: [GanttTask] = filteredTasks
        for project in dataStore.projects {
            let projTasks: [GanttTask] = visibleTasks.filter { $0.projectID == project.id.recordName }
            let sortedProjTasks: [GanttTask] = projTasks.sorted { $0.sortOrder < $1.sortOrder }
            if !sortedProjTasks.isEmpty || selectedProjectFilter == project.id.recordName {
                groups.append((project: project, tasks: sortedProjTasks))
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
                chartBody(geo: geo)
                    .onAppear {
                        vm.availableWidth = geo.size.width - vm.taskListWidth
                        if allTasks.isEmpty { dataStore.generateSampleGanttTasks() }
                        vm.fitToWindow(tasks: filteredTasks,
                                       availableWidth: vm.availableWidth)
                    }
                    .onChange(of: geo.size.width) { _, newValue in
                        vm.availableWidth = newValue - vm.taskListWidth
                    }
            }
        }
        .sheet(isPresented: $showAddTask) {
            GanttTaskEditSheet(projects: dataStore.projects, selectedProjectID: selectedProjectFilter) { newTask in
                dataStore.addGanttTask(newTask)
            }
            .environmentObject(dataStore)
        }
        .sheet(item: $editingTask) { task in
            GanttTaskEditSheet(projects: dataStore.projects, editingTask: task) { updated in
                dataStore.updateGanttTask(updated)
            } onDelete: {
                dataStore.deleteGanttTask(task)
            }
            .environmentObject(dataStore)
        }
        .navigationTitle("Schedule")
        .onAppear { isVisible = true; currentDate = Date() }
        .onDisappear { isVisible = false }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
            if isVisible { currentDate = Date() }
        }
    }

    // MARK: - Chart Body (extracted to keep SwiftUI type-checker happy)

    @ViewBuilder
    private func chartBody(geo: GeometryProxy) -> some View {
        let availHeight = geo.size.height
        HStack(spacing: 0) {
            taskListPanel
                .frame(width: vm.taskListWidth, height: availHeight)
            Divider()
            timelinePane(availHeight: availHeight, availWidth: geo.size.width - vm.taskListWidth)
        }
    }

    @ViewBuilder
    private func timelinePane(availHeight: CGFloat, availWidth: CGFloat) -> some View {
        let contentTimelineHeight = max(timelineHeight, availHeight)
        let timelineWidth = max(vm.totalWidth(tasks: filteredTasks), availWidth)

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                GanttTimelineGridView(vm: vm, tasks: filteredTasks)
                    .frame(width: timelineWidth, height: contentTimelineHeight)

                GanttDependencyOverlay(
                    rows: rows,
                    filteredTasks: filteredTasks,
                    vm: vm,
                    rowYOffsets: rowYOffsets
                )
                .frame(width: timelineWidth, height: contentTimelineHeight)
                .allowsHitTesting(false)

                taskBarsLayer()

                GanttTodayMarkerView(vm: vm, tasks: filteredTasks, height: contentTimelineHeight, now: currentDate)
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

    @ViewBuilder
    private func taskBarsLayer() -> some View {
        let critical = criticalPathIDs
        let conflicts = crewConflictIDs
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            switch row {
            case .task(let task):
                GanttTaskBarView(
                    task: task, vm: vm, allTasks: filteredTasks,
                    projectColor: projectColor(for: task.projectID),
                    isOnCriticalPath: critical.contains(task.id),
                    hasCrewConflict: conflicts.contains(task.id),
                    onEdit: { editingTask = task },
                    onUpdate: { updated in dataStore.updateGanttTask(updated) },
                    onTogglePin: { togglePin(task) },
                    onDelete: { dataStore.deleteGanttTask(task) }
                )
                .position(
                    x: vm.xPosition(for: task.startDate, tasks: filteredTasks) + vm.barWidth(for: task) / 2,
                    y: yOffset(for: index) + vm.rowHeight / 2
                )
            case .projectHeader(let project):
                projectHeaderBar(project: project, yPos: yOffset(for: index))
            }
        }
    }

    // MARK: - Toolbar
    private var toolbar: some View {
        VStack(spacing: 6) {
            // Row 1: project filter, search, filters, zoom, add
            HStack(spacing: AppTheme.Spacing.md) {
                Picker("Project", selection: $selectedProjectFilter) {
                    Text("All Projects").tag(String?.none)
                    ForEach(dataStore.projects) { project in
                        Text(project.title).tag(Optional(project.id.recordName))
                    }
                }
                #if os(macOS)
                .frame(width: 200)
                #else
                .frame(width: 180)
                #endif

                // Search field
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Search tasks, assignee, category", text: $vm.searchText)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !vm.searchText.isEmpty {
                        Button { vm.searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(maxWidth: 260)

                // Status filter
                Menu {
                    Button("All Statuses") { vm.statusFilter = nil }
                    Divider()
                    ForEach(TaskStatus.allCases) { status in
                        Button {
                            vm.statusFilter = status
                        } label: {
                            Label(status.rawValue, systemImage: status.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text(vm.statusFilter?.rawValue ?? "All")
                            .font(.caption)
                    }
                }
                .menuStyle(.borderlessButton)
                .frame(width: 110)

                Spacer()

                // Critical path toggle
                Toggle(isOn: $vm.showCriticalPathOnly) {
                    Label("Critical", systemImage: "bolt.fill")
                        .font(.caption)
                }
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Show only tasks on the critical path")

                // Conflict count badge
                if !crewConflictIDs.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("\(crewConflictIDs.count / 2) conflict\(crewConflictIDs.count / 2 == 1 ? "" : "s")")
                    }
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.85))
                    .clipShape(Capsule())
                    .help("Crew double-bookings — bars outlined in red")
                }

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
                        vm.fitToWindow(tasks: filteredTasks, availableWidth: vm.availableWidth)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(vm.availableWidth <= 0)
                }

                Button(action: { showAddTask = true }) {
                    Label("Add", systemImage: "plus")
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
                            Text(cat.rawValue).font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                    // Legend for new shapes
                    Divider().frame(height: 12)
                    HStack(spacing: 4) {
                        Image(systemName: "diamond.fill").font(.system(size: 8)).foregroundColor(.purple)
                        Text("Milestone").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "flag.fill").font(.system(size: 8)).foregroundColor(.red)
                        Text("Deadline").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "pin.fill").font(.system(size: 8)).foregroundColor(.orange)
                        Text("Pinned").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(AppTheme.secondaryBackground)
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
                                    Button(task.isPinned ? "Unpin" : "Pin") { togglePin(task) }
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

    /// Precomputed y offsets for every row — used by the dependency overlay
    /// so it can find task bar positions without re-walking the row list per line.
    private var rowYOffsets: [CGFloat] {
        var result: [CGFloat] = []
        result.reserveCapacity(rows.count)
        var y = vm.headerHeight
        for row in rows {
            result.append(y)
            y += isHeader(row) ? vm.projectHeaderHeight : vm.rowHeight
        }
        return result
    }

    private func togglePin(_ task: GanttTask) {
        var updated = task
        updated.isPinned.toggle()
        dataStore.updateGanttTask(updated)
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

            if task.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.orange)
            }

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

// MARK: - Dependency Overlay

/// Draws elbow connector lines between each task and its predecessors.
/// Only renders tasks that are currently visible in `filteredTasks`;
/// predecessors outside the filter are skipped so the view stays clean.
struct GanttDependencyOverlay: View {
    let rows: [GanttChartView.GanttRow]
    let filteredTasks: [GanttTask]
    let vm: GanttViewModel
    let rowYOffsets: [CGFloat]

    var body: some View {
        Canvas { context, size in
            // Build lookup of taskID → (startX, endX, centerY)
            var positions: [UUID: (startX: CGFloat, endX: CGFloat, centerY: CGFloat)] = [:]
            for (index, row) in rows.enumerated() {
                guard case .task(let task) = row else { continue }
                let startX = vm.xPosition(for: task.startDate, tasks: filteredTasks)
                let width = vm.barWidth(for: task)
                let y = rowYOffsets[index] + vm.rowHeight / 2
                positions[task.id] = (startX, startX + width, y)
            }

            let lineColor = Color.gray.opacity(0.55)
            let lineWidth: CGFloat = 1.4

            for (_, row) in rows.enumerated() {
                guard case .task(let task) = row, !task.predecessorIDs.isEmpty else { continue }
                guard let curr = positions[task.id] else { continue }

                for predID in task.predecessorIDs {
                    guard let pred = positions[predID] else { continue }

                    // Elbow path: from predecessor end → bend → successor start
                    let gap: CGFloat = 6
                    let p1 = CGPoint(x: pred.endX, y: pred.centerY)
                    let p2 = CGPoint(x: pred.endX + gap, y: pred.centerY)
                    let p3 = CGPoint(x: pred.endX + gap, y: curr.centerY)
                    let p4 = CGPoint(x: curr.startX - 2, y: curr.centerY)

                    let path = Path { p in
                        p.move(to: p1)
                        p.addLine(to: p2)
                        p.addLine(to: p3)
                        p.addLine(to: p4)
                    }
                    context.stroke(path, with: .color(lineColor), lineWidth: lineWidth)

                    // Small arrow head (triangle) at successor start
                    let arrow = Path { p in
                        p.move(to: p4)
                        p.addLine(to: CGPoint(x: p4.x - 4, y: p4.y - 3))
                        p.addLine(to: CGPoint(x: p4.x - 4, y: p4.y + 3))
                        p.closeSubpath()
                    }
                    context.fill(arrow, with: .color(lineColor))
                }
            }
        }
    }
}
