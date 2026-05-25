import SwiftUI
import CloudKit
import UniformTypeIdentifiers

struct GanttChartView: View {
    @EnvironmentObject var dataStore: DataStore
    @StateObject private var vm = GanttViewModel()
    @State private var showAddTask = false
    @State private var showExportSheet = false
    @State private var editingTask: GanttTask?
    /// Multi-select project filter. Each entry is a `Project.id.recordName`.
    /// The set always represents the *visible* projects — empty means
    /// "nothing showing". On first appearance it's seeded with every project
    /// so the default state matches the previous "All Projects" behavior.
    @State private var selectedProjectFilters: Set<String> = []
    @State private var didSeedProjectFilters = false
    @State private var currentDate = Date()
    @State private var isVisible = false
    // Marquee (rubber-band) selection — content-space points while dragging.
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    // Drag-to-reorder in the task list.
    @State private var draggingTaskID: UUID?

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
        var result = allTasks.filter { selectedProjectFilters.contains($0.projectID) }
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
            // Skip projects the user has filtered out entirely.
            guard selectedProjectFilters.contains(project.id.recordName) else { continue }
            let projTasks: [GanttTask] = visibleTasks.filter { $0.projectID == project.id.recordName }
            let sortedProjTasks: [GanttTask] = projTasks.sorted { $0.sortOrder < $1.sortOrder }
            // When the user has narrowed down to ≤3 projects we show empty
            // groups so they can see "this project has no tasks". For wider
            // selections we hide empty ones to keep the chart compact.
            let isNarrow = selectedProjectFilters.count <= 3
            if !sortedProjTasks.isEmpty || isNarrow {
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
        // Single-project view skips headers — same as before, just keyed off
        // the multi-select set having exactly one entry.
        if selectedProjectFilters.count == 1 {
            return filteredTasks.map { .task($0) }
        }
        var result: [GanttRow] = []
        for (project, tasks) in projectGroups {
            result.append(.projectHeader(project))
            result += tasks.map { .task($0) }
        }
        return result
    }

    /// Single project ID when exactly one is selected, otherwise nil. Used to
    /// hand a sensible default to the Add Task and Export sheets without
    /// teaching them about multi-select (yet).
    private var soleSelectedProjectID: String? {
        selectedProjectFilters.count == 1 ? selectedProjectFilters.first : nil
    }

    /// Compact label shown on the toolbar's project menu button.
    private var projectFilterLabel: String {
        let total = dataStore.projects.count
        let count = selectedProjectFilters.count
        if count == 0 { return "No Projects" }
        if count == total { return "All Projects" }
        if count == 1,
           let id = selectedProjectFilters.first,
           let project = dataStore.projects.first(where: { $0.id.recordName == id }) {
            return project.title
        }
        return "\(count) of \(total) Projects"
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
                        seedProjectFiltersIfNeeded()
                        vm.fitToWindow(tasks: filteredTasks,
                                       availableWidth: vm.availableWidth)
                    }
                    .onChange(of: geo.size.width) { _, newValue in
                        vm.availableWidth = newValue - vm.taskListWidth
                    }
                    .onChange(of: dataStore.projects.count) { _, _ in
                        // Seed once on first data, then leave alone — the
                        // user owns the filter set after that.
                        seedProjectFiltersIfNeeded()
                    }
            }
        }
        .inlineForm(isPresented: $showAddTask) {
            GanttTaskEditSheet(projects: dataStore.projects, selectedProjectID: soleSelectedProjectID) { newTask in
                dataStore.addGanttTask(newTask)
            }
            .environmentObject(dataStore)
        }
        .sheet(isPresented: $showExportSheet) {
            GanttExportSheet(
                allTasks: allTasks,
                projects: dataStore.projects,
                initialSelectedProjects: selectedProjectFilters
            )
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

                #if os(macOS)
                // Drag-catcher for marquee selection on empty timeline space.
                // Sits above the grid but below the bars, so dragging a bar
                // still moves the bar; dragging blank space rubber-bands.
                marqueeCatcher(width: timelineWidth, height: contentTimelineHeight)
                #endif

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

                #if os(macOS)
                marqueeOverlay()
                #endif
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
                    onDelete: { dataStore.deleteGanttTask(task) },
                    onGroupMove: { days in dataStore.moveGanttTasks(ids: vm.selectedTaskIDs, byDays: days) }
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

    // MARK: - Marquee Selection (macOS)

    /// Current rubber-band rect in timeline content coordinates, or nil when
    /// not dragging.
    private var marqueeRect: CGRect? {
        guard let s = marqueeStart, let c = marqueeCurrent else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                      width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    /// Transparent full-content layer that turns an empty-space click-drag
    /// into a selection rectangle, and a plain click into "clear selection".
    @ViewBuilder
    private func marqueeCatcher(width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: width, height: height)
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if marqueeStart == nil { marqueeStart = value.startLocation }
                        marqueeCurrent = value.location
                    }
                    .onEnded { _ in
                        if let rect = marqueeRect {
                            vm.selectedTaskIDs = tasksIntersecting(rect)
                        }
                        marqueeStart = nil
                        marqueeCurrent = nil
                    }
            )
            .onTapGesture { vm.selectedTaskIDs = [] }
    }

    /// Visible rubber-band rectangle drawn on top of the bars.
    @ViewBuilder
    private func marqueeOverlay() -> some View {
        if let rect = marqueeRect {
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .overlay(Rectangle().stroke(Color.accentColor.opacity(0.8), lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .allowsHitTesting(false)
        }
    }

    /// Task IDs whose bar frame intersects `rect` (timeline content coords).
    private func tasksIntersecting(_ rect: CGRect) -> Set<UUID> {
        var result: Set<UUID> = []
        for (index, row) in rows.enumerated() {
            guard case .task(let task) = row else { continue }
            let x = vm.xPosition(for: task.startDate, tasks: filteredTasks)
            let w = max(vm.barWidth(for: task), vm.rowHeight)  // milestones are ~square
            let y = yOffset(for: index)
            let frame = CGRect(x: x, y: y, width: w, height: vm.rowHeight)
            if frame.intersects(rect) { result.insert(task.id) }
        }
        return result
    }

    // MARK: - Toolbar
    private var toolbar: some View {
        VStack(spacing: 6) {
            // Row 1: project filter, search, filters, zoom, add
            HStack(spacing: AppTheme.Spacing.md) {
                projectFilterMenu

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

                // Multi-selection count + quick clear.
                if vm.selectedTaskIDs.count > 1 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("\(vm.selectedTaskIDs.count) selected")
                        Button {
                            vm.selectedTaskIDs = []
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.primaryOrange.opacity(0.9))
                    .clipShape(Capsule())
                    .help("Tasks selected — drag any one to move the group")
                }

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
                    .buttonStyle(.appSecondary)
                    .controlSize(.small)
                    .disabled(vm.availableWidth <= 0)
                }

                Button(action: { dataStore.sortGanttTasksByStartDate() }) {
                    Label("Sort by Date", systemImage: "arrow.up.arrow.down")
                }
                .buttonStyle(.appSecondary)
                .controlSize(.small)
                .disabled(allTasks.isEmpty)
                .help("Reorder all tasks top-to-bottom by start date")

                Button(action: { showExportSheet = true }) {
                    Label("Export PDF", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.appSecondary)
                .controlSize(.small)
                .disabled(allTasks.isEmpty)

                Button(action: { showAddTask = true }) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.appPrimary)
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
                            taskListRow(task)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    /// One task row with reorder controls + context menu. Computes the task's
    /// position among its project siblings once and feeds it to both the
    /// inline up/down buttons and the right-click menu.
    @ViewBuilder
    private func taskListRow(_ task: GanttTask) -> some View {
        let siblings = projectSiblings(of: task)
        let position = siblings.firstIndex(where: { $0.id == task.id })
        let canUp = position != nil && position! > 0
        let canDown = position != nil && position! < siblings.count - 1

        GanttTaskListRow(
            task: task,
            isSelected: vm.isSelected(task.id),
            canMoveUp: canUp,
            canMoveDown: canDown,
            onMoveUp: { dataStore.moveGanttTaskUp(task, in: siblings) },
            onMoveDown: { dataStore.moveGanttTaskDown(task, in: siblings) }
        )
        .frame(height: vm.rowHeight)
        .onTapGesture { vm.selectedTaskID = task.id }
        .contextMenu {
            Button("Edit") { editingTask = task }
            Button(task.isPinned ? "Unpin" : "Pin") { togglePin(task) }
            Divider()
            Button("Move Up") { dataStore.moveGanttTaskUp(task, in: siblings) }
                .disabled(!canUp)
            Button("Move Down") { dataStore.moveGanttTaskDown(task, in: siblings) }
                .disabled(!canDown)
            Divider()
            Button("Delete", role: .destructive) { dataStore.deleteGanttTask(task) }
        }
        .opacity(draggingTaskID == task.id ? 0.5 : 1)
        .onDrag {
            draggingTaskID = task.id
            return NSItemProvider(object: task.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: RowReorderDropDelegate(
            targetID: task.id,
            draggingID: $draggingTaskID,
            onReorder: { from, to in reorderTasksByDrag(from: from, to: to) }
        ))
    }

    /// Drag-reorder within a project: move task `from` to the slot of `to`.
    /// Cross-project drags are ignored so reordering stays scoped to a job.
    private func reorderTasksByDrag(from: UUID, to: UUID) {
        guard let fromTask = dataStore.ganttTasks.first(where: { $0.id == from }),
              let toTask = dataStore.ganttTasks.first(where: { $0.id == to }),
              fromTask.projectID == toTask.projectID else { return }
        var sibs = projectSiblings(of: fromTask)
        guard let f = sibs.firstIndex(where: { $0.id == from }),
              let t = sibs.firstIndex(where: { $0.id == to }), f != t else { return }
        sibs.move(fromOffsets: IndexSet(integer: f), toOffset: t > f ? t + 1 : t)
        dataStore.reorderGanttSiblings(sibs)
    }

    /// Tasks visible in the same project group as `task`, in display order.
    /// Used to scope Move Up/Down so reordering only swaps with on-screen
    /// neighbors of the same project.
    private func projectSiblings(of task: GanttTask) -> [GanttTask] {
        filteredTasks.filter { $0.projectID == task.projectID }
    }

    /// Multi-select project filter menu. Each project is a row with a leading
    /// checkmark; tapping toggles its membership in `selectedProjectFilters`.
    /// "Show All" / "Show None" actions sit at the top for bulk toggling.
    @ViewBuilder
    private var projectFilterMenu: some View {
        Menu {
            Button {
                selectedProjectFilters = Set(dataStore.projects.map { $0.id.recordName })
            } label: {
                Label("Show All Projects", systemImage: "checkmark.circle.fill")
            }
            Button {
                selectedProjectFilters.removeAll()
            } label: {
                Label("Show None", systemImage: "xmark.circle")
            }
            Divider()
            ForEach(dataStore.projects) { project in
                Button {
                    let id = project.id.recordName
                    if selectedProjectFilters.contains(id) {
                        selectedProjectFilters.remove(id)
                    } else {
                        selectedProjectFilters.insert(id)
                    }
                } label: {
                    if selectedProjectFilters.contains(project.id.recordName) {
                        Label(project.title, systemImage: "checkmark")
                    } else {
                        Text(project.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "building.2")
                    .font(.caption)
                Text(projectFilterLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppTheme.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(AppTheme.primaryText.opacity(0.1), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        #if os(macOS)
        .frame(width: 220)
        #else
        .frame(width: 200)
        #endif
    }

    /// Seeds `selectedProjectFilters` with every project on first appearance
    /// so the default state mirrors "All Projects". Idempotent — once the
    /// user has interacted, we don't overwrite their selection.
    private func seedProjectFiltersIfNeeded() {
        guard !didSeedProjectFilters, !dataStore.projects.isEmpty else { return }
        selectedProjectFilters = Set(dataStore.projects.map { $0.id.recordName })
        didSeedProjectFilters = true
    }

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
    var canMoveUp: Bool = false
    var canMoveDown: Bool = false
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}

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

            // Reorder controls — only on the selected row to avoid clutter.
            if isSelected {
                HStack(spacing: 1) {
                    Button(action: onMoveUp) {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMoveUp)
                    .foregroundColor(canMoveUp ? .secondary : Color.secondary.opacity(0.3))

                    Button(action: onMoveDown) {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.plain)
                    .disabled(!canMoveDown)
                    .foregroundColor(canMoveDown ? .secondary : Color.secondary.opacity(0.3))
                }
                .font(.system(size: 11, weight: .semibold))
                .help("Move task up or down in the list")
            }

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
