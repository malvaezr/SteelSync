import SwiftUI
import CloudKit

/// Top-level cross-project RFI log. Promoted from ProjectDetailView so PMs can
/// triage RFIs across all projects in one place. Reuses AddRFISheet / EditRFISheet
/// from the existing project-detail flow.
struct RFILogView: View {
    @EnvironmentObject var dataStore: DataStore

    @State private var statusFilter: RFIStatusFilter = .open
    @State private var projectFilter: String = "All"
    @State private var searchText: String = ""
    @State private var editingRFI: ProjectRFI?
    @State private var showAddSheet = false
    @State private var addProject: Project?
    @State private var rfiToDelete: ProjectRFI?

    enum RFIStatusFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case open = "Open"
        case overdue = "Overdue"
        case responded = "Responded"
        case closed = "Closed"
        var id: String { rawValue }
    }

    /// Pairs an RFI with its parent project context.
    struct ProjectRFI: Identifiable, Hashable {
        let rfi: RFI
        let projectID: CKRecord.ID
        let projectTitle: String
        var id: UUID { rfi.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "RFI Log",
                subtitle: subtitle,
                icon: AppIcons.document
            ) {
                Button {
                    if let first = dataStore.projects.first {
                        addProject = first
                        showAddSheet = true
                    }
                } label: {
                    Label("New RFI", systemImage: AppIcons.add)
                }
                .buttonStyle(.appPrimary)
                .disabled(dataStore.projects.isEmpty)
            }

            // Metric strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    MetricCard(title: "Open", value: "\(allRFIs.filter { $0.rfi.status != .closed }.count)",
                               icon: "questionmark.bubble.fill", color: .blue)
                    MetricCard(title: "Overdue", value: "\(allRFIs.filter { $0.rfi.isOverdue }.count)",
                               icon: AppIcons.warning, color: .red)
                    MetricCard(title: "Responded", value: "\(allRFIs.filter { $0.rfi.status == .responded }.count)",
                               icon: AppIcons.success, color: .orange)
                    MetricCard(title: "Closed", value: "\(allRFIs.filter { $0.rfi.status == .closed }.count)",
                               icon: "lock.fill", color: .green)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
                .padding(.vertical, AppTheme.Spacing.sm)
            }
            .frame(height: 110)

            Divider()

            // Filter bar
            HStack(spacing: AppTheme.Spacing.md) {
                Picker("Status", selection: $statusFilter) {
                    ForEach(RFIStatusFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 420)

                Spacer()

                Picker("Project", selection: $projectFilter) {
                    Text("All Projects").tag("All")
                    ForEach(dataStore.projects) { project in
                        Text(project.title).tag(project.id.recordName)
                    }
                }
                .frame(width: 200)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)
            .padding(.vertical, AppTheme.Spacing.sm)

            Divider()

            // List
            if filteredRFIs.isEmpty {
                EmptyStateView(
                    icon: "questionmark.bubble",
                    title: emptyStateTitle,
                    message: emptyStateMessage
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredRFIs) { entry in
                        RFILogRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture { editingRFI = entry }
                            .contextMenu {
                                Button("Edit") { editingRFI = entry }
                                Divider()
                                Button("Delete…", role: .destructive) { rfiToDelete = entry }
                            }
                    }
                }
                .listStyle(.inset)
                .searchable(text: $searchText, prompt: "Search by subject, recipient, or project")
            }
        }
        .background(AppTheme.background)
        .inlineForm(item: $addProject) { project in
            AddRFISheet(projectID: project.id, nextNumber: dataStore.nextRFINumber(for: project.id))
        }
        .sheet(item: $editingRFI) { entry in
            EditRFISheet(rfi: entry.rfi, projectID: entry.projectID)
        }
        .confirmationDialog(
            "Delete RFI?",
            isPresented: Binding(
                get: { rfiToDelete != nil },
                set: { if !$0 { rfiToDelete = nil } }
            ),
            presenting: rfiToDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                dataStore.deleteRFI(entry.rfi, from: entry.projectID)
                rfiToDelete = nil
            }
            Button("Cancel", role: .cancel) { rfiToDelete = nil }
        } message: { entry in
            Text("RFI #\(entry.rfi.number) — \"\(entry.rfi.subject)\" will be removed along with its attachments. This cannot be undone.")
        }
    }

    // MARK: - Computed slices

    private var allRFIs: [ProjectRFI] {
        var result: [ProjectRFI] = []
        for project in dataStore.projects {
            for rfi in dataStore.rfis(for: project.id) {
                result.append(ProjectRFI(rfi: rfi, projectID: project.id, projectTitle: project.title))
            }
        }
        return result
    }

    private var filteredRFIs: [ProjectRFI] {
        var result = allRFIs

        switch statusFilter {
        case .all: break
        case .open: result = result.filter { $0.rfi.status != .closed }
        case .overdue: result = result.filter { $0.rfi.isOverdue }
        case .responded: result = result.filter { $0.rfi.status == .responded }
        case .closed: result = result.filter { $0.rfi.status == .closed }
        }

        if projectFilter != "All" {
            result = result.filter { $0.projectID.recordName == projectFilter }
        }

        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            result = result.filter { entry in
                entry.rfi.subject.lowercased().contains(q)
                    || entry.rfi.submittedTo.lowercased().contains(q)
                    || entry.projectTitle.lowercased().contains(q)
                    || String(entry.rfi.number).contains(q)
            }
        }

        return result.sorted { $0.rfi.submittedDate > $1.rfi.submittedDate }
    }

    private var subtitle: String {
        let total = allRFIs.count
        let visible = filteredRFIs.count
        return total == visible
            ? "\(total) total"
            : "\(visible) of \(total) shown"
    }

    private var emptyStateTitle: String {
        switch statusFilter {
        case .all: return "No RFIs yet"
        case .open: return "No open RFIs"
        case .overdue: return "Nothing overdue"
        case .responded: return "No responded RFIs"
        case .closed: return "No closed RFIs"
        }
    }

    private var emptyStateMessage: String {
        if dataStore.projects.isEmpty {
            return "Add a project first, then you can log RFIs against it."
        }
        return "Use the New RFI button to log a request for information against a project."
    }
}

// MARK: - Row

private struct RFILogRow: View {
    let entry: RFILogView.ProjectRFI

    private var statusColor: Color {
        switch entry.rfi.status {
        case .draft: return .gray
        case .submitted: return .blue
        case .responded: return .orange
        case .closed: return .green
        }
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            // Number badge
            Text("#\(entry.rfi.number)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.rfi.subject)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if entry.rfi.isOverdue {
                        Image(systemName: AppIcons.warning)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                HStack(spacing: 8) {
                    Label(entry.projectTitle, systemImage: AppIcons.building)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("To: \(entry.rfi.submittedTo)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                StatusBadge(text: entry.rfi.status.rawValue, color: statusColor)
                Text("Due \(entry.rfi.responseDueDate.formatted("MMM d"))")
                    .font(.caption2)
                    .foregroundColor(entry.rfi.isOverdue ? .red : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
