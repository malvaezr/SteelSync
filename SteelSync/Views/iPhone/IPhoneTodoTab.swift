#if STEELSYNC_IPHONE
import SwiftUI

struct IPhoneTodoTab: View {
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

    private var dueTodayCount: Int {
        dataStore.todos.filter { $0.isDueToday }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Metric cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricCard(title: "Active", value: "\(dataStore.activeTodos.count)",
                               icon: "checklist", color: .blue)
                    MetricCard(title: "Overdue", value: "\(dataStore.overdueTodos.count)",
                               icon: "exclamationmark.triangle.fill", color: .red)
                    MetricCard(title: "Due Today", value: "\(dueTodayCount)",
                               icon: "calendar.badge.exclamationmark", color: .orange)
                    MetricCard(title: "Completed", value: "\(dataStore.completedTodos.count)",
                               icon: "checkmark.circle.fill", color: .green)
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.top, AppTheme.Spacing.sm)

                // Filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(filters, id: \.self) { filter in
                            FilterPill(filter, isSelected: selectedFilter == filter) {
                                selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // Todo list
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
                            TodoRowView(todo: todo)
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
                                            systemImage: todo.isCompleted ? "arrow.uturn.backward" : "checkmark"
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
            .navigationTitle("To-Do")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddTodo = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable {
                await dataStore.pullFromCloud()
            }
            .sheet(isPresented: $showAddTodo) {
                NavigationStack {
                    AddTodoView()
                }
            }
            .sheet(item: $editingTodo) { todo in
                NavigationStack {
                    EditTodoView(todo: todo)
                }
            }
        }
    }

    // MARK: - Todo Row
    @ViewBuilder
    private func TodoRowView(todo: TodoItem) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundColor(todo.isCompleted ? .green : priorityColor(for: todo.priority))

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .strikethrough(todo.isCompleted)
                    .foregroundColor(todo.isCompleted ? .secondary : AppTheme.primaryText)
                    .fontWeight(.medium)
                    .lineLimit(2)

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

            StatusBadge(text: todo.priority.displayName, color: priorityColor(for: todo.priority))
        }
        .padding(.vertical, 4)
    }

    private func priorityColor(for priority: TodoPriority) -> Color {
        switch priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}
#endif
