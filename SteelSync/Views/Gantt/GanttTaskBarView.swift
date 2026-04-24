import SwiftUI

struct GanttTaskBarView: View {
    let task: GanttTask
    let vm: GanttViewModel
    let allTasks: [GanttTask]
    var projectColor: Color = .orange
    var isOnCriticalPath: Bool = false
    var hasCrewConflict: Bool = false
    let onEdit: () -> Void
    let onUpdate: (GanttTask) -> Void
    var onTogglePin: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var dragOffset: CGFloat = 0
    @State private var resizeRightOffset: CGFloat = 0
    @State private var resizeLeftOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var isResizingRight = false
    @State private var isResizingLeft = false

    private var effectiveBarWidth: CGFloat {
        max(vm.barWidth(for: task) + resizeRightOffset - resizeLeftOffset, 10)
    }
    private var barHeight: CGFloat { vm.rowHeight - 10 }
    private var isSelected: Bool { vm.selectedTaskID == task.id }
    private var isResizing: Bool { isResizingRight || isResizingLeft }
    private var handleWidth: CGFloat {
        #if os(macOS)
        return 10
        #else
        return 18
        #endif
    }

    private var isMilestone: Bool { task.status == .milestone }
    private var isDeadline: Bool { task.category == .deadline }
    private var isOverdueRisk: Bool {
        task.endDate < Date() && task.status != .completed
    }

    var body: some View {
        Group {
            if isMilestone {
                milestoneBody
            } else {
                standardBarBody
            }
        }
        .overlay(alignment: .topTrailing) {
            if task.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .padding(3)
                    .background(Circle().fill(Color.white.opacity(0.85)))
                    .offset(x: 4, y: -4)
            }
        }
        .overlay(alignment: .topLeading) {
            if isOverdueRisk {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .background(Circle().fill(Color.white))
                    .offset(x: -4, y: -4)
            }
        }
        .onTapGesture { vm.selectedTaskID = task.id }
        .onTapGesture(count: 2) { onEdit() }
        .contextMenu {
            Button("Edit") { onEdit() }
            Button(task.isPinned ? "Unpin" : "Pin") { onTogglePin() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        }
        .help(tooltipText)
    }

    private var tooltipText: String {
        var parts = [
            task.name,
            "\(task.startDate.shortDate) – \(task.endDate.shortDate)",
            "\(task.durationDays) work days",
            "Status: \(task.status.rawValue)"
        ]
        if !task.assignedTo.isEmpty { parts.append("Assigned: \(task.assignedTo)") }
        if task.isPinned { parts.append("📌 Pinned (drag disabled)") }
        if isOnCriticalPath { parts.append("⚡ On critical path") }
        if hasCrewConflict { parts.append("⚠️ Crew conflict") }
        return parts.joined(separator: "\n")
    }

    // MARK: - Standard Bar

    private var standardBarBody: some View {
        ZStack(alignment: .leading) {
            // Background bar
            RoundedRectangle(cornerRadius: vm.barRadius)
                .fill(projectColor.opacity(task.isPinned ? 0.7 : 0.85))
                .frame(width: effectiveBarWidth, height: barHeight)

            // Deadline: replace fill with red tint
            if isDeadline {
                RoundedRectangle(cornerRadius: vm.barRadius)
                    .fill(Color.red.opacity(0.55))
                    .frame(width: effectiveBarWidth, height: barHeight)
            }

            // Progress fill
            if task.progress > 0 {
                RoundedRectangle(cornerRadius: vm.barRadius)
                    .fill(isDeadline ? Color.red : projectColor)
                    .frame(width: max(effectiveBarWidth * task.progress, 4), height: barHeight)
            }

            // Label (only if bar is wide enough)
            if effectiveBarWidth > 70 {
                HStack(spacing: 4) {
                    Image(systemName: isDeadline ? "flag.fill" : task.category.icon)
                        .font(.system(size: 9))
                    Text(task.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, handleWidth + 2)
                .frame(width: effectiveBarWidth, alignment: .leading)
            }

            // LEFT resize handle
            resizeHandle(isLeft: true)
                .offset(x: 0)
                .gesture(resizeLeftDrag)

            // RIGHT resize handle
            resizeHandle(isLeft: false)
                .offset(x: effectiveBarWidth - handleWidth)
                .gesture(resizeRightDrag)
        }
        .frame(width: effectiveBarWidth, height: barHeight)
        .overlay(
            RoundedRectangle(cornerRadius: vm.barRadius)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .shadow(
            color: shadowColor,
            radius: isOnCriticalPath || hasCrewConflict ? 4 : (isSelected ? 3 : 1)
        )
        .offset(x: dragOffset + resizeLeftOffset)
        .opacity(isDragging || isResizing ? 0.8 : 1)
        .gesture(moveDrag)
    }

    private var borderColor: Color {
        if hasCrewConflict { return .red }
        if isOnCriticalPath { return .orange }
        if isSelected { return .white }
        return .clear
    }

    private var borderWidth: CGFloat {
        if hasCrewConflict { return 2.5 }
        if isOnCriticalPath { return 2.0 }
        if isSelected { return 2.0 }
        return 0
    }

    private var shadowColor: Color {
        if hasCrewConflict { return .red.opacity(0.5) }
        if isOnCriticalPath { return .orange.opacity(0.5) }
        return .black.opacity(isSelected ? 0.2 : 0.08)
    }

    // MARK: - Milestone (Diamond)

    private var milestoneBody: some View {
        // Milestones render as a diamond centered at the bar's start,
        // regardless of durationDays.
        let diamondSize = barHeight
        return ZStack {
            DiamondShape()
                .fill(Color.purple)
                .frame(width: diamondSize, height: diamondSize)
            DiamondShape()
                .stroke(borderColor, lineWidth: borderWidth == 0 ? 1 : borderWidth)
                .frame(width: diamondSize, height: diamondSize)
            Image(systemName: "diamond.fill")
                .font(.system(size: 10))
                .foregroundColor(.white)
        }
        .frame(width: max(effectiveBarWidth, diamondSize), height: barHeight, alignment: .leading)
        .offset(x: dragOffset + resizeLeftOffset)
        .opacity(isDragging ? 0.8 : 1)
        .gesture(moveDrag)
    }

    // MARK: - Resize Handle View

    @ViewBuilder
    private func resizeHandle(isLeft: Bool) -> some View {
        ZStack {
            // Invisible wide touch target
            Rectangle()
                .fill(Color.clear)
                .frame(width: handleWidth, height: barHeight)

            // Visible grip dots (3 vertical dots) — only show when interactive
            if !task.isPinned {
                VStack(spacing: 2) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(isResizing || isSelected ? 0.7 : 0.35))
                            .frame(width: 3, height: 3)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { hovering in
            guard !task.isPinned else { return }
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        #endif
    }

    // MARK: - Move Gesture (drag from middle of bar)

    private var moveDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !task.isPinned else { return }
                isDragging = true
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard !task.isPinned else {
                    dragOffset = 0
                    isDragging = false
                    return
                }
                isDragging = false
                let daysMoved = Int(round(value.translation.width / vm.dayWidth))
                if daysMoved != 0 {
                    var updated = task
                    updated.startDate = Calendar.current.date(byAdding: .day, value: daysMoved, to: task.startDate) ?? task.startDate
                    onUpdate(updated)
                }
                dragOffset = 0
            }
    }

    // MARK: - Resize Right Gesture

    private var resizeRightDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !task.isPinned else { return }
                isResizingRight = true
                resizeRightOffset = value.translation.width
            }
            .onEnded { value in
                guard !task.isPinned else {
                    resizeRightOffset = 0
                    isResizingRight = false
                    return
                }
                isResizingRight = false
                let calendarDaysAdded = Int(round(value.translation.width / vm.dayWidth))
                let newEndDate = Calendar.current.date(byAdding: .day, value: calendarDaysAdded, to: task.endDate) ?? task.endDate
                let newWorkDays = countWorkDays(from: task.startDate, to: newEndDate, includeSaturdays: task.includesSaturdays)
                var updated = task
                updated.durationDays = max(1, newWorkDays)
                onUpdate(updated)
                resizeRightOffset = 0
            }
    }

    // MARK: - Resize Left Gesture

    private var resizeLeftDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !task.isPinned else { return }
                isResizingLeft = true
                resizeLeftOffset = value.translation.width
            }
            .onEnded { value in
                guard !task.isPinned else {
                    resizeLeftOffset = 0
                    isResizingLeft = false
                    return
                }
                isResizingLeft = false
                let calendarDaysMoved = Int(round(value.translation.width / vm.dayWidth))
                let newStartDate = Calendar.current.date(byAdding: .day, value: calendarDaysMoved, to: task.startDate) ?? task.startDate
                let newWorkDays = countWorkDays(from: newStartDate, to: task.endDate, includeSaturdays: task.includesSaturdays)
                var updated = task
                updated.startDate = newStartDate
                updated.durationDays = max(1, newWorkDays)
                onUpdate(updated)
                resizeLeftOffset = 0
            }
    }

    // MARK: - Helpers

    /// Count work days between two dates, respecting the task's Saturday setting
    private func countWorkDays(from start: Date, to end: Date, includeSaturdays: Bool) -> Int {
        let cal = Calendar.current
        var count = 0
        var current = cal.startOfDay(for: start)
        let target = cal.startOfDay(for: end)
        while current < target {
            let weekday = cal.component(.weekday, from: current)
            let isSunday = weekday == 1
            let isSaturday = weekday == 7
            if !isSunday && (!isSaturday || includeSaturdays) {
                count += 1
            }
            current = cal.date(byAdding: .day, value: 1, to: current) ?? current
        }
        return max(1, count)
    }
}

// MARK: - Diamond Shape (Milestones)

struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: CGPoint(x: mid.x, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: mid.y))
        path.addLine(to: CGPoint(x: mid.x, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: mid.y))
        path.closeSubpath()
        return path
    }
}
