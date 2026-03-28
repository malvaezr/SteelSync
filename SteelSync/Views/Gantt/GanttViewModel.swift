import SwiftUI

@MainActor
class GanttViewModel: ObservableObject {
    @Published var dayWidth: CGFloat = 24
    @Published var selectedTaskID: UUID?
    @Published var showingAddTask = false
    @Published var showingEditTask = false

    // MARK: - Layout Constants
    let rowHeight: CGFloat = 36
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
    let gridLineColor = Color.gray.opacity(0.15)

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
}
