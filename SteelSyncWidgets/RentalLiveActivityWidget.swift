import WidgetKit
import SwiftUI
#if os(iOS)
import ActivityKit

// MARK: - Equipment Rental Live Activity (Glass spec §6.6)
//
// ActivityKit Live Activity for an active equipment rental. The main app
// starts the activity when a rental begins (or on demand from the Rentals UI)
// and ends it when the rental is closed. iOS only.
//
// Lock-screen view: equipment name + project + big Day-N + days-to-cutoff +
// "Since" date.
// Dynamic Island: compact day count (trailing) + box icon (leading); the
// expanded layout mirrors the lock-screen rows; minimal shows just the day.

@available(iOS 16.2, *)
struct RentalLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RentalActivityAttributes.self) { context in
            // Lock screen / banner.
            RentalLiveLockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.4))
            .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.equipmentName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "shippingbox.fill")
                            .foregroundColor(.orange)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Day \(context.state.daysOnRent)")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(cutoffNear(context.state) ? .red : .orange)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.projectName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.status)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        cutoffPill(context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "shippingbox.fill")
                    .foregroundColor(.orange)
            } compactTrailing: {
                Text("\(context.state.daysOnRent)d")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundColor(cutoffNear(context.state) ? .red : .orange)
            } minimal: {
                Text("\(context.state.daysOnRent)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(cutoffNear(context.state) ? .red : .orange)
            }
            .widgetURL(URL(string: "steelsync://equipment"))
        }
    }

    private func cutoffNear(_ state: RentalActivityAttributes.ContentState) -> Bool {
        state.nextCutoffDays >= 0 && state.nextCutoffDays <= 3
    }

    @ViewBuilder
    private func cutoffPill(_ state: RentalActivityAttributes.ContentState) -> some View {
        let near = state.nextCutoffDays >= 0 && state.nextCutoffDays <= 3
        let label: String = {
            if state.nextCutoffDays < 0 { return "Past cutoff" }
            if state.nextCutoffDays == 0 { return "Cutoff today" }
            return "Cutoff in \(state.nextCutoffDays)d"
        }()
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill((near ? Color.red : Color.orange).opacity(0.18)))
            .foregroundColor(near ? .red : .orange)
    }
}

// MARK: - Lock-screen view

@available(iOS 16.2, *)
struct RentalLiveLockScreenView: View {
    let attributes: RentalActivityAttributes
    let state: RentalActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.18))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.orange)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(attributes.equipmentName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(attributes.projectName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text("Since \(formatShortDate(attributes.startDate))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Day \(state.daysOnRent)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(cutoffNear ? .red : .orange)
                cutoffLabel
            }
        }
    }

    private var cutoffNear: Bool {
        state.nextCutoffDays >= 0 && state.nextCutoffDays <= 3
    }

    @ViewBuilder
    private var cutoffLabel: some View {
        if state.nextCutoffDays < 0 {
            Text("Past 28-day cutoff")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.red)
        } else if state.nextCutoffDays == 0 {
            Text("Cutoff today")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.red)
        } else {
            Text("Cutoff in \(state.nextCutoffDays)d")
                .font(.caption2)
                .foregroundColor(cutoffNear ? .red : .secondary)
        }
    }

    private func formatShortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}

#endif
