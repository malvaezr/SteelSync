import AppIntents
import Foundation

// MARK: - Add Todo Shortcut

struct AddTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Task"
    static var description = IntentDescription("Add a new task to SteelSync Field")
    static var openAppWhenRun = false

    @Parameter(title: "Task Title")
    var title: String

    @Parameter(title: "Priority", default: .medium)
    var priority: TaskPriorityEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = await DataStore.shared
        let todoPriority: TodoPriority = switch priority {
        case .low: .low
        case .medium: .medium
        case .high: .high
        case .urgent: .urgent
        }
        let todo = TodoItem(title: title, priority: todoPriority)
        await store.addTodo(todo)
        return .result(dialog: "Added '\(title)' to your tasks.")
    }
}

// MARK: - Check Off Task Shortcut

struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var description = IntentDescription("Mark a task as completed in SteelSync Field")
    static var openAppWhenRun = false

    @Parameter(title: "Task Name")
    var taskName: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = await DataStore.shared
        let todos = await store.activeTodos
        guard let todo = todos.first(where: { $0.title.localizedCaseInsensitiveContains(taskName) }) else {
            return .result(dialog: "No active task found matching '\(taskName)'.")
        }
        await store.toggleTodo(todo)
        return .result(dialog: "Completed '\(todo.title)'.")
    }
}

// MARK: - Project Status Shortcut

struct ProjectStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Project Status"
    static var description = IntentDescription("Get a quick summary of your SteelSync projects")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = await DataStore.shared
        let active = await store.activeProjects.count
        let overdue = await store.overdueTodos.count
        let upcoming = await store.upcomingProjects.count

        var summary = "\(active) active project\(active == 1 ? "" : "s")"
        if upcoming > 0 { summary += ", \(upcoming) upcoming" }
        if overdue > 0 { summary += ". \(overdue) overdue task\(overdue == 1 ? "" : "s")!" }
        else { summary += ". No overdue tasks." }

        return .result(dialog: "\(summary)")
    }
}

// MARK: - Priority Entity

enum TaskPriorityEntity: String, AppEnum {
    case low, medium, high, urgent

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Priority")
    static var caseDisplayRepresentations: [TaskPriorityEntity: DisplayRepresentation] = [
        .low: "Low",
        .medium: "Medium",
        .high: "High",
        .urgent: "Urgent"
    ]
}

// MARK: - Shortcuts Provider

struct SteelSyncShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTodoIntent(),
            phrases: [
                "Add a task in \(.applicationName)",
                "New task in \(.applicationName)",
                "Add todo in \(.applicationName)"
            ],
            shortTitle: "Add Task",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: [
                "Complete a task in \(.applicationName)",
                "Check off task in \(.applicationName)",
                "Mark task done in \(.applicationName)"
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: ProjectStatusIntent(),
            phrases: [
                "Project status in \(.applicationName)",
                "How are my projects in \(.applicationName)",
                "Check status in \(.applicationName)"
            ],
            shortTitle: "Project Status",
            systemImageName: "building.2.fill"
        )
    }
}

// MARK: - Shared DataStore accessor (Phone target only)

extension DataStore: @unchecked Sendable {
    @MainActor
    static let shared = DataStore()
}
