import SwiftUI

@MainActor
class GanttViewModel: ObservableObject {
    @Published var dayWidth: CGFloat = 24
    /// Multi-selection. Marquee selection and modifier-click both write here.
    @Published var selectedTaskIDs: Set<UUID> = []
    @Published var showingAddTask = false
    @Published var showingEditTask = false

    /// Live horizontal offset while group-dragging a multi-selection. Every
    /// selected bar reads this so they move together. Reset on drag end.
    @Published var groupDragOffsetX: CGFloat = 0
    @Published var isGroupDragging = false

    /// Backward-compatible single-selection accessor used by callers that
    /// only deal with one task at a time.
    var selectedTaskID: UUID? {
        get { selectedTaskIDs.count == 1 ? selectedTaskIDs.first : nil }
        set { selectedTaskIDs = newValue.map { [$0] } ?? [] }
    }

    func isSelected(_ id: UUID) -> Bool { selectedTaskIDs.contains(id) }

    func toggleSelection(_ id: UUID) {
        if selectedTaskIDs.contains(id) { selectedTaskIDs.remove(id) }
        else { selectedTaskIDs.insert(id) }
    }

    // MARK: - Filter / Search
    @Published var searchText: String = ""
    @Published var statusFilter: TaskStatus? = nil
    @Published var showCriticalPathOnly: Bool = false

    /// Latest observed width of the timeline pane — captured in GeometryReader so
    /// the toolbar Fit button can call fitToWindow without needing a geometry handle.
    @Published var availableWidth: CGFloat = 0

    // MARK: - Layout Constants
    /// Row height honors the glass density toggle (Comfortable 42 / Compact 30,
    /// per §5's Schedule density control); legacy themes keep the classic 36.
    var rowHeight: CGFloat {
        ThemeManager.shared.glassEnabled ? ThemeManager.shared.density.rowHeight : 36
    }
    #if os(macOS)
    let taskListWidth: CGFloat = 280
    #else
    let taskListWidth: CGFloat = 200
    #endif
    let headerHeight: CGFloat = 56
    let minDayWidth: CGFloat = 5
    let maxDayWidth: CGFloat = 100
    let barRadius: CGFloat = 4
    let projectHeaderHeight: CGFloat = 28

    // MARK: - Timeline Colors
    let weekendFill = Color.gray.opacity(0.08)
    let todayLineColor = Color.red.opacity(0.7)
    /// Hairline gridlines — `--divider` under the glass design, neutral gray otherwise.
    var gridLineColor: Color { ThemeManager.shared.glassEnabled ? Glass.divider : Color.gray.opacity(0.15) }

    // MARK: - Timeline Calculations (All Projects)

    func timelineStartDate(tasks: [GanttTask]) -> Date {
        let earliest = tasks.map(\.startDate).min() ?? Date()
        return Calendar.current.date(byAdding: .day, value: -7, to: earliest) ?? earliest
    }

    func timelineEndDate(tasks: [GanttTask]) -> Date {
        let latest = tasks.map(\.endDate).max() ?? Date().adding(days: 90)
        return Calendar.current.date(byAdding: .day, value: 14, to: latest) ?? latest
    }

    func totalDays(tasks: [GanttTask]) -> Int {
        let start = timelineStartDate(tasks: tasks)
        let end = timelineEndDate(tasks: tasks)
        return max(1, Calendar.current.dateComponents([.day], from: start, to: end).day ?? 1)
    }

    func totalWidth(tasks: [GanttTask]) -> CGFloat {
        CGFloat(totalDays(tasks: tasks)) * dayWidth
    }

    func xPosition(for date: Date, tasks: [GanttTask]) -> CGFloat {
        let start = timelineStartDate(tasks: tasks)
        let days = Calendar.current.dateComponents([.day], from: start.startOfDay, to: date.startOfDay).day ?? 0
        return CGFloat(days) * dayWidth
    }

    func barWidth(for task: GanttTask) -> CGFloat {
        CGFloat(task.calendarSpan) * dayWidth
    }

    // MARK: - Dates & Month Spans

    func datesInRange(tasks: [GanttTask]) -> [Date] {
        let start = timelineStartDate(tasks: tasks)
        let count = totalDays(tasks: tasks)
        return (0..<count).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: start)
        }
    }

    func monthSpans(tasks: [GanttTask]) -> [(label: String, startX: CGFloat, width: CGFloat)] {
        let dates = datesInRange(tasks: tasks)
        guard !dates.isEmpty else { return [] }

        var spans: [(label: String, startX: CGFloat, width: CGFloat)] = []
        var currentMonth = dates[0].monthYear
        var startIndex = 0

        for i in 1..<dates.count {
            let month = dates[i].monthYear
            if month != currentMonth {
                let startX = CGFloat(startIndex) * dayWidth
                let width = CGFloat(i - startIndex) * dayWidth
                spans.append((label: currentMonth, startX: startX, width: width))
                currentMonth = month
                startIndex = i
            }
        }
        // Last span
        let startX = CGFloat(startIndex) * dayWidth
        let width = CGFloat(dates.count - startIndex) * dayWidth
        spans.append((label: currentMonth, startX: startX, width: width))

        return spans
    }

    // MARK: - Zoom

    func zoomIn() {
        withAnimation(.easeInOut(duration: 0.2)) {
            dayWidth = min(dayWidth + 4, maxDayWidth)
        }
    }

    func zoomOut() {
        withAnimation(.easeInOut(duration: 0.2)) {
            dayWidth = max(dayWidth - 4, minDayWidth)
        }
    }

    /// For pinch-to-zoom gesture on iPad
    var dayWidthBeforePinch: CGFloat = 24

    func applyPinchScale(_ scale: CGFloat) {
        let newWidth = dayWidthBeforePinch * scale
        dayWidth = min(max(newWidth, minDayWidth), maxDayWidth)
    }

    func fitToWindow(tasks: [GanttTask], availableWidth: CGFloat) {
        let days = totalDays(tasks: tasks)
        guard days > 0 else { return }
        let fitted = max(minDayWidth, min(maxDayWidth, availableWidth / CGFloat(days)))
        withAnimation(.easeInOut(duration: 0.3)) {
            dayWidth = fitted
        }
    }

    // MARK: - Task Drag & Resize

    func moveTask(_ task: inout GanttTask, byDays days: Int) {
        task.startDate = Calendar.current.date(byAdding: .day, value: days, to: task.startDate) ?? task.startDate
    }

    func resizeTask(_ task: inout GanttTask, newDuration: Int) {
        task.durationDays = max(1, newDuration)
    }

    // MARK: - Critical Path (CPM)

    /// Returns the set of task IDs that lie on the critical path. Only meaningful
    /// when tasks have predecessor dependencies — if none do, returns an empty set.
    /// Uses the classic forward/backward pass, with memoized recursion.
    func criticalPathTaskIDs(tasks: [GanttTask]) -> Set<UUID> {
        let hasAnyDependency = tasks.contains { !$0.predecessorIDs.isEmpty }
        guard hasAnyDependency else { return [] }

        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })

        // Earliest finish (EF) for each task.
        var ef: [UUID: Date] = [:]
        var visitingEF: Set<UUID> = []
        func computeEF(_ id: UUID) -> Date {
            if let cached = ef[id] { return cached }
            if visitingEF.contains(id) { return .distantPast }  // cycle guard
            visitingEF.insert(id)
            defer { visitingEF.remove(id) }
            guard let task = byID[id] else { return .distantPast }
            let preds = task.predecessorIDs.compactMap { byID[$0] != nil ? computeEF($0) : nil }
            let earliestStart = preds.max() ?? task.startDate
            let duration = TimeInterval(task.durationDays) * 86_400
            let finish = earliestStart.addingTimeInterval(duration)
            ef[id] = finish
            return finish
        }
        for t in tasks { _ = computeEF(t.id) }

        guard let projectEnd = ef.values.max() else { return [] }

        // Successor map (reverse adjacency).
        var successors: [UUID: [UUID]] = [:]
        for t in tasks {
            for p in t.predecessorIDs {
                successors[p, default: []].append(t.id)
            }
        }

        // Latest finish (LF) for each task.
        var lf: [UUID: Date] = [:]
        var visitingLF: Set<UUID> = []
        func computeLF(_ id: UUID) -> Date {
            if let cached = lf[id] { return cached }
            if visitingLF.contains(id) { return projectEnd }
            visitingLF.insert(id)
            defer { visitingLF.remove(id) }
            guard let task = byID[id] else { return projectEnd }
            let succIDs = successors[id] ?? []
            if succIDs.isEmpty {
                lf[id] = projectEnd
                return projectEnd
            }
            let succLatestStarts: [Date] = succIDs.compactMap { sid in
                guard let s = byID[sid] else { return nil }
                let slf = computeLF(sid)
                return slf.addingTimeInterval(-TimeInterval(s.durationDays) * 86_400)
            }
            let candidate = succLatestStarts.min() ?? projectEnd
            let duration = TimeInterval(task.durationDays) * 86_400
            let myLF = candidate.addingTimeInterval(duration)
            lf[id] = myLF
            return myLF
        }
        for t in tasks { _ = computeLF(t.id) }

        // Zero-slack tasks are on the critical path.
        var critical: Set<UUID> = []
        for t in tasks {
            guard let e = ef[t.id], let l = lf[t.id] else { continue }
            if abs(e.timeIntervalSince(l)) < 60 {  // ±1 minute tolerance
                critical.insert(t.id)
            }
        }
        return critical
    }

    // MARK: - Crew Conflict Detection

    /// Returns task IDs whose assignee (non-empty) is also assigned to another task
    /// with overlapping dates. Compares across all projects so the user sees
    /// double-bookings regardless of the project filter.
    func crewConflictTaskIDs(tasks: [GanttTask]) -> Set<UUID> {
        var conflicts: Set<UUID> = []
        var byAssignee: [String: [GanttTask]] = [:]
        for t in tasks where !t.assignedTo.trimmingCharacters(in: .whitespaces).isEmpty {
            byAssignee[t.assignedTo.trimmingCharacters(in: .whitespaces), default: []].append(t)
        }
        for (_, group) in byAssignee where group.count > 1 {
            let sorted = group.sorted { $0.startDate < $1.startDate }
            for i in 0..<sorted.count {
                for j in (i + 1)..<sorted.count {
                    // Overlap if first ends after second starts.
                    if sorted[i].endDate > sorted[j].startDate && sorted[i].startDate < sorted[j].endDate {
                        conflicts.insert(sorted[i].id)
                        conflicts.insert(sorted[j].id)
                    }
                }
            }
        }
        return conflicts
    }
}
