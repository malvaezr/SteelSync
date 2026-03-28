import SwiftUI

struct GanttTaskBarView: View {
    let task: GanttTask
    let vm: GanttViewModel
    let allTasks: [GanttTask]
    var projectColor: Color = .orange
    let onEdit: () -> Void
    let onUpdate: (GanttTask) -> Void

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

    var body: some View {
        ZStack(alignment: .leading) {
            // Background bar
            RoundedRectangle(cornerRadius: vm.barRadius)
                .fill(projectColor.opacity(0.85))
                .frame(width: effectiveBarWidth, height: barHeight)

            // Progress fill
            if task.progress > 0 {
                RoundedRectangle(cornerRadius: vm.barRadius)
                    .fill(projectColor)
                    .frame(width: max(effectiveBarWidth * task.progress, 4), height: barHeight)
            }

            // Label (only if bar is wide enough)
            if effectiveBarWidth > 70 {
                HStack(spacing: 4) {
                    Image(systemName: task.category.icon)
                        .font(.system(size: 9))
                    Text(task.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .padding(.horizontal, handleWidth + 2)
                .frame(width: effectiveBarWidth, alignment: .leading)
            }

            // LEFT resize handle — grip dots
            resizeHandle(isLeft: true)
                .offset(x: 0)
                .gesture(resizeLeftDrag)

            // RIGHT resize handle — grip dots
            resizeHandle(isLeft: false)
                .offset(x: effectiveBarWidth - handleWidth)
                .gesture(resizeRightDrag)
        }
        .frame(width: effectiveBarWidth, height: barHeight)
        .overlay(
            RoundedRectangle(cornerRadius: vm.barRadius)
                .stroke(Color.white, lineWidth: isSelected ? 2 : 0)
        )
        .shadow(color: .black.opacity(isSelected ? 0.2 : 0.08), radius: isSelected ? 3 : 1)
        .offset(x: dragOffset + resizeLeftOffset)
        .opacity(isDragging || isResizing ? 0.8 : 1)
        .gesture(moveDrag)
        .onTapGesture { vm.selectedTaskID = task.id }
        .onTapGesture(count: 2) { onEdit() }
        .help("\(task.name)\n\(task.startDate.shortDate) – \(task.endDate.shortDate)\n\(task.durationDays) work days\nStatus: \(task.status.rawValue)")
    }

    // MARK: - Resize Handle View

    @ViewBuilder
    private func resizeHandle(isLeft: Bool) -> some View {
        ZStack {
            // Invisible wide touch target
            Rectangle()
                .fill(Color.clear)
                .frame(width: handleWidth, height: barHeight)

            // Visible grip dots (3 vertical dots)
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(isResizing || isSelected ? 0.7 : 0.35))
                        .frame(width: 3, height: 3)
                }
            }
        }
        .contentShape(Rectangle())
        #if os(macOS)
        .onHover { hovering in
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
                isDragging = true
                dragOffset = value.translation.width
            }
            .onEnded { value in
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

    // MARK: - Resize Right Gesture (stretch/compress end date)

    private var resizeRightDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                isResizingRight = true
                resizeRightOffset = value.translation.width
            }
            .onEnded { value in
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

    // MARK: - Resize Left Gesture (compress/stretch start date)

    private var resizeLeftDrag: some Gesture {
        DragGesture()
            .onChanged { value in
                isResizingLeft = true
                resizeLeftOffset = value.translation.width
            }
            .onEnded { value in
                isResizingLeft = false
                let calendarDaysMoved = Int(round(value.translation.width / vm.dayWidth))
                let newStartDate = Calendar.current.date(byAdding: .day, value: calendarDaysMoved, to: task.startDate) ?? task.startDate
                // Recalculate duration from new start to existing end
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
