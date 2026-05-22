import Foundation
import CoreGraphics
import CoreText
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders a date-range slice of the Gantt chart to a PDF.
///
/// Output: US Letter landscape (792 × 612 pt). Each page has:
/// - title block (project + date range + generated stamp)
/// - date-axis header with month/day labels and tick marks
/// - task table with Name / Start / End / Days columns
/// - timeline bars colored by category, with "Today" line if in range
/// - category legend on the last page
///
/// All drawing uses raw CGContext for precise positioning. Pagination is by
/// task row; the date scale stays consistent across pages so a task that
/// spans the full range looks identical on page 1 and page N.
struct GanttPDFRenderer {
    let title: String
    let tasks: [GanttTask]
    let projectsByID: [String: String]   // recordName → project title (unused on page; kept in case legend needs it)
    let dateRange: ClosedRange<Date>

    // MARK: - Layout (CG coordinates: y=0 is bottom of page)

    private let pageWidth: CGFloat = 792
    private let pageHeight: CGFloat = 612
    private let margin: CGFloat = 36
    private let titleBlockHeight: CGFloat = 60
    private let dateHeaderHeight: CGFloat = 38
    private let footerHeight: CGFloat = 30   // legend strip on last page
    private let taskListWidth: CGFloat = 320

    /// Multi-project exports get a project subtitle under each task name.
    private var showsProjectSubtitle: Bool {
        Set(tasks.map(\.projectID)).count > 1
    }

    /// Minimum row height. Rows whose task name wraps onto extra lines grow
    /// taller than this; single-line rows stay at the compact minimum so the
    /// look matches the previous fixed-height layout.
    private var minRowHeight: CGFloat { showsProjectSubtitle ? 30 : 22 }

    /// Vertical space per wrapped line of the task name (regular 10pt) and per
    /// project subtitle line (regular 7pt).
    private let nameLineHeight: CGFloat = 13
    private let subtitleLineHeight: CGFloat = 10
    /// Hard cap on wrapped name lines so one pathological name can't eat a
    /// whole page; the last line gets an ellipsis if it overflows the cap.
    private let maxNameLines = 4

    // Column splits inside the task list (relative to task-list left edge).
    // Sum + 8pt left padding = taskListWidth (320). Days column gets a wider
    // slot so the bold "DAYS" header doesn't bleed into the timeline area.
    private let nameColumnWidth: CGFloat = 178
    private let startColumnWidth: CGFloat = 52
    private let endColumnWidth: CGFloat = 52
    private let daysColumnWidth: CGFloat = 30

    // Reference y-values, top-down. All are CG y (bottom-origin).
    private var pageTop: CGFloat { pageHeight - margin }
    private var titleBlockBottom: CGFloat { pageTop - titleBlockHeight }
    private var dateHeaderBottom: CGFloat { titleBlockBottom - dateHeaderHeight }
    private var rowAreaBottom: CGFloat { margin + footerHeight }
    /// Vertical space available for task rows on a page.
    private var availableRowHeight: CGFloat { dateHeaderBottom - rowAreaBottom }

    private var timelineLeft: CGFloat { margin + taskListWidth }
    private var timelineRight: CGFloat { pageWidth - margin }
    private var timelineWidth: CGFloat { timelineRight - timelineLeft }

    // MARK: - Render

    func render() -> URL? {
        // Only include tasks whose active span intersects the export window —
        // passed tasks (ending before the range) and not-yet-started tasks
        // (starting after the range) are omitted entirely.
        let visibleTasks = tasks
            .filter { taskOverlapsRange($0) }
            .sorted { $0.sortOrder < $1.sortOrder }
        let rows = layoutRows(visibleTasks)

        let totalDays = max(1, daysBetween(dateRange.lowerBound, dateRange.upperBound))
        let dayWidth = timelineWidth / CGFloat(totalDays)

        // Paginate by cumulative row height: keep adding rows to a page until
        // the next one wouldn't fit in the available row area.
        var pages: [[LaidOutRow]] = []
        var currentPage: [LaidOutRow] = []
        var usedHeight: CGFloat = 0
        for row in rows {
            if !currentPage.isEmpty && usedHeight + row.height > availableRowHeight {
                pages.append(currentPage)
                currentPage = []
                usedHeight = 0
            }
            currentPage.append(row)
            usedHeight += row.height
        }
        if !currentPage.isEmpty { pages.append(currentPage) }
        if pages.isEmpty { pages = [[]] }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Gantt-\(safeFilename(title))-\(Self.timestamp).pdf")

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return nil }

        for (pageIndex, pageRows) in pages.enumerated() {
            let isLastPage = (pageIndex == pages.count - 1)
            let rowsHeight = pageRows.reduce(0) { $0 + $1.height }

            context.beginPDFPage(nil)
            drawTitleBlock(in: context, pageIndex: pageIndex, pageCount: pages.count)
            drawColumnHeaders(in: context)
            drawDateHeader(in: context, dayWidth: dayWidth, totalDays: totalDays)
            // Weekend shading sits BELOW gridlines and bars but ABOVE the
            // date header fill, so the chart background visibly differs on
            // Sat/Sun without obscuring tick labels above.
            drawWeekendShading(in: context, dayWidth: dayWidth, totalDays: totalDays, rowsHeight: rowsHeight)
            drawGridlines(in: context, dayWidth: dayWidth, totalDays: totalDays, rowsHeight: rowsHeight)
            drawTaskRows(in: context, pageRows: pageRows, dayWidth: dayWidth)
            drawTodayLine(in: context, dayWidth: dayWidth, totalDays: totalDays, rowsHeight: rowsHeight)
            if isLastPage {
                drawCategoryLegend(in: context, tasks: visibleTasks)
            }
            context.endPDFPage()
        }

        context.closePDF()
        return url
    }

    // MARK: - Row layout (wrapping + height)

    /// A task row with its name pre-wrapped to fit the name column and the
    /// resulting row height computed.
    private struct LaidOutRow {
        let task: GanttTask
        let nameLines: [String]
        let height: CGFloat
    }

    private func layoutRows(_ tasks: [GanttTask]) -> [LaidOutRow] {
        tasks.map { task in
            let lines = wrapText(task.name, font: regular(10),
                                 maxWidth: nameColumnWidth - 16, maxLines: maxNameLines)
            let textBlock = CGFloat(lines.count) * nameLineHeight
                + (showsProjectSubtitle ? subtitleLineHeight : 0)
            let height = max(minRowHeight, textBlock + 9)
            return LaidOutRow(task: task, nameLines: lines, height: height)
        }
    }

    // MARK: - Drawing — title block

    private func drawTitleBlock(in ctx: CGContext, pageIndex: Int, pageCount: Int) {
        let topY = pageTop
        // Project title
        drawText(title, at: CGPoint(x: margin, y: topY - 22),
                 font: bold(20), color: .black, in: ctx)

        // Date range subtitle
        let dateLine = "\(formatLongDate(dateRange.lowerBound))  →  \(formatLongDate(dateRange.upperBound))   ·   \(daysBetween(dateRange.lowerBound, dateRange.upperBound)) days"
        drawText(dateLine, at: CGPoint(x: margin, y: topY - 42),
                 font: regular(11), color: gray(0.35), in: ctx)

        // Right side: page count + generation stamp
        let pageLabel = "Page \(pageIndex + 1) of \(pageCount)"
        let pageWidthEst = estimateWidth(pageLabel, font: regular(10))
        drawText(pageLabel, at: CGPoint(x: pageWidth - margin - pageWidthEst, y: topY - 22),
                 font: regular(10), color: gray(0.4), in: ctx)

        let stamp = "Generated \(formatDateTime(Date()))"
        let stampWidth = estimateWidth(stamp, font: regular(9))
        drawText(stamp, at: CGPoint(x: pageWidth - margin - stampWidth, y: topY - 42),
                 font: regular(9), color: gray(0.5), in: ctx)

        // Underline rule
        ctx.setStrokeColor(gray(0.7))
        ctx.setLineWidth(0.6)
        ctx.move(to: CGPoint(x: margin, y: titleBlockBottom + 4))
        ctx.addLine(to: CGPoint(x: pageWidth - margin, y: titleBlockBottom + 4))
        ctx.strokePath()
    }

    // MARK: - Drawing — column headers (Task / Start / End / Days)

    private func drawColumnHeaders(in ctx: CGContext) {
        // Sits in the same vertical band as the date header.
        let centerY = dateHeaderBottom + dateHeaderHeight / 2 - 4

        ctx.setFillColor(gray(0.93))
        ctx.fill(CGRect(x: margin, y: dateHeaderBottom,
                        width: taskListWidth, height: dateHeaderHeight))

        var x = margin + 8
        drawText("TASK", at: CGPoint(x: x, y: centerY),
                 font: bold(9), color: gray(0.25), in: ctx)
        x += nameColumnWidth
        drawText("START", at: CGPoint(x: x, y: centerY),
                 font: bold(9), color: gray(0.25), in: ctx)
        x += startColumnWidth
        drawText("END", at: CGPoint(x: x, y: centerY),
                 font: bold(9), color: gray(0.25), in: ctx)
        x += endColumnWidth
        drawText("DAYS", at: CGPoint(x: x, y: centerY),
                 font: bold(9), color: gray(0.25), in: ctx)
    }

    // MARK: - Drawing — date axis

    private func drawDateHeader(in ctx: CGContext, dayWidth: CGFloat, totalDays: Int) {
        // Background fill for the timeline portion
        ctx.setFillColor(gray(0.96))
        ctx.fill(CGRect(x: timelineLeft, y: dateHeaderBottom,
                        width: timelineWidth, height: dateHeaderHeight))

        // Bottom rule across the full header
        ctx.setStrokeColor(gray(0.55))
        ctx.setLineWidth(0.7)
        ctx.move(to: CGPoint(x: margin, y: dateHeaderBottom))
        ctx.addLine(to: CGPoint(x: pageWidth - margin, y: dateHeaderBottom))
        ctx.strokePath()

        // Tick stride: pick day count between labels so we get ~6–14 labels max.
        let stride = tickStride(forDays: totalDays)
        let cal = Calendar.current
        var day = 0
        while day <= totalDays {
            let x = timelineLeft + CGFloat(day) * dayWidth
            let date = cal.date(byAdding: .day, value: day, to: dateRange.lowerBound) ?? dateRange.lowerBound

            // Tick mark (extends slightly below the header rule)
            ctx.setStrokeColor(gray(0.55))
            ctx.setLineWidth(0.6)
            ctx.move(to: CGPoint(x: x, y: dateHeaderBottom - 3))
            ctx.addLine(to: CGPoint(x: x, y: dateHeaderBottom + 4))
            ctx.strokePath()

            // Two-line label: month above, day below (or one line for sparse strides).
            // Anchor strategy:
            //   - first tick (day == 0): left-align so labels stay inside the timeline
            //   - last tick (day == totalDays): right-align so they stay inside too
            //   - middle ticks: center on the tick
            // Without this, "Apr 29" at the first tick spills into the task-list column.
            let isFirst = (day == 0)
            let isLast = (day == totalDays)

            if stride < 30 {
                let monthLabel = monthFormatter.string(from: date)
                let dayLabel = dayFormatter.string(from: date)
                let monthW = estimateWidth(monthLabel, font: regular(8))
                let dayW = estimateWidth(dayLabel, font: bold(11))

                let monthX: CGFloat
                let dayX: CGFloat
                if isFirst {
                    monthX = x + 3
                    dayX = x + 3
                } else if isLast {
                    monthX = x - monthW - 3
                    dayX = x - dayW - 3
                } else {
                    monthX = x - monthW / 2
                    dayX = x - dayW / 2
                }

                drawText(monthLabel,
                         at: CGPoint(x: monthX, y: dateHeaderBottom + dateHeaderHeight - 14),
                         font: regular(8), color: gray(0.4), in: ctx)
                drawText(dayLabel,
                         at: CGPoint(x: dayX, y: dateHeaderBottom + 8),
                         font: bold(11), color: .black, in: ctx)
            } else {
                let label = monthYearFormatter.string(from: date)
                let labelWidth = estimateWidth(label, font: bold(10))
                let labelX: CGFloat
                if isFirst {
                    labelX = x + 3
                } else if isLast {
                    labelX = x - labelWidth - 3
                } else {
                    labelX = x - labelWidth / 2
                }
                drawText(label,
                         at: CGPoint(x: labelX, y: dateHeaderBottom + dateHeaderHeight / 2 - 4),
                         font: bold(10), color: .black, in: ctx)
            }

            day += stride
        }
    }

    // MARK: - Drawing — weekend shading
    //
    // Light bluish-gray vertical bands behind every Saturday and Sunday in
    // the chart row area. Helps the PM see at a glance which days are
    // off-calendar so a bar that crosses a weekend is obvious.

    private func drawWeekendShading(in ctx: CGContext, dayWidth: CGFloat, totalDays: Int, rowsHeight: CGFloat) {
        guard rowsHeight > 0 else { return }
        let cal = Calendar.current
        let topY = dateHeaderBottom
        let bottomY = topY - rowsHeight

        // Cool-tinted gray so weekends read as "non-working time" and don't
        // visually compete with the warmer category bar colors.
        let weekendColor = CGColor(srgbRed: 0.91, green: 0.92, blue: 0.94, alpha: 1)
        ctx.setFillColor(weekendColor)

        for day in 0..<totalDays {
            let date = cal.date(byAdding: .day, value: day, to: dateRange.lowerBound) ?? dateRange.lowerBound
            let weekday = cal.component(.weekday, from: date)   // Sunday = 1, Saturday = 7
            guard weekday == 1 || weekday == 7 else { continue }
            let x = timelineLeft + CGFloat(day) * dayWidth
            ctx.fill(CGRect(x: x, y: bottomY, width: dayWidth, height: topY - bottomY))
        }
    }

    // MARK: - Drawing — gridlines extending into the chart area

    private func drawGridlines(in ctx: CGContext, dayWidth: CGFloat, totalDays: Int, rowsHeight: CGFloat) {
        let stride = tickStride(forDays: totalDays)
        let topY = dateHeaderBottom
        let bottomY = topY - rowsHeight
        var day = 0
        while day <= totalDays {
            let x = timelineLeft + CGFloat(day) * dayWidth
            ctx.setStrokeColor(gray(0.88))
            ctx.setLineWidth(0.3)
            ctx.move(to: CGPoint(x: x, y: bottomY))
            ctx.addLine(to: CGPoint(x: x, y: topY))
            ctx.strokePath()
            day += stride
        }

        // Vertical separator between task list and timeline (above the header
        // we already drew the underline rule, so this just continues it down
        // through the row area).
        ctx.setStrokeColor(gray(0.55))
        ctx.setLineWidth(0.7)
        ctx.move(to: CGPoint(x: timelineLeft, y: bottomY))
        ctx.addLine(to: CGPoint(x: timelineLeft, y: dateHeaderBottom + dateHeaderHeight))
        ctx.strokePath()
    }

    // MARK: - Drawing — task rows

    private func drawTaskRows(in ctx: CGContext, pageRows: [LaidOutRow], dayWidth: CGFloat) {
        var y = dateHeaderBottom
        for (i, row) in pageRows.enumerated() {
            let task = row.task
            let h = row.height
            y -= h   // y is now the BOTTOM of this row

            // Zebra striping (subtle — light gray for even rows in task-list area only;
            // the timeline gets a fully transparent stripe so gridlines remain visible)
            if i % 2 == 0 {
                ctx.setFillColor(gray(0.97))
                ctx.fill(CGRect(x: margin, y: y, width: taskListWidth, height: h))
            }

            drawTaskListColumns(in: ctx, row: row, rowY: y)

            // Bar
            let barRect = barRect(for: task, rowY: y, rowHeight: h, dayWidth: dayWidth)
            if barRect.width > 0 {
                let color = categoryColor(task.category)
                ctx.setFillColor(color)
                let path = CGPath(roundedRect: barRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
                ctx.addPath(path)
                ctx.fillPath()

                // Progress overlay (darker shade over completed portion)
                if task.progress > 0 && task.progress < 1 {
                    let progressRect = CGRect(x: barRect.minX, y: barRect.minY,
                                              width: barRect.width * CGFloat(min(max(task.progress, 0), 1)),
                                              height: barRect.height)
                    ctx.setFillColor(darken(color, by: 0.25))
                    let progressPath = CGPath(roundedRect: progressRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
                    ctx.addPath(progressPath)
                    ctx.fillPath()
                }

                // Percent label on bar (when completed bar is wide enough)
                if barRect.width > 80, task.progress > 0 {
                    let pctLabel = "\(Int(task.progress * 100))%"
                    let pctWidth = estimateWidth(pctLabel, font: bold(8))
                    drawText(pctLabel,
                             at: CGPoint(x: barRect.maxX - pctWidth - 6, y: barRect.minY + 4),
                             font: bold(8),
                             color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85),
                             in: ctx)
                }
            }

            // Row baseline rule
            ctx.setStrokeColor(gray(0.92))
            ctx.setLineWidth(0.3)
            ctx.move(to: CGPoint(x: margin, y: y))
            ctx.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            ctx.strokePath()
        }
    }

    private func drawTaskListColumns(in ctx: CGContext, row: LaidOutRow, rowY: CGFloat) {
        let task = row.task
        let h = row.height
        let lines = row.nameLines

        // Vertically center the name block (plus subtitle, if any) within the
        // row. `firstBaseline` is the text baseline of the top name line; each
        // subsequent line drops by `nameLineHeight`. For a single-line,
        // no-subtitle row this lands on the same baseline as the old layout.
        let blockHeight = CGFloat(lines.count) * nameLineHeight
            + (showsProjectSubtitle ? subtitleLineHeight : 0)
        let blockTop = rowY + (h + blockHeight) / 2
        let firstBaseline = blockTop - nameLineHeight + 3

        var x = margin + 8

        // Status indicator dot — aligned to the top name line.
        let dotY = firstBaseline + 1
        ctx.setFillColor(statusCGColor(task.status))
        ctx.fillEllipse(in: CGRect(x: x, y: dotY, width: 7, height: 7))
        x += 12

        // Task name, wrapped across as many lines as it needs.
        for (idx, lineStr) in lines.enumerated() {
            drawText(lineStr,
                     at: CGPoint(x: x, y: firstBaseline - CGFloat(idx) * nameLineHeight),
                     font: regular(10), color: .black, in: ctx)
        }

        // Project subtitle (multi-project exports) sits just below the name.
        if showsProjectSubtitle {
            let projectTitle = projectsByID[task.projectID] ?? ""
            if !projectTitle.isEmpty {
                let subY = firstBaseline - CGFloat(lines.count) * nameLineHeight
                drawText(projectTitle,
                         at: CGPoint(x: x, y: subY),
                         font: regular(7), color: gray(0.5), in: ctx,
                         maxWidth: nameColumnWidth - 16, truncate: true)
            }
        }

        // Dates + days align to the top name line.
        let textY = firstBaseline
        x = margin + 8 + nameColumnWidth
        drawText(formatShortDate(task.startDate),
                 at: CGPoint(x: x, y: textY),
                 font: regular(9), color: gray(0.25), in: ctx)

        // End date (inclusive last working day, matching on-screen Gantt math)
        x += startColumnWidth
        drawText(formatShortDate(inclusiveEndDate(for: task)),
                 at: CGPoint(x: x, y: textY),
                 font: regular(9), color: gray(0.25), in: ctx)

        // Days — right-aligned inside its column so the column reads as
        // a number column, not a left-justified one.
        x += endColumnWidth
        let dur = "\(task.durationDays)"
        let durWidth = estimateWidth(dur, font: bold(9))
        drawText(dur,
                 at: CGPoint(x: x + daysColumnWidth - durWidth - 8, y: textY),
                 font: bold(9), color: gray(0.2), in: ctx)
    }

    // MARK: - Drawing — Today line

    private func drawTodayLine(in ctx: CGContext, dayWidth: CGFloat, totalDays: Int, rowsHeight: CGFloat) {
        let today = Date()
        guard today >= dateRange.lowerBound && today <= dateRange.upperBound else { return }

        let offset = CGFloat(daysBetween(dateRange.lowerBound, today))
        let x = timelineLeft + offset * dayWidth
        let topY = dateHeaderBottom + dateHeaderHeight
        let bottomY = max(rowAreaBottom, dateHeaderBottom - rowsHeight)

        ctx.saveGState()
        ctx.setStrokeColor(CGColor(srgbRed: 0.9, green: 0.2, blue: 0.2, alpha: 0.85))
        ctx.setLineWidth(1.0)
        ctx.setLineDash(phase: 0, lengths: [3, 2])
        ctx.move(to: CGPoint(x: x, y: bottomY))
        ctx.addLine(to: CGPoint(x: x, y: topY))
        ctx.strokePath()
        ctx.restoreGState()

        // "TODAY" pill above the line. Anchor to whichever side of the line
        // keeps the pill inside the timeline (left half → pill goes right,
        // right half → pill goes left), so it never crowds an edge tick.
        let label = "TODAY"
        let lw = estimateWidth(label, font: bold(8))
        let pillWidth = lw + 8
        let pillHeight: CGFloat = 12
        let midX = (timelineLeft + timelineRight) / 2
        let pillX: CGFloat = (x <= midX) ? x : x - pillWidth
        let labelRect = CGRect(x: pillX, y: topY + 2, width: pillWidth, height: pillHeight)
        ctx.setFillColor(CGColor(srgbRed: 0.9, green: 0.2, blue: 0.2, alpha: 1.0))
        ctx.fill(labelRect)
        drawText(label,
                 at: CGPoint(x: pillX + 4, y: topY + 4),
                 font: bold(8),
                 color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                 in: ctx)
    }

    // MARK: - Drawing — category legend

    private func drawCategoryLegend(in ctx: CGContext, tasks: [GanttTask]) {
        let y = margin + 6
        let categories = Array(Set(tasks.map(\.category))).sorted { $0.rawValue < $1.rawValue }
        guard !categories.isEmpty else { return }

        var x = margin
        drawText("LEGEND",
                 at: CGPoint(x: x, y: y),
                 font: bold(8), color: gray(0.4), in: ctx)
        x += estimateWidth("LEGEND", font: bold(8)) + 12

        for cat in categories {
            ctx.setFillColor(categoryColor(cat))
            ctx.fill(CGRect(x: x, y: y + 1, width: 10, height: 8))
            x += 14
            let label = cat.rawValue
            drawText(label,
                     at: CGPoint(x: x, y: y),
                     font: regular(9), color: gray(0.25), in: ctx)
            x += estimateWidth(label, font: regular(9)) + 14
            // Wrap to a second line if we run out of room
            if x > pageWidth - margin - 100 { break }
        }
    }

    // MARK: - Geometry helpers

    private func barRect(for task: GanttTask, rowY: CGFloat, rowHeight: CGFloat, dayWidth: CGFloat) -> CGRect {
        // Task occupies [startDate, startDate + durationDays). Exclusive end.
        let taskEnd = endDate(for: task)
        let clippedStart = max(task.startDate, dateRange.lowerBound)
        let clippedEnd = min(taskEnd, dateRange.upperBound)
        guard clippedEnd > clippedStart else { return .zero }

        let startOffset = CGFloat(daysBetween(dateRange.lowerBound, clippedStart))
        let endOffset = CGFloat(daysBetween(dateRange.lowerBound, clippedEnd))

        let x = timelineLeft + startOffset * dayWidth
        let width = max(2, (endOffset - startOffset) * dayWidth)
        // Cap bar thickness so tall (multi-line) rows don't get a chunky bar;
        // center it vertically within the row.
        let barHeight: CGFloat = min(14, rowHeight - 8)
        let y = rowY + (rowHeight - barHeight) / 2
        return CGRect(x: x, y: y, width: width, height: barHeight)
    }

    private func endDate(for task: GanttTask) -> Date {
        // Workday-aware exclusive end — same calculation the on-screen Gantt
        // uses (`GanttTask.endDate`), which advances `durationDays` workdays
        // past `startDate` skipping Sundays (and Saturdays unless the task
        // opts in). Using plain calendar arithmetic here would draw shorter
        // bars in the PDF than what the user sees on-screen for any task
        // that crosses a weekend.
        task.endDate
    }

    /// Last day the task is still in progress (inclusive). Used for the
    /// End column display ("ends Apr 15") instead of the exclusive
    /// start-of-next-day. Falls back to startDate for 0-duration tasks.
    private func inclusiveEndDate(for task: GanttTask) -> Date {
        let exclusiveEnd = task.endDate
        let oneDayBack = Calendar.current.date(byAdding: .day, value: -1, to: exclusiveEnd) ?? task.startDate
        return max(task.startDate, oneDayBack)
    }

    /// Whether a task's active span intersects the export window. Tasks that
    /// end before the range (passed) or start after it are excluded from the
    /// export entirely.
    private func taskOverlapsRange(_ task: GanttTask) -> Bool {
        let taskEnd = endDate(for: task)
        return taskEnd > dateRange.lowerBound && task.startDate <= dateRange.upperBound
    }

    private func daysBetween(_ a: Date, _ b: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
    }

    private func tickStride(forDays days: Int) -> Int {
        switch days {
        case 0...10: return 1
        case 11...30: return 3
        case 31...60: return 7
        case 61...120: return 14
        case 121...365: return 30
        default: return 60
        }
    }

    // MARK: - Date formatting

    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f
    }()
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f
    }()
    private let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM yy"
        return f
    }()
    private let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()
    private let longDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
    private let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    private func formatLongDate(_ date: Date) -> String { longDateFormatter.string(from: date) }
    private func formatShortDate(_ date: Date) -> String { shortDateFormatter.string(from: date) }
    private func formatDateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }

    private static var timestamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    private func safeFilename(_ s: String) -> String {
        let cleaned = s.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return String(cleaned).prefix(40).description
    }

    // MARK: - Color helpers
    //
    // Mirrors `TaskCategory.color` so the on-screen and exported colors
    // match exactly. Updates here must update there.

    private func categoryColor(_ cat: TaskCategory) -> CGColor {
        switch cat {
        case .leadTime: return cgColor(0x60, 0x7D, 0x8B)      // slate
        case .fabrication: return cgColor(0x6A, 0x1B, 0x9A)   // deep purple
        case .delivery: return cgColor(0x19, 0x76, 0xD2)      // blue
        case .erection: return cgColor(0xE6, 0x51, 0x00)      // deep orange
        case .inspection: return cgColor(0x2E, 0x7D, 0x32)    // green
        case .rfiSubmittal: return cgColor(0x00, 0x83, 0x8F)  // cyan
        case .deadline: return cgColor(0xC6, 0x28, 0x28)      // red
        case .meetings: return cgColor(0x45, 0x27, 0xA0)      // indigo
        case .payApp: return cgColor(0x00, 0x69, 0x5C)        // dark teal
        case .other: return cgColor(0x5D, 0x40, 0x37)         // brown
        }
    }

    /// Smaller dot palette for the per-row status indicator.
    private func statusCGColor(_ status: TaskStatus) -> CGColor {
        switch status {
        case .notStarted: return gray(0.7)
        case .inProgress: return cgColor(0x19, 0x76, 0xD2)    // blue
        case .completed: return cgColor(0x2E, 0x7D, 0x32)     // green
        case .delayed: return cgColor(0xC6, 0x28, 0x28)       // red
        case .onHold: return cgColor(0xE6, 0x51, 0x00)        // orange
        case .milestone: return cgColor(0x6A, 0x1B, 0x9A)     // purple
        }
    }

    private func cgColor(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    private func gray(_ value: CGFloat) -> CGColor {
        CGColor(srgbRed: value, green: value, blue: value, alpha: 1)
    }

    private func gray(_ value: Double) -> CGColor { gray(CGFloat(value)) }

    private func darken(_ color: CGColor, by amount: CGFloat) -> CGColor {
        guard let comps = color.components, comps.count >= 3 else { return color }
        let factor = max(0, 1 - amount)
        return CGColor(srgbRed: comps[0] * factor, green: comps[1] * factor, blue: comps[2] * factor,
                       alpha: comps.count >= 4 ? comps[3] : 1)
    }

    // MARK: - Text drawing

    private func bold(_ size: CGFloat) -> CTFont {
        CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }
    private func regular(_ size: CGFloat) -> CTFont {
        CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private func drawText(_ string: String, at point: CGPoint, font: CTFont, color: CGColor,
                          in ctx: CGContext, maxWidth: CGFloat? = nil, truncate: Bool = false) {
        let displayString = (truncate && maxWidth != nil)
            ? truncated(string, font: font, maxWidth: maxWidth!)
            : string
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attributed = NSAttributedString(string: displayString, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)
        ctx.textPosition = point
        CTLineDraw(line, ctx)
    }

    private func estimateWidth(_ string: String, font: CTFont) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let attributed = NSAttributedString(string: string, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attributed)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private func truncated(_ string: String, font: CTFont, maxWidth: CGFloat) -> String {
        if estimateWidth(string, font: font) <= maxWidth { return string }
        var current = string
        while current.count > 1 && estimateWidth(current + "…", font: font) > maxWidth {
            current.removeLast()
        }
        return current + "…"
    }

    /// Word-wrap `string` to fit `maxWidth`, returning one entry per line.
    /// Words longer than the column are hard-broken by character. If the text
    /// needs more than `maxLines`, the final line is ellipsized.
    private func wrapText(_ string: String, font: CTFont, maxWidth: CGFloat, maxLines: Int) -> [String] {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [""] }
        if estimateWidth(trimmed, font: font) <= maxWidth { return [trimmed] }

        var words = trimmed.split(separator: " ").map(String.init)
        var lines: [String] = []
        var current = ""
        var i = 0

        while i < words.count {
            let word = words[i]
            let candidate = current.isEmpty ? word : current + " " + word
            if estimateWidth(candidate, font: font) <= maxWidth {
                current = candidate
                i += 1
            } else if current.isEmpty {
                // Single word wider than the column — hard-break by character.
                var chunk = ""
                var consumed = 0
                for ch in word {
                    if estimateWidth(chunk + String(ch), font: font) <= maxWidth {
                        chunk.append(ch); consumed += 1
                    } else { break }
                }
                if chunk.isEmpty { chunk = String(word.first!); consumed = 1 }
                lines.append(chunk)
                words[i] = String(word.dropFirst(consumed))
                if lines.count >= maxLines { break }
            } else {
                lines.append(current)
                current = ""
                if lines.count >= maxLines { break }
            }
        }
        if lines.count < maxLines && !current.isEmpty { lines.append(current) }

        // If text remains beyond the cap, ellipsize the last line.
        let consumedEverything = (i >= words.count) && current.isEmpty
        if !consumedEverything, lines.count >= maxLines, var last = lines.popLast() {
            while !last.isEmpty && estimateWidth(last + "…", font: font) > maxWidth {
                last.removeLast()
            }
            lines.append(last + "…")
        }

        return lines.isEmpty ? [trimmed] : lines
    }
}

private extension CGColor {
    static var black: CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) }
}
