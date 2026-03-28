import SwiftUI

struct GanttTaskEditSheet: View {
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

    init(projects: [Project], selectedProjectID: String? = nil, editingTask: GanttTask? = nil,
         onSave: @escaping (GanttTask) -> Void, onDelete: (() -> Void)? = nil) {
        self.projects = projects
        self.editingTask = editingTask
        self.selectedProjectID = selectedProjectID
        self.onSave = onSave
        self.onDelete = onDelete
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
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
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
            onSave(task)
        } else {
            let task = GanttTask(
                projectID: projectID, name: name, category: category,
                status: status, startDate: startDate, durationDays: durationDays,
                assignedTo: assignedTo, notes: notes,
                sortOrder: 999, progress: progress, includesSaturdays: includesSaturdays
            )
            onSave(task)
        }
        dismiss()
    }
}
