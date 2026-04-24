import SwiftUI
import CloudKit

/// Morning briefing for SteelSync Field. Mobile adaptation of the Mac TodayView.
/// Single-column layout with a greeting header, attention strip, and sectioned
/// briefing rows with "why it needs attention" pills.
struct PhoneTodayView: View {
    @EnvironmentObject var dataStore: DataStore
    @Binding var selectedTab: PhoneContentView.Tab
    @Binding var moreDestination: PhoneContentView.MoreDestination?

    @State private var now = Date()
    @State private var showQuickEntryPicker = false
    @State private var quickEntryProject: Project?

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    greetingHeader

                    attentionStrip

                    quickEntryButton

                    if hasOverdue {
                        overdueSection
                    }

                    if !upcomingGanttTasks.isEmpty {
                        upcomingSection
                    }

                    if !staleBids.isEmpty {
                        staleBidsSection
                    }

                    if !hasOverdue && upcomingGanttTasks.isEmpty && staleBids.isEmpty {
                        allCaughtUpView
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(AppTheme.background.ignoresSafeArea())
            .refreshable {
                await dataStore.pullFromCloud()
                now = Date()
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .onReceive(timer) { value in now = value }
            .sheet(isPresented: $showQuickEntryPicker) {
                PhoneQuickEntryPicker { project in
                    quickEntryProject = project
                    showQuickEntryPicker = false
                }
                .environmentObject(dataStore)
            }
            .sheet(item: $quickEntryProject) { project in
                QuickEntrySheet(project: project)
                    .environmentObject(dataStore)
            }
        }
    }

    // MARK: - Greeting

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greeting)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppTheme.primaryText)
            Text(dateString)
                .font(.subheadline)
                .foregroundColor(AppTheme.secondaryText)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<12: return "Good Morning"
        case 12..<17: return "Good Afternoon"
        case 17..<22: return "Good Evening"
        default: return "Working Late"
        }
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE · MMMM d"
        return f.string(from: now)
    }

    // MARK: - Attention Strip

    private var attentionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                attentionCard("Overdue Tasks", count: dataStore.overdueTodos.count, icon: "exclamationmark.circle.fill", color: .red) {
                    selectedTab = .tasks
                }
                attentionCard("Overdue Schedule", count: overdueGanttTasks.count, icon: "calendar.badge.exclamationmark", color: .red) {
                    // Phone doesn't have a full Gantt view; jump to Projects
                    selectedTab = .projects
                }
                attentionCard("Overdue RFIs", count: overdueRFIs.count, icon: "questionmark.bubble.fill", color: .orange) {
                    moreDestination = .rfis
                    selectedTab = .more
                }
                attentionCard("Overdue Invoices", count: overdueInvoices.count, icon: "doc.text.fill", color: .red) {
                    moreDestination = .invoices
                    selectedTab = .more
                }
                attentionCard("Milestones (7d)", count: upcomingGanttTasks.count, icon: "flag.fill", color: AppTheme.primaryOrange) {
                    selectedTab = .projects
                }
                attentionCard("Stale Bids", count: staleBids.count, icon: "clock.badge.exclamationmark", color: .blue) {
                    // Bidding is not in tabs; surface through Projects / leave inline
                    selectedTab = .projects
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func attentionCard(_ title: String, count: Int, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
                Text("\(count)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(count > 0 ? AppTheme.primaryText : AppTheme.tertiaryText)
                Text(title)
                    .font(.caption2)
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: 130, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.secondaryBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(count > 0 ? color.opacity(0.35) : Color.gray.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quick Entry

    private var quickEntryButton: some View {
        Button {
            showQuickEntryPicker = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Quick Entry")
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(AppTheme.primaryOrange)
            )
            .foregroundColor(.white)
        }
        .disabled(dataStore.projects.isEmpty)
    }

    // MARK: - Overdue Section

    private var hasOverdue: Bool {
        !dataStore.overdueTodos.isEmpty
            || !overdueGanttTasks.isEmpty
            || !overdueRFIs.isEmpty
            || !overdueInvoices.isEmpty
    }

    private var overdueSection: some View {
        sectionCard(title: "Needs Attention", icon: "exclamationmark.triangle.fill", tint: .red) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(dataStore.overdueTodos.prefix(5)) { todo in
                    briefingRow(
                        title: todo.title,
                        subtitle: todoSubtitle(todo),
                        reason: todoReason(todo),
                        reasonColor: .red,
                        icon: "checklist"
                    ) { selectedTab = .tasks }
                }
                ForEach(overdueGanttTasks.prefix(5), id: \.id) { task in
                    briefingRow(
                        title: task.name,
                        subtitle: "\(projectTitle(for: task.projectID)) · \(Int(task.progress * 100))% complete",
                        reason: ganttOverdueReason(task),
                        reasonColor: .red,
                        icon: "calendar"
                    ) { selectedTab = .projects }
                }
                ForEach(overdueRFIs.prefix(5), id: \.rfi.id) { entry in
                    briefingRow(
                        title: "RFI #\(entry.rfi.number) — \(entry.rfi.subject)",
                        subtitle: "\(entry.projectName) · Sent to \(entry.rfi.submittedTo.isEmpty ? "—" : entry.rfi.submittedTo)",
                        reason: "\(daysBetween(entry.rfi.responseDueDate, now))d late",
                        reasonColor: .red,
                        icon: "questionmark.bubble.fill"
                    ) {
                        moreDestination = .rfis
                        selectedTab = .more
                    }
                }
                ForEach(overdueInvoices.prefix(5), id: \.invoice.id) { entry in
                    briefingRow(
                        title: "Invoice \(entry.invoice.invoiceNumber)",
                        subtitle: "\(entry.projectTitle) · \(dataStore.balanceRemaining(for: entry.invoice).currencyFormatted) outstanding",
                        reason: "\(entry.invoice.daysOverdue)d late",
                        reasonColor: .red,
                        icon: "doc.text.fill"
                    ) {
                        moreDestination = .invoices
                        selectedTab = .more
                    }
                }
            }
        }
    }

    // MARK: - Upcoming Section

    private var upcomingSection: some View {
        sectionCard(title: "Upcoming (Next 7 Days)", icon: "calendar", tint: AppTheme.primaryOrange) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(upcomingGanttTasks.prefix(6), id: \.id) { task in
                    briefingRow(
                        title: task.name,
                        subtitle: "\(projectTitle(for: task.projectID)) · \(task.durationDays)d task",
                        reason: upcomingReason(task),
                        reasonColor: task.status == .milestone ? .purple : AppTheme.primaryOrange,
                        icon: task.status == .milestone ? "diamond.fill" : "calendar"
                    ) { selectedTab = .projects }
                }
            }
        }
    }

    // MARK: - Stale Bids Section

    private var staleBidsSection: some View {
        sectionCard(title: "Bids Needing Follow-Up", icon: "clock.badge.exclamationmark", tint: .blue) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(staleBids.prefix(5)) { bid in
                    let submitted = bid.submittedDate ?? bid.createdDate
                    let days = Int(now.timeIntervalSince(submitted) / 86_400)
                    briefingRow(
                        title: bid.projectName,
                        subtitle: "\(bid.clientName) · \(bid.bidAmount.currencyFormatted)",
                        reason: "\(days)d no response",
                        reasonColor: .blue,
                        icon: "doc.text.fill"
                    ) { selectedTab = .projects }
                }
            }
        }
    }

    // MARK: - All caught up

    private var allCaughtUpView: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 40)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundColor(.green)
            Text("You're all caught up.")
                .font(.title3)
                .fontWeight(.semibold)
            Text("Nothing overdue, no upcoming milestones in the next 7 days, and no stale bids.")
                .font(.subheadline)
                .foregroundColor(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    // MARK: - Section card builder

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundColor(tint)
                Text(title)
                    .font(.headline)
                Spacer()
            }
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppTheme.secondaryBackground)
        )
    }

    // MARK: - Briefing row

    private func briefingRow(
        title: String,
        subtitle: String,
        reason: String,
        reasonColor: Color,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(reasonColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout)
                        .foregroundColor(AppTheme.primaryText)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(reason)
                    .font(.caption2.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundColor(reasonColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(reasonColor.opacity(0.15))
                    )
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    // MARK: - Reason helpers

    private func todoReason(_ todo: TodoItem) -> String {
        guard let due = todo.dueDate else { return "No due date" }
        let days = daysBetween(due, now)
        if days == 0 { return "Due today" }
        if days == 1 { return "1d overdue" }
        return "\(days)d overdue"
    }

    private func todoSubtitle(_ todo: TodoItem) -> String {
        var parts: [String] = [todo.priority.displayName]
        if let pid = todo.relatedProjectID,
           let title = dataStore.projects.first(where: { $0.id.recordName == pid })?.title {
            parts.append(title)
        }
        return parts.joined(separator: " · ")
    }

    private func ganttOverdueReason(_ task: GanttTask) -> String {
        let days = daysBetween(task.endDate, now)
        if days == 0 { return "Ended today" }
        if days == 1 { return "1d overdue" }
        return "\(days)d overdue"
    }

    private func upcomingReason(_ task: GanttTask) -> String {
        let days = daysBetween(now, task.startDate)
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "In \(days)d"
    }

    private func daysBetween(_ earlier: Date, _ later: Date) -> Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.day], from: cal.startOfDay(for: earlier), to: cal.startOfDay(for: later))
        return max(0, comps.day ?? 0)
    }

    // MARK: - Data slices

    private var overdueGanttTasks: [GanttTask] {
        dataStore.ganttTasks
            .filter { $0.endDate < now && $0.status != .completed }
            .sorted { $0.endDate < $1.endDate }
    }

    private var upcomingGanttTasks: [GanttTask] {
        let weekOut = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
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

    private var overdueInvoices: [(invoice: Invoice, projectTitle: String)] {
        dataStore.allInvoices
            .filter { $0.invoice.isOverdue }
            .map { (invoice: $0.invoice, projectTitle: $0.projectTitle) }
            .sorted { $0.invoice.daysOverdue > $1.invoice.daysOverdue }
    }

    private var staleBids: [BidProject] {
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        return dataStore.bids
            .filter { $0.status == .submitted && ($0.submittedDate ?? $0.createdDate) <= twoWeeksAgo }
            .sorted { ($0.submittedDate ?? $0.createdDate) < ($1.submittedDate ?? $1.createdDate) }
    }

    private func projectTitle(for projectID: String) -> String {
        dataStore.projects.first { $0.id.recordName == projectID }?.title ?? "Unknown"
    }
}

// MARK: - Quick Entry Picker

private struct PhoneQuickEntryPicker: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss
    let onPick: (Project) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Pick a project") {
                    ForEach(dataStore.activeProjects) { project in
                        Button {
                            onPick(project)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.title)
                                        .font(.callout)
                                        .foregroundColor(AppTheme.primaryText)
                                    if !project.location.isEmpty {
                                        Text(project.location)
                                            .font(.caption)
                                            .foregroundColor(AppTheme.secondaryText)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
