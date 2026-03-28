import WidgetKit
import SwiftUI

// MARK: - Bid Tracker Widget

struct BidPipelineTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BidPipelineEntry { BidPipelineEntry(date: Date(), isPlaceholder: true) }
    func getSnapshot(in context: Context, completion: @escaping (BidPipelineEntry) -> Void) { completion(BidPipelineEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BidPipelineEntry>) -> Void) {
        let entry = BidPipelineEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct BidPipelineEntry: TimelineEntry {
    let date: Date
    var isPlaceholder = false
    var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.jrfv.SteelSync.shared") }

    var bidsDueThisWeek: Int { isPlaceholder ? 3 : (defaults?.integer(forKey: "bidsDueThisWeekCount") ?? 0) }
    var pendingBids: Int { isPlaceholder ? 6 : (defaults?.integer(forKey: "pendingBidCount") ?? 0) }
    var submittedBids: Int { isPlaceholder ? 10 : (defaults?.integer(forKey: "submittedBidCount") ?? 0) }
    var winRate: Double { isPlaceholder ? 67 : (defaults?.double(forKey: "winRate") ?? 0) }
    var pipelineValue: Double { isPlaceholder ? 1_250_000 : (defaults?.double(forKey: "pipelineValue") ?? 0) }

    struct BidDue: Identifiable {
        let id: Int; let name: String; let client: String; let amount: Double; let dueDate: Date
    }

    var bidsDue: [BidDue] {
        if isPlaceholder {
            return [
                BidDue(id: 0, name: "Metro Tower Phase 2", client: "Metro Construction", amount: 620_000, dueDate: Date().addingTimeInterval(86400 * 2)),
                BidDue(id: 1, name: "Airport Hangar", client: "Acme Developers", amount: 480_000, dueDate: Date().addingTimeInterval(86400 * 5))
            ]
        }
        let names = defaults?.stringArray(forKey: "bidsDueNames") ?? []
        let clients = defaults?.stringArray(forKey: "bidsDueClients") ?? []
        let amounts = defaults?.array(forKey: "bidsDueAmounts") as? [Double] ?? []
        let dates = defaults?.array(forKey: "bidsDueDates") as? [Double] ?? []
        return names.enumerated().map { i, name in
            BidDue(id: i, name: name,
                   client: i < clients.count ? clients[i] : "",
                   amount: i < amounts.count ? amounts[i] : 0,
                   dueDate: i < dates.count ? Date(timeIntervalSince1970: dates[i]) : Date())
        }
    }
}

// MARK: - Small: Bids Due + Win Rate

struct BidSmallView: View {
    let entry: BidPipelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Bids", systemImage: "doc.text.fill")
                .font(.caption2.weight(.bold))
                .foregroundColor(WidgetColors.bidBlue)

            Spacer()

            if entry.bidsDueThisWeek > 0 {
                Text("\(entry.bidsDueThisWeek)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.orange)
                Text("Due This Week")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.secondaryText)
            } else {
                Text("0")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(WidgetColors.green)
                Text("Due This Week")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.secondaryText)
            }

            Spacer()

            HStack(spacing: 8) {
                VStack(spacing: 1) {
                    Text(String(format: "%.0f%%", entry.winRate))
                        .font(.caption.weight(.bold))
                        .foregroundColor(WidgetColors.green)
                    Text("Win").font(.system(size: 8)).foregroundColor(WidgetColors.secondaryText)
                }
                VStack(spacing: 1) {
                    Text("\(entry.pendingBids)")
                        .font(.caption.weight(.bold))
                        .foregroundColor(WidgetColors.bidTeal)
                    Text("Open").font(.system(size: 8)).foregroundColor(WidgetColors.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .widgetBackground()
    }
}

// MARK: - Medium: Due This Week + Next Bid Details

struct BidMediumView: View {
    let entry: BidPipelineEntry

    var body: some View {
        HStack(spacing: 12) {
            // Left — Key numbers
            VStack(alignment: .leading, spacing: 4) {
                Label("Bids", systemImage: "doc.text.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(WidgetColors.bidBlue)
                Spacer()

                VStack(alignment: .leading, spacing: 6) {
                    BidCountRow(icon: "calendar.badge.exclamationmark", count: entry.bidsDueThisWeek, label: "Due This Week",
                                color: entry.bidsDueThisWeek > 0 ? WidgetColors.orange : WidgetColors.green)
                    BidCountRow(icon: "clock.fill", count: entry.pendingBids, label: "Open", color: WidgetColors.bidTeal)
                    BidCountRow(icon: "paperplane.fill", count: entry.submittedBids, label: "Submitted", color: WidgetColors.bidBlue)
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill").font(.system(size: 10)).foregroundColor(WidgetColors.green)
                        Text(String(format: "%.0f%%", entry.winRate)).font(.caption.weight(.bold)).foregroundColor(WidgetColors.green)
                        Text("Win Rate").font(.system(size: 10)).foregroundColor(WidgetColors.secondaryText)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(WidgetColors.divider).frame(width: 1).padding(.vertical, 4)

            // Right — Next bid due
            VStack(alignment: .leading, spacing: 4) {
                Text("Coming Up")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(WidgetColors.secondaryText)

                if entry.bidsDue.isEmpty {
                    Spacer()
                    Text("No bids due soon")
                        .font(.caption)
                        .foregroundColor(WidgetColors.green)
                    Spacer()
                } else {
                    ForEach(entry.bidsDue.prefix(2)) { bid in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bid.name)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(WidgetColors.primaryText)
                                .lineLimit(1)
                            HStack(spacing: 4) {
                                Text(formatCurrencyCompact(bid.amount))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(WidgetColors.bidBlue)
                                Text("•")
                                    .foregroundColor(WidgetColors.secondaryText)
                                Text(formatRelativeDate(bid.dueDate))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(isDueSoon(bid.dueDate) ? WidgetColors.orange : WidgetColors.bidTeal)
                            }
                        }
                        .padding(.vertical, 2)
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

// MARK: - Large: Full Bid Tracker

struct BidLargeView: View {
    let entry: BidPipelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Bid Tracker", systemImage: "doc.text.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(WidgetColors.primaryText)
                Spacer()
                if entry.bidsDueThisWeek > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "calendar.badge.exclamationmark").font(.caption2)
                        Text("\(entry.bidsDueThisWeek) due this week").font(.caption2.weight(.bold))
                    }
                    .foregroundColor(WidgetColors.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(WidgetColors.orange.opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            Divider().overlay(WidgetColors.divider)

            // Stats
            HStack(spacing: 0) {
                BidStatBlock2(value: formatCurrencyCompact(entry.pipelineValue), label: "Pipeline", color: WidgetColors.bidBlue)
                Spacer()
                BidStatBlock2(value: String(format: "%.0f%%", entry.winRate), label: "Win Rate", color: WidgetColors.green)
                Spacer()
                BidStatBlock2(value: "\(entry.pendingBids)", label: "Open", color: WidgetColors.bidTeal)
                Spacer()
                BidStatBlock2(value: "\(entry.submittedBids)", label: "Submitted", color: WidgetColors.bidBlue)
            }

            Divider().overlay(WidgetColors.divider)

            Text("Due Soon")
                .font(.caption.weight(.semibold))
                .foregroundColor(WidgetColors.secondaryText)

            if entry.bidsDue.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill").font(.title3).foregroundColor(WidgetColors.green)
                        Text("No upcoming deadlines").font(.caption).foregroundColor(WidgetColors.green)
                    }
                    .padding(.vertical, 8)
                    Spacer()
                }
            } else {
                ForEach(entry.bidsDue.prefix(4)) { bid in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bid.name).font(.caption.weight(.medium)).foregroundColor(WidgetColors.primaryText).lineLimit(1)
                            Text(bid.client).font(.system(size: 10)).foregroundColor(WidgetColors.secondaryText).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(formatCurrencyCompact(bid.amount)).font(.caption.weight(.semibold)).foregroundColor(WidgetColors.bidBlue)
                            Text(formatRelativeDate(bid.dueDate)).font(.system(size: 10, weight: .medium))
                                .foregroundColor(isDueSoon(bid.dueDate) ? WidgetColors.orange : WidgetColors.secondaryText)
                        }
                    }
                    .padding(.vertical, 2)
                    if bid.id != entry.bidsDue.prefix(4).last?.id {
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

private struct BidCountRow: View {
    let icon: String; let count: Int; let label: String; let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundColor(color)
            Text("\(count)").font(.caption.weight(.bold)).foregroundColor(color)
            Text(label).font(.system(size: 10)).foregroundColor(WidgetColors.secondaryText)
        }
    }
}

private struct BidStatBlock2: View {
    let value: String; let label: String; let color: Color
    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.bold)).foregroundColor(color).minimumScaleFactor(0.7).lineLimit(1)
            Text(label).font(.system(size: 9)).foregroundColor(WidgetColors.secondaryText)
        }
    }
}

// MARK: - Widget

struct BidPipelineWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: BidPipelineEntry
    var body: some View {
        switch family {
        case .systemSmall: BidSmallView(entry: entry)
        case .systemMedium: BidMediumView(entry: entry)
        case .systemLarge: BidLargeView(entry: entry)
        default: BidSmallView(entry: entry)
        }
    }
}

struct BidPipelineWidget: Widget {
    let kind = "SteelSyncBidPipelineWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BidPipelineTimelineProvider()) { entry in
            BidPipelineWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Bid Tracker")
        .description("Upcoming bid deadlines, win rate, and pipeline status.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
