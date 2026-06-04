import SwiftUI

/// Read-only "who's on the clock right now" screen — the in-app counterpart to
/// the Crew On the Clock widget, with per-member elapsed time. Reflects the live
/// `ClockInSession`: members still on the clock show a running timer; members who
/// clocked out early show their frozen worked duration.
struct PhoneClockedInCrewView: View {
    @EnvironmentObject var dataStore: DataStore

    var body: some View {
        ScrollView {
            if let session = dataStore.activeClockInSession {
                VStack(spacing: AppTheme.Spacing.md) {
                    header(session)
                    crewList(session)
                }
                .padding(AppTheme.Spacing.md)
            } else {
                emptyState
            }
        }
        .navigationTitle("On the Clock")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ session: ClockInSession) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Circle().fill(Color.green).frame(width: 12, height: 12)
                Text("\(session.stillOnClockIDs.count) on the clock")
                    .font(AppTheme.Typography.title2)
                Spacer()
            }
            HStack {
                Image(systemName: "building.2.fill").foregroundColor(AppTheme.primaryOrange)
                Text(session.projectName).font(AppTheme.Typography.headline)
                Spacer()
            }
            HStack {
                Image(systemName: "person.fill.checkmark").foregroundColor(.secondary)
                Text("Foreman \(session.foremanName)")
                    .font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Text(session.clockInTime, style: .timer)
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundColor(AppTheme.primaryOrange)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(Color.green.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    private func crewList(_ session: ClockInSession) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            ForEach(crew(session), id: \.id) { e in
                let id = e.id.uuidString
                let on = session.isStillOnClock(id)
                let start = session.startTime(for: id)
                HStack(spacing: 10) {
                    Image(systemName: on ? "person.fill" : "person.fill.xmark")
                        .foregroundColor(on ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(e.fullName).font(.callout)
                        Text(e.employeeType.rawValue).font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    if on {
                        Text(start, style: .timer)
                            .font(.callout.monospacedDigit())
                            .foregroundColor(.green)
                    } else if let end = session.memberClockOutTimes[id] {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(durationText(end.timeIntervalSince(start)))
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .foregroundColor(.secondary)
                            Text("out \(end, style: .time)")
                                .font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    private func crew(_ session: ClockInSession) -> [Employee] {
        let set = Set(session.crewMemberIDs)
        return dataStore.employees.filter { set.contains($0.id.uuidString) }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No crew clocked in").font(.headline)
            Text("Clock a crew in from the Time Clock and they'll show up here with live time.")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.horizontal, 24)
    }
}
