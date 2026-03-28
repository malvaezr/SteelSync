import WidgetKit
import SwiftUI

// MARK: - Gantt Preview Widget

struct GanttPreviewTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> GanttPreviewEntry { GanttPreviewEntry(date: Date(), isPlaceholder: true) }
    func getSnapshot(in context: Context, completion: @escaping (GanttPreviewEntry) -> Void) { completion(GanttPreviewEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<GanttPreviewEntry>) -> Void) {
        let entry = GanttPreviewEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct GanttPreviewEntry: TimelineEntry {
    let date: Date
    var isPlaceholder = false

    struct TaskBar: Identifiable {
        let id: Int
        let name: String
        let projectName: String
        let projectColorIndex: Int
        let start: Date
        let end: Date
        let progress: Double
        let status: String
    }

    var tasks: [TaskBar] {
        if isPlaceholder { return Self.placeholderTasks }
        guard let defaults = UserDefaults(suiteName: "group.com.jrfv.SteelSync.shared") else { return [] }

        let names = defaults.stringArray(forKey: "ganttTaskNames") ?? []
        let projectIDs = defaults.stringArray(forKey: "ganttTaskProjectIDs") ?? []
        let starts = defaults.array(forKey: "ganttTaskStarts") as? [Double] ?? []
        let ends = defaults.array(forKey: "ganttTaskEnds") as? [Double] ?? []
        let statuses = defaults.stringArray(forKey: "ganttTaskStatuses") ?? []
        let progresses = defaults.array(forKey: "ganttTaskProgress") as? [Double] ?? []

        // Build project color map
        let uniqueProjectIDs = defaults.stringArray(forKey: "ganttProjectIDs") ?? []
        let projectNames = defaults.stringArray(forKey: "ganttProjectNames") ?? []
        let idToName = Dictionary(uniqueKeysWithValues: zip(uniqueProjectIDs, projectNames))
        let idToColor = Dictionary(uniqueKeysWithValues: uniqueProjectIDs.enumerated().map { ($1, $0) })

        return names.enumerated().compactMap { i, name in
            guard i < starts.count, i < ends.count else { return nil }
            let pid = i < projectIDs.count ? projectIDs[i] : ""
            return TaskBar(
                id: i, name: name,
                projectName: idToName[pid] ?? "Unknown",
                projectColorIndex: idToColor[pid] ?? 0,
                start: Date(timeIntervalSince1970: starts[i]),
                end: Date(timeIntervalSince1970: ends[i]),
                progress: i < progresses.count ? progresses[i] : 0,
                status: i < statuses.count ? statuses[i] : ""
            )
        }
    }

    var timelineStart: Date { tasks.map(\.start).min() ?? Date() }
    var timelineEnd: Date {
        let end = tasks.map(\.end).max() ?? Date().addingTimeInterval(86400 * 30)
        // Ensure at least 14 days visible
        let minEnd = Calendar.current.date(byAdding: .day, value: 14, to: timelineStart) ?? end
        return max(end, minEnd)
    }

    static let placeholderTasks: [TaskBar] = {
        let now = Date()
        return [
            TaskBar(id: 0, name: "Shop Drawings", projectName: "UTSA East Gates", projectColorIndex: 0, start: now.addingTimeInterval(-86400*10), end: now.addingTimeInterval(-86400*2), progress: 1.0, status: "Completed"),
            TaskBar(id: 1, name: "Steel Fabrication", projectName: "UTSA East Gates", projectColorIndex: 0, start: now.addingTimeInterval(-86400*5), end: now.addingTimeInterval(86400*10), progress: 0.6, status: "In Progress"),
            TaskBar(id: 2, name: "Beam & Deck", projectName: "GATX Renovation", projectColorIndex: 1, start: now.addingTimeInterval(-86400*3), end: now.addingTimeInterval(86400*4), progress: 0.3, status: "In Progress"),
            TaskBar(id: 3, name: "Area A,B,C Erection", projectName: "Ascalon Medical", projectColorIndex: 2, start: now, end: now.addingTimeInterval(86400*20), progress: 0, status: "Not Started"),
            TaskBar(id: 4, name: "Delivery #1", projectName: "Alice Stadium", projectColorIndex: 3, start: now.addingTimeInterval(86400*2), end: now.addingTimeInterval(86400*5), progress: 0, status: "Not Started"),
            TaskBar(id: 5, name: "Erection Phase 1", projectName: "Great Oaks", projectColorIndex: 4, start: now.addingTimeInterval(86400*5), end: now.addingTimeInterval(86400*15), progress: 0, status: "Not Started"),
        ]
    }()
}

// MARK: - Shared Palette

private let projectPalette: [Color] = [
    .orange, .cyan, .green, .pink, .yellow, .purple, .mint, .indigo, .teal, .red, .blue,
    Color(red: 1, green: 0.6, blue: 0.2), Color(red: 0.4, green: 0.8, blue: 0.4)
]

// MARK: - Medium View

struct GanttMediumView: View {
    let entry: GanttPreviewEntry

    var body: some View {
        let tasks = entry.tasks
        let tStart = entry.timelineStart
        let tEnd = entry.timelineEnd
        let span = tEnd.timeIntervalSince(tStart)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Schedule", systemImage: "calendar.day.timeline.left")
                    .font(.caption.weight(.bold))
                    .foregroundColor(WidgetColors.orange)
                Spacer()
                Text("\(tasks.count) tasks")
                    .font(.system(size: 9))
                    .foregroundColor(WidgetColors.secondaryText)
            }

            GeometryReader { geo in
                let w = geo.size.width
                let rowH: CGFloat = 12
                let gap: CGFloat = 2
                let todayX = span > 0 ? w * CGFloat(Date().timeIntervalSince(tStart) / span) : 0

                ZStack(alignment: .topLeading) {
                    // Today marker
                    if todayX > 0 && todayX < w {
                        Rectangle().fill(Color.gray.opacity(0.25))
                            .frame(width: max(w * 0.02, 2), height: geo.size.height)
                            .offset(x: todayX)
                    }

                    ForEach(tasks.prefix(5)) { task in
                        let x = span > 0 ? w * CGFloat(task.start.timeIntervalSince(tStart) / span) : 0
                        let barW = span > 0 ? max(w * CGFloat(task.end.timeIntervalSince(task.start) / span), 6) : 20
                        let color = projectPalette[task.projectColorIndex % projectPalette.count]

                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(0.8))
                            .frame(width: barW, height: rowH)
                            .overlay(alignment: .leading) {
                                if barW > 40 {
                                    Text(task.name)
                                        .font(.system(size: 7, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                        .padding(.leading, 2)
                                }
                            }
                            .offset(x: x, y: CGFloat(task.id) * (rowH + gap))
                    }
                }
            }
        }
        .padding()
        .widgetBackground()
    }
}

// MARK: - Large View

struct GanttLargeView: View {
    let entry: GanttPreviewEntry

    var body: some View {
        let tasks = entry.tasks
        let tStart = entry.timelineStart
        let tEnd = entry.timelineEnd
        let span = tEnd.timeIntervalSince(tStart)

        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack {
                Label("Project Schedule", systemImage: "calendar.day.timeline.left")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(WidgetColors.primaryText)
                Spacer()
                Text("SteelSync")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.secondaryText)
            }

            Divider().overlay(WidgetColors.divider)

            // Project legend
            let uniqueProjects = Dictionary(grouping: tasks, by: \.projectColorIndex)
                .sorted { $0.key < $1.key }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(uniqueProjects.prefix(6), id: \.key) { colorIdx, taskGroup in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(projectPalette[colorIdx % projectPalette.count])
                                .frame(width: 6, height: 6)
                            Text(taskGroup.first?.projectName ?? "")
                                .font(.system(size: 9))
                                .foregroundColor(WidgetColors.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
            }

            // Timeline
            GeometryReader { geo in
                let w = geo.size.width
                let rowH: CGFloat = 16
                let gap: CGFloat = 3
                let todayX = span > 0 ? w * CGFloat(Date().timeIntervalSince(tStart) / span) : 0

                ZStack(alignment: .topLeading) {
                    // Today column
                    if todayX > 0 && todayX < w {
                        Rectangle().fill(Color.gray.opacity(0.2))
                            .frame(width: max(w * 0.02, 3), height: geo.size.height)
                            .offset(x: todayX)
                        // "Today" label
                        Text("Today")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.gray)
                            .offset(x: todayX - 10, y: -2)
                    }

                    ForEach(tasks.prefix(10)) { task in
                        let x = span > 0 ? w * CGFloat(task.start.timeIntervalSince(tStart) / span) : 0
                        let barW = span > 0 ? max(w * CGFloat(task.end.timeIntervalSince(task.start) / span), 8) : 20
                        let color = projectPalette[task.projectColorIndex % projectPalette.count]

                        ZStack(alignment: .leading) {
                            // Background
                            RoundedRectangle(cornerRadius: 3)
                                .fill(color.opacity(0.7))
                                .frame(width: barW, height: rowH)

                            // Progress fill
                            if task.progress > 0 {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color)
                                    .frame(width: barW * task.progress, height: rowH)
                            }

                            // Label
                            if barW > 50 {
                                HStack(spacing: 2) {
                                    Circle().fill(color).frame(width: 4, height: 4)
                                    Text(task.name)
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                }
                                .padding(.leading, 3)
                                .frame(width: barW, alignment: .leading)
                            }
                        }
                        .offset(x: x, y: CGFloat(task.id) * (rowH + gap) + 10)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .widgetBackground()
    }
}

// MARK: - Widget

struct GanttPreviewWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: GanttPreviewEntry
    var body: some View {
        switch family {
        case .systemMedium: GanttMediumView(entry: entry)
        case .systemLarge: GanttLargeView(entry: entry)
        default: GanttMediumView(entry: entry)
        }
    }
}

struct GanttPreviewWidget: Widget {
    let kind = "SteelSyncGanttWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GanttPreviewTimelineProvider()) { entry in
            GanttPreviewWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Schedule Preview")
        .description("Visual timeline of active Gantt tasks across projects.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
