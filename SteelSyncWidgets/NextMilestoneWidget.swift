import WidgetKit
import SwiftUI

// MARK: - Next Milestone Widget (Glass spec §6.6)
//
// Reads `nextMilestoneTitle` / `nextMilestoneDate` / `nextMilestoneProject`
// from the shared App Group suite — published by both WidgetBridge and
// WidgetDataPublisher. Calls out the next .milestone GanttTask across
// every project so you can see what's about to drop.

struct NextMilestoneTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextMilestoneEntry {
        NextMilestoneEntry(date: Date(), isPlaceholder: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (NextMilestoneEntry) -> Void) {
        completion(NextMilestoneEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<NextMilestoneEntry>) -> Void) {
        // Days-until rolls over at midnight; refresh on the next boundary.
        let cal = Calendar.current
        let nextMidnight = cal.nextDate(after: Date(),
                                        matching: DateComponents(hour: 0),
                                        matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [NextMilestoneEntry(date: Date())], policy: .after(nextMidnight)))
    }
}

struct NextMilestoneEntry: TimelineEntry {
    let date: Date
    var isPlaceholder = false
    var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.jrfv.SteelSync.shared") }

    var title: String {
        if isPlaceholder { return "Crane Mobilization" }
        return defaults?.string(forKey: "nextMilestoneTitle") ?? ""
    }
    var project: String {
        if isPlaceholder { return "Ascalon Medical Plaza" }
        return defaults?.string(forKey: "nextMilestoneProject") ?? ""
    }
    var milestoneDate: Date? {
        if isPlaceholder { return Date().addingTimeInterval(3 * 86400) }
        let ts = defaults?.double(forKey: "nextMilestoneDate") ?? 0
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }
    var daysUntil: Int {
        guard let d = milestoneDate else { return 0 }
        let cal = Calendar.current
        return cal.dateComponents([.day],
                                  from: cal.startOfDay(for: date),
                                  to: cal.startOfDay(for: d)).day ?? 0
    }
}

// MARK: - Small

struct NextMilestoneSmallView: View {
    let entry: NextMilestoneEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Next Milestone", systemImage: "flag.fill")
                .font(.caption2.weight(.bold))
                .foregroundColor(WidgetColors.orange)

            Spacer()

            if entry.title.isEmpty {
                Text("No upcoming milestone")
                    .font(.caption)
                    .foregroundColor(WidgetColors.secondaryText)
            } else {
                Text(entry.title)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(WidgetColors.primaryText)
                    .lineLimit(2)
                Text(daysLabel)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(urgencyColor)
                    .monospacedDigit()
                Text(entry.project)
                    .font(.caption2)
                    .foregroundColor(WidgetColors.secondaryText)
                    .lineLimit(1)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .widgetURL(URL(string: "steelsync://today"))
        .widgetBackground()
    }

    private var daysLabel: String {
        let n = entry.daysUntil
        if n == 0 { return "Today" }
        if n == 1 { return "Tomorrow" }
        if n < 0 { return "\(-n)d ago" }
        return "In \(n)d"
    }

    private var urgencyColor: Color {
        let n = entry.daysUntil
        if n <= 0 { return WidgetColors.red }
        if n <= 3 { return WidgetColors.orange }
        return WidgetColors.primaryText
    }
}

// MARK: - Medium

struct NextMilestoneMediumView: View {
    let entry: NextMilestoneEntry

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Next Milestone", systemImage: "flag.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(WidgetColors.orange)
                Spacer()
                if entry.title.isEmpty {
                    Text("No upcoming milestone")
                        .font(.callout)
                        .foregroundColor(WidgetColors.secondaryText)
                } else {
                    Text(entry.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(WidgetColors.primaryText)
                        .lineLimit(2)
                    Text(entry.project)
                        .font(.caption)
                        .foregroundColor(WidgetColors.secondaryText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.horizontal, 10)

            VStack(alignment: .center, spacing: 4) {
                Spacer()
                if entry.title.isEmpty {
                    Text("—")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.tertiaryText)
                } else {
                    Text(daysNumberLabel)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(urgencyColor)
                        .monospacedDigit()
                    Text(daysCaption)
                        .font(.caption2)
                        .foregroundColor(WidgetColors.secondaryText)
                    if let d = entry.milestoneDate {
                        Text(formatShortDate(d))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(WidgetColors.tertiaryText)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding()
        .widgetURL(URL(string: "steelsync://today"))
        .widgetBackground()
    }

    private var daysNumberLabel: String {
        let n = entry.daysUntil
        if n == 0 { return "0" }
        if n < 0 { return "\(-n)" }
        return "\(n)"
    }

    private var daysCaption: String {
        let n = entry.daysUntil
        if n == 0 { return "Today" }
        if n == 1 { return "day to go" }
        if n < 0 { return "\(-n == 1 ? "day" : "days") ago" }
        return "days to go"
    }

    private var urgencyColor: Color {
        let n = entry.daysUntil
        if n <= 0 { return WidgetColors.red }
        if n <= 3 { return WidgetColors.orange }
        return WidgetColors.primaryText
    }
}

// MARK: - Widget

struct NextMilestoneWidget: Widget {
    let kind = "NextMilestoneWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NextMilestoneTimelineProvider()) { entry in
            NextMilestoneWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next Milestone")
        .description("Days-until countdown for the closest upcoming Gantt milestone — red within 3 days, danger past due.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct NextMilestoneWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: NextMilestoneEntry

    var body: some View {
        switch family {
        case .systemSmall:  NextMilestoneSmallView(entry: entry)
        case .systemMedium: NextMilestoneMediumView(entry: entry)
        default:            NextMilestoneSmallView(entry: entry)
        }
    }
}
