import SwiftUI

struct GanttTaskEditSheet: View {
    @EnvironmentObject var dataStore: DataStore
    let projects: [Project]
    var editingTask: GanttTask?
    var selectedProjectID: String?
    let onSave: (GanttTask) -> Void
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

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
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(isEditing ? "Edit Task" : "New Task")
                    .font(AppTheme.Typography.title3)
                Spacer()
                if isEditing, let onDelete = onDelete {
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.isEmpty || projectID.isEmpty)
                    .buttonStyle(.appPrimary)
            }
            .padding()
            Divider()

            Form {
                Section("Task Details") {
                    TextField("Task Name", text: $name)
                    Picker("Project", selection: $projectID) {
                        Text("Select Project").tag("")
                        ForEach(projects) { p in
                            Text(p.title).tag(p.id.recordName)
                        }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(TaskCategory.allCases) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat)
                        }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(TaskStatus.allCases) { s in
                            Label(s.rawValue, systemImage: s.icon).tag(s)
                        }
                    }
                }

                Section("Schedule") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    Stepper("Duration: \(durationDays) day\(durationDays == 1 ? "" : "s")",
                            value: $durationDays, in: 1...365)
                    Toggle("Include Saturdays", isOn: $includesSaturdays)
                    HStack {
                        Text("End Date")
                        Spacer()
                        Text(endDate.shortDate)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Work Schedule")
                        Spacer()
                        Text(includesSaturdays ? "Mon - Sat" : "Mon - Fri")
                            .foregroundColor(.secondary)
                    }
                }

                Section("Progress") {
                    HStack {
                        Slider(value: $progress, in: 0...1, step: 0.05)
                        Text("\(Int(progress * 100))%")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 40)
                    }
                }

                Section("Dependencies") {
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
                                .foregroundColor(.secondary)
                        }
                    }
                    if !predecessorIDs.isEmpty {
                        Text("Finish-to-start: this task's earliest start is after its predecessors finish. Connector lines will be drawn in the chart.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Protection") {
                    Toggle(isOn: $isPinned) {
                        Label("Pin Task", systemImage: "pin.fill")
                    }
                    Text("Pinned tasks cannot be dragged or resized in the chart. Use the context menu to unpin.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Additional") {
                    TextField("Assigned To", text: $assignedTo)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 480, height: 620)
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
            } else if let pid = selectedProjectID {
                projectID = pid
            } else if let first = projects.first {
                projectID = first.id.recordName
            }
        }
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
            onSave(task)
        } else {
            let task = GanttTask(
                projectID: projectID, name: name, category: category,
                status: status, startDate: startDate, durationDays: durationDays,
                assignedTo: assignedTo, notes: notes,
                sortOrder: 999, progress: progress, includesSaturdays: includesSaturdays,
                predecessorIDs: Array(predecessorIDs),
                isPinned: isPinned
            )
            onSave(task)
        }
        dismiss()
    }
}
