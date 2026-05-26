import SwiftUI
import CloudKit

/// Morning briefing screen. The first thing a PM/APM sees when they open the app.
/// Aggregates everything that needs attention so they don't have to visit 4 sections.
/// Read-only — clicking any section card jumps to the relevant top-level view.
struct TodayView: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var navigationState: NavigationState

    @State private var showQuickEntryProjectPicker = false
    @State private var quickEntryProject: Project?
    @State private var now = Date()

    /// Refresh "now" once a minute so relative dates stay accurate.
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                ScreenHeader(
                    title: greeting,
                    subtitle: now.formatted("EEEE, MMMM d, yyyy"),
                    icon: AppIcons.calendar
                ) {
                    Button {
                        showQuickEntryProjectPicker = true
                    } label: {
                        Label("Quick Entry", systemImage: AppIcons.add)
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(dataStore.projects.isEmpty)
                }
                .padding(.horizontal, -AppTheme.Spacing.lg)
                .padding(.top, -AppTheme.Spacing.lg)

                attentionSummary

                if hasAnythingOverdue {
                    overdueSection
                }

                upcomingSection

                staleBidsSection

                recentActivitySection

                if !hasAnythingOverdue && !hasUpcoming && staleBids.isEmpty && recentActivity.isEmpty {
                    allCaughtUpView
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .background(AppTheme.background)
        .onReceive(timer) { value in now = value }
        .sheet(isPresented: $showQuickEntryProjectPicker) {
            QuickEntryProjectPicker(onPick: { project in
                quickEntryProject = project
                showQuickEntryProjectPicker = false
            })
        }
        .sheet(item: $quickEntryProject) { project in
            QuickEntrySheet(project: project)
        }
    }

    // MARK: - Greeting

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default: return "Working Late"
        }
    }

    // MARK: - Attention Summary (top metric strip)

    private var attentionSummary: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                AttentionCard(
                    title: "Overdue Tasks",
                    count: dataStore.overdueTodos.count,
                    icon: "exclamationmark.circle.fill",
                    color: .red
                ) { navigationState.selectedSection = .todo }

                AttentionCard(
                    title: "Overdue Schedule",
                    count: overdueGanttTasks.count,
                    icon: "calendar.badge.exclamationmark",
                    color: .red
                ) { navigationState.selectedSection = .schedule }

                AttentionCard(
                    title: "Overdue RFIs",
                    count: overdueRFIs.count,
                    icon: "questionmark.bubble.fill",
                    color: .orange
                ) { navigationState.selectedSection = .rfis }

                AttentionCard(
                    title: "Overdue Invoices",
                    count: overdueInvoices.count,
                    icon: "doc.text.fill",
                    color: .red
                ) { navigationState.selectedSection = .invoices }

                AttentionCard(
                    title: "Milestones (7 days)",
                    count: upcomingGanttTasks.count,
                    icon: "flag.fill",
                    color: AppTheme.primaryOrange
                ) { navigationState.selectedSection = .schedule }

                AttentionCard(
                    title: "Stale Bids",
                    count: staleBids.count,
                    icon: "clock.badge.exclamationmark",
                    color: .blue
                ) { navigationState.selectedSection = .bidding }
            }
        }
    }

    // MARK: - Overdue Section

    private var overdueSection: some View {
        SectionCard(title: "Needs Attention", icon: "exclamationmark.triangle.fill", tint: .red) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                ForEach(dataStore.overdueTodos.prefix(5)) { todo in
                    BriefingRow(
                        title: todo.title,
                        subtitle: todoSubtitle(todo),
                        reason: todoReason(todo),
                        reasonColor: .red,
                        icon: "checklist",
                        color: .red
                    ) { navigationState.selectedSection = .todo }
                }
                ForEach(overdueGanttTasks.prefix(5), id: \.id) { task in
                    let projectName = projectTitle(for: task.projectID)
                    BriefingRow(
                        title: task.name,
                        subtitle: "\(projectName) · \(Int(task.progress * 100))% complete",
                        reason: ganttOverdueReason(task),
                        reasonColor: .red,
                        icon: "calendar",
                        color: .red
                    ) { navigationState.selectedSection = .schedule }
                }
                ForEach(overdueRFIs.prefix(5), id: \.rfi.id) { entry in
                    BriefingRow(
                        title: "RFI #\(entry.rfi.number) — \(entry.rfi.subject)",
                        subtitle: "\(entry.projectName) · Sent to \(entry.rfi.submittedTo.isEmpty ? "—" : entry.rfi.submittedTo)",
                        reason: rfiOverdueReason(entry.rfi),
                        reasonColor: .red,
                        icon: "questionmark.bubble.fill",
                        color: .red
                    ) { navigationState.selectedSection = .rfis }
                }
                ForEach(overdueInvoices.prefix(5), id: \.invoice.id) { entry in
                    BriefingRow(
                        title: "Invoice \(entry.invoice.invoiceNumber)",
                        subtitle: "\(entry.projectTitle) · \(dataStore.balanceRemaining(for: entry.invoice).currencyFormatted) outstanding",
                        reason: "\(entry.invoice.daysOverdue)d late",
                        reasonColor: .red,
                        icon: "doc.text.fill",
                        color: .red
                    ) { navigationState.selectedSection = .invoices }
                }
            }
        }
    }

    // MARK: - Upcoming Section

    private var upcomingSection: some View {
        SectionCard(title: "Upcoming (Next 7 Days)", icon: "calendar", tint: AppTheme.primaryOrange) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                if upcomingGanttTasks.isEmpty {
                    Text("Nothing scheduled in the next 7 days.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(upcomingGanttTasks.prefix(8), id: \.id) { task in
                        let projectName = projectTitle(for: task.projectID)
                        BriefingRow(
                            title: task.name,
                            subtitle: "\(projectName) · \(task.durationDays)d task · \(task.category.rawValue)",
                            reason: upcomingReason(task),
                            reasonColor: task.status == .milestone ? .purple : AppTheme.primaryOrange,
                            icon: task.status == .milestone ? "diamond.fill" : "calendar",
                            color: task.status == .milestone ? .purple : AppTheme.primaryOrange
                        ) { navigationState.selectedSection = .schedule }
                    }
                }
            }
        }
    }

    // MARK: - Stale Bids Section

    private var staleBidsSection: some View {
        Group {
            if !staleBids.isEmpty {
                SectionCard(title: "Bids Needing Follow-Up", icon: "clock.badge.exclamationmark", tint: .blue) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        ForEach(staleBids.prefix(5)) { bid in
                            let submitted = bid.submittedDate ?? bid.createdDate
                            let days = Int(now.timeIntervalSince(submitted) / 86_400)
                            BriefingRow(
                                title: bid.projectName,
                                subtitle: "\(bid.clientName) · \(bid.bidAmount.currencyFormatted) · Due \(bid.bidDueDate.formatted("MMM d"))",
                                reason: "No response · \(days)d",
                                reasonColor: .blue,
                                icon: "doc.text.fill",
                                color: .blue
                            ) { navigationState.selectedSection = .bidding }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reason / subtitle helpers

    /// Primary "why" label for an overdue todo.
    private func todoReason(_ todo: TodoItem) -> String {
        guard let due = todo.dueDate else { return "No due date" }
        let days = daysBetween(due, now)
        if days == 0 { return "Due today" }
        if days == 1 { return "1d overdue" }
        return "\(days)d overdue"
    }

    private func todoSubtitle(_ todo: TodoItem) -> String {
        var parts: [String] = [todo.priority.displayName]
        if let pid = todo.relatedProjectID, let title = dataStore.projects.first(where: { $0.id.recordName == pid })?.title {
            parts.append(title)
        }
        if let due = todo.dueDate {
            parts.append("Was due \(due.formatted("MMM d"))")
        }
        return parts.joined(separator: " · ")
    }

    private func ganttOverdueReason(_ task: GanttTask) -> String {
        let days = daysBetween(task.endDate, now)
        if task.progress >= 1.0 { return "Not closed" }
        if days == 0 { return "Ended today" }
        if days == 1 { return "1d overdue" }
        return "\(days)d overdue"
    }

    private func rfiOverdueReason(_ rfi: RFI) -> String {
        let days = daysBetween(rfi.responseDueDate, now)
        if days == 0 { return "Response due today" }
        if days == 1 { return "1d late" }
        return "\(days)d late"
    }

    private func upcomingReason(_ task: GanttTask) -> String {
        let days = daysBetween(now, task.startDate)
        if days == 0 { return "Starts today" }
        if days == 1 { return "Starts tomorrow" }
        return "In \(days)d"
    }

    /// Calendar-day difference, always returned as non-negative.
    private func daysBetween(_ earlier: Date, _ later: Date) -> Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.day], from: cal.startOfDay(for: earlier), to: cal.startOfDay(for: later))
        return max(0, comps.day ?? 0)
    }

    // MARK: - Recent Activity

    private var recentActivitySection: some View {
        Group {
            if !recentActivity.isEmpty {
                SectionCard(title: "Last 24 Hours", icon: "clock.arrow.circlepath", tint: .gray) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        ForEach(recentActivity.prefix(6), id: \.id) { entry in
                            BriefingRow(
                                title: entry.entityDescription,
                                subtitle: "\(entry.action.rawValue) \(entry.entityType) — \(entry.timestamp.formatted("h:mm a"))",
                                icon: AppIcons.history,
                                color: .gray
                            ) { navigationState.selectedSection = .activity }
                        }
                    }
                }
            }
        }
    }

    // MARK: - All-Caught-Up

    private var allCaughtUpView: some View {
        VStack(spacing: AppTheme.Spacing.md) {
            Spacer().frame(height: 40)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            Text("You're all caught up.")
                .font(AppTheme.Typography.title2)
            Text("Nothing overdue, no upcoming milestones in the next 7 days, and no stale bids. Use Quick Entry to log new costs or payroll.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppTheme.Spacing.lg)
    }

    // MARK: - Computed data slices

    private var hasAnythingOverdue: Bool {
        !dataStore.overdueTodos.isEmpty || !overdueGanttTasks.isEmpty || !overdueRFIs.isEmpty || !overdueInvoices.isEmpty
    }

    private var overdueInvoices: [(invoice: Invoice, projectTitle: String)] {
        dataStore.allInvoices
            .filter { $0.invoice.isOverdue }
            .map { (invoice: $0.invoice, projectTitle: $0.projectTitle) }
            .sorted { $0.invoice.daysOverdue > $1.invoice.daysOverdue }
    }

    private var hasUpcoming: Bool {
        !upcomingGanttTasks.isEmpty
    }

    private var overdueGanttTasks: [GanttTask] {
        dataStore.ganttTasks
            .filter { $0.endDate < now && $0.status != .completed }
            .sorted { $0.endDate < $1.endDate }
    }

    private var upcomingGanttTasks: [GanttTask] {
        let cal = Calendar.current
        let weekOut = cal.date(byAdding: .day, value: 7, to: now) ?? now
        return dataStore.ganttTasks
            .filter { $0.status != .completed && $0.startDate >= now && $0.startDate <= weekOut }
            .sorted { $0.startDate < $1.startDate }
    }

    private var overdueRFIs: [(rfi: RFI, projectName: String)] {
        var result: [(RFI, String)] = []
        for project in dataStore.projects {
            for rfi in dataStore.rfis(for: project.id) where rfi.isOverdue {
                result.append((rfi, project.title))
            }
        }
        return result.sorted { $0.0.responseDueDate < $1.0.responseDueDate }
    }

    private var staleBids: [BidProject] {
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        return dataStore.bids
            .filter { $0.status == .submitted && ($0.submittedDate ?? $0.createdDate) <= twoWeeksAgo }
            .sorted { ($0.submittedDate ?? $0.createdDate) < ($1.submittedDate ?? $1.createdDate) }
    }

    private var recentActivity: [AuditEntry] {
        let cutoff = Calendar.current.date(byAdding: .hour, value: -24, to: now) ?? now
        return dataStore.auditLog
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func projectTitle(for projectID: String) -> String {
        dataStore.projects.first { $0.id.recordName == projectID }?.title ?? "Unknown Project"
    }
}

// MARK: - Supporting types

private struct AttentionCounts {
    let overdueTodos: Int
    let overdueGantt: Int
    let overdueRFIs: Int
    let upcomingMilestones: Int
    let staleBids: Int
}

private struct AttentionCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 4) {
                    // Metric — 28/600 mono. Urgent (non-zero) figures take the
                    // single accent per the design's "one accent" rule.
                    Text("\(count)")
                        .font(.system(size: 28, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(count > 0 ? AppTheme.primaryOrange : AppTheme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                GlassChip(systemImage: icon, color: color)
            }
            .frame(width: 150, alignment: .leading)
            .padding(16)
            .appPanel(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppTheme.primaryText)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
            content()
        }
        .padding(.bottom, 4)
        .appPanel(cornerRadius: 16)
    }
}

private struct BriefingRow: View {
    let title: String
    let subtitle: String
    var reason: String? = nil
    var reasonColor: Color = .secondary
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                GlassChip(systemImage: icon, color: color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let reason = reason, !reason.isEmpty {
                    Text(reason)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundColor(reasonColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(reasonColor.opacity(0.18)))
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(AppTheme.tertiaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .appRow(cornerRadius: 12)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Quick Entry Project Picker

private struct QuickEntryProjectPicker: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    let onPick: (Project) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Choose a project for quick entry") {
                    ForEach(dataStore.activeProjects) { project in
                        Button {
                            onPick(project)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.title)
                                        .font(.callout)
                                        .foregroundColor(.primary)
                                    if !project.location.isEmpty {
                                        Text(project.location)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Quick Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .frame(minWidth: 400, minHeight: 400)
        }
    }
}
