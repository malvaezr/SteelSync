import SwiftUI

struct PhoneTasksView: View {
    @EnvironmentObject var dataStore: DataStore

    @State private var selectedFilter = "Active"
    @State private var showAddTodo = false
    @State private var editingTodo: TodoItem?

    private let filters = ["Active", "Overdue", "Completed", "All"]

    private var filteredTodos: [TodoItem] {
        switch selectedFilter {
        case "Active":
            return dataStore.activeTodos.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        case "Overdue":
            return dataStore.overdueTodos.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        case "Completed":
            return dataStore.completedTodos.sorted { ($0.completedDate ?? .distantPast) > ($1.completedDate ?? .distantPast) }
        default:
            return dataStore.todos.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // MARK: - Compact Metrics
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "checklist")
                            .foregroundColor(.blue)
                        Text("\(dataStore.activeTodos.count) Active")
                            .font(AppTheme.Typography.subheadline)
                            .fontWeight(.medium)
                            
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("\(dataStore.overdueTodos.count) Overdue")
                            .font(AppTheme.Typography.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(dataStore.overdueTodos.isEmpty ? AppTheme.primaryText : .red)
                    }

                    Spacer()
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)

                // MARK: - Filter Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(filters, id: \.self) { filter in
                            FilterPill(filter, isSelected: selectedFilter == filter, count: countFor(filter)) {
                                selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                }
                .padding(.bottom, AppTheme.Spacing.sm)

                // MARK: - Task List
                if filteredTodos.isEmpty {
                    EmptyStateView(
                        icon: "checklist",
                        title: "All Clear!",
                        message: "No tasks in this category.",
                        buttonTitle: "Add Task"
                    ) {
                        showAddTodo = true
                    }
                } else {
                    List {
                        ForEach(filteredTodos) { todo in
                            PhoneTaskRow(todo: todo, onToggle: { dataStore.toggleTodo(todo) })
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    editingTodo = todo
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        dataStore.toggleTodo(todo)
                                    } label: {
                                        Label(
                                            todo.isCompleted ? "Reopen" : "Complete",
                                            systemImage: todo.isCompleted ? "arrow.uturn.backward" : "checkmark.circle.fill"
                                        )
                                    }
                                    .tint(todo.isCompleted ? .orange : .green)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        dataStore.deleteTodo(todo)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Tasks")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddTodo = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundColor(AppTheme.primaryOrange)
                    }
                }
            }
            .sheet(isPresented: $showAddTodo) {
                AddTodoView()
            }
            .sheet(item: $editingTodo) { todo in
                EditTodoView(todo: todo)
            }
            .refreshable {
                if dataStore.cloudKitAvailable {
                    await dataStore.pullFromCloud()
                }
            }
        }
    }

    private func countFor(_ filter: String) -> Int? {
        switch filter {
        case "Active": return dataStore.activeTodos.count
        case "Overdue": return dataStore.overdueTodos.count
        case "Completed": return dataStore.completedTodos.count
        case "All": return dataStore.todos.count
        default: return nil
        }
    }
}

// MARK: - Phone Task Row

private struct PhoneTaskRow: View {
    let todo: TodoItem
    var onToggle: () -> Void = {}

    private var priorityColor: Color {
        switch todo.priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Button { onToggle() } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(todo.isCompleted ? .green : priorityColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .font(AppTheme.Typography.subheadline)
                    .fontWeight(.medium)
                    .strikethrough(todo.isCompleted)
                    .foregroundColor(todo.isCompleted ? AppTheme.secondaryText : AppTheme.primaryText)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: todo.category.icon)
                            .font(.system(size: 10))
                        Text(todo.category.rawValue)
                    }
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(AppTheme.tertiaryText)

                    if let due = todo.dueDate {
                        Text(due.shortDate)
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(todo.isOverdue ? .red : (todo.isDueToday ? .orange : AppTheme.tertiaryText))
                    }
                }
            }

            Spacer()

            StatusBadge(text: todo.priority.displayName, color: priorityColor)
        }
        .padding(.vertical, 2)
    }
}
