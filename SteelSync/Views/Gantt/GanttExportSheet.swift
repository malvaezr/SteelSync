import SwiftUI
import CloudKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Date-range PDF export for the Gantt chart.
///
/// Lets the user pick any subset of projects (1, several, or all) plus a
/// start/end date, then renders a slice of the chart through
/// `GanttPDFRenderer`. Auto-fills the date range from the actual span of
/// visible tasks so common "export everything" use cases require zero
/// adjustment.
struct GanttExportSheet: View {
    let allTasks: [GanttTask]
    let projects: [Project]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedProjectIDs: Set<String>
    /// Assignees to include. Stored as raw `assignedTo` strings; the empty
    /// string represents "unassigned". `nil` means "no assignee filter
    /// applied" (show every assignee, including assignees added later) —
    /// distinct from "empty set" which means "show nothing".
    @State private var selectedAssignees: Set<String>? = nil
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isRendering = false
    @State private var renderError: String?
    /// When set, the sheet shows a "PDF Ready" panel with Save / Share /
    /// Reveal options anchored on this URL. Cleared on Cancel and when the
    /// user picks Save (which dismisses).
    @State private var renderedURL: URL?

    /// Initialize with an explicit set of project IDs to pre-select.
    /// Empty set means "no projects" — caller should usually pass either a
    /// specific subset or the full set of project IDs (= "All Projects").
    init(allTasks: [GanttTask], projects: [Project], initialSelectedProjects: Set<String>) {
        self.allTasks = allTasks
        self.projects = projects
        _selectedProjectIDs = State(initialValue: initialSelectedProjects)

        // Default range: span of tasks matching the initial filter, padded a few days.
        let scope: [GanttTask]
        if initialSelectedProjects.isEmpty {
            scope = []
        } else {
            scope = allTasks.filter { initialSelectedProjects.contains($0.projectID) }
        }
        let cal = Calendar.current
        let starts = scope.map(\.startDate)
        let ends = scope.map { task in
            cal.date(byAdding: .day, value: max(0, task.durationDays - 1), to: task.startDate) ?? task.startDate
        }
        let defaultStart = (starts.min() ?? Date()).addingTimeInterval(-2 * 86400)
        let defaultEnd = (ends.max() ?? Date().addingTimeInterval(30 * 86400)).addingTimeInterval(2 * 86400)
        _startDate = State(initialValue: defaultStart)
        _endDate = State(initialValue: defaultEnd)
    }

    /// Backward-compatible single-project initializer. Used by call sites
    /// that haven't migrated to multi-select yet — either nil (= all projects)
    /// or a single project ID.
    init(allTasks: [GanttTask], projects: [Project], initialProjectFilter: String?) {
        let initial: Set<String>
        if let pid = initialProjectFilter {
            initial = [pid]
        } else {
            initial = Set(projects.map { $0.id.recordName })
        }
        self.init(allTasks: allTasks, projects: projects, initialSelectedProjects: initial)
    }

    /// Distinct assignees across the project-filtered task set, preserved
    /// in insertion order. The `assignedTo` field is free-text on the task,
    /// so we just dedupe the strings as-is. An empty string is preserved as
    /// "Unassigned" in the menu.
    private var availableAssignees: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        // Multi-assignee: expand each task's `assignees` so a task with
        // "Joe; Mike" contributes BOTH names to the filter menu.
        for task in allTasks where selectedProjectIDs.contains(task.projectID) {
            let names = task.assignees
            if names.isEmpty {
                if !seen.contains("") {
                    seen.insert("")
                    ordered.append("")
                }
            } else {
                for name in names where !seen.contains(name) {
                    seen.insert(name)
                    ordered.append(name)
                }
            }
        }
        // Sort: unassigned ("") first, then alphabetical
        ordered.sort { lhs, rhs in
            if lhs.isEmpty && !rhs.isEmpty { return true }
            if !lhs.isEmpty && rhs.isEmpty { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return ordered
    }

    private var filteredTasks: [GanttTask] {
        let projectMatches = allTasks.filter { selectedProjectIDs.contains($0.projectID) }
        guard let assignees = selectedAssignees else { return projectMatches }
        return projectMatches.filter { task in
            let names = task.assignees
            // Treat an empty assignees list as "" so the "Unassigned" filter entry works.
            if names.isEmpty { return assignees.contains("") }
            return names.contains(where: { assignees.contains($0) })
        }
    }

    private var assigneeFilterLabel: String {
        let total = availableAssignees.count
        guard let selected = selectedAssignees else { return "All Assignees" }
        if selected.isEmpty { return "None" }
        if selected.count == total { return "All Assignees" }
        if selected.count == 1, let name = selected.first {
            return name.isEmpty ? "Unassigned" : name
        }
        return "\(selected.count) of \(total) Assignees"
    }

    private func displayAssignee(_ raw: String) -> String {
        raw.isEmpty ? "Unassigned" : raw
    }

    private var inRangeCount: Int {
        let cal = Calendar.current
        return filteredTasks.filter { task in
            let taskEnd = cal.date(byAdding: .day, value: max(0, task.durationDays - 1), to: task.startDate) ?? task.startDate
            return taskEnd >= startDate && task.startDate <= endDate
        }.count
    }

    private var canExport: Bool {
        startDate <= endDate && !selectedProjectIDs.isEmpty && inRangeCount > 0 && !isRendering
    }

    private var projectFilterLabel: String {
        let total = projects.count
        let count = selectedProjectIDs.count
        if count == 0 { return "No Projects" }
        if count == total { return "All Projects" }
        if count == 1,
           let id = selectedProjectIDs.first,
           let project = projects.first(where: { $0.id.recordName == id }) {
            return project.title
        }
        return "\(count) of \(total) Projects"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Export Gantt PDF",
                saveTitle: isRendering ? "Rendering…" : "Export",
                saveDisabled: !canExport,
                onCancel: { dismiss() },
                onSave: export
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        SectionTitle(text: "Scope")

                        LabeledField(label: "Projects",
                                     helpText: "Pick any combination of projects. Tasks from selected projects will appear together in the PDF.") {
                            projectMultiSelectMenu
                        }

                        LabeledField(label: "Assigned To",
                                     helpText: "Optional. Narrow the export to specific people. Leave on \"All Assignees\" to include everyone, including assignees that haven't been added yet.") {
                            assigneeMultiSelectMenu
                        }

                        HStack(spacing: AppTheme.Spacing.md) {
                            LabeledField(label: "Start Date") {
                                DatePicker("", selection: $startDate, displayedComponents: .date)
                                    .labelsHidden()
                                    .appControlSurface()
                            }
                            LabeledField(label: "End Date") {
                                DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                                    .labelsHidden()
                                    .appControlSurface()
                            }
                        }

                        rangePresets
                    }

                    summaryCard

                    if let url = renderedURL {
                        readyCard(url: url)
                    }

                    if let error = renderError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(AppTheme.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.red.opacity(0.08))
                            )
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 560, height: 580)
        #endif
    }

    @ViewBuilder private var projectMultiSelectMenu: some View {
        Menu {
            Button {
                selectedProjectIDs = Set(projects.map { $0.id.recordName })
            } label: {
                Label("Select All", systemImage: "checkmark.circle.fill")
            }
            Button {
                selectedProjectIDs.removeAll()
            } label: {
                Label("Clear All", systemImage: "xmark.circle")
            }
            Divider()
            ForEach(projects) { project in
                Button {
                    let id = project.id.recordName
                    if selectedProjectIDs.contains(id) {
                        selectedProjectIDs.remove(id)
                    } else {
                        selectedProjectIDs.insert(id)
                    }
                } label: {
                    if selectedProjectIDs.contains(project.id.recordName) {
                        Label(project.title, systemImage: "checkmark")
                    } else {
                        Text(project.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "building.2")
                    .font(.caption)
                Text(projectFilterLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appControlSurface()
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder private var assigneeMultiSelectMenu: some View {
        let assignees = availableAssignees
        Menu {
            Button {
                selectedAssignees = nil   // nil = follow availability automatically
            } label: {
                Label("All Assignees", systemImage: "checkmark.circle.fill")
            }
            Button {
                selectedAssignees = []    // explicit empty = filter out everyone
            } label: {
                Label("Clear Selection", systemImage: "xmark.circle")
            }
            if !assignees.isEmpty {
                Divider()
                ForEach(assignees, id: \.self) { name in
                    Button {
                        // First click after "All Assignees": initialize the
                        // set to everyone, then toggle the chosen one. This
                        // matches user intent — they tapped a name to narrow,
                        // not to switch from "all" to "only this one".
                        var current = selectedAssignees ?? Set(assignees)
                        if current.contains(name) {
                            current.remove(name)
                        } else {
                            current.insert(name)
                        }
                        selectedAssignees = current
                    } label: {
                        let active = selectedAssignees?.contains(name) ?? true
                        if active {
                            Label(displayAssignee(name), systemImage: "checkmark")
                        } else {
                            Text(displayAssignee(name))
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.2")
                    .font(.caption)
                Text(assigneeFilterLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appControlSurface()
        }
        .menuStyle(.borderlessButton)
        .disabled(assignees.isEmpty)
    }

    @ViewBuilder private var rangePresets: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            presetButton("This Month") {
                let cal = Calendar.current
                let now = Date()
                if let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)),
                   let monthEnd = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) {
                    startDate = monthStart
                    endDate = monthEnd
                }
            }
            presetButton("Next 30 Days") {
                startDate = Date()
                endDate = Date().addingTimeInterval(30 * 86400)
            }
            presetButton("Next 90 Days") {
                startDate = Date()
                endDate = Date().addingTimeInterval(90 * 86400)
            }
            presetButton("Full Span") {
                let cal = Calendar.current
                let starts = filteredTasks.map(\.startDate)
                let ends = filteredTasks.map { task in
                    cal.date(byAdding: .day, value: max(0, task.durationDays - 1), to: task.startDate) ?? task.startDate
                }
                if let s = starts.min(), let e = ends.max() {
                    startDate = s.addingTimeInterval(-2 * 86400)
                    endDate = e.addingTimeInterval(2 * 86400)
                }
            }
        }
    }

    private func presetButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.appOutline)
            .controlSize(.small)
    }

    @ViewBuilder
    private func readyCard(url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(text: "PDF Ready")
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.richtext.fill")
                        .foregroundColor(AppTheme.primaryOrange)
                    Text(url.lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    Button {
                        saveToDisk(url)
                    } label: {
                        Label("Save…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.appPrimary)

                    ShareLink(
                        item: url,
                        subject: Text("\(selectedProjectTitles.first ?? "Schedule") — Schedule PDF"),
                        message: Text(shareMessage())
                    ) {
                        Label("Share with Client…", systemImage: "paperplane")
                    }
                    .buttonStyle(.appSecondary)

                    #if os(macOS)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .buttonStyle(.appOutline)
                    #endif
                    Spacer()
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.primaryOrange.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(AppTheme.primaryOrange.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private func shareMessage() -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        let projectsLabel: String
        switch selectedProjectTitles.count {
        case 0: projectsLabel = "Schedule"
        case 1: projectsLabel = selectedProjectTitles[0]
        default: projectsLabel = "\(selectedProjectTitles.count) projects"
        }
        var lines: [String] = []
        lines.append("Hi,")
        lines.append("")
        lines.append("Attached is the schedule for \(projectsLabel).")
        lines.append("Window: \(f.string(from: startDate)) → \(f.string(from: endDate)).")
        lines.append("")
        lines.append("— Ruben")
        return lines.joined(separator: "\n")
    }

    @ViewBuilder private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle(text: "Preview")
            VStack(spacing: AppTheme.Spacing.sm) {
                InfoRow(label: "Tasks in range", value: "\(inRangeCount)", icon: "list.bullet")
                InfoRow(label: "Date range",
                        value: "\(formatDate(startDate)) → \(formatDate(endDate))",
                        icon: "calendar")
                InfoRow(label: "Duration",
                        value: "\(daysBetween(startDate, endDate)) days",
                        icon: "clock")
                InfoRow(label: "Projects",
                        value: projectFilterLabel,
                        icon: "building.2")
                InfoRow(label: "Assigned To",
                        value: assigneeFilterLabel,
                        icon: "person.2")
            }
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.secondaryBackground)
            )
        }
    }

    // MARK: - Actions

    private func export() {
        isRendering = true
        renderError = nil

        let projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id.recordName, $0.title) })
        let title: String
        if selectedProjectIDs.count == projects.count {
            title = "SteelSync Schedule"
        } else if selectedProjectIDs.count == 1,
                  let id = selectedProjectIDs.first,
                  let p = projects.first(where: { $0.id.recordName == id }) {
            title = "\(p.title) — Schedule"
        } else {
            // Multi-project export: use the alphabetically-first selected
            // project plus a "+ N others" suffix so the title fits on one line.
            let selected = projects
                .filter { selectedProjectIDs.contains($0.id.recordName) }
                .sorted { $0.title < $1.title }
            if let first = selected.first {
                let othersCount = selected.count - 1
                title = othersCount > 0
                    ? "\(first.title) + \(othersCount) other\(othersCount == 1 ? "" : "s") — Schedule"
                    : "\(first.title) — Schedule"
            } else {
                title = "SteelSync Schedule"
            }
        }

        let renderer = GanttPDFRenderer(
            title: title,
            tasks: filteredTasks,
            projectsByID: projectsByID,
            dateRange: startDate...endDate
        )

        Task.detached {
            let url = renderer.render()
            await MainActor.run {
                isRendering = false
                guard let url = url else {
                    renderError = "Could not generate PDF. Try a smaller date range."
                    return
                }
                renderedURL = url
            }
        }
    }

    /// Save the temp-file PDF to a permanent location of the user's choosing.
    /// macOS uses NSSavePanel + reveal-in-Finder; iOS hands off to the
    /// system share sheet so the user can save / share / AirDrop.
    private func saveToDisk(_ url: URL) {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = url.lastPathComponent
        panel.begin { result in
            if result == .OK, let dest = panel.url {
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            dismiss()
        }
        #else
        PlatformService.shareItems([url])
        dismiss()
        #endif
    }

    /// Titles of the projects in the current selection — used to build a
    /// readable "Share" subject + body.
    private var selectedProjectTitles: [String] {
        projects
            .filter { selectedProjectIDs.contains($0.id.recordName) }
            .map(\.title)
            .sorted()
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    private func daysBetween(_ a: Date, _ b: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
    }
}
