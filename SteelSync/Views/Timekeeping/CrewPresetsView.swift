import SwiftUI

// MARK: - Apply Crew Preset Sheet

/// Lets the user pick one of their saved crew presets, choose an optional
/// default project, and drop one TimesheetEntry per preset member into the
/// current week. Members whose employee already has a row that week are
/// skipped — the preset is additive, not destructive.
struct ApplyCrewPresetSheet: View {
    let weekStart: Date
    /// Reports back how many rows were actually added so the host can show a toast.
    let onApplied: (Int) -> Void

    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var selectedPresetID: UUID?
    @State private var defaultProject: Project?

    private var selectedPreset: CrewPreset? {
        guard let id = selectedPresetID else { return nil }
        return dataStore.crewPresets.first { $0.id == id }
    }

    var body: some View {
        EntryFormScaffold(
            title: "Apply Crew Preset",
            icon: AppIcons.crew,
            saveTitle: "Apply",
            saveDisabled: selectedPreset == nil,
            onCancel: closeForm,
            onSave: apply
        ) {
            EntrySection("Crew Preset", systemImage: AppIcons.people) {
                if dataStore.crewPresets.isEmpty {
                    Text("No presets yet. Create one from the Manage Presets screen.")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                } else {
                    LabeledField(label: "Preset") {
                        Picker("", selection: $selectedPresetID) {
                            Text("Select…").tag(nil as UUID?)
                            ForEach(dataStore.crewPresets.sorted(by: { $0.name < $1.name })) { preset in
                                Text(preset.isRoleTemplate
                                     ? "\(preset.name) — Role Template"
                                     : "\(preset.name) (\(preset.members.count))"
                                ).tag(preset.id as UUID?)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).appControlSurface()
                    }
                }
            }

            if let preset = selectedPreset {
                EntrySection("Members (\(preset.members.count))", systemImage: AppIcons.person) {
                    ForEach(preset.members) { m in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.employeeName.isEmpty ? "(unnamed)" : m.employeeName)
                                .font(.callout)
                                .fontWeight(.medium)
                            HStack(spacing: 8) {
                                if !m.employeeType.isEmpty {
                                    Text(m.employeeType)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.gray.opacity(0.18)))
                                }
                                Text("\(m.totalDefaultHours.formatted()) h default")
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.secondaryText)
                                if let r = m.hourlyRateOverride {
                                    Text("@ $\(r.formatted())/hr")
                                        .font(.caption2)
                                        .foregroundColor(AppTheme.secondaryText)
                                }
                                if m.perDiem > 0 {
                                    Text("$\(m.perDiem.formatted())/day per diem")
                                        .font(.caption2)
                                        .foregroundColor(AppTheme.secondaryText)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Divider()
                    }
                }

                EntrySection("Apply To", systemImage: AppIcons.building) {
                    LabeledField(label: "Default Project") {
                        Picker("", selection: $defaultProject) {
                            Text("None — assign per row").tag(nil as Project?)
                            ForEach(dataStore.projects) { p in
                                Text(p.title).tag(p as Project?)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).appControlSurface()
                    }
                    Text("Members whose employee already has a row in this week will be skipped.")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func apply() {
        guard let preset = selectedPreset else { return }
        let added = dataStore.applyCrewPreset(preset, to: weekStart, defaultProject: defaultProject)
        onApplied(added)
        closeForm()
    }
}

// MARK: - Manage Crew Presets

/// List view + editor for the user's saved presets. Presets are modular:
/// add/remove members, override rates per-member, set a default daily-hours
/// pattern, and "Duplicate as Role Template" to spin off a people-less copy.
struct ManageCrewPresetsView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingPreset: CrewPreset?
    @State private var showCreateNew = false
    @State private var presetToDelete: CrewPreset?

    var body: some View {
        NavigationStack {
            List {
                if dataStore.crewPresets.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No crew presets yet.")
                                .font(.callout)
                                .fontWeight(.medium)
                            Text("Save a recurring crew (foreman + ironworkers, day shift, etc.) so you can drop the whole roster onto a week with one tap.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    ForEach(dataStore.crewPresets.sorted(by: { $0.name < $1.name })) { preset in
                        Button { editingPreset = preset } label: {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(preset.name)
                                            .font(.callout)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)
                                        if preset.isRoleTemplate {
                                            Text("ROLES")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Capsule().fill(Color.purple.opacity(0.2)))
                                                .foregroundColor(.purple)
                                        }
                                    }
                                    Text("\(preset.members.count) member\(preset.members.count == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Edit…") { editingPreset = preset }
                            Button("Duplicate as Role Template") {
                                let template = preset.duplicatedAsRoleTemplate()
                                dataStore.addCrewPreset(template)
                            }
                            Divider()
                            Button("Delete…", role: .destructive) { presetToDelete = preset }
                        }
                    }
                }
            }
            .navigationTitle("Crew Presets")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showCreateNew = true
                    } label: {
                        Label("New Preset", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateNew) {
                EditCrewPresetSheet(preset: CrewPreset(name: "New Crew"), isNew: true)
            }
            .sheet(item: $editingPreset) { preset in
                EditCrewPresetSheet(preset: preset, isNew: false)
            }
            .confirmationDialog(
                "Delete preset?",
                isPresented: Binding(
                    get: { presetToDelete != nil },
                    set: { if !$0 { presetToDelete = nil } }
                ),
                presenting: presetToDelete
            ) { preset in
                Button("Delete", role: .destructive) {
                    dataStore.deleteCrewPreset(preset)
                    presetToDelete = nil
                }
                Button("Cancel", role: .cancel) { presetToDelete = nil }
            } message: { preset in
                Text("\"\(preset.name)\" will be removed. Any timesheet rows already added from it stay in place.")
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
    }
}

// MARK: - Edit Preset Sheet

/// Editor for a single preset. Renders the member list inline so adding /
/// removing / re-rate-ing happens without nesting another sheet.
struct EditCrewPresetSheet: View {
    @State var preset: CrewPreset
    let isNew: Bool
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var addingMemberFor: UUID?  // sentinel to trigger AddMemberSheet
    @State private var showAddMember = false

    var body: some View {
        EntryFormScaffold(
            title: isNew ? "New Crew Preset" : "Edit Preset",
            icon: AppIcons.crew,
            saveDisabled: preset.name.trimmingCharacters(in: .whitespaces).isEmpty,
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Name", systemImage: "tag") {
                TextField("Crew name", text: $preset.name)
                    .textFieldStyle(.appField)
            }

            EntrySection("Members (\(preset.members.count))", systemImage: AppIcons.people) {
                if preset.members.isEmpty {
                    Text("No members yet. Add workers below — you can override rate, per diem, and weekly hours per row.")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                } else {
                    ForEach($preset.members) { $member in
                        HStack(alignment: .top, spacing: 8) {
                            CrewPresetMemberEditor(member: $member)
                            Button {
                                preset.members.removeAll { $0.id == member.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        Divider()
                    }
                }

                Button {
                    showAddMember = true
                } label: {
                    Label("Add Member", systemImage: "person.badge.plus")
                        .font(.callout)
                        .foregroundColor(AppTheme.primaryOrange)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Default daily hours apply when this preset is dropped onto a new week. You can still edit each row after.")
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
            }

            if !isNew {
                EntrySection("Role Template", systemImage: "doc.on.doc") {
                    Button {
                        let template = preset.duplicatedAsRoleTemplate()
                        dataStore.addCrewPreset(template)
                        closeForm()
                    } label: {
                        Label("Duplicate as Role Template", systemImage: "doc.on.doc")
                            .foregroundColor(AppTheme.primaryOrange)
                    }
                    .buttonStyle(.plain)
                    Text("Creates a copy of this preset with employee links removed, leaving role labels for later assignment.")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
        }
        #if os(macOS)
        .frame(width: 560, height: 640)
        #endif
        .sheet(isPresented: $showAddMember) {
            AddPresetMemberSheet { newMember in
                preset.members.append(newMember)
            }
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func save() {
        if isNew {
            dataStore.addCrewPreset(preset)
        } else {
            dataStore.updateCrewPreset(preset)
        }
        closeForm()
    }
}

// MARK: - Per-Member Inline Editor

private struct CrewPresetMemberEditor: View {
    @Binding var member: CrewPresetMember
    @State private var rateText: String = ""
    @State private var perDiemText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(member.employeeName.isEmpty ? "(unnamed)" : member.employeeName)
                    .font(.callout)
                    .fontWeight(.semibold)
                if !member.employeeType.isEmpty {
                    Text(member.employeeType)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.gray.opacity(0.18)))
                }
                Spacer()
            }

            HStack {
                Text("Rate override")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("$")
                    .foregroundColor(.secondary)
                TextField("Use default", text: $rateText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    #if !os(macOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .onChange(of: rateText) { _, new in
                        member.hourlyRateOverride = new.isEmpty ? nil : Decimal(string: new)
                    }
            }

            HStack {
                Text("Per diem")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("$")
                    .foregroundColor(.secondary)
                TextField("0", text: $perDiemText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    #if !os(macOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .onChange(of: perDiemText) { _, new in
                        member.perDiem = Decimal(string: new) ?? 0
                    }
                Text("/ day")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Default daily hours")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("8h M–F") {
                        member.dailyHours = [8, 8, 8, 8, 8, 0, 0]
                    }
                    .font(.caption2)
                    .buttonStyle(.appSecondary)
                    Button("Clear") {
                        member.dailyHours = [0, 0, 0, 0, 0, 0, 0]
                    }
                    .font(.caption2)
                    .buttonStyle(.appSecondary)
                }

                HStack(spacing: 4) {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { idx, label in
                        VStack(spacing: 2) {
                            Text(label)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            DailyHoursField(value: dailyBinding(idx))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            rateText = member.hourlyRateOverride.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            perDiemText = member.perDiem == 0 ? "" : NSDecimalNumber(decimal: member.perDiem).stringValue
        }
    }

    private func dailyBinding(_ idx: Int) -> Binding<Decimal> {
        Binding(
            get: { member.dailyHours[idx] },
            set: { member.dailyHours[idx] = $0 }
        )
    }
}

private struct DailyHoursField: View {
    @Binding var value: Decimal
    @State private var text: String = ""

    var body: some View {
        TextField("0", text: $text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 44)
            .multilineTextAlignment(.center)
            #if !os(macOS)
            .keyboardType(.decimalPad)
            #endif
            .onAppear { text = value == 0 ? "" : NSDecimalNumber(decimal: value).stringValue }
            .onChange(of: text) { _, new in
                value = Decimal(string: new) ?? 0
            }
    }
}

// MARK: - Add Member Sheet (employee picker)

struct AddPresetMemberSheet: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    let onAdd: (CrewPresetMember) -> Void

    @State private var selectedEmployee: Employee?
    @State private var perDiem: String = ""
    @State private var pattern: WeeklyPattern = .fiveTen
    @State private var roleLabel: String = ""

    enum WeeklyPattern: String, CaseIterable, Identifiable {
        case standard5Day = "8h M–F"
        case sixDay = "8h M–Sat"
        case fourTen = "10h M–Th"
        case fiveTen = "10h M–F"
        case empty = "Empty (fill later)"
        var id: String { rawValue }

        var hours: [Decimal] {
            switch self {
            case .standard5Day: return [8, 8, 8, 8, 8, 0, 0]
            case .sixDay: return [8, 8, 8, 8, 8, 8, 0]
            case .fourTen: return [10, 10, 10, 10, 0, 0, 0]
            case .fiveTen: return [10, 10, 10, 10, 10, 0, 0]
            case .empty: return [0, 0, 0, 0, 0, 0, 0]
            }
        }
    }

    var body: some View {
        EntryFormScaffold(
            title: "Add Member",
            icon: AppIcons.person,
            saveTitle: "Add",
            saveDisabled: !canAdd,
            onCancel: closeForm,
            onSave: add
        ) {
            EntrySection("Employee", systemImage: AppIcons.person) {
                LabeledField(label: "Employee") {
                    Picker("", selection: $selectedEmployee) {
                        Text("Role-only (no employee)").tag(nil as Employee?)
                        ForEach(dataStore.activeEmployees) { e in
                            Text("\(e.fullName) — \(e.employeeType.rawValue)").tag(e as Employee?)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }
                if selectedEmployee == nil {
                    LabeledField(label: "Role Label") {
                        TextField("e.g. Foreman, Ironworker", text: $roleLabel)
                            .textFieldStyle(.appField)
                    }
                }
            }

            EntrySection("Defaults", systemImage: AppIcons.calendar) {
                LabeledField(label: "Default weekly pattern") {
                    Picker("", selection: $pattern) {
                        ForEach(WeeklyPattern.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }
                LabeledField(label: "Per Diem (/day)") {
                    CurrencyInput(placeholder: "0", text: $perDiem)
                }
            }
        }
        #if os(macOS)
        .frame(width: 480, height: 420)
        #endif
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private var canAdd: Bool {
        if let _ = selectedEmployee { return true }
        return !roleLabel.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func add() {
        let member: CrewPresetMember
        if let e = selectedEmployee {
            member = CrewPresetMember(
                employeeRef: e.id.uuidString,
                employeeName: e.fullName,
                employeeType: e.employeeType.rawValue,
                hourlyRateOverride: nil,
                perDiem: Decimal(string: perDiem) ?? 0,
                dailyHours: pattern.hours
            )
        } else {
            let role = roleLabel.trimmingCharacters(in: .whitespaces)
            member = CrewPresetMember(
                employeeRef: nil,
                employeeName: role,
                employeeType: role,
                hourlyRateOverride: nil,
                perDiem: Decimal(string: perDiem) ?? 0,
                dailyHours: pattern.hours
            )
        }
        onAdd(member)
        closeForm()
    }
}
