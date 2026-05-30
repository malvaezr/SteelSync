import SwiftUI

struct GanttTaskEditSheet: View {
    @EnvironmentObject var dataStore: DataStore
    let projects: [Project]
    var editingTask: GanttTask?
    var selectedProjectID: String?
    let onSave: (GanttTask) -> Void
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var name = ""
    @State private var projectID = ""
    @State private var category: TaskCategory = .other
    @State private var status: TaskStatus = .notStarted
    @State private var startDate = Date()
    @State private var durationDays = 5
    @State private var assignedTo = ""
    @State private var notes = ""
    @State private var progress: Double = 0
    @State private var includesSaturdays = false
    @State private var predecessorIDs: Set<UUID> = []
    @State private var isPinned = false
    @State private var hasManpower = false
    @State private var manpower = 1

    init(projects: [Project], selectedProjectID: String? = nil, editingTask: GanttTask? = nil,
         onSave: @escaping (GanttTask) -> Void, onDelete: (() -> Void)? = nil) {
        self.projects = projects
        self.editingTask = editingTask
        self.selectedProjectID = selectedProjectID
        self.onSave = onSave
        self.onDelete = onDelete
    }

    /// Other tasks from the same project that could be predecessors (excluding self).
    private var availablePredecessors: [GanttTask] {
        dataStore.ganttTasks
            .filter { $0.projectID == projectID && $0.id != editingTask?.id }
            .sorted { $0.startDate < $1.startDate }
    }

    private var predecessorSummary: String {
        if predecessorIDs.isEmpty { return "None" }
        return "\(predecessorIDs.count) selected"
    }

    var isEditing: Bool { editingTask != nil }

    var endDate: Date {
        startDate.addingWorkdays(durationDays, includeSaturdays: includesSaturdays)
    }

    var body: some View {
        EntryFormScaffold(
            title: isEditing ? "Edit Task" : "New Task",
            icon: AppIcons.calendar,
            saveDisabled: name.isEmpty || projectID.isEmpty,
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Task Details", systemImage: "list.bullet.rectangle") {
                LabeledField(label: "Task Name") {
                    TextField("Task Name", text: $name).textFieldStyle(.appField)
                }
                LabeledField(label: "Project") {
                    Picker("", selection: $projectID) {
                        Text("Select Project").tag("")
                        ForEach(projects) { p in
                            Text(p.title).tag(p.id.recordName)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    LabeledField(label: "Category") {
                        Picker("", selection: $category) {
                            ForEach(TaskCategory.allCases) { cat in
                                Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).appControlSurface()
                    }
                    LabeledField(label: "Status") {
                        Picker("", selection: $status) {
                            ForEach(TaskStatus.allCases) { s in
                                Label(s.rawValue, systemImage: s.icon).tag(s)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).appControlSurface()
                    }
                }
            }

            EntrySection("Schedule", systemImage: AppIcons.calendar) {
                LabeledField(label: "Start Date") {
                    DatePicker("", selection: $startDate, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
                Stepper("Duration: \(durationDays) day\(durationDays == 1 ? "" : "s")",
                        value: $durationDays, in: 1...365)
                Toggle("Include Saturdays", isOn: $includesSaturdays)
                    .tint(AppTheme.primaryOrange)
                InfoRow(label: "End Date", value: endDate.shortDate)
                InfoRow(label: "Work Schedule", value: includesSaturdays ? "Mon - Sat" : "Mon - Fri")
            }

            EntrySection("Progress", systemImage: "chart.bar.fill") {
                HStack {
                    Slider(value: $progress, in: 0...1, step: 0.05)
                    Text("\(Int(progress * 100))%")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 40)
                }
            }

            EntrySection("Dependencies", systemImage: "arrow.turn.down.right") {
                Menu {
                    if availablePredecessors.isEmpty {
                        Text("No other tasks in this project yet.")
                    } else {
                        ForEach(availablePredecessors, id: \.id) { other in
                            Button {
                                if predecessorIDs.contains(other.id) {
                                    predecessorIDs.remove(other.id)
                                } else {
                                    predecessorIDs.insert(other.id)
                                }
                            } label: {
                                if predecessorIDs.contains(other.id) {
                                    Label("\(other.name) — \(other.startDate.shortDate)", systemImage: "checkmark")
                                } else {
                                    Text("\(other.name) — \(other.startDate.shortDate)")
                                }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Label("Depends On", systemImage: "arrow.turn.down.right")
                        Spacer()
                        Text(predecessorSummary)
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    .appControlSurface()
                }
                .buttonStyle(.plain)
                if !predecessorIDs.isEmpty {
                    Text("Finish-to-start: this task's earliest start is after its predecessors finish. Connector lines will be drawn in the chart.")
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                }
            }

            EntrySection("Protection", systemImage: AppIcons.pinned) {
                Toggle(isOn: $isPinned) {
                    Label("Pin Task", systemImage: "pin.fill")
                }
                .tint(AppTheme.primaryOrange)
                Text("Pinned tasks cannot be dragged or resized in the chart. Use the context menu to unpin.")
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
            }

            EntrySection("Manpower", systemImage: AppIcons.crew) {
                Toggle(isOn: $hasManpower) {
                    Label("Assign Manpower", systemImage: "person.3.fill")
                }
                .tint(AppTheme.primaryOrange)
                if hasManpower {
                    Stepper("Crew: \(manpower) worker\(manpower == 1 ? "" : "s")",
                            value: $manpower, in: 1...999)
                }
            }

            EntrySection("Additional", systemImage: "note.text") {
                LabeledField(label: "Assigned To") {
                    assignedToPicker
                }
                LabeledField(label: "Notes") {
                    NotesField(text: $notes, minHeight: 70)
                }
            }

            if isEditing, let onDelete = onDelete {
                EntrySection("Danger Zone", systemImage: AppIcons.delete) {
                    Button(role: .destructive) {
                        onDelete()
                        closeForm()
                    } label: {
                        Label("Delete Task", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appDestructive)
                }
            }
        }
        #if os(macOS)
        // Fixed size when presented as a sheet (edit); fill the pane when inline (add).
        .frame(width: inlineDismiss == nil ? 520 : nil,
               height: inlineDismiss == nil ? 640 : nil)
        #endif
        .onAppear {
            if let task = editingTask {
                name = task.name; projectID = task.projectID
                category = task.category; status = task.status
                startDate = task.startDate; durationDays = task.durationDays
                assignedTo = task.assignedTo; notes = task.notes
                progress = task.progress; includesSaturdays = task.includesSaturdays
                predecessorIDs = Set(task.predecessorIDs)
                isPinned = task.isPinned
                if let m = task.manpower { hasManpower = true; manpower = m }
            } else if let pid = selectedProjectID {
                projectID = pid
            } else if let first = projects.first {
                projectID = first.id.recordName
            }
        }
    }

    /// Grouped picker over the active employee roster (Foremen section first,
    /// then Crew). If the task currently holds a legacy free-text name that
    /// isn't on the roster, it stays selected and shows as "(legacy)" so we
    /// don't quietly clobber it — the user can re-pick to update.
    @ViewBuilder
    private var assignedToPicker: some View {
        let active = dataStore.activeEmployees
        let foremen = active.filter { $0.isForeman }
        let crew = active.filter { !$0.isForeman }
        let allNames = Set(active.map { $0.fullName })
        let isLegacy = !assignedTo.isEmpty && !allNames.contains(assignedTo)

        Picker("", selection: $assignedTo) {
            Text("Unassigned").tag("")
            if !foremen.isEmpty {
                Section("Foremen") {
                    ForEach(foremen) { emp in
                        Text(emp.fullName).tag(emp.fullName)
                    }
                }
            }
            if !crew.isEmpty {
                Section("Crew") {
                    ForEach(crew) { emp in
                        Text(emp.fullName).tag(emp.fullName)
                    }
                }
            }
            if isLegacy {
                Section("Other") {
                    Text("\(assignedTo) (legacy)").tag(assignedTo)
                }
            }
            if active.isEmpty {
                Section {
                    Text("Add crew in Operations → Crew & Timesheets")
                        .foregroundColor(.secondary)
                }
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .appControlSurface()
    }

    private func save() {
        if var task = editingTask {
            task.name = name; task.projectID = projectID
            task.category = category; task.status = status
            task.startDate = startDate; task.durationDays = durationDays
            task.assignedTo = assignedTo; task.notes = notes
            task.progress = progress; task.includesSaturdays = includesSaturdays
            task.predecessorIDs = Array(predecessorIDs)
            task.isPinned = isPinned
            task.manpower = hasManpower ? manpower : nil
            onSave(task)
        } else {
            let task = GanttTask(
                projectID: projectID, name: name, category: category,
                status: status, startDate: startDate, durationDays: durationDays,
                assignedTo: assignedTo, notes: notes,
                sortOrder: 999, progress: progress, includesSaturdays: includesSaturdays,
                predecessorIDs: Array(predecessorIDs),
                isPinned: isPinned,
                manpower: hasManpower ? manpower : nil
            )
            onSave(task)
        }
        closeForm()
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }
}
