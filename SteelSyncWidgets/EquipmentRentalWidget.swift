import WidgetKit
import SwiftUI

// MARK: - Equipment Rental Countdown Widget (Glass spec §6.6)
//
// Shows the longest-on-rent active rentals so the user can spot anything
// burning daily/weekly/4-week rate while sitting idle. Reads `rentalNames`,
// `rentalDays`, `rentalProjectNames`, and `activeRentalsCount` from the
// shared App Group suite — published by both WidgetBridge and
// WidgetDataPublisher when the app writes data.

struct EquipmentRentalTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> EquipmentRentalEntry {
        EquipmentRentalEntry(date: Date(), isPlaceholder: true)
    }
    func getSnapshot(in context: Context, completion: @escaping (EquipmentRentalEntry) -> Void) {
        completion(EquipmentRentalEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<EquipmentRentalEntry>) -> Void) {
        // Day-counter rolls over daily — refresh at the next midnight.
        let cal = Calendar.current
        let nextMidnight = cal.nextDate(after: Date(), matching: DateComponents(hour: 0), matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)
        let entry = EquipmentRentalEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

struct EquipmentRentalEntry: TimelineEntry {
    let date: Date
    var isPlaceholder = false
    var defaults: UserDefaults? { UserDefaults(suiteName: "group.com.jrfv.SteelSync.shared") }

    var names: [String] {
        if isPlaceholder { return ["10k Telehandler", "Boom Lift 60'", "Welder Bottle"] }
        return defaults?.stringArray(forKey: "rentalNames") ?? []
    }
    var days: [Int] {
        if isPlaceholder { return [51, 28, 14] }
        return (defaults?.array(forKey: "rentalDays") as? [Int]) ?? []
    }
    var projectNames: [String] {
        if isPlaceholder { return ["Ascalon Medical Plaza", "Alice Stadium", "UTSA East Gates"] }
        return defaults?.stringArray(forKey: "rentalProjectNames") ?? []
    }
    var activeCount: Int {
        isPlaceholder ? 7 : (defaults?.integer(forKey: "activeRentalsCount") ?? 0)
    }

    /// Day count at which the next rate tier kicks in — 28 days = end of the
    /// 4-week cycle (the typical "cutoff" the field cares about). Highlights
    /// the rental in orange when within 3 days of crossing a 28-day boundary.
    func isApproachingCutoff(_ d: Int) -> Bool {
        let into = d % 28
        return into >= 25 || into == 0
    }
}

// MARK: - Small

struct EquipmentRentalSmallView: View {
    let entry: EquipmentRentalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Rentals", systemImage: "shippingbox.fill")
                .font(.caption2.weight(.bold))
                .foregroundColor(WidgetColors.orange)

            Spacer()

            if let first = entry.names.first {
                Text(first)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(WidgetColors.primaryText)
                    .lineLimit(2)
                if let d = entry.days.first {
                    Text("Day \(d)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(entry.isApproachingCutoff(d) ? WidgetColors.red : WidgetColors.orange)
                }
                if let project = entry.projectNames.first {
                    Text(project)
                        .font(.caption2)
                        .foregroundColor(WidgetColors.secondaryText)
                        .lineLimit(1)
                }
            } else {
                Text("No active rentals")
                    .font(.caption)
                    .foregroundColor(WidgetColors.secondaryText)
            }

            Spacer()

            Text("\(entry.activeCount) active total")
                .font(.caption2)
                .foregroundColor(WidgetColors.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .widgetURL(URL(string: "steelsync://equipment"))
        .widgetBackground()
    }
}

// MARK: - Medium

struct EquipmentRentalMediumView: View {
    let entry: EquipmentRentalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Equipment on Rent", systemImage: "shippingbox.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(WidgetColors.orange)
                Spacer()
                Text("\(entry.activeCount) active")
                    .font(.caption2)
                    .foregroundColor(WidgetColors.tertiaryText)
            }

            if entry.names.isEmpty {
                Spacer()
                Text("No active rentals")
                    .font(.callout)
                    .foregroundColor(WidgetColors.secondaryText)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<min(3, entry.names.count), id: \.self) { i in
                        rentalRow(
                            name: entry.names[i],
                            day: i < entry.days.count ? entry.days[i] : 0,
                            project: i < entry.projectNames.count ? entry.projectNames[i] : ""
                        )
                        if i < min(3, entry.names.count) - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
        .padding()
        .widgetURL(URL(string: "steelsync://equipment"))
        .widgetBackground()
    }

    @ViewBuilder
    private func rentalRow(name: String, day: Int, project: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(WidgetColors.primaryText)
                    .lineLimit(1)
                if !project.isEmpty {
                    Text(project)
                        .font(.caption2)
                        .foregroundColor(WidgetColors.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("Day \(day)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(entry.isApproachingCutoff(day) ? WidgetColors.red : WidgetColors.orange)
                .monospacedDigit()
        }
    }
}

// MARK: - Widget

struct EquipmentRentalWidget: Widget {
    let kind = "EquipmentRentalWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EquipmentRentalTimelineProvider()) { entry in
            EquipmentRentalWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Equipment on Rent")
        .description("Longest-on-rent items + their day counts. Red when approaching the next 28-day billing cutoff.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct EquipmentRentalWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: EquipmentRentalEntry

    var body: some View {
        switch family {
        case .systemSmall:  EquipmentRentalSmallView(entry: entry)
        case .systemMedium: EquipmentRentalMediumView(entry: entry)
        default:            EquipmentRentalSmallView(entry: entry)
        }
    }
}
