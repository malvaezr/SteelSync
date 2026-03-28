import WidgetKit
import SwiftUI

// MARK: - PM Performance Widget

struct SummaryTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry { SummaryEntry(date: Date(), isPlaceholder: true) }
    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) { completion(SummaryEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let entry = SummaryEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct SummaryEntry: TimelineEntry {
    let date: Date
    var isPlaceholder = false
    var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.jrfv.SteelSync.shared") }

    var winRate: Double { isPlaceholder ? 67 : (defaults?.double(forKey: "winRate") ?? 0) }
    var avgMargin: Double { isPlaceholder ? 23.5 : (defaults?.double(forKey: "avgMargin") ?? 0) }
    var activeProjects: Int { isPlaceholder ? 10 : (defaults?.integer(forKey: "activeProjects") ?? 0) }
    var atRiskCount: Int { isPlaceholder ? 2 : (defaults?.integer(forKey: "atRiskCount") ?? 0) }
    var overdueCount: Int { isPlaceholder ? 3 : (defaults?.integer(forKey: "overdueCount") ?? 0) }
    var completedProjects: Int { isPlaceholder ? 5 : (defaults?.integer(forKey: "completedProjects") ?? 0) }
    var atRiskNames: [String] { isPlaceholder ? ["UTSA East Gates", "Alice Stadium"] : (defaults?.stringArray(forKey: "atRiskNames") ?? []) }
}

// MARK: - Small: Win Rate + At Risk

struct SummarySmallView: View {
    let entry: SummaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Performance", systemImage: "chart.bar.fill")
                .font(.caption2.weight(.bold))
                .foregroundColor(WidgetColors.orange)

            Spacer()

            Text(String(format: "%.0f%%", entry.winRate))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(entry.winRate >= 50 ? WidgetColors.green : WidgetColors.orange)
            Text("Win Rate")
                .font(.caption2)
                .foregroundColor(WidgetColors.secondaryText)

            Spacer()

            HStack(spacing: 8) {
                MiniStat(value: "\(entry.activeProjects)", label: "Active", color: WidgetColors.orange)
                if entry.atRiskCount > 0 {
                    MiniStat(value: "\(entry.atRiskCount)", label: "At Risk", color: WidgetColors.red)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .widgetBackground()
    }
}

// MARK: - Medium: Win Rate + Margin + Active + Overdue

struct SummaryMediumView: View {
    let entry: SummaryEntry

    var body: some View {
        HStack(spacing: 0) {
            // Left — Win Rate
            VStack(alignment: .leading, spacing: 4) {
                Label("Performance", systemImage: "chart.bar.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(WidgetColors.orange)
                Spacer()
                Text(String(format: "%.0f%%", entry.winRate))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(entry.winRate >= 50 ? WidgetColors.green : WidgetColors.orange)
                Text("Win Rate")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right — Key stats grid
            VStack(alignment: .trailing, spacing: 8) {
                Spacer()
                KPIRow(icon: "percent", label: "Avg Margin", value: String(format: "%.1f%%", entry.avgMargin),
                       color: entry.avgMargin >= 15 ? WidgetColors.green : WidgetColors.orange)
                KPIRow(icon: "building.2.fill", label: "Active", value: "\(entry.activeProjects)",
                       color: WidgetColors.bidBlue)
                if entry.overdueCount > 0 {
                    KPIRow(icon: "exclamationmark.triangle.fill", label: "Overdue Tasks", value: "\(entry.overdueCount)",
                           color: WidgetColors.red)
                }
                if entry.atRiskCount > 0 {
                    KPIRow(icon: "clock.badge.exclamationmark", label: "At Risk", value: "\(entry.atRiskCount)",
                           color: WidgetColors.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
        .widgetBackground()
    }
}

// MARK: - Large: Full PM Scorecard

struct SummaryLargeView: View {
    let entry: SummaryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("PM Scorecard", systemImage: "chart.bar.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(WidgetColors.primaryText)
                Spacer()
                Text("SteelSync")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.secondaryText)
            }

            Divider().overlay(WidgetColors.divider)

            // KPI Row
            HStack(spacing: 0) {
                ScoreBlock(value: String(format: "%.0f%%", entry.winRate), label: "Win Rate",
                           color: entry.winRate >= 50 ? WidgetColors.green : WidgetColors.orange)
                Spacer()
                ScoreBlock(value: String(format: "%.1f%%", entry.avgMargin), label: "Avg Margin",
                           color: entry.avgMargin >= 15 ? WidgetColors.green : WidgetColors.orange)
                Spacer()
                ScoreBlock(value: "\(entry.activeProjects)", label: "Active", color: WidgetColors.bidBlue)
                Spacer()
                ScoreBlock(value: "\(entry.completedProjects)", label: "Completed", color: WidgetColors.green)
            }

            Divider().overlay(WidgetColors.divider)

            // Alerts section
            if entry.atRiskCount > 0 || entry.overdueCount > 0 {
                Text("Attention Needed")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(WidgetColors.red)

                if entry.overdueCount > 0 {
                    AlertRow(icon: "exclamationmark.triangle.fill", text: "\(entry.overdueCount) overdue task\(entry.overdueCount == 1 ? "" : "s")", color: WidgetColors.red)
                }

                if entry.atRiskCount > 0 {
                    AlertRow(icon: "clock.badge.exclamationmark", text: "\(entry.atRiskCount) project\(entry.atRiskCount == 1 ? "" : "s") at risk", color: WidgetColors.orange)
                    ForEach(entry.atRiskNames.prefix(2), id: \.self) { name in
                        HStack(spacing: 4) {
                            Text("•")
                                .foregroundColor(WidgetColors.orange)
                            Text(name)
                                .font(.caption)
                                .foregroundColor(WidgetColors.primaryText)
                                .lineLimit(1)
                        }
                        .padding(.leading, 20)
                    }
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(WidgetColors.green)
                    Text("All projects on track")
                        .font(.caption.weight(.medium))
                        .foregroundColor(WidgetColors.green)
                }
                .padding(.vertical, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .widgetBackground()
    }
}

// MARK: - Helpers

private struct MiniStat: View {
    let value: String; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 1) {
            Text(value).font(.caption.weight(.bold)).foregroundColor(color)
            Text(label).font(.system(size: 8)).foregroundColor(WidgetColors.secondaryText)
        }
    }
}

private struct KPIRow: View {
    let icon: String; let label: String; let value: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10)).foregroundColor(WidgetColors.secondaryText)
            Text(value).font(.caption.weight(.bold)).foregroundColor(color)
        }
    }
}

private struct ScoreBlock: View {
    let value: String; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.bold)).foregroundColor(color)
            Text(label).font(.system(size: 9)).foregroundColor(WidgetColors.secondaryText)
        }
    }
}

private struct AlertRow: View {
    let icon: String; let text: String; let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.caption2).foregroundColor(color)
            Text(text).font(.caption).foregroundColor(WidgetColors.primaryText)
            Spacer()
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Widget

struct SummaryWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: SummaryEntry
    var body: some View {
        switch family {
        case .systemSmall: SummarySmallView(entry: entry)
        case .systemMedium: SummaryMediumView(entry: entry)
        case .systemLarge: SummaryLargeView(entry: entry)
        default: SummarySmallView(entry: entry)
        }
    }
}

struct SummaryWidget: Widget {
    let kind = "SteelSyncSummaryWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SummaryTimelineProvider()) { entry in
            SummaryWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("PM Performance")
        .description("Win rate, margins, and project health at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
