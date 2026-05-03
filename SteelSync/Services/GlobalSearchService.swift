import Foundation
import SwiftUI
import CloudKit

/// Cross-module search aggregator. Given a query and the live `DataStore`,
/// returns a flat list of results grouped by entity kind. The UI layer
/// (`GlobalSearchSheet`) renders the groups and dispatches the result's
/// `action` closure on tap, which talks to `NavigationState` to jump to
/// the right place in the app.
///
/// Search is case-insensitive substring across the most-relevant fields
/// per entity. Results within each kind are capped at `perKindLimit` so the
/// list stays scannable; users tighten the query to surface more.
enum GlobalSearchService {
    static let perKindLimit = 5

    @MainActor
    static func search(_ query: String, in store: DataStore, navigation: NavigationState) -> [SearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }

        var out: [SearchResult] = []

        // Projects
        out.append(contentsOf: store.projects
            .filter { project in
                project.title.lowercased().contains(q) ||
                project.location.lowercased().contains(q) ||
                project.notes.lowercased().contains(q)
            }
            .prefix(perKindLimit)
            .map { project in
                SearchResult(
                    kind: .project,
                    title: project.title,
                    subtitle: [project.location, project.computedStatus]
                        .filter { !$0.isEmpty }.joined(separator: " · "),
                    action: { navigation.navigate(toProjectID: project.id.recordName) }
                )
            })

        // Bids
        out.append(contentsOf: store.bids
            .filter { bid in
                bid.projectName.lowercased().contains(q) ||
                bid.clientName.lowercased().contains(q) ||
                bid.address.lowercased().contains(q)
            }
            .prefix(perKindLimit)
            .map { bid in
                SearchResult(
                    kind: .bid,
                    title: bid.projectName,
                    subtitle: "\(bid.clientName) · \(bid.bidAmount.currencyFormatted) · \(bid.status.rawValue)",
                    action: { navigation.selectedSection = .bidding }
                )
            })

        // Clients
        out.append(contentsOf: store.clients
            .filter { client in
                client.name.lowercased().contains(q) ||
                client.contactName.lowercased().contains(q) ||
                client.email.lowercased().contains(q)
            }
            .prefix(perKindLimit)
            .map { client in
                SearchResult(
                    kind: .client,
                    title: client.name,
                    subtitle: [client.contactName, client.email]
                        .filter { !$0.isEmpty }.joined(separator: " · "),
                    action: { navigation.selectedSection = .clients }
                )
            })

        // Employees
        out.append(contentsOf: store.employees
            .filter { e in
                e.firstName.lowercased().contains(q) ||
                e.lastName.lowercased().contains(q) ||
                e.fullName.lowercased().contains(q)
            }
            .prefix(perKindLimit)
            .map { e in
                SearchResult(
                    kind: .employee,
                    title: e.fullName,
                    subtitle: e.employeeType.displayName,
                    action: { navigation.selectedSection = .timekeeping }
                )
            })

        // Gantt tasks
        out.append(contentsOf: store.ganttTasks
            .filter { task in
                task.name.lowercased().contains(q) ||
                task.assignedTo.lowercased().contains(q) ||
                task.notes.lowercased().contains(q)
            }
            .prefix(perKindLimit)
            .map { task in
                let projectTitle = store.projects.first(where: { $0.id.recordName == task.projectID })?.title ?? ""
                let parts = [projectTitle, task.assignedTo, "\(task.durationDays)d"]
                    .filter { !$0.isEmpty }
                return SearchResult(
                    kind: .ganttTask,
                    title: task.name,
                    subtitle: parts.joined(separator: " · "),
                    action: { navigation.selectedSection = .schedule }
                )
            })

        // Todos
        out.append(contentsOf: store.todos
            .filter { todo in
                todo.title.lowercased().contains(q) ||
                todo.notes.lowercased().contains(q)
            }
            .prefix(perKindLimit)
            .map { todo in
                SearchResult(
                    kind: .todo,
                    title: todo.title,
                    subtitle: todo.dueDate.map { "Due \($0.shortDate)" } ?? "No due date",
                    action: { navigation.selectedSection = .todo }
                )
            })

        // Change Orders (across all projects)
        var coMatches: [(co: ChangeOrder, project: Project)] = []
        for project in store.projects {
            for co in store.changeOrders(for: project.id) {
                if co.description.lowercased().contains(q) ||
                   "\(co.number)".contains(q) ||
                   co.invoiceNumber.lowercased().contains(q) {
                    coMatches.append((co, project))
                }
            }
            if coMatches.count >= perKindLimit { break }
        }
        out.append(contentsOf: coMatches.prefix(perKindLimit).map { pair in
            SearchResult(
                kind: .changeOrder,
                title: "CO #\(pair.co.number) — \(pair.co.description.isEmpty ? "(no title)" : pair.co.description)",
                subtitle: "\(pair.project.title) · \(pair.co.amount.currencyFormatted)",
                action: { navigation.navigate(toProjectID: pair.project.id.recordName) }
            )
        })

        // Invoices (across all projects)
        out.append(contentsOf: store.allInvoices
            .filter { ctx in
                ctx.invoice.invoiceNumber.lowercased().contains(q) ||
                ctx.invoice.clientName.lowercased().contains(q) ||
                ctx.projectTitle.lowercased().contains(q)
            }
            .prefix(perKindLimit)
            .map { ctx in
                SearchResult(
                    kind: .invoice,
                    title: "Inv #\(ctx.invoice.invoiceNumber)",
                    subtitle: "\(ctx.projectTitle) · \(ctx.invoice.netAmountDue.currencyFormatted) · \(ctx.invoice.status.rawValue)",
                    action: { navigation.selectedSection = .invoices }
                )
            })

        // RFIs (across all projects)
        var rfiMatches: [(rfi: RFI, project: Project)] = []
        for project in store.projects {
            for rfi in store.rfis(for: project.id) {
                if rfi.subject.lowercased().contains(q) ||
                   "\(rfi.number)".contains(q) {
                    rfiMatches.append((rfi, project))
                }
            }
            if rfiMatches.count >= perKindLimit { break }
        }
        out.append(contentsOf: rfiMatches.prefix(perKindLimit).map { pair in
            SearchResult(
                kind: .rfi,
                title: "RFI #\(pair.rfi.number) — \(pair.rfi.subject)",
                subtitle: "\(pair.project.title) · \(pair.rfi.status.rawValue)",
                action: { navigation.selectedSection = .rfis }
            )
        })

        // Overhead
        out.append(contentsOf: store.overheadExpenses
            .filter { expense in
                expense.vendor.lowercased().contains(q) ||
                expense.expenseDescription.lowercased().contains(q) ||
                expense.category.rawValue.lowercased().contains(q)
            }
            .prefix(perKindLimit)
            .map { expense in
                let label = expense.expenseDescription.isEmpty ? expense.category.rawValue : expense.expenseDescription
                return SearchResult(
                    kind: .overhead,
                    title: label,
                    subtitle: "\(expense.vendor) · \(expense.amount.currencyFormatted) · \(expense.date.shortDate)",
                    action: { navigation.selectedSection = .overhead }
                )
            })

        return out
    }
}

// MARK: - Search Result Types

struct SearchResult: Identifiable {
    let id = UUID()
    let kind: ResultKind
    let title: String
    let subtitle: String
    let action: () -> Void
}

enum ResultKind: String, CaseIterable {
    case project = "Projects"
    case bid = "Bids"
    case client = "Clients"
    case employee = "Employees"
    case ganttTask = "Schedule Tasks"
    case todo = "To-Dos"
    case changeOrder = "Change Orders"
    case invoice = "Invoices"
    case rfi = "RFIs"
    case overhead = "Overhead"

    var icon: String {
        switch self {
        case .project: return "building.2.fill"
        case .bid: return "doc.text.fill"
        case .client: return "person.2.fill"
        case .employee: return "person.crop.rectangle.fill"
        case .ganttTask: return "calendar.day.timeline.left"
        case .todo: return "checklist"
        case .changeOrder: return "arrow.triangle.branch"
        case .invoice: return "doc.plaintext.fill"
        case .rfi: return "questionmark.bubble.fill"
        case .overhead: return "briefcase.fill"
        }
    }

    var tint: Color {
        switch self {
        case .project: return AppTheme.primaryOrange
        case .bid: return .blue
        case .client: return .purple
        case .employee: return .indigo
        case .ganttTask: return .teal
        case .todo: return .green
        case .changeOrder: return .orange
        case .invoice: return .cyan
        case .rfi: return .pink
        case .overhead: return .brown
        }
    }
}
