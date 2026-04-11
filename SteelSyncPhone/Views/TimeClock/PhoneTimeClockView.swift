import SwiftUI

struct PhoneTimeClockView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var isClockedIn = false
    @State private var clockInTime: Date? = nil
    @State private var selectedProjectID: String? = nil
    @State private var elapsedSeconds: TimeInterval = 0
    @State private var timer: Timer? = nil

    private var todayEntries: [(id: UUID, projectName: String, clockIn: Date, clockOut: Date, hours: Decimal)] {
        // Pull today's timesheet entries from DataStore
        let cal = Calendar.current
        return dataStore.timesheetEntries
            .filter { cal.isDateInToday($0.weekStartDate) || $0.totalHours > 0 }
            .filter { !$0.projectName.isEmpty }
            .map { (id: $0.id, projectName: $0.projectName, clockIn: $0.weekStartDate, clockOut: Date(), hours: $0.totalHours) }
    }

    private var weekTotalHours: Decimal {
        let weekStart = TimesheetEntry.currentWeekStart()
        return dataStore.timesheetEntries(for: weekStart).reduce(Decimal.zero) { $0 + $1.totalHours }
    }

    private var selectedProject: Project? {
        guard let pid = selectedProjectID else { return nil }
        return dataStore.activeProjects.first { $0.id.recordName == pid }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.Spacing.md) {
                    statusBanner
                    projectPicker
                    clockButton
                    todaySection
                    weekSummary
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.lg)
            }
            .navigationTitle("Time Clock")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            HStack {
                Circle()
                    .fill(isClockedIn ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                Text(isClockedIn ? "Clocked In" : "Not Clocked In")
                    .font(AppTheme.Typography.title2)
                    
                Spacer()
            }

            if isClockedIn, let project = selectedProject {
                HStack {
                    Image(systemName: "building.2.fill")
                        .foregroundColor(AppTheme.primaryOrange)
                    Text(project.title)
                        .font(AppTheme.Typography.headline)
                        
                    Spacer()
                }

                HStack {
                    if let clockIn = clockInTime {
                        Image(systemName: "clock")
                            .foregroundColor(AppTheme.secondaryText)
                        Text("Since \(clockIn, style: .time)")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    Spacer()
                    Text(formattedElapsed)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .foregroundColor(AppTheme.primaryOrange)
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(isClockedIn ? Color.green.opacity(0.1) : AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    // MARK: - Project Picker

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Project")
                .font(AppTheme.Typography.caption)
                .foregroundColor(AppTheme.secondaryText)

            Picker("Select Project", selection: $selectedProjectID) {
                Text("Select a project...")
                    .tag(nil as String?)
                ForEach(dataStore.activeProjects, id: \.id) { project in
                    Text(project.title)
                        .tag(project.id.recordName as String?)
                }
            }
            .pickerStyle(.menu)
            .tint(AppTheme.primaryOrange)
            .disabled(isClockedIn)
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    // MARK: - Clock Button

    private var clockButton: some View {
        Button(action: toggleClock) {
            ClockButton(isClockedIn: isClockedIn)
        }
        .disabled(!isClockedIn && selectedProjectID == nil)
        .opacity(!isClockedIn && selectedProjectID == nil ? 0.5 : 1.0)
        .padding(.vertical, AppTheme.Spacing.sm)
    }

    // MARK: - Today's Entries

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            Text("Today's Entries")
                .font(AppTheme.Typography.title3)
                

            if todayEntries.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: AppTheme.Spacing.sm) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 32))
                            .foregroundColor(AppTheme.tertiaryText)
                        Text("No entries today")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundColor(AppTheme.tertiaryText)
                    }
                    .padding(.vertical, AppTheme.Spacing.lg)
                    Spacer()
                }
            } else {
                ForEach(todayEntries, id: \.id) { entry in
                    TimeEntryRow(
                        projectName: entry.projectName,
                        clockIn: entry.clockIn,
                        clockOut: entry.clockOut,
                        hours: entry.hours
                    )
                }
            }
        }
        .padding(AppTheme.Spacing.md)
        .background(AppTheme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
    }

    // MARK: - Week Summary

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

    // MARK: - Helpers

    private var formattedElapsed: String {
        let hours = Int(elapsedSeconds) / 3600
        let minutes = (Int(elapsedSeconds) % 3600) / 60
        let seconds = Int(elapsedSeconds) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func toggleClock() {
        if isClockedIn {
            // Clock out — create a TimesheetEntry for today's hours
            let clockOut = Date()
            if let clockIn = clockInTime, let project = selectedProject {
                let hours = TimeEntry.calculateHours(from: clockIn, to: clockOut)
                let weekStart = TimesheetEntry.weekStart(for: clockIn)
                let dayOfWeek = Calendar.current.component(.weekday, from: clockIn)

                // Build entry with hours placed in the correct day column
                var entry = TimesheetEntry(
                    employeeName: "Field Entry",
                    employeeType: "",
                    projectName: project.title,
                    projectRef: project.id.recordName,
                    weekStartDate: weekStart
                )

                // Map weekday (1=Sun..7=Sat) to the right column
                switch dayOfWeek {
                case 2: entry.mondayHours = hours
                case 3: entry.tuesdayHours = hours
                case 4: entry.wednesdayHours = hours
                case 5: entry.thursdayHours = hours
                case 6: entry.fridayHours = hours
                case 7: entry.saturdayHours = hours
                case 1: entry.sundayHours = hours
                default: entry.mondayHours = hours
                }

                entry.notes = "Clocked \(clockIn.formatted(date: .omitted, time: .shortened)) - \(clockOut.formatted(date: .omitted, time: .shortened))"
                dataStore.addTimesheetEntry(entry)
            }
            stopTimer()
            isClockedIn = false
            clockInTime = nil
        } else {
            // Clock in
            clockInTime = Date()
            isClockedIn = true
            elapsedSeconds = 0
            startTimer()
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if let clockIn = clockInTime {
                elapsedSeconds = Date().timeIntervalSince(clockIn)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        elapsedSeconds = 0
    }
}
