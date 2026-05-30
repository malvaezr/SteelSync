import WidgetKit
import SwiftUI
#if os(iOS)
import ActivityKit

// MARK: - Crew Clocked-In Live Activity (Glass spec §6.6)
//
// Lock-screen banner + Dynamic Island for an active foreman-clocks-crew
// shift. Started and ended by `DataStore.startCrewClockIn(...)` /
// `endCrewClockIn()`. Elapsed time is rendered locally from
// `clockInTime` (the system live-updates `Text(date:style:.timer)` so we
// don't have to push the activity every second).

@available(iOS 16.2, *)
struct CrewClockInLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CrewClockInActivityAttributes.self) { context in
            // Lock screen / banner
            CrewClockInLockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.4))
            .activitySystemActionForegroundColor(.green)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.projectName)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "person.3.fill")
                            .foregroundColor(.green)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.clockInTime, style: .timer)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.green)
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.state.crewCount) on the clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Foreman: \(context.attributes.foremanName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        if !context.state.notes.isEmpty {
                            Text(context.state.notes)
                                .font(.caption2)
                                .foregroundColor(.orange)
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "person.3.fill")
                    .foregroundColor(.green)
            } compactTrailing: {
                Text(context.attributes.clockInTime, style: .timer)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundColor(.green)
                    .frame(maxWidth: 70)
            } minimal: {
                Image(systemName: "person.3.fill")
                    .foregroundColor(.green)
            }
            .widgetURL(URL(string: "steelsync://timeclock"))
        }
    }
}

// MARK: - Lock-screen view

@available(iOS 16.2, *)
struct CrewClockInLockScreenView: View {
    let attributes: CrewClockInActivityAttributes
    let state: CrewClockInActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.green.opacity(0.18))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.green)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(attributes.projectName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("\(state.crewCount) clocked in · Foreman \(attributes.foremanName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if !state.notes.isEmpty {
                    Text(state.notes)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(attributes.clockInTime, style: .timer)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.green)
                    .multilineTextAlignment(.trailing)
                Text("on the clock")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#endif
