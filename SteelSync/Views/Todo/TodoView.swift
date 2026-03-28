import SwiftUI

struct TodoView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedFilter = "Active"
    @State private var showAddTodo = false
    @State private var editingTodo: TodoItem?

    private let filters = ["Active", "Overdue", "Completed", "All"]

    var filteredTodos: [TodoItem] {
        switch selectedFilter {
        case "Active": return dataStore.activeTodos.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        case "Overdue": return dataStore.overdueTodos.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        case "Completed": return dataStore.completedTodos.sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }
        default: return dataStore.todos.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Stats & filters
            #if os(macOS)
            HStack(spacing: AppTheme.Spacing.sm) {
                MetricCard(title: "Active", value: "\(dataStore.activeTodos.count)", icon: "checklist", color: .blue)
                MetricCard(title: "Overdue", value: "\(dataStore.overdueTodos.count)", icon: "exclamationmark.triangle.fill", color: .red)
                MetricCard(title: "Due Today", value: "\(dataStore.todos.filter { $0.isDueToday }.count)", icon: "calendar.badge.exclamationmark", color: .orange)
                MetricCard(title: "Completed", value: "\(dataStore.completedTodos.count)", icon: "checkmark.circle.fill", color: .green)
            }
            .padding(AppTheme.Spacing.md)
            #else
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                MetricCard(title: "Active", value: "\(dataStore.activeTodos.count)", icon: "checklist", color: .blue)
                MetricCard(title: "Overdue", value: "\(dataStore.overdueTodos.count)", icon: "exclamationmark.triangle.fill", color: .red)
                MetricCard(title: "Due Today", value: "\(dataStore.todos.filter { $0.isDueToday }.count)", icon: "calendar.badge.exclamationmark", color: .orange)
                MetricCard(title: "Completed", value: "\(dataStore.completedTodos.count)", icon: "checkmark.circle.fill", color: .green)
            }
            .padding(AppTheme.Spacing.md)
            #endif

            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(filters, id: \.self) { filter in
                    FilterPill(filter, isSelected: selectedFilter == filter) {
                        selectedFilter = filter
                    }
                }
                Spacer()
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.sm)

            // Todo list
            if filteredTodos.isEmpty {
                EmptyStateView(icon: "checklist", title: "All Clear!",
                               message: "No tasks in this category.",
                               buttonTitle: "Add Task") { showAddTodo = true }
            } else {
                List {
                    ForEach(filteredTodos) { todo in
                        TodoItemRow(todo: todo) {
                            dataStore.toggleTodo(todo)
                        }
                        .contextMenu {
                            Button("Edit") { editingTodo = todo }
                            Divider()
                            Button(todo.isCompleted ? "Mark Active" : "Complete") { dataStore.toggleTodo(todo) }
                            Button("Delete", role: .destructive) { dataStore.deleteTodo(todo) }
                        }
                    }
                }
                #if os(macOS)
                .listStyle(.inset(alternatesRowBackgrounds: true))
                #else
                .listStyle(.insetGrouped)
                #endif
            }
        }
        .sheet(isPresented: $showAddTodo) {
            AddTodoView()
        }
        .sheet(item: $editingTodo) { todo in
            EditTodoView(todo: todo)
        }
        .navigationTitle("To-Do")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showAddTodo = true }) {
                    Label("Add Task", systemImage: "plus")
                }
            }
        }
    }
}

// MARK: - Todo Item Row
struct TodoItemRow: View {
    let todo: TodoItem
    let toggleAction: () -> Void

    var priorityColor: Color {
        switch todo.priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Button(action: toggleAction) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(todo.isCompleted ? .green : priorityColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .strikethrough(todo.isCompleted)
                    .foregroundColor(todo.isCompleted ? .secondary : AppTheme.primaryText)
                    .fontWeight(.medium)

                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: todo.category.icon)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(todo.category.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let due = todo.dueDate {
                        Text("Due: \(due.shortDate)")
                            .font(.caption)
                            .foregroundColor(todo.isOverdue ? .red : (todo.isDueToday ? .orange : .secondary))
                    }
                }
            }

            Spacer()

            StatusBadge(text: todo.priority.displayName, color: priorityColor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Todo
struct AddTodoView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(86400)
    @State private var priority: TodoPriority = .medium
    @State private var category: TodoCategory = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Task").font(AppTheme.Typography.title2)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
            }
            .padding()
            Divider()
            Form {
                TextField("Title", text: $title)
                TextEditor(text: $notes).frame(height: 60)
                Picker("Priority", selection: $priority) {
                    ForEach(TodoPriority.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Category", selection: $category) {
                    ForEach(TodoCategory.allCases, id: \.self) {
                        Label($0.rawValue, systemImage: $0.icon).tag($0)
                    }
                }
                Toggle("Set Due Date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 450, height: 420)
        #endif
    }

    private func save() {
        let todo = TodoItem(title: title, notes: notes, dueDate: hasDueDate ? dueDate : nil,
                            priority: priority, category: category)
        dataStore.addTodo(todo)
        dismiss()
    }
}

// MARK: - Edit Todo
struct EditTodoView: View {
    let todo: TodoItem
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var priority: TodoPriority
    @State private var category: TodoCategory

    init(todo: TodoItem) {
        self.todo = todo
        _title = State(initialValue: todo.title)
        _notes = State(initialValue: todo.notes)
        _hasDueDate = State(initialValue: todo.dueDate != nil)
        _dueDate = State(initialValue: todo.dueDate ?? Date().addingTimeInterval(86400))
        _priority = State(initialValue: todo.priority)
        _category = State(initialValue: todo.category)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Task").font(AppTheme.Typography.title2)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
            }
            .padding()
            Divider()
            Form {
                TextField("Title", text: $title)
                TextEditor(text: $notes).frame(height: 60)
                Picker("Priority", selection: $priority) {
                    ForEach(TodoPriority.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Category", selection: $category) {
                    ForEach(TodoCategory.allCases, id: \.self) {
                        Label($0.rawValue, systemImage: $0.icon).tag($0)
                    }
                }
                Toggle("Set Due Date", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 450, height: 420)
        #endif
    }

    private func save() {
        var updated = todo
        updated.title = title; updated.notes = notes
        updated.dueDate = hasDueDate ? dueDate : nil
        updated.priority = priority; updated.category = category
        dataStore.updateTodo(updated)
        dismiss()
    }
}
