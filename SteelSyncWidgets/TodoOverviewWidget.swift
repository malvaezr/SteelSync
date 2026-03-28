import WidgetKit
import SwiftUI

// MARK: - Task Urgency Widget

struct TodoTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodoEntry { TodoEntry(date: Date(), isPlaceholder: true) }
    func getSnapshot(in context: Context, completion: @escaping (TodoEntry) -> Void) { completion(TodoEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodoEntry>) -> Void) {
        let entry = TodoEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
    }
}

struct TodoEntry: TimelineEntry {
    let date: Date
    var isPlaceholder = false
    var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.jrfv.SteelSync.shared") }

    var overdueCount: Int { isPlaceholder ? 3 : (defaults?.integer(forKey: "overdueCount") ?? 0) }
    var dueTodayCount: Int { isPlaceholder ? 2 : (defaults?.integer(forKey: "dueTodayCount") ?? 0) }
    var activeCount: Int { isPlaceholder ? 8 : (defaults?.integer(forKey: "activeTaskCount") ?? 0) }
    var completedCount: Int { isPlaceholder ? 12 : (defaults?.integer(forKey: "completedTaskCount") ?? 0) }

    var urgentTasks: [(title: String, isOverdue: Bool, priority: Int)] {
        if isPlaceholder {
            return [("Submit Metro Tower bid", true, 3), ("Follow up with Acme", true, 2), ("Order steel beams", false, 1)]
        }
        let titles = defaults?.stringArray(forKey: "urgentTaskTitles") ?? []
        let overdue = defaults?.array(forKey: "urgentTaskOverdue") as? [Bool] ?? []
        let priorities = defaults?.array(forKey: "urgentTaskPriorities") as? [Int] ?? []
        return titles.enumerated().map { i, title in
            (title, i < overdue.count ? overdue[i] : false, i < priorities.count ? priorities[i] : 0)
        }
    }
}

// MARK: - Small: Overdue Alert

struct TodoSmallView: View {
    let entry: TodoEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Tasks", systemImage: "checklist")
                .font(.caption2.weight(.bold))
                .foregroundColor(WidgetColors.orange)

            Spacer()

            if entry.overdueCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundColor(WidgetColors.red)
                    Text("\(entry.overdueCount)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.red)
                }
                Text("Overdue")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.red.opacity(0.8))
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title)
                    .foregroundColor(WidgetColors.green)
                Text("All Clear")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(WidgetColors.green)
            }

            Spacer()

            HStack(spacing: 8) {
                MiniTaskStat(value: "\(entry.dueTodayCount)", label: "Today", color: .yellow)
                MiniTaskStat(value: "\(entry.activeCount)", label: "Open", color: WidgetColors.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .widgetBackground()
    }
}

// MARK: - Medium: Overdue + Urgent Tasks List

struct TodoMediumView: View {
    let entry: TodoEntry

    var body: some View {
        HStack(spacing: 12) {
            // Left — Counts
            VStack(alignment: .leading, spacing: 4) {
                Label("Tasks", systemImage: "checklist")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(WidgetColors.orange)
                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    CountRow(icon: "exclamationmark.triangle.fill", count: entry.overdueCount, label: "Overdue",
                             color: entry.overdueCount > 0 ? WidgetColors.red : WidgetColors.secondaryText)
                    CountRow(icon: "clock.fill", count: entry.dueTodayCount, label: "Due Today",
                             color: entry.dueTodayCount > 0 ? .yellow : WidgetColors.secondaryText)
                    CountRow(icon: "circle", count: entry.activeCount, label: "Open", color: WidgetColors.orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(WidgetColors.divider).frame(width: 1).padding(.vertical, 4)

            // Right — Urgent tasks
            VStack(alignment: .leading, spacing: 4) {
                Text("Urgent")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(WidgetColors.secondaryText)

                if entry.urgentTasks.isEmpty {
                    Spacer()
                    Text("Nothing urgent")
                        .font(.caption)
                        .foregroundColor(WidgetColors.green)
                    Spacer()
                } else {
                    ForEach(Array(entry.urgentTasks.prefix(3).enumerated()), id: \.offset) { _, task in
                        TaskItemRow(title: task.title, isOverdue: task.isOverdue, priority: task.priority)
                    }
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .widgetBackground()
    }
}

// MARK: - Large: Full Task Dashboard

struct TodoLargeView: View {
    let entry: TodoEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Task Dashboard", systemImage: "checklist")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(WidgetColors.primaryText)
                Spacer()
                if entry.overdueCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                        Text("\(entry.overdueCount) overdue")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundColor(WidgetColors.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(WidgetColors.red.opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            Divider().overlay(WidgetColors.divider)

            // Stats bar
            HStack(spacing: 0) {
                TaskStatBlock(count: entry.overdueCount, label: "Overdue", color: WidgetColors.red, icon: "exclamationmark.triangle.fill")
                Spacer()
                TaskStatBlock(count: entry.dueTodayCount, label: "Today", color: .yellow, icon: "clock.fill")
                Spacer()
                TaskStatBlock(count: entry.activeCount, label: "Open", color: WidgetColors.orange, icon: "circle")
                Spacer()
                TaskStatBlock(count: entry.completedCount, label: "Done", color: WidgetColors.green, icon: "checkmark.circle.fill")
            }

            Divider().overlay(WidgetColors.divider)

            Text("Needs Attention")
                .font(.caption.weight(.semibold))
                .foregroundColor(WidgetColors.secondaryText)

            if entry.urgentTasks.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title3)
                            .foregroundColor(WidgetColors.green)
                        Text("All caught up!")
                            .font(.caption)
                            .foregroundColor(WidgetColors.green)
                    }
                    .padding(.vertical, 8)
                    Spacer()
                }
            } else {
                ForEach(Array(entry.urgentTasks.prefix(5).enumerated()), id: \.offset) { i, task in
                    TaskItemRow(title: task.title, isOverdue: task.isOverdue, priority: task.priority)
                    if i < min(entry.urgentTasks.count - 1, 4) {
                        Divider().overlay(WidgetColors.divider.opacity(0.5))
                    }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .widgetBackground()
    }
}

// MARK: - Helpers

private struct MiniTaskStat: View {
    let value: String; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 1) {
            Text(value).font(.caption.weight(.bold)).foregroundColor(color)
            Text(label).font(.system(size: 8)).foregroundColor(WidgetColors.secondaryText)
        }
    }
}

private struct CountRow: View {
    let icon: String; let count: Int; let label: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(color)
            Text("\(count)").font(.caption.weight(.bold)).foregroundColor(color)
            Text(label).font(.system(size: 10)).foregroundColor(WidgetColors.secondaryText)
        }
    }
}

private struct TaskItemRow: View {
    let title: String; let isOverdue: Bool; let priority: Int
    private var priorityColor: Color {
        switch priority { case 3: return WidgetColors.red; case 2: return WidgetColors.orange; case 1: return .blue; default: return WidgetColors.secondaryText }
    }
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(priorityColor).frame(width: 6, height: 6)
            Text(title).font(.caption).foregroundColor(isOverdue ? WidgetColors.red : WidgetColors.primaryText).lineLimit(1)
            Spacer()
            if isOverdue {
                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 10)).foregroundColor(WidgetColors.red)
            }
        }
        .padding(.vertical, 1)
    }
}

private struct TaskStatBlock: View {
    let count: Int; let label: String; let color: Color; let icon: String
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 8))
                Text("\(count)").font(.subheadline.weight(.bold))
            }.foregroundColor(color)
            Text(label).font(.system(size: 9)).foregroundColor(WidgetColors.secondaryText)
        }
    }
}

// MARK: - Widget

struct TodoOverviewWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: TodoEntry
    var body: some View {
        switch family {
        case .systemSmall: TodoSmallView(entry: entry)
        case .systemMedium: TodoMediumView(entry: entry)
        case .systemLarge: TodoLargeView(entry: entry)
        default: TodoSmallView(entry: entry)
        }
    }
}

struct TodoOverviewWidget: Widget {
    let kind = "SteelSyncTodoWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodoTimelineProvider()) { entry in
            TodoOverviewWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Task Urgency")
        .description("Overdue tasks, deadlines, and urgent items at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
