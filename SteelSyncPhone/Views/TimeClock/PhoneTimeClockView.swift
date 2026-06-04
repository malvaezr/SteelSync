import SwiftUI

/// Foreman-clocks-crew time clock. The device represents one foreman (set
/// once via `@AppStorage("deviceForemanID")`); the foreman picks a project,
/// checks off which crew members are starting the shift, taps Clock In,
/// works, then taps Clock Out which materializes one `TimesheetEntry` per
/// crew member with the elapsed hours dropped into the right day-of-week
/// column. State lives on `DataStore.activeClockInSession` (persisted to
/// UserDefaults), so quitting the app mid-shift doesn't lose the session.
/// On iOS 16.2+ a `Crew Clocked-In` Live Activity rides alongside.
struct PhoneTimeClockView: View {
    @EnvironmentObject var dataStore: DataStore

    @AppStorage("deviceForemanID") private var deviceForemanID: String = ""

    @State private var pickedProjectID: String?
    @State private var pickedCrewIDs: Set<String> = []
    @State private var editingEntry: TimesheetEntry?
    @ObservedObject private var notifications = NotificationService.shared

    private var deviceForeman: Employee? {
        guard !deviceForemanID.isEmpty else { return nil }
        return dataStore.employees.first { $0.id.uuidString == deviceForemanID }
    }

    private var activeForemen: [Employee] {
        dataStore.employees.filter { $0.isForeman && $0.isActive }
    }

    private var selectedProject: Project? {
        guard let pid = pickedProjectID else { return nil }
        return dataStore.activeProjects.first { $0.id.recordName == pid }
    }

    private var pickedCrew: [Employee] {
        dataStore.activeEmployees.filter { pickedCrewIDs.contains($0.id.uuidString) }
    }

    private var canClockIn: Bool {
        deviceForeman != nil && selectedProject != nil && !pickedCrew.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.md) {
                    if deviceForeman == nil {
                        foremanSetupCard
                    } else if let session = dataStore.activeClockInSession {
                        activeShiftBanner(session)
                        activeCrewList(session)
                        addLateArrivalControl(session)
                        lunchCard(session)
                        clockOutButton
                    } else {
                        projectPicker
                        crewPicker
                        clockInButton
                    }
                    todaySection
                    weekSummary
                    if deviceForeman != nil {
                        remindersSection
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.lg)
            }
            .navigationTitle("Time Clock")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if deviceForeman != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Foreman", selection: $deviceForemanID) {
                                ForEach(activeForemen, id: \.id) { f in
                                    Text(f.fullName).tag(f.id.uuidString)
                                }
                            }
                        } label: {
                            Image(systemName: "person.crop.circle")
                        }
                    }
                }
            }
            .sheet(item: $editingEntry) { entry in
                EditTimesheetEntrySheet(entry: entry)
                    .environmentObject(dataStore)
            }
        }
    }

    // MARK: - Foreman setup (first launch on a new device)

    private var foremanSetupCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundColor(AppTheme.primaryOrange)
                Text("Set Up Time Clock")
                    .font(AppTheme.Typography.headline)
                Spacer()
            }
            Text("Pick which foreman this device belongs to. Clock-ins from this phone will be recorded under their name and clocked crew will be billed to the project they pick.")
                .font(.caption)
                .foregroundColor(.secondary)
            if activeForemen.isEmpty {
                Text("⚠ No foremen on file. Add an Employee in Crew & Timesheets with the Foreman role first.")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Menu {
                    ForEach(activeForemen, id: \.id) { f in
                        Button(f.fullName) { deviceForemanID = f.id.uuidString }
                    }
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle")
                        Text("Pick foreman")
                            .fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .padding()
                    .background(AppTheme.primaryOrange.opacity(0.18))
                    .foregroundColor(AppTheme.primaryOrange)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    // MARK: - Active shift (currently clocked in)

    private func activeShiftBanner(_ session: ClockInSession) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Circle().fill(Color.green).frame(width: 12, height: 12)
                Text("Crew Clocked In")
                    .font(AppTheme.Typography.title2)
                Spacer()
            }
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundColor(AppTheme.primaryOrange)
                Text(session.projectName)
                    .font(AppTheme.Typography.headline)
                Spacer()
            }
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                Text("Since \(session.clockInTime, style: .time)")
                    .font(AppTheme.Typography.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                // Live timer — SwiftUI auto-refreshes Text(_:style:.timer).
                Text(session.clockInTime, style: .timer)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundColor(AppTheme.primaryOrange)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(Color.green.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    private func activeCrewList(_ session: ClockInSession) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("On the clock")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(session.stillOnClockIDs.count) of \(session.crewMemberIDs.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            ForEach(activeCrew(session), id: \.id) { e in
                crewMemberRow(e, session: session)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    /// One crew row with that member's own live timer (or frozen worked time if
    /// they clocked out early) and a per-member Clock Out / Resume control.
    @ViewBuilder
    private func crewMemberRow(_ e: Employee, session: ClockInSession) -> some View {
        let id = e.id.uuidString
        let onClock = session.isStillOnClock(id)
        let start = session.startTime(for: id)
        HStack(spacing: 10) {
            Image(systemName: e.isForeman ? "person.fill.checkmark" : "person.fill")
                .foregroundColor(onClock ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.fullName).font(.callout)
                HStack(spacing: 6) {
                    if onClock {
                        Image(systemName: "clock").font(.caption2).foregroundColor(.secondary)
                        Text(start, style: .timer)
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                    } else if let end = session.memberClockOutTimes[id] {
                        Image(systemName: "checkmark.circle").font(.caption2).foregroundColor(.secondary)
                        Text("Out \(end, style: .time) · \(durationText(end.timeIntervalSince(start)))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            Spacer()
            if onClock {
                Button { dataStore.clockOutMemberEarly(id) } label: {
                    Text("Clock Out")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.red.opacity(0.12)))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button { dataStore.resumeCrewMember(id) } label: {
                    Text("Resume")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(AppTheme.primaryOrange.opacity(0.14)))
                        .foregroundColor(AppTheme.primaryOrange)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 3)
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return "\(total / 3600)h \((total % 3600) / 60)m"
    }

    /// Late-arrival picker: anyone active and not already on the shift can be
    /// clocked in mid-shift (their clock-in is now, not the shift open).
    @ViewBuilder
    private func addLateArrivalControl(_ session: ClockInSession) -> some View {
        let present = Set(session.crewMemberIDs)
        let available = dataStore.activeEmployees.filter { !present.contains($0.id.uuidString) }
        if !available.isEmpty {
            Menu {
                ForEach(available, id: \.id) { e in
                    Button {
                        dataStore.addCrewMemberMidShift(e)
                    } label: {
                        Label(e.fullName, systemImage: "person.fill.badge.plus")
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.fill.badge.plus")
                    Text("Add Late Arrival")
                        .font(.callout.weight(.semibold))
                    Spacer()
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: AppTheme.Radius.lg).fill(AppTheme.secondaryBackground))
                .overlay(RoundedRectangle(cornerRadius: AppTheme.Radius.lg).stroke(AppTheme.primaryOrange.opacity(0.4), lineWidth: 1))
                .foregroundColor(AppTheme.primaryOrange)
            }
        }
    }

    /// Per-shift lunch control: a "skip today" override plus a one-line summary
    /// of the auto-deduction policy.
    private func lunchCard(_ session: ClockInSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { session.skipLunchDeduction },
                set: { dataStore.setSkipLunch($0) }
            )) {
                Label("Skip lunch deduction today", systemImage: "fork.knife")
            }
            .tint(AppTheme.primaryOrange)
            Text(session.skipLunchDeduction
                 ? "No lunch will be deducted on this shift."
                 : "A \(session.lunchMinutes)-min lunch auto-deducts per person on days of 6 h or more.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    private func activeCrew(_ session: ClockInSession) -> [Employee] {
        let set = Set(session.crewMemberIDs)
        return dataStore.employees.filter { set.contains($0.id.uuidString) }
    }

    private func rateFor(_ e: Employee) -> String {
        let v = NSDecimalNumber(decimal: e.defaultHourlyRate).doubleValue
        return String(format: "$%.2f/hr", v)
    }

    private var clockOutButton: some View {
        Button {
            dataStore.endCrewClockIn()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "stop.fill")
                Text("Clock Out Crew")
                    .font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.red)
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        }
    }

    // MARK: - Not clocked in: pickers + clock-in button

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Project")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Picker("Select Project", selection: $pickedProjectID) {
                Text("Select a project").tag(nil as String?)
                ForEach(dataStore.activeProjects, id: \.id) { p in
                    Text(p.title).tag(p.id.recordName as String?)
                }
            }
            .pickerStyle(.menu)
            .tint(AppTheme.primaryOrange)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    private var crewPicker: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("Crew")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(pickedCrewIDs.count) selected")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                Button {
                    if pickedCrewIDs.count == dataStore.activeEmployees.count {
                        pickedCrewIDs.removeAll()
                    } else {
                        pickedCrewIDs = Set(dataStore.activeEmployees.map { $0.id.uuidString })
                    }
                } label: {
                    Text(pickedCrewIDs.count == dataStore.activeEmployees.count ? "Clear" : "All")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(AppTheme.primaryOrange)
                }
            }
            if dataStore.activeEmployees.isEmpty {
                Text("No active employees on file.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(dataStore.activeEmployees, id: \.id) { e in
                    crewRow(e)
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    @ViewBuilder
    private func crewRow(_ e: Employee) -> some View {
        let isPicked = pickedCrewIDs.contains(e.id.uuidString)
        Button {
            if isPicked { pickedCrewIDs.remove(e.id.uuidString) }
            else { pickedCrewIDs.insert(e.id.uuidString) }
        } label: {
            HStack {
                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isPicked ? AppTheme.primaryOrange : .secondary)
                Text(e.fullName)
                    .foregroundColor(.primary)
                if e.isForeman {
                    Text("Foreman")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(AppTheme.primaryOrange.opacity(0.18)))
                        .foregroundColor(AppTheme.primaryOrange)
                }
                Spacer()
                Text(rateFor(e))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var clockInButton: some View {
        Button {
            guard let foreman = deviceForeman,
                  let project = selectedProject,
                  !pickedCrew.isEmpty else { return }
            dataStore.startCrewClockIn(foreman: foreman, project: project, crew: pickedCrew)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                Text("Clock In Crew")
                    .font(.title3.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(canClockIn ? Color.green : Color.gray.opacity(0.4))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
        }
        .disabled(!canClockIn)
    }

    // MARK: - Today + week summary

    /// Timesheet entries with non-zero hours in today's day-of-week column.
    private var todayEntries: [TimesheetEntry] {
        let cal = Calendar.current
        let weekStart = TimesheetEntry.currentWeekStart()
        let dayOfWeek = cal.component(.weekday, from: Date())
        return dataStore.timesheetEntries(for: weekStart).filter { entry in
            switch dayOfWeek {
            case 2: return entry.mondayHours > 0
            case 3: return entry.tuesdayHours > 0
            case 4: return entry.wednesdayHours > 0
            case 5: return entry.thursdayHours > 0
            case 6: return entry.fridayHours > 0
            case 7: return entry.saturdayHours > 0
            case 1: return entry.sundayHours > 0
            default: return false
            }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text("Today's Entries")
                    .font(AppTheme.Typography.title3)
                Spacer()
                if !todayEntries.isEmpty {
                    Text("Tap to edit")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            if todayEntries.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No entries today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppTheme.Spacing.md)
            } else {
                ForEach(todayEntries, id: \.id) { entry in
                    Button { editingEntry = entry } label: {
                        TodayEntryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    private var weekTotalHours: Decimal {
        let weekStart = TimesheetEntry.currentWeekStart()
        return dataStore.timesheetEntries(for: weekStart).reduce(Decimal.zero) { $0 + $1.totalHours }
    }

    private var weekSummary: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundColor(AppTheme.primaryOrange)
            Text("This Week")
                .font(AppTheme.Typography.headline)
            Spacer()
            Text("\(NSDecimalNumber(decimal: weekTotalHours).doubleValue, specifier: "%.1f") hrs")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.primaryOrange)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(AppTheme.primaryOrange)
                Text("Reminders")
                    .font(AppTheme.Typography.headline)
                Spacer()
            }

            Toggle("Remind me to clock in", isOn: $notifications.clockInReminderEnabled)
                .tint(AppTheme.primaryOrange)
                .onChange(of: notifications.clockInReminderEnabled) { _, _ in
                    notifications.scheduleClockInReminder()
                }
            if notifications.clockInReminderEnabled {
                DatePicker("Time", selection: clockInTimeBinding, displayedComponents: .hourAndMinute)
                    .font(.subheadline)
            }

            Divider()

            Toggle("Remind me to clock out", isOn: $notifications.clockOutReminderEnabled)
                .tint(AppTheme.primaryOrange)
                .onChange(of: notifications.clockOutReminderEnabled) { _, _ in
                    notifications.rescheduleTimeClockReminders(from: dataStore)
                }
            if notifications.clockOutReminderEnabled {
                Stepper("After \(notifications.clockOutReminderHours) hours",
                        value: $notifications.clockOutReminderHours, in: 4...16)
                    .font(.subheadline)
                    .onChange(of: notifications.clockOutReminderHours) { _, _ in
                        notifications.rescheduleTimeClockReminders(from: dataStore)
                    }
            }

            if notifications.permissionStatus == .denied {
                Text("Notifications are off in Settings — reminders won't appear until you turn them on.")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    /// Bridges the clock-in reminder hour/minute prefs to a `Date` for the
    /// time picker; reschedules the daily reminder on change.
    private var clockInTimeBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = notifications.clockInReminderHour
                c.minute = notifications.clockInReminderMinute
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                notifications.clockInReminderHour = c.hour ?? 7
                notifications.clockInReminderMinute = c.minute ?? 0
                notifications.scheduleClockInReminder()
            }
        )
    }
}

// MARK: - Today entry row

private struct TodayEntryRow: View {
    let entry: TimesheetEntry
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.employeeName.isEmpty ? "Unnamed" : entry.employeeName)
                    .font(.callout)
                Text(entry.projectName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(String(format: "%.2fh", NSDecimalNumber(decimal: entry.totalHours).doubleValue))
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundColor(AppTheme.primaryOrange)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
