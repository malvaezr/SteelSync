import WidgetKit
import SwiftUI

// MARK: - Today Attention Widget
//
// One-glance "what needs me today" widget. Sums overdue todos, overdue RFIs,
// and overdue Gantt tasks into a single attention count, and shows the
// breakdown on the medium size. Reads `todayAttentionCount`,
// `overdueTodos`, `overdueRFIs` from the shared App Group suite —
// already published by both WidgetBridge and WidgetDataPublisher.

struct TodayAttentionTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayAttentionEntry {
        TodayAttentionEntry(date: Date(), isPlaceholder: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (TodayAttentionEntry) -> Void) {
        completion(TodayAttentionEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayAttentionEntry>) -> Void) {
        let entry = TodayAttentionEntry(date: Date())
        // Hourly refresh — overdue counts roll over at day boundaries and
        // when the user marks things done.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct TodayAttentionEntry: TimelineEntry {
    let date: Date
    var isPlaceholder = false
    var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.jrfv.SteelSync.shared") }

    var total: Int { isPlaceholder ? 7 : (defaults?.integer(forKey: "todayAttentionCount") ?? 0) }
    var overdueTodos: Int { isPlaceholder ? 3 : (defaults?.integer(forKey: "overdueTodos") ?? 0) }
    var overdueRFIs: Int { isPlaceholder ? 2 : (defaults?.integer(forKey: "overdueRFIs") ?? 0) }
    /// Inferred remainder = overdue Gantt tasks. Computed (not stored).
    var overdueGantt: Int { max(0, total - overdueTodos - overdueRFIs) }
}

// MARK: - Small

struct TodayAttentionSmallView: View {
    let entry: TodayAttentionEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Needs You", systemImage: "exclamationmark.bubble.fill")
                .font(.caption2.weight(.bold))
                .foregroundColor(entry.total > 0 ? WidgetColors.red : WidgetColors.green)

            Spacer()

            Text("\(entry.total)")
                .font(.system(size: 50, weight: .bold, design: .rounded))
                .foregroundColor(entry.total > 0 ? WidgetColors.orange : WidgetColors.green)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(entry.total == 1 ? "open item" : "open items")
                .font(.caption2)
                .foregroundColor(WidgetColors.secondaryText)

            Spacer()

            if entry.total == 0 {
                Text("All clear")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.tertiaryText)
            } else {
                Text("Tap to triage")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .widgetURL(URL(string: "steelsync://today"))
        .widgetBackground()
    }
}

// MARK: - Medium

struct TodayAttentionMediumView: View {
    let entry: TodayAttentionEntry

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Needs You", systemImage: "exclamationmark.bubble.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(entry.total > 0 ? WidgetColors.red : WidgetColors.green)
                Spacer()
                Text("\(entry.total)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundColor(entry.total > 0 ? WidgetColors.orange : WidgetColors.green)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(entry.total == 1 ? "open item" : "open items")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 8) {
                breakdownRow(label: "Overdue tasks", value: entry.overdueTodos, color: WidgetColors.orange)
                breakdownRow(label: "Overdue RFIs", value: entry.overdueRFIs, color: WidgetColors.bidBlue)
                breakdownRow(label: "Overdue schedule", value: entry.overdueGantt, color: WidgetColors.red)
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .widgetURL(URL(string: "steelsync://today"))
        .widgetBackground()
    }

    @ViewBuilder
    private func breakdownRow(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .frame(width: 26, alignment: .trailing)
            Text(label)
                .font(.caption2)
                .foregroundColor(WidgetColors.secondaryText)
                .lineLimit(1)
        }
    }
}

// MARK: - Widget

struct TodayAttentionWidget: Widget {
    let kind = "TodayAttentionWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayAttentionTimelineProvider()) { entry in
            TodayAttentionWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Needs You Today")
        .description("Overdue tasks, RFIs, and schedule items rolled up into one count.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct TodayAttentionWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: TodayAttentionEntry

    var body: some View {
        switch family {
        case .systemSmall:  TodayAttentionSmallView(entry: entry)
        case .systemMedium: TodayAttentionMediumView(entry: entry)
        default:            TodayAttentionSmallView(entry: entry)
        }
    }
}
