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
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var isRendering = false
    @State private var renderError: String?

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

    private var filteredTasks: [GanttTask] {
        allTasks.filter { selectedProjectIDs.contains($0.projectID) }
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
                deliver(url)
            }
        }
    }

    private func deliver(_ url: URL) {
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
                // Cancel = still show the temp file in Finder so it isn't lost
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            dismiss()
        }
        #else
        PlatformService.shareItems([url])
        dismiss()
        #endif
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
