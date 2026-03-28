import SwiftUI

struct PhoneDashboardView: View {
    @EnvironmentObject var dataStore: DataStore

    private var overdueTodos: [TodoItem] {
        dataStore.overdueTodos.sorted { ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
    }

    private var upcomingDeadlineProjects: [Project] {
        let sevenDaysOut = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return dataStore.activeProjects.filter { project in
            guard let end = project.endDate else { return false }
            return end >= Date() && end <= sevenDaysOut
        }.sorted { ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // MARK: - Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SteelSync Field")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(Date(), style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "building.2.fill")
                        .font(.title3)
                        .foregroundColor(AppTheme.primaryOrange)
                }
                .padding(.horizontal)

                // MARK: - Quick Metrics
                HStack(spacing: 10) {
                        QuickMetricTile(icon: "hammer.fill", value: "\(dataStore.activeProjects.count)", label: "Active", color: AppTheme.primaryGreen)
                        QuickMetricTile(icon: "clock.fill", value: "0h", label: "Hours", color: AppTheme.primaryOrange)
                        QuickMetricTile(icon: "checklist", value: "\(dataStore.activeTodos.count)", label: "Tasks", color: .blue)
                    }
                    .padding(.horizontal)

                    // MARK: - Financials
                    VStack(spacing: 8) {
                        HStack {
                            Text("Financials")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(AppTheme.secondaryText)
                                .textCase(.uppercase)
                            Spacer()
                        }
                        HStack(spacing: 0) {
                            FinancialCell(label: "Revenue", value: dataStore.totalRevenue.currencyFormatted, color: .green)
                            FinancialCell(label: "Profit", value: dataStore.totalProfit.currencyFormatted, color: AppTheme.primaryOrange)
                            FinancialCell(label: "Pipeline", value: dataStore.totalBidPipeline.currencyFormatted, color: .blue)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal)

                    // MARK: - Active Projects
                    SectionCard(title: "Active Projects", count: dataStore.activeProjects.count) {
                        if dataStore.activeProjects.isEmpty {
                            EmptyRow(icon: "folder", text: "No active projects")
                        } else {
                            ForEach(dataStore.activeProjects) { project in
                                DashboardProjectRow(project: project, clientName: dataStore.clientName(for: project),
                                                hasGanttTasks: dataStore.ganttTasks.contains { $0.projectID == project.id.recordName })
                                if project.id != dataStore.activeProjects.last?.id {
                                    Divider().padding(.leading)
                                }
                            }
                        }
                    }

                    // MARK: - Overdue Tasks
                    if !overdueTodos.isEmpty {
                        SectionCard(title: "Overdue Tasks", count: overdueTodos.count, titleColor: .red) {
                            ForEach(overdueTodos) { todo in
                                OverdueTaskRow(todo: todo)
                                if todo.id != overdueTodos.last?.id {
                                    Divider().padding(.leading)
                                }
                            }
                        }
                    }

                    // MARK: - Upcoming Deadlines
                    if !upcomingDeadlineProjects.isEmpty {
                        SectionCard(title: "Upcoming Deadlines", count: upcomingDeadlineProjects.count) {
                            ForEach(upcomingDeadlineProjects) { project in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(project.title)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        if let end = project.endDate {
                                            let daysLeft = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
                                            Text("\(daysLeft)d remaining")
                                                .font(.caption)
                                                .foregroundColor(daysLeft <= 2 ? .red : .orange)
                                        }
                                    }
                                    Spacer()
                                    if let end = project.endDate {
                                        Text(end.shortDate)
                                            .font(.caption)
                                            .foregroundColor(AppTheme.secondaryText)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.bottom, 80) // space for tab bar
            }
            .refreshable {
                if dataStore.cloudKitAvailable {
                    await dataStore.pullFromCloud()
                }
            }
    }
}

// MARK: - Section Card Container

private struct SectionCard<Content: View>: View {
    let title: String
    var count: Int = 0
    var titleColor: Color = .secondary
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(titleColor)
                    .textCase(.uppercase)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(titleColor.opacity(0.2))
                        .foregroundColor(titleColor)
                        .clipShape(Capsule())
                }
                Spacer()
            }
            VStack(spacing: 0) {
                content()
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal)
    }
}

// MARK: - Financial Cell

private struct FinancialCell: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Quick Metric Tile

private struct QuickMetricTile: View {
    let icon: String
    let value: String
    let label: String
    var color: Color = AppTheme.primaryOrange

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Dashboard Project Row

private struct DashboardProjectRow: View {
    let project: Project
    let clientName: String?
    var hasGanttTasks: Bool = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(project.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if hasGanttTasks {
                        Image(systemName: "calendar.day.timeline.left")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.primaryOrange)
                    }
                }
                if let name = clientName {
                    Text(name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(project.contractAmount.currencyFormatted)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.primaryOrange)
                StatusBadge(text: project.computedStatus, color: statusColor(for: project.computedStatus))
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Overdue Task Row

private struct OverdueTaskRow: View {
    let todo: TodoItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.caption)
            VStack(alignment: .leading, spacing: 1) {
                Text(todo.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let due = todo.dueDate {
                    Text("Due: \(due.shortDate)")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty Row

private struct EmptyRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            Spacer()
        }
    }
}

// MARK: - Helpers

private func statusColor(for status: String) -> Color {
    switch status {
    case "Active": return AppTheme.ProjectStatus.active
    case "Upcoming": return AppTheme.ProjectStatus.upcoming
    case "Completed": return AppTheme.ProjectStatus.completed
    default: return AppTheme.ProjectStatus.onHold
    }
}
