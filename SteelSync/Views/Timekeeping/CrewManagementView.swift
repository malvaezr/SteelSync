import SwiftUI

struct CrewManagementView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var weekStart = TimesheetEntry.currentWeekStart()
    @State private var showAddRow = false
    @State private var editingEntry: TimesheetEntry?
    @State private var showApplyPreset = false
    @State private var showManagePresets = false
    @State private var presetApplyToast: String?

    private var entries: [TimesheetEntry] {
        dataStore.timesheetEntries(for: weekStart)
    }

    private var totals: (hours: Decimal, perDiem: Decimal, pay: Decimal) {
        dataStore.timesheetWeekTotals(for: weekStart)
    }

    private var weekLabel: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let yearFmt = DateFormatter()
        yearFmt.dateFormat = ", yyyy"
        return "\(fmt.string(from: weekStart)) - \(fmt.string(from: end))\(yearFmt.string(from: weekStart))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar: week navigation + actions
            HStack(spacing: 12) {
                Button { shiftWeek(by: -1) } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)

                Text("Pay Period: \(weekLabel)")
                    .font(.headline)
                    .fontWeight(.semibold)

                Button { shiftWeek(by: 1) } label: { Image(systemName: "chevron.right") }
                    .buttonStyle(.borderless)

                Button("This Week") { weekStart = TimesheetEntry.currentWeekStart() }
                    .font(.caption)
                    .buttonStyle(.appSecondary)

                Spacer()

                Text("\(entries.count) worker\(entries.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Menu {
                    Button {
                        showApplyPreset = true
                    } label: {
                        Label("Apply Crew Preset…", systemImage: "person.3.sequence.fill")
                    }
                    .disabled(dataStore.crewPresets.isEmpty)

                    Button {
                        showManagePresets = true
                    } label: {
                        Label("Manage Presets…", systemImage: "slider.horizontal.3")
                    }
                } label: {
                    Label("Presets", systemImage: "person.3.sequence")
                        .font(.callout)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button { showAddRow = true } label: {
                    Label("Add Row", systemImage: "plus")
                        .font(.callout)
                }
                .buttonStyle(.appPrimary)
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)

            Divider()

            if entries.isEmpty {
                EmptyStateView(
                    icon: "person.3.fill",
                    title: "No Timesheet Entries",
                    message: "Add workers to this pay period to start tracking hours.",
                    buttonTitle: "Add Row"
                ) { showAddRow = true }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Scrollable timesheet grid
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(spacing: 0) {
                        headerRow
                        Divider()

                        ForEach(entries) { entry in
                            entryRow(entry)
                            Divider()
                        }

                        totalsRow
                    }
                    .frame(minWidth: 900)
                }
            }
        }
        .inlineForm(isPresented: $showAddRow) {
            AddTimesheetRowSheet(weekStart: weekStart)
        }
        .sheet(item: $editingEntry) { entry in
            EditTimesheetRowSheet(entry: entry)
        }
        .inlineForm(isPresented: $showApplyPreset) {
            ApplyCrewPresetSheet(weekStart: weekStart) { added in
                presetApplyToast = added > 0
                    ? "Added \(added) row\(added == 1 ? "" : "s") to this week"
                    : "Everyone in that preset is already on the week"
            }
        }
        .sheet(isPresented: $showManagePresets) {
            ManageCrewPresetsView()
        }
        .overlay(alignment: .top) {
            if let toast = presetApplyToast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(AppTheme.primaryOrange.opacity(0.92))
                    )
                    .foregroundColor(.white)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                            withAnimation { presetApplyToast = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: presetApplyToast)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Worker").gridHeader(width: 180, alignment: .leading)
            Text("Project").gridHeader(width: 140, alignment: .leading)
            Text("Rate").gridHeader(width: 60)
            Text("Mon").gridHeader(width: 45)
            Text("Tue").gridHeader(width: 45)
            Text("Wed").gridHeader(width: 45)
            Text("Thu").gridHeader(width: 45)
            Text("Fri").gridHeader(width: 45)
            Text("Sat").gridHeader(width: 45)
            Text("Sun").gridHeader(width: 45)
            Text("Hours").gridHeader(width: 55)
            Text("Per Diem").gridHeader(width: 90)
            Text("Total").gridHeader(width: 80)
            Text("").gridHeader(width: 30) // actions
        }
        .background(AppTheme.primaryOrange.opacity(0.12))
    }

    // MARK: - Entry Row

    private func entryRow(_ entry: TimesheetEntry) -> some View {
        HStack(spacing: 0) {
            Text(entry.displayName)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)
                .padding(.horizontal, 4)

            Text(entry.projectName)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
                .padding(.horizontal, 4)

            Text(entry.hourlyRate.currencyWithCents)
                .font(.caption)
                .frame(width: 60)

            dayCell(entry.mondayHours)
            dayCell(entry.tuesdayHours)
            dayCell(entry.wednesdayHours)
            dayCell(entry.thursdayHours)
            dayCell(entry.fridayHours)
            dayCell(entry.saturdayHours)
            dayCell(entry.sundayHours)

            Text(entry.totalHours.formatted())
                .font(.caption).fontWeight(.semibold)
                .frame(width: 55)

            VStack(alignment: .trailing, spacing: 1) {
                Text(entry.totalPerDiem.currencyFormatted)
                    .font(.caption)
                if entry.daysWorked > 0 && entry.perDiem > 0 {
                    Text("\(entry.perDiem.currencyFormatted)/d × \(entry.daysWorked)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 90, alignment: .trailing)

            Text(entry.totalPay.currencyFormatted)
                .font(.caption).fontWeight(.bold)
                .foregroundColor(.green)
                .frame(width: 80)

            // Actions
            Menu {
                Button("Edit") { editingEntry = entry }
                Divider()
                Button("Delete", role: .destructive) { dataStore.deleteTimesheetEntry(entry) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .frame(width: 30)
        }
        .padding(.vertical, 4)
    }

    private func dayCell(_ hours: Decimal) -> some View {
        Text(hours > 0 ? hours.formatted() : "")
            .font(.caption)
            .frame(width: 45)
            .foregroundColor(hours > 0 ? .primary : .secondary)
    }

    // MARK: - Totals Row

    private var totalsRow: some View {
        HStack(spacing: 0) {
            Text("TOTALS")
                .font(.caption).fontWeight(.bold)
                .frame(width: 180, alignment: .leading)
                .padding(.horizontal, 4)
            Text("").frame(width: 140)
            Text("").frame(width: 60)
            Text("").frame(width: 45) // Mon
            Text("").frame(width: 45) // Tue
            Text("").frame(width: 45) // Wed
            Text("").frame(width: 45) // Thu
            Text("").frame(width: 45) // Fri
            Text("").frame(width: 45) // Sat
            Text("").frame(width: 45) // Sun
            Text(totals.hours.formatted())
                .font(.caption).fontWeight(.bold)
                .frame(width: 55)
            Text(totals.perDiem.currencyFormatted)
                .font(.caption).fontWeight(.bold)
                .frame(width: 90, alignment: .trailing)
            Text(totals.pay.currencyFormatted)
                .font(.caption).fontWeight(.bold)
                .foregroundColor(.green)
                .frame(width: 80)
            Text("").frame(width: 30)
        }
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.08))
    }

    private func shiftWeek(by weeks: Int) {
        weekStart = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: weekStart) ?? weekStart
    }
}

// MARK: - Grid Header Modifier

private extension Text {
    func gridHeader(width: CGFloat, alignment: Alignment = .center) -> some View {
        self.font(.system(size: 10, weight: .bold))
            .frame(width: width, alignment: alignment)
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
    }
}

// MARK: - Add Timesheet Row Sheet

struct AddTimesheetRowSheet: View {
    let weekStart: Date
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var selectedEmployee: Employee?
    @State private var selectedProject: Project?
    @State private var hourlyRate = ""
    @State private var perDiem = ""
    @State private var mon = ""
    @State private var tue = ""
    @State private var wed = ""
    @State private var thu = ""
    @State private var fri = ""
    @State private var sat = ""
    @State private var sun = ""

    /// Live preview of `perDiem × daysWorked`. Returned as nil when there's
    /// nothing useful to show (no rate or no days entered).
    private var perDiemPreview: String? {
        let rate = Decimal(string: perDiem) ?? 0
        guard rate > 0 else { return nil }
        let days = [mon, tue, wed, thu, fri, sat, sun]
            .reduce(0) { $0 + ((Decimal(string: $1) ?? 0) > 0 ? 1 : 0) }
        guard days > 0 else { return "Per diem applies once hours are entered for at least one day." }
        let total = rate * Decimal(days)
        return "Per diem total: \(rate.currencyFormatted)/day × \(days) day\(days == 1 ? "" : "s") = \(total.currencyFormatted)"
    }

    var body: some View {
        EntryFormScaffold(
            title: "Add Timesheet Row",
            icon: AppIcons.crew,
            saveTitle: "Add",
            saveDisabled: selectedEmployee == nil,
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Worker & Project", systemImage: AppIcons.person) {
                LabeledField(label: "Employee") {
                    Picker("", selection: $selectedEmployee) {
                        Text("Select...").tag(nil as Employee?)
                        ForEach(dataStore.activeEmployees) { emp in
                            Text("\(emp.fullName) (\(emp.employeeType.rawValue))").tag(emp as Employee?)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                    .onChange(of: selectedEmployee) { _, emp in
                        if let emp {
                            hourlyRate = NSDecimalNumber(decimal: emp.defaultHourlyRate).stringValue
                        }
                    }
                }
                LabeledField(label: "Project") {
                    Picker("", selection: $selectedProject) {
                        Text("Select...").tag(nil as Project?)
                        ForEach(dataStore.projects) { proj in
                            Text(proj.title).tag(proj as Project?)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    LabeledField(label: "Hourly Rate") {
                        CurrencyInput(placeholder: "0", text: $hourlyRate)
                    }
                    LabeledField(label: "Per Diem (/day)") {
                        CurrencyInput(placeholder: "0", text: $perDiem)
                    }
                }
            }

            EntrySection("Daily Hours", systemImage: AppIcons.clock) {
                dayField("Monday", value: $mon)
                dayField("Tuesday", value: $tue)
                dayField("Wednesday", value: $wed)
                dayField("Thursday", value: $thu)
                dayField("Friday", value: $fri)
                dayField("Saturday", value: $sat)
                dayField("Sunday", value: $sun)
                if let preview = perDiemPreview {
                    Text(preview)
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func dayField(_ label: String, value: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                #if !os(macOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }

    private func save() {
        guard let emp = selectedEmployee else { return }
        let entry = TimesheetEntry(
            employeeName: emp.fullName,
            employeeType: emp.employeeType.rawValue,
            employeeRef: emp.id.uuidString,
            projectName: selectedProject?.title ?? "",
            projectRef: selectedProject?.id.recordName ?? "",
            hourlyRate: Decimal(string: hourlyRate) ?? emp.defaultHourlyRate,
            mondayHours: Decimal(string: mon) ?? 0,
            tuesdayHours: Decimal(string: tue) ?? 0,
            wednesdayHours: Decimal(string: wed) ?? 0,
            thursdayHours: Decimal(string: thu) ?? 0,
            fridayHours: Decimal(string: fri) ?? 0,
            saturdayHours: Decimal(string: sat) ?? 0,
            sundayHours: Decimal(string: sun) ?? 0,
            perDiem: Decimal(string: perDiem) ?? 0,
            weekStartDate: weekStart
        )
        dataStore.addTimesheetEntry(entry)
        closeForm()
    }
}

// MARK: - Edit Timesheet Row Sheet

struct EditTimesheetRowSheet: View {
    @State var entry: TimesheetEntry
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var hourlyRate: String
    @State private var perDiem: String
    @State private var mon: String
    @State private var tue: String
    @State private var wed: String
    @State private var thu: String
    @State private var fri: String
    @State private var sat: String
    @State private var sun: String

    init(entry: TimesheetEntry) {
        _entry = State(initialValue: entry)
        _hourlyRate = State(initialValue: NSDecimalNumber(decimal: entry.hourlyRate).stringValue)
        _perDiem = State(initialValue: NSDecimalNumber(decimal: entry.perDiem).stringValue)
        _mon = State(initialValue: entry.mondayHours > 0 ? NSDecimalNumber(decimal: entry.mondayHours).stringValue : "")
        _tue = State(initialValue: entry.tuesdayHours > 0 ? NSDecimalNumber(decimal: entry.tuesdayHours).stringValue : "")
        _wed = State(initialValue: entry.wednesdayHours > 0 ? NSDecimalNumber(decimal: entry.wednesdayHours).stringValue : "")
        _thu = State(initialValue: entry.thursdayHours > 0 ? NSDecimalNumber(decimal: entry.thursdayHours).stringValue : "")
        _fri = State(initialValue: entry.fridayHours > 0 ? NSDecimalNumber(decimal: entry.fridayHours).stringValue : "")
        _sat = State(initialValue: entry.saturdayHours > 0 ? NSDecimalNumber(decimal: entry.saturdayHours).stringValue : "")
        _sun = State(initialValue: entry.sundayHours > 0 ? NSDecimalNumber(decimal: entry.sundayHours).stringValue : "")
    }

    private var perDiemPreview: String? {
        let rate = Decimal(string: perDiem) ?? 0
        guard rate > 0 else { return nil }
        let days = [mon, tue, wed, thu, fri, sat, sun]
            .reduce(0) { $0 + ((Decimal(string: $1) ?? 0) > 0 ? 1 : 0) }
        guard days > 0 else { return "Per diem applies once hours are entered for at least one day." }
        let total = rate * Decimal(days)
        return "Per diem total: \(rate.currencyFormatted)/day × \(days) day\(days == 1 ? "" : "s") = \(total.currencyFormatted)"
    }

    var body: some View {
        EntryFormScaffold(
            title: "Edit Hours",
            icon: AppIcons.clock,
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection(entry.employeeName, systemImage: AppIcons.person) {
                InfoRow(label: "Project", value: entry.projectName)
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    LabeledField(label: "Hourly Rate") {
                        CurrencyInput(placeholder: "0", text: $hourlyRate)
                    }
                    LabeledField(label: "Per Diem (/day)") {
                        CurrencyInput(placeholder: "0", text: $perDiem)
                    }
                }
            }

            EntrySection("Daily Hours", systemImage: AppIcons.clock) {
                dayField("Monday", value: $mon)
                dayField("Tuesday", value: $tue)
                dayField("Wednesday", value: $wed)
                dayField("Thursday", value: $thu)
                dayField("Friday", value: $fri)
                dayField("Saturday", value: $sat)
                dayField("Sunday", value: $sun)
                if let preview = perDiemPreview {
                    Text(preview)
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 600)
        #endif
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func dayField(_ label: String, value: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
                .multilineTextAlignment(.trailing)
                #if !os(macOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }

    private func save() {
        entry.hourlyRate = Decimal(string: hourlyRate) ?? entry.hourlyRate
        entry.perDiem = Decimal(string: perDiem) ?? entry.perDiem
        entry.mondayHours = Decimal(string: mon) ?? 0
        entry.tuesdayHours = Decimal(string: tue) ?? 0
        entry.wednesdayHours = Decimal(string: wed) ?? 0
        entry.thursdayHours = Decimal(string: thu) ?? 0
        entry.fridayHours = Decimal(string: fri) ?? 0
        entry.saturdayHours = Decimal(string: sat) ?? 0
        entry.sundayHours = Decimal(string: sun) ?? 0
        dataStore.updateTimesheetEntry(entry)
        closeForm()
    }
}
