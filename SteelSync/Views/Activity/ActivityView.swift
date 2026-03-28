import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var typeFilter = "All"
    @State private var actionFilter = "All"
    @State private var searchText = ""

    private let entityTypes = ["All", "Project", "Bid", "Client", "Employee", "Change Order",
                                "Payment", "Payroll Entry", "Cost", "Equipment Rental",
                                "Gantt Task", "Todo", "Calendar Event", "Attachment"]

    private var filteredEntries: [AuditEntry] {
        var result = dataStore.auditLog
        if typeFilter != "All" {
            result = result.filter { $0.entityType == typeFilter }
        }
        if actionFilter != "All" {
            if let action = AuditAction.allCases.first(where: { $0.rawValue == actionFilter }) {
                result = result.filter { $0.action == action }
            }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.entityDescription.localizedCaseInsensitiveContains(searchText) ||
                $0.details.localizedCaseInsensitiveContains(searchText) ||
                $0.userName.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    private var groupedEntries: [(String, [AuditEntry])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filteredEntries) { entry -> String in
            if cal.isDateInToday(entry.timestamp) { return "Today" }
            if cal.isDateInYesterday(entry.timestamp) { return "Yesterday" }
            if let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()),
               entry.timestamp > weekAgo { return "This Week" }
            return "Earlier"
        }
        let order = ["Today", "Yesterday", "This Week", "Earlier"]
        return order.compactMap { key in
            guard let entries = grouped[key], !entries.isEmpty else { return nil }
            return (key, entries)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filters
            HStack(spacing: AppTheme.Spacing.sm) {
                Picker("Type", selection: $typeFilter) {
                    ForEach(entityTypes, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 160)

                Picker("Action", selection: $actionFilter) {
                    Text("All").tag("All")
                    ForEach(AuditAction.allCases, id: \.self) { action in
                        Text(action.rawValue).tag(action.rawValue)
                    }
                }
                .frame(width: 130)

                Spacer()

                Text("\(filteredEntries.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.secondaryBackground)

            Divider()

            if dataStore.auditLog.isEmpty {
                EmptyStateView(icon: "clock.arrow.circlepath", title: "No Activity Yet",
                               message: "Actions you take in SteelSync will appear here with a log of who made each change.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEntries.isEmpty {
                VStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No matching entries")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedEntries, id: \.0) { section, entries in
                        Section(section) {
                            ForEach(entries) { entry in
                                auditRow(entry)
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .searchable(text: $searchText, prompt: "Search activity...")
            }
        }
        .navigationTitle("Activity Log")
    }

    // MARK: - Audit Row

    @ViewBuilder
    private func auditRow(_ entry: AuditEntry) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            // Action icon
            Image(systemName: entry.action.icon)
                .font(.title3)
                .foregroundColor(actionColor(entry.action))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                // Main line
                HStack(spacing: 6) {
                    Text(entry.action.rawValue)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(actionColor(entry.action).opacity(0.15))
                        .foregroundColor(actionColor(entry.action))
                        .clipShape(RoundedRectangle(cornerRadius: 3))

                    Text(entry.entityType)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Description
                Text(entry.entityDescription)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(2)

                // Details (if any)
                if !entry.details.isEmpty {
                    Text(entry.details)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Footer: user + time
                HStack(spacing: AppTheme.Spacing.sm) {
                    Label(entry.userName, systemImage: "person.circle")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(entry.timestamp.timeAgo)
                        .font(.caption2)
                        .foregroundColor(AppTheme.tertiaryText)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func actionColor(_ action: AuditAction) -> Color {
        switch action {
        case .created: return .green
        case .updated: return .blue
        case .deleted: return .red
        }
    }
}
