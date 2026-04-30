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
/// Output: US Letter landscape (792 × 612 pt). Each page has a title block,
/// a date axis, and up to ~22 task rows. Long task lists paginate by row;
/// the date scale stays consistent across pages so a task that spans the
/// full range looks the same on page 1 and page 5.
///
/// Task bars are colored by `TaskCategory` to match the on-screen chart.
/// Returns a temp-directory file URL that callers can hand to NSWorkspace
/// or ShareLink.
struct GanttPDFRenderer {
    let title: String
    let tasks: [GanttTask]
    let projectsByID: [String: String]   // recordName → project title
    let dateRange: ClosedRange<Date>

    // MARK: - Layout

    private let pageWidth: CGFloat = 792
    private let pageHeight: CGFloat = 612
    private let margin: CGFloat = 36
    private let titleBlockHeight: CGFloat = 56
    private let dateHeaderHeight: CGFloat = 32
    private let rowHeight: CGFloat = 22
    private let taskListWidth: CGFloat = 240
    private let footerHeight: CGFloat = 22

    private var contentTop: CGFloat { pageHeight - margin - titleBlockHeight }
    private var dateHeaderTop: CGFloat { contentTop - dateHeaderHeight }
    private var firstRowTop: CGFloat { dateHeaderTop - rowHeight }
    private var rowsPerPage: Int {
        max(1, Int((dateHeaderTop - margin - footerHeight) / rowHeight))
    }
    private var timelineLeft: CGFloat { margin + taskListWidth }
    private var timelineRight: CGFloat { pageWidth - margin }
    private var timelineWidth: CGFloat { timelineRight - timelineLeft }

    // MARK: - Render

    func render() -> URL? {
        let visibleTasks = tasks
            .filter { task in
                let taskEnd = endDate(for: task)
                return taskEnd >= dateRange.lowerBound && task.startDate <= dateRange.upperBound
            }
            .sorted { $0.sortOrder < $1.sortOrder }

        let totalDays = max(1, daysBetween(dateRange.lowerBound, dateRange.upperBound))
        let dayWidth = timelineWidth / CGFloat(totalDays)

        let pageCount = max(1, Int(ceil(Double(visibleTasks.count) / Double(rowsPerPage))))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Gantt-\(safeFilename(title))-\(Self.timestamp).pdf")

        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return nil }

        for pageIndex in 0..<pageCount {
            let start = pageIndex * rowsPerPage
            let end = min(start + rowsPerPage, visibleTasks.count)
            let pageTasks = Array(visibleTasks[start..<end])

            context.beginPDFPage(nil)
            drawTitleBlock(in: context, pageIndex: pageIndex, pageCount: pageCount)
            drawDateHeader(in: context, dayWidth: dayWidth, totalDays: totalDays)
            drawTaskRows(in: context, pageTasks: pageTasks, dayWidth: dayWidth)
            drawFooter(in: context, taskRange: (start + 1, end), totalTasks: visibleTasks.count)
            context.endPDFPage()
        }

        context.closePDF()
        return url
    }

    // MARK: - Drawing primitives

    private func drawTitleBlock(in ctx: CGContext, pageIndex: Int, pageCount: Int) {
        let rect = CGRect(x: margin, y: pageHeight - margin - titleBlockHeight,
                          width: pageWidth - margin * 2, height: titleBlockHeight)

        drawText(title, at: CGPoint(x: rect.minX, y: rect.maxY - 18),
                 font: bold(18), color: .black, in: ctx)

        let dateLine = "\(formatDate(dateRange.lowerBound)) — \(formatDate(dateRange.upperBound))"
        drawText(dateLine, at: CGPoint(x: rect.minX, y: rect.maxY - 36),
                 font: regular(11), color: gray(0.4), in: ctx)

        let pageLabel = "Page \(pageIndex + 1) of \(pageCount)"
        let pageWidthEst = estimateWidth(pageLabel, font: regular(10))
        drawText(pageLabel, at: CGPoint(x: rect.maxX - pageWidthEst, y: rect.maxY - 18),
                 font: regular(10), color: gray(0.5), in: ctx)

        let stamp = "Generated \(formatDateTime(Date()))"
        let stampWidth = estimateWidth(stamp, font: regular(9))
        drawText(stamp, at: CGPoint(x: rect.maxX - stampWidth, y: rect.maxY - 36),
                 font: regular(9), color: gray(0.55), in: ctx)

        // Underline
        ctx.setStrokeColor(gray(0.85))
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: rect.minX, y: rect.minY + 4))
        ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 4))
        ctx.strokePath()
    }

    private func drawDateHeader(in ctx: CGContext, dayWidth: CGFloat, totalDays: Int) {
        let topY = dateHeaderTop
        let bottomY = dateHeaderTop - dateHeaderHeight + 4

        // Background fill for the header strip
        ctx.setFillColor(gray(0.96))
        ctx.fill(CGRect(x: timelineLeft, y: bottomY, width: timelineWidth, height: dateHeaderHeight - 4))

        // Vertical column for the task-list label area
        drawText("Task", at: CGPoint(x: margin + 4, y: topY - 18),
                 font: bold(10), color: gray(0.3), in: ctx)
        drawText("Dur.", at: CGPoint(x: margin + taskListWidth - 36, y: topY - 18),
                 font: bold(10), color: gray(0.3), in: ctx)

        // Tick interval: pick a stride so we get ~10–14 labels max
        let stride = tickStride(forDays: totalDays)
        var day = 0
        while day <= totalDays {
            let x = timelineLeft + CGFloat(day) * dayWidth
            ctx.setStrokeColor(gray(0.82))
            ctx.setLineWidth(0.4)
            ctx.move(to: CGPoint(x: x, y: bottomY))
            ctx.addLine(to: CGPoint(x: x, y: topY))
            ctx.strokePath()

            let date = Calendar.current.date(byAdding: .day, value: day, to: dateRange.lowerBound) ?? dateRange.lowerBound
            let label = formatTickLabel(date, stride: stride)
            drawText(label, at: CGPoint(x: x + 2, y: topY - 14),
                     font: regular(8), color: gray(0.35), in: ctx)
            day += stride
        }

        // Bottom rule
        ctx.setStrokeColor(gray(0.7))
        ctx.setLineWidth(0.6)
        ctx.move(to: CGPoint(x: margin, y: bottomY))
        ctx.addLine(to: CGPoint(x: pageWidth - margin, y: bottomY))
        ctx.strokePath()
    }

    private func drawTaskRows(in ctx: CGContext, pageTasks: [GanttTask], dayWidth: CGFloat) {
        var y = firstRowTop
        for (i, task) in pageTasks.enumerated() {
            let rowRect = CGRect(x: margin, y: y, width: pageWidth - margin * 2, height: rowHeight)

            // Zebra striping
            if i % 2 == 0 {
                ctx.setFillColor(gray(0.97))
                ctx.fill(rowRect)
            }

            // Task label column — project + name
            let projectLabel = projectsByID[task.projectID] ?? ""
            let primary = task.name
            drawText(primary, at: CGPoint(x: margin + 4, y: y + rowHeight - 14),
                     font: regular(10), color: .black, in: ctx,
                     maxWidth: taskListWidth - 50, truncate: true)
            if !projectLabel.isEmpty {
                drawText(projectLabel, at: CGPoint(x: margin + 4, y: y + 2),
                         font: regular(8), color: gray(0.5), in: ctx,
                         maxWidth: taskListWidth - 50, truncate: true)
            }
            // Duration on the right of the task column
            let durLabel = "\(task.durationDays)d"
            let durWidth = estimateWidth(durLabel, font: regular(9))
            drawText(durLabel, at: CGPoint(x: margin + taskListWidth - durWidth - 6, y: y + rowHeight - 14),
                     font: regular(9), color: gray(0.4), in: ctx)

            // Bar
            let barRect = barRect(for: task, in: rowRect, dayWidth: dayWidth)
            if barRect.width > 0 {
                let color = categoryColor(task.category)
                ctx.setFillColor(color)
                let path = CGPath(roundedRect: barRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
                ctx.addPath(path)
                ctx.fillPath()

                // Progress overlay (darker shade over the completed portion)
                if task.progress > 0 && task.progress < 1 {
                    let progressRect = CGRect(x: barRect.minX, y: barRect.minY,
                                              width: barRect.width * CGFloat(min(max(task.progress, 0), 1)),
                                              height: barRect.height)
                    ctx.setFillColor(darken(color, by: 0.25))
                    let progressPath = CGPath(roundedRect: progressRect, cornerWidth: 3, cornerHeight: 3, transform: nil)
                    ctx.addPath(progressPath)
                    ctx.fillPath()
                }

                // Task name overlaid on bar if there's room
                if barRect.width > 60 {
                    let inset = barRect.insetBy(dx: 4, dy: 0)
                    drawText(task.name, at: CGPoint(x: inset.minX, y: inset.minY + 5),
                             font: bold(9),
                             color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                             in: ctx,
                             maxWidth: inset.width, truncate: true)
                }
            }

            // Row baseline rule
            ctx.setStrokeColor(gray(0.92))
            ctx.setLineWidth(0.3)
            ctx.move(to: CGPoint(x: margin, y: y))
            ctx.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            ctx.strokePath()

            y -= rowHeight
        }

        // Vertical separator between task list and timeline
        ctx.setStrokeColor(gray(0.75))
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: timelineLeft, y: margin + footerHeight))
        ctx.addLine(to: CGPoint(x: timelineLeft, y: dateHeaderTop))
        ctx.strokePath()
    }

    private func drawFooter(in ctx: CGContext, taskRange: (Int, Int), totalTasks: Int) {
        let line = "Tasks \(taskRange.0)–\(taskRange.1) of \(totalTasks) · SteelSync"
        drawText(line, at: CGPoint(x: margin, y: margin + 6),
                 font: regular(8), color: gray(0.55), in: ctx)
    }

    // MARK: - Geometry

    private func barRect(for task: GanttTask, in rowRect: CGRect, dayWidth: CGFloat) -> CGRect {
        let clippedStart = max(task.startDate, dateRange.lowerBound)
        let taskEnd = endDate(for: task)
        let clippedEnd = min(taskEnd, dateRange.upperBound)
        guard clippedEnd > clippedStart else { return .zero }

        let startOffset = CGFloat(daysBetween(dateRange.lowerBound, clippedStart))
        let endOffset = CGFloat(daysBetween(dateRange.lowerBound, clippedEnd))

        let x = timelineLeft + startOffset * dayWidth
        let width = max(2, (endOffset - startOffset) * dayWidth)
        let barHeight: CGFloat = rowHeight - 8
        let y = rowRect.minY + (rowHeight - barHeight) / 2
        return CGRect(x: x, y: y, width: width, height: barHeight)
    }

    private func endDate(for task: GanttTask) -> Date {
        Calendar.current.date(byAdding: .day, value: max(0, task.durationDays - 1), to: task.startDate) ?? task.startDate
    }

    private func daysBetween(_ a: Date, _ b: Date) -> Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b))
        return comps.day ?? 0
    }

    private func tickStride(forDays days: Int) -> Int {
        switch days {
        case 0...14: return 1
        case 15...60: return 7
        case 61...180: return 14
        case 181...365: return 30
        default: return 60
        }
    }

    private func formatTickLabel(_ date: Date, stride: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = stride < 7 ? "M/d" : (stride < 30 ? "M/d" : "MMM yy")
        return f.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private static var timestamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }

    private func safeFilename(_ s: String) -> String {
        let cleaned = s.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "-" }
        return String(cleaned).prefix(40).description
    }

    // MARK: - Color helpers (CGColor — bypasses SwiftUI Color since we draw with CG)

    private func categoryColor(_ cat: TaskCategory) -> CGColor {
        switch cat {
        case .leadTime: return cgColor(0x78, 0x90, 0x9C)
        case .fabrication: return cgColor(0x5C, 0x6B, 0xC0)
        case .delivery: return cgColor(0x26, 0xA6, 0x9A)
        case .erection: return cgColor(0xFF, 0x70, 0x43)
        case .inspection: return cgColor(0xAB, 0x47, 0xBC)
        case .rfiSubmittal: return cgColor(0x42, 0xA5, 0xF5)
        case .deadline: return cgColor(0xEF, 0x53, 0x50)
        case .meetings: return cgColor(0x00, 0x89, 0x7B)
        case .payApp: return cgColor(0x5E, 0x35, 0xB1)
        case .other: return cgColor(0x8D, 0x6E, 0x63)
        }
    }

    private func cgColor(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    private func gray(_ value: CGFloat) -> CGColor {
        CGColor(srgbRed: value, green: value, blue: value, alpha: 1)
    }

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

    private func gray(_ value: Double) -> CGColor { gray(CGFloat(value)) }

    private var black: CGColor {
        CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    }
}

private extension CGColor {
    static var black: CGColor { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1) }
}
