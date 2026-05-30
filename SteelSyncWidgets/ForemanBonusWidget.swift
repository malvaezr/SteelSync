import WidgetKit
import SwiftUI

// MARK: - Foreman Bonus Widget
//
// Year-to-date foreman bonus pool snapshot. Reads the `bonusPoolYTD` value
// the main app writes via `DataStore.bonusPoolYTD()` (revenue basis, 2 %
// multiplier default). Tweak the multiplier in Reports → Bonuses for
// what-if analysis; the widget always shows this default snapshot.

struct ForemanBonusTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> ForemanBonusEntry {
        ForemanBonusEntry(date: Date(), isPlaceholder: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (ForemanBonusEntry) -> Void) {
        completion(ForemanBonusEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ForemanBonusEntry>) -> Void) {
        let entry = ForemanBonusEntry(date: Date())
        // Pool only meaningfully shifts when tasks flip to Completed — hourly
        // refresh is plenty (timelines also re-evaluate on app writes).
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600))))
    }
}

struct ForemanBonusEntry: TimelineEntry {
    let date: Date
    var isPlaceholder = false
    var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.jrfv.SteelSync.shared") }

    var pool: Double { isPlaceholder ? 42_300 : (defaults?.double(forKey: "bonusPoolYTD") ?? 0) }
    var foremenCount: Int { isPlaceholder ? 4 : (defaults?.integer(forKey: "foremenCount") ?? 0) }
    var year: Int { Calendar.current.component(.year, from: date) }
}

// MARK: - Small

struct ForemanBonusSmallView: View {
    let entry: ForemanBonusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Foreman Bonus", systemImage: "person.fill.checkmark")
                .font(.caption2.weight(.bold))
                .foregroundColor(WidgetColors.orange)

            Spacer()

            Text(formatCurrencyCompact(entry.pool))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundColor(WidgetColors.orange)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("Pool · YTD")
                .font(.caption2)
                .foregroundColor(WidgetColors.secondaryText)

            Spacer()

            Text("\(entry.foremenCount) foremen · \(String(entry.year))")
                .font(.caption2)
                .foregroundColor(WidgetColors.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .widgetBackground()
    }
}

// MARK: - Medium

struct ForemanBonusMediumView: View {
    let entry: ForemanBonusEntry

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Foreman Bonus", systemImage: "person.fill.checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(WidgetColors.orange)
                Spacer()
                Text(formatCurrency(entry.pool))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.orange)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("Estimated pool · \(String(entry.year))")
                    .font(.caption)
                    .foregroundColor(WidgetColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 4) {
                Spacer()
                Text("\(entry.foremenCount)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.primaryText)
                Text("foremen on file")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.secondaryText)
                Spacer()
                Text("Revenue × 2 % default —")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.tertiaryText)
                Text("tweak in Reports.")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.tertiaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .widgetBackground()
    }
}

// MARK: - Widget

struct ForemanBonusWidget: Widget {
    let kind = "ForemanBonusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ForemanBonusTimelineProvider()) { entry in
            switch entry {
            default:
                ForemanBonusWidgetEntryView(entry: entry)
            }
        }
        .configurationDisplayName("Foreman Bonus YTD")
        .description("Year-to-date estimated bonus pool from the Gantt schedule. Tap to open Reports → Bonuses.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct ForemanBonusWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: ForemanBonusEntry

    var body: some View {
        switch family {
        case .systemSmall:  ForemanBonusSmallView(entry: entry)
        case .systemMedium: ForemanBonusMediumView(entry: entry)
        default:            ForemanBonusSmallView(entry: entry)
        }
    }
}
