import WidgetKit
import SwiftUI

// MARK: - Crew Clocked-In Widget
//
// Who is on the clock right now and on which project, with live elapsed time.
// Reads the snapshot the app writes via `ClockInWidgetData` (keys below). The
// `Text(_:style:.timer)` labels tick locally, so we don't push per-second
// updates — the app reloads timelines on every clock change.

struct CrewClockedInEntry: TimelineEntry {
    let date: Date
    var isPlaceholder = false
    private var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.jrfv.SteelSync.shared") }

    var count: Int { isPlaceholder ? 3 : (defaults?.integer(forKey: "clockedInCount") ?? 0) }
    var project: String { isPlaceholder ? "Ascalon Medical Plaza" : (defaults?.string(forKey: "clockedInProject") ?? "") }
    var foreman: String { isPlaceholder ? "Mike Reyes" : (defaults?.string(forKey: "clockedInForeman") ?? "") }
    var since: Date? {
        if isPlaceholder { return Date().addingTimeInterval(-3 * 3600) }
        let t = defaults?.double(forKey: "clockedInSince") ?? 0
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    var names: [String] {
        isPlaceholder ? ["Mike Reyes", "Joe Smith", "Elis Lara"]
                      : (defaults?.stringArray(forKey: "clockedInNames") ?? [])
    }
    var memberSince: [Date] {
        if isPlaceholder {
            return [Date().addingTimeInterval(-3 * 3600),
                    Date().addingTimeInterval(-2.5 * 3600),
                    Date().addingTimeInterval(-1 * 3600)]
        }
        return (defaults?.array(forKey: "clockedInMemberSince") as? [Double] ?? [])
            .map { Date(timeIntervalSince1970: $0) }
    }
    var isActive: Bool { count > 0 && since != nil }
}

struct CrewClockedInProvider: TimelineProvider {
    func placeholder(in context: Context) -> CrewClockedInEntry {
        CrewClockedInEntry(date: Date(), isPlaceholder: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (CrewClockedInEntry) -> Void) {
        completion(CrewClockedInEntry(date: Date(), isPlaceholder: context.isPreview))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CrewClockedInEntry>) -> Void) {
        let entry = CrewClockedInEntry(date: Date())
        // Timer labels tick themselves; a 15-min backstop refresh is plenty
        // (the app also reloads timelines on every clock-in / out / member change).
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(900))))
    }
}

// MARK: - Small

struct CrewClockedInSmallView: View {
    let entry: CrewClockedInEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("On the Clock", systemImage: "person.3.fill")
                .font(.caption2.weight(.bold))
                .foregroundColor(WidgetColors.green)
            Spacer()
            if entry.isActive {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Circle().fill(WidgetColors.green).frame(width: 9, height: 9)
                    Text("\(entry.count)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(WidgetColors.primaryText)
                }
                Text(entry.count == 1 ? "crew member" : "crew members")
                    .font(.caption2).foregroundColor(WidgetColors.secondaryText)
                Spacer()
                Text(entry.project)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(WidgetColors.orange).lineLimit(1)
                if let since = entry.since {
                    Text(since, style: .timer)
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(WidgetColors.secondaryText).lineLimit(1)
                }
            } else {
                Spacer()
                Text("No crew clocked in")
                    .font(.caption).foregroundColor(WidgetColors.secondaryText)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .widgetBackground()
    }
}

// MARK: - Medium

struct CrewClockedInMediumView: View {
    let entry: CrewClockedInEntry
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Label("On the Clock", systemImage: "person.3.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(WidgetColors.green)
                Spacer()
                if entry.isActive {
                    HStack(spacing: 6) {
                        Circle().fill(WidgetColors.green).frame(width: 9, height: 9)
                        Text("\(entry.count)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(WidgetColors.primaryText)
                    }
                    Text(entry.project)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(WidgetColors.orange).lineLimit(1)
                    if let since = entry.since {
                        Text(since, style: .timer)
                            .font(.callout.monospacedDigit().weight(.semibold))
                            .foregroundColor(WidgetColors.secondaryText)
                    }
                    if !entry.foreman.isEmpty {
                        Text("Foreman \(entry.foreman)")
                            .font(.caption2).foregroundColor(WidgetColors.tertiaryText).lineLimit(1)
                    }
                } else {
                    Spacer()
                    Text("No crew clocked in")
                        .font(.callout).foregroundColor(WidgetColors.secondaryText)
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if entry.isActive && !entry.names.isEmpty {
                Divider().padding(.horizontal, 10)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.names.prefix(5), id: \.self) { n in
                        HStack(spacing: 5) {
                            Circle().fill(WidgetColors.green).frame(width: 5, height: 5)
                            Text(n).font(.caption2).foregroundColor(WidgetColors.primaryText).lineLimit(1)
                        }
                    }
                    if entry.names.count > 5 {
                        Text("+\(entry.names.count - 5) more")
                            .font(.caption2).foregroundColor(WidgetColors.tertiaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .widgetBackground()
    }
}

// MARK: - Large

struct CrewClockedInLargeView: View {
    let entry: CrewClockedInEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("On the Clock", systemImage: "person.3.fill")
                    .font(.caption.weight(.bold))
                    .foregroundColor(WidgetColors.green)
                Spacer()
                if entry.isActive, let since = entry.since {
                    Text(since, style: .timer)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(WidgetColors.secondaryText)
                }
            }
            if entry.isActive {
                Text(entry.project)
                    .font(.headline).foregroundColor(WidgetColors.orange).lineLimit(1)
                Text("Foreman \(entry.foreman) · \(entry.count) on the clock")
                    .font(.caption2).foregroundColor(WidgetColors.secondaryText)
                Divider()
                ForEach(Array(entry.names.enumerated()), id: \.offset) { i, n in
                    HStack(spacing: 8) {
                        Circle().fill(WidgetColors.green).frame(width: 7, height: 7)
                        Text(n).font(.caption).foregroundColor(WidgetColors.primaryText).lineLimit(1)
                        Spacer()
                        if i < entry.memberSince.count {
                            Text(entry.memberSince[i], style: .timer)
                                .font(.caption.monospacedDigit())
                                .foregroundColor(WidgetColors.secondaryText)
                        }
                    }
                }
                Spacer(minLength: 0)
            } else {
                Spacer()
                Text("No crew clocked in")
                    .font(.callout).foregroundColor(WidgetColors.secondaryText)
                    .frame(maxWidth: .infinity)
                Text("Clock a crew in from the Time Clock to see them here.")
                    .font(.caption2).foregroundColor(WidgetColors.tertiaryText)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .widgetBackground()
    }
}

// MARK: - Widget

struct CrewClockedInWidget: Widget {
    let kind = "CrewClockedInWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CrewClockedInProvider()) { entry in
            CrewClockedInEntryView(entry: entry)
        }
        .configurationDisplayName("Crew On the Clock")
        .description("Who is clocked in right now and on which project, with live time. Tap for per-person detail.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct CrewClockedInEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: CrewClockedInEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:  CrewClockedInSmallView(entry: entry)
            case .systemMedium: CrewClockedInMediumView(entry: entry)
            case .systemLarge:  CrewClockedInLargeView(entry: entry)
            default:            CrewClockedInSmallView(entry: entry)
            }
        }
        .widgetURL(URL(string: "steelsync://clockedin"))
    }
}
