import SwiftUI

struct GanttTimelineGridView: View {
    let vm: GanttViewModel
    let tasks: [GanttTask]

    var body: some View {
        Canvas { context, size in
            let dates = vm.datesInRange(tasks: tasks)
            let dayWidth = vm.dayWidth
            let headerHeight = vm.headerHeight
            let rowHeight = vm.rowHeight

            // 1. Weekend shading
            for (i, date) in dates.enumerated() {
                if date.isWeekend {
                    let rect = CGRect(x: CGFloat(i) * dayWidth, y: 0,
                                      width: dayWidth, height: size.height)
                    context.fill(Path(rect), with: .color(vm.weekendFill))
                }
            }

            // 2. Horizontal row lines
            var y = headerHeight
            while y < size.height {
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(vm.gridLineColor), lineWidth: 0.5)
                y += rowHeight
            }

            // 3. Vertical day lines (only if zoomed enough)
            if dayWidth >= 14 {
                for i in 0...dates.count {
                    let x = CGFloat(i) * dayWidth
                    let path = Path { p in
                        p.move(to: CGPoint(x: x, y: headerHeight))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    context.stroke(path, with: .color(vm.gridLineColor), lineWidth: 0.5)
                }
            }

            // 4. Header background
            let headerRect = CGRect(x: 0, y: 0, width: size.width, height: headerHeight)
            context.fill(Path(headerRect), with: .color(AppTheme.secondaryBackground))

            // 5. Month labels & separators
            let spans = vm.monthSpans(tasks: tasks)
            for span in spans {
                // Month separator line
                let sepPath = Path { p in
                    p.move(to: CGPoint(x: span.startX, y: 0))
                    p.addLine(to: CGPoint(x: span.startX, y: size.height))
                }
                context.stroke(sepPath, with: .color(vm.gridLineColor), lineWidth: 1)

                // Month label
                let label = Text(span.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                context.draw(label, at: CGPoint(x: span.startX + 8, y: 14), anchor: .leading)
            }

            // 6. Day numbers (only if zoomed enough)
            if dayWidth >= 18 {
                for (i, date) in dates.enumerated() {
                    let x = CGFloat(i) * dayWidth + dayWidth / 2
                    let fontSize: CGFloat = dayWidth >= 30 ? 10 : 8
                    let label = Text("\(date.dayOfMonth)")
                        .font(.system(size: fontSize, design: .monospaced))
                        .foregroundColor(date.isWeekend ? .secondary : .primary)
                    context.draw(label, at: CGPoint(x: x, y: headerHeight - 14), anchor: .center)
                }
            }

            // 7. Header bottom border
            let borderPath = Path { p in
                p.move(to: CGPoint(x: 0, y: headerHeight))
                p.addLine(to: CGPoint(x: size.width, y: headerHeight))
            }
            context.stroke(borderPath, with: .color(vm.gridLineColor), lineWidth: 1)
        }
    }
}

// MARK: - Today Marker (grey highlight column spanning the full day width)
struct GanttTodayMarkerView: View {
    let vm: GanttViewModel
    let tasks: [GanttTask]
    let height: CGFloat

    var body: some View {
        let x = vm.xPosition(for: Date(), tasks: tasks)
        let columnWidth = vm.dayWidth

        ZStack(alignment: .top) {
            // Full-day highlight column — scales with zoom
            Rectangle()
                .fill(Color.gray.opacity(0.25))
                .frame(width: max(columnWidth, 2), height: height)
                .position(x: x + columnWidth / 2, y: height / 2)

            // Left and right edge lines
            Rectangle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 1, height: height)
                .position(x: x, y: height / 2)
            Rectangle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 1, height: height)
                .position(x: x + columnWidth, y: height / 2)

            // "Today" badge
            Text("Today")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .position(x: x + columnWidth / 2, y: 8)
        }
        .allowsHitTesting(false)
    }
}
