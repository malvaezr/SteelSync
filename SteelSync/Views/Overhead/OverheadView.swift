import SwiftUI
import CloudKit
import UniformTypeIdentifiers

// MARK: - Range Preset

enum OverheadRangePreset: String, CaseIterable, Identifiable {
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case thisQuarter = "Quarter"
    case thisYear = "Year"
    case allTime = "All Time"
    var id: String { rawValue }

    func range(asOf today: Date = Date()) -> ClosedRange<Date> {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: today)
        switch self {
        case .thisMonth:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: startOfDay)) ?? startOfDay
            let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? today
            return start...cal.date(bySettingHour: 23, minute: 59, second: 59, of: end)!
        case .lastMonth:
            let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: startOfDay)) ?? startOfDay
            let start = cal.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
            let end = cal.date(byAdding: DateComponents(day: -1), to: thisMonthStart) ?? thisMonthStart
            return start...cal.date(bySettingHour: 23, minute: 59, second: 59, of: end)!
        case .thisQuarter:
            let comps = cal.dateComponents([.year, .month], from: startOfDay)
            let month = comps.month ?? 1
            let quarterStartMonth = ((month - 1) / 3) * 3 + 1
            var startComps = DateComponents()
            startComps.year = comps.year
            startComps.month = quarterStartMonth
            startComps.day = 1
            let start = cal.date(from: startComps) ?? startOfDay
            return start...today
        case .thisYear:
            let comps = cal.dateComponents([.year], from: startOfDay)
            let start = cal.date(from: comps) ?? startOfDay
            return start...today
        case .allTime:
            return Date.distantPast...Date.distantFuture
        }
    }
}

// MARK: - Main View

struct OverheadView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var rangePreset: OverheadRangePreset = .thisMonth
    @State private var searchText = ""
    @State private var selectedExpense: OverheadExpense?
    @State private var showAddSheet = false
    @State private var expenseToDelete: OverheadExpense?
    @State private var categoryFilter: OverheadCategory?
    @State private var showRecurringOnly = false

    private var activeRange: ClosedRange<Date> {
        rangePreset.range()
    }

    private var filteredEntries: [OverheadExpense] {
        var result = dataStore.overheadEntries(in: activeRange)
        if let cat = categoryFilter {
            result = result.filter { $0.category == cat }
        }
        if showRecurringOnly {
            result = result.filter { $0.isRecurringTemplate || $0.parentRecurringID != nil }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.vendor.localizedCaseInsensitiveContains(searchText) ||
                $0.expenseDescription.localizedCaseInsensitiveContains(searchText) ||
                $0.category.rawValue.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result.sorted { $0.date > $1.date }
    }

    private var periodTotal: Decimal { dataStore.overheadTotal(in: activeRange) }
    private var categoryBreakdown: [(OverheadCategory, Decimal)] {
        dataStore.overheadByCategory(in: activeRange)
    }
    private var recurringCount: Int { dataStore.overheadRecurringTemplates.count }

    var body: some View {
        PlatformSplitView {
            listPane
                #if os(macOS)
                .frame(minWidth: 320, idealWidth: 520)
                #endif

            if let expense = selectedExpense,
               let refreshed = dataStore.overheadExpenses.first(where: { $0.id == expense.id }) {
                OverheadDetailView(
                    expense: refreshed,
                    onEdit: { selectedExpense = refreshed },
                    onDelete: { expenseToDelete = refreshed }
                )
                #if os(macOS)
                .frame(minWidth: 280, idealWidth: 420)
                #endif
            } else {
                EmptyStateView(
                    icon: "briefcase",
                    title: "No Expense Selected",
                    message: "Pick an entry from the list, or add a new overhead expense.",
                    buttonTitle: "New Expense",
                    action: { showAddSheet = true }
                )
                #if os(macOS)
                .frame(minWidth: 280, idealWidth: 420)
                #endif
            }
        }
        .inlineForm(isPresented: $showAddSheet) {
            AddOverheadExpenseView()
        }
        .confirmationDialog(
            "Delete expense?",
            isPresented: Binding(
                get: { expenseToDelete != nil },
                set: { if !$0 { expenseToDelete = nil } }
            ),
            presenting: expenseToDelete
        ) { expense in
            Button("Delete", role: .destructive) {
                dataStore.deleteOverhead(expense)
                if selectedExpense?.id == expense.id { selectedExpense = nil }
                expenseToDelete = nil
            }
            Button("Cancel", role: .cancel) { expenseToDelete = nil }
        } message: { expense in
            if expense.isRecurringTemplate {
                Text("\"\(displayName(expense))\" is a recurring template. Past generated entries will survive but future ones will stop.")
            } else {
                Text("\"\(displayName(expense))\" will be removed. This cannot be undone.")
            }
        }
        .navigationTitle("Overhead")
    }

    // MARK: - List pane

    @ViewBuilder private var listPane: some View {
        VStack(spacing: 0) {
            ScreenHeader(
                title: "Overhead",
                subtitle: "\(filteredEntries.count) entries · \(recurringCount) recurring",
                icon: "briefcase.fill"
            ) {
                Button { showAddSheet = true } label: {
                    Label("New Expense", systemImage: "plus")
                }
                .buttonStyle(.appPrimary)
            }

            metricStrip

            rangePickerStrip

            categoryFilterStrip

            List(selection: $selectedExpense) {
                ForEach(filteredEntries) { entry in
                    OverheadRow(entry: entry)
                        .tag(entry)
                        .contextMenu {
                            Button("Edit") { selectedExpense = entry }
                            Divider()
                            Button("Delete…", role: .destructive) { expenseToDelete = entry }
                        }
                }
                if filteredEntries.isEmpty {
                    Text("No entries in this range.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.vertical, AppTheme.Spacing.lg)
                        .frame(maxWidth: .infinity)
                }
            }
            .listStyle(.inset)
            .searchable(text: $searchText, prompt: "Search overhead...")
        }
    }

    @ViewBuilder private var metricStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                MetricCard(
                    title: "\(rangePreset.rawValue) Total",
                    value: periodTotal.currencyFormatted,
                    icon: "sum",
                    color: AppTheme.primaryOrange
                )
                MetricCard(
                    title: "Entries",
                    value: "\(dataStore.overheadEntries(in: activeRange).count)",
                    icon: "list.bullet.rectangle",
                    color: .blue
                )
                MetricCard(
                    title: "Recurring",
                    value: "\(recurringCount)",
                    icon: "repeat",
                    color: .purple
                )
                if let top = categoryBreakdown.first {
                    MetricCard(
                        title: "Top: \(top.0.rawValue)",
                        value: top.1.currencyFormatted,
                        icon: top.0.icon,
                        color: .green
                    )
                }
            }
            .padding(AppTheme.Spacing.md)
        }
        .frame(height: 130)
    }

    @ViewBuilder private var rangePickerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                ForEach(OverheadRangePreset.allCases) { preset in
                    FilterPill(
                        preset.rawValue,
                        isSelected: rangePreset == preset
                    ) { rangePreset = preset }
                }
                Divider().frame(height: 20)
                FilterPill(
                    "Recurring only",
                    isSelected: showRecurringOnly
                ) { showRecurringOnly.toggle() }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
        }
        .frame(height: 44)
    }

    @ViewBuilder private var categoryFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppTheme.Spacing.sm) {
                FilterPill("All", isSelected: categoryFilter == nil) {
                    categoryFilter = nil
                }
                ForEach(OverheadCategory.allCases, id: \.self) { cat in
                    FilterPill(
                        cat.rawValue,
                        isSelected: categoryFilter == cat
                    ) {
                        categoryFilter = categoryFilter == cat ? nil : cat
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.sm)
        }
        .frame(height: 40)
    }

    private func displayName(_ e: OverheadExpense) -> String {
        let label = e.expenseDescription.isEmpty ? e.category.rawValue : e.expenseDescription
        return e.vendor.isEmpty ? label : "\(label) — \(e.vendor)"
    }
}

// MARK: - Row

struct OverheadRow: View {
    let entry: OverheadExpense

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.primaryOrange.opacity(0.14))
                    .frame(width: 32, height: 32)
                Image(systemName: entry.category.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.primaryOrange)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(primaryLabel)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if entry.isRecurringTemplate {
                        StatusBadge(text: "Recurring", color: .purple)
                    } else if entry.parentRecurringID != nil {
                        Image(systemName: "repeat")
                            .font(.system(size: 10))
                            .foregroundColor(.purple)
                    }
                }
                HStack(spacing: 4) {
                    Text(entry.category.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !entry.vendor.isEmpty {
                        Text("·").foregroundColor(.secondary)
                        Text(entry.vendor)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(entry.date.shortDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(entry.amount.currencyFormatted)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
        }
        .padding(.vertical, 4)
    }

    private var primaryLabel: String {
        entry.expenseDescription.isEmpty ? entry.category.rawValue : entry.expenseDescription
    }
}

// MARK: - Detail Pane

struct OverheadDetailView: View {
    let expense: OverheadExpense
    let onEdit: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject var dataStore: DataStore
    @State private var showEditSheet = false
    @State private var showFileImporter = false
    @State private var uploadError: String?
    @State private var attachmentToDelete: Attachment?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                header

                infoCard

                allocationCard

                attachmentsCard

                if !expense.notes.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        SectionTitle(text: "Notes")
                        Text(expense.notes)
                            .font(.body)
                            .foregroundColor(AppTheme.primaryText)
                            .padding(AppTheme.Spacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(AppTheme.secondaryBackground)
                            )
                    }
                }

                if expense.isRecurringTemplate {
                    recurringChildrenCard
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .sheet(isPresented: $showEditSheet) {
            EditOverheadExpenseView(expense: expense)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.pdf, .png, .jpeg, .tiff, .data],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importFiles(urls)
            case .failure(let error):
                uploadError = error.localizedDescription
            }
        }
        .alert("Upload error", isPresented: Binding(
            get: { uploadError != nil },
            set: { if !$0 { uploadError = nil } }
        ), presenting: uploadError) { _ in
            Button("OK") { uploadError = nil }
        } message: { msg in
            Text(msg)
        }
        .confirmationDialog(
            "Remove attachment?",
            isPresented: Binding(
                get: { attachmentToDelete != nil },
                set: { if !$0 { attachmentToDelete = nil } }
            ),
            presenting: attachmentToDelete
        ) { att in
            Button("Remove", role: .destructive) {
                dataStore.removeOverheadAttachment(att, from: expense.id)
                attachmentToDelete = nil
            }
            Button("Cancel", role: .cancel) { attachmentToDelete = nil }
        } message: { att in
            Text("\"\(att.filename)\" will be deleted from local storage.")
        }
    }

    @ViewBuilder private var attachmentsCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                SectionTitle(text: "Receipts (\(expense.attachments.count))")
                Spacer()
                Button { pickFiles() } label: {
                    Label("Upload", systemImage: "paperclip")
                }
                .buttonStyle(.appSecondary)
                .controlSize(.small)
            }

            if expense.attachments.isEmpty {
                HStack {
                    Image(systemName: "doc.badge.plus")
                        .foregroundColor(.secondary)
                    Text("No receipts attached. Drag a file in, or click Upload.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(AppTheme.Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.secondaryBackground)
                )
                .fileDropOverhead(expenseID: expense.recordID.recordName) { attachment in
                    Task { @MainActor in
                        dataStore.addOverheadAttachment(attachment, to: expense.id)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(expense.attachments) { att in
                        attachmentRow(att)
                    }
                }
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.secondaryBackground)
                )
                .fileDrop(folderID: "overhead/\(expense.recordID.recordName)", showHint: false) { attachment in
                    Task { @MainActor in
                        dataStore.addOverheadAttachment(attachment, to: expense.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentRow(_ att: Attachment) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: FileStorageService.iconName(for: att.filename))
                .foregroundColor(AppTheme.primaryOrange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(att.filename)
                    .font(.callout)
                    .lineLimit(1)
                Text("\(FileStorageService.fileTypeLabel(for: att.filename)) · \(att.fileSizeFormatted)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                FileStorageService.openFile(att)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Open")
            Button {
                attachmentToDelete = att
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
    }

    private func pickFiles() {
        #if os(macOS)
        let urls = FileStorageService.presentFilePicker()
        importFiles(urls)
        #else
        showFileImporter = true
        #endif
    }

    private func importFiles(_ urls: [URL]) {
        let expenseID = expense.recordID.recordName
        for url in urls {
            switch FileStorageService.importFile(from: url, overheadID: expenseID) {
            case .success(let attachment):
                dataStore.addOverheadAttachment(attachment, to: expense.id)
            case .failure(let error):
                uploadError = error.localizedDescription
            }
        }
    }

    @ViewBuilder private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.expenseDescription.isEmpty ? expense.category.rawValue : expense.expenseDescription)
                    .font(.system(size: 20, weight: .bold))
                    .lineLimit(2)
                if !expense.vendor.isEmpty {
                    Text(expense.vendor)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Text(expense.amount.currencyFormatted)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(AppTheme.primaryOrange)
        }

        HStack(spacing: AppTheme.Spacing.sm) {
            Button { showEditSheet = true } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.appSecondary)
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.appSecondary)
            Spacer()
        }
    }

    @ViewBuilder private var infoCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(text: "Details")
            VStack(spacing: AppTheme.Spacing.sm) {
                InfoRow(label: "Category", value: expense.category.rawValue, icon: expense.category.icon)
                InfoRow(label: "Date", value: expense.date.shortDate, icon: "calendar")
                InfoRow(label: "Recurrence", value: expense.recurrence.rawValue, icon: "repeat")
                if expense.parentRecurringID != nil {
                    InfoRow(label: "Source", value: "Generated from recurring template", icon: "arrow.triangle.branch")
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.secondaryBackground)
            )
        }
    }

    @ViewBuilder private var allocationCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(text: "Allocation")
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                InfoRow(label: "Mode", value: expense.distributionMode.rawValue, icon: "arrow.triangle.branch")
                let shares = allocationShares()
                if shares.isEmpty {
                    Text("No projects currently absorb this expense.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Divider().padding(.vertical, 2)
                    ForEach(shares, id: \.project.id) { item in
                        HStack {
                            Text(item.project.title)
                                .font(.callout)
                            Spacer()
                            Text(item.amount.currencyFormatted)
                                .font(.callout)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.secondaryBackground)
            )
        }
    }

    private func allocationShares() -> [(project: Project, amount: Decimal)] {
        switch expense.distributionMode {
        case .companyOnly:
            return []

        case .scheduleDaily:
            // Defer to DataStore so the per-expense detail breakdown matches
            // the aggregated `allocateOverhead` (single source of truth, and
            // any retroactive Gantt edits land here automatically).
            let shares = dataStore.scheduleDailyShares(for: expense)
            return shares
                .compactMap { (id, amount) -> (Project, Decimal)? in
                    guard let proj = dataStore.projects.first(where: { $0.id.recordName == id }) else { return nil }
                    return (proj, amount)
                }
                .sorted { $0.1 > $1.1 }

        case .allActive, .specificProjects:
            let targets: [Project]
            if expense.distributionMode == .allActive {
                targets = dataStore.projects.filter { $0.wasActive(on: expense.date) }
            } else {
                let ids = Set(expense.distributionProjectIDs)
                targets = dataStore.projects.filter { ids.contains($0.id.recordName) }
            }
            let totalContract = targets.reduce(Decimal.zero) { $0 + $1.contractAmount }
            guard totalContract > 0 else { return [] }
            return targets.map { project in
                (project, expense.amount * (project.contractAmount / totalContract))
            }
        }
    }

    @ViewBuilder private var recurringChildrenCard: some View {
        let children = dataStore.overheadExpenses
            .filter { $0.parentRecurringID == expense.recordID.recordName }
            .sorted { $0.date > $1.date }
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            SectionTitle(text: "Generated Instances (\(children.count))")
            if children.isEmpty {
                Text("No instances yet. Next one appears on \(nextOccurrence().shortDate).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(children.prefix(8)) { child in
                        HStack {
                            Text(child.date.shortDate)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(child.amount.currencyFormatted)
                                .font(.callout)
                                .fontWeight(.medium)
                        }
                    }
                    if children.count > 8 {
                        Text("+ \(children.count - 8) more")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.secondaryBackground)
                )
            }
        }
    }

    private func nextOccurrence() -> Date {
        let parentName = expense.recordID.recordName
        let children = dataStore.overheadExpenses.filter { $0.parentRecurringID == parentName }
        let last = (children.map(\.date) + [expense.date]).max() ?? expense.date
        return expense.recurrence.next(after: last) ?? last
    }
}
