import SwiftUI
import CloudKit

/// Mobile adaptation of the Mac RFILogView. Cross-project RFI triage with
/// status filter, search, and tap-to-edit via the existing EditRFISheet.
struct PhoneRFILogView: View {
    @EnvironmentObject var dataStore: DataStore

    @State private var statusFilter: RFIStatusFilter = .open
    @State private var searchText: String = ""
    @State private var editingRFI: ProjectRFI?

    enum RFIStatusFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case open = "Open"
        case overdue = "Overdue"
        case responded = "Responded"
        case closed = "Closed"
        var id: String { rawValue }
    }

    struct ProjectRFI: Identifiable, Hashable {
        let rfi: RFI
        let projectID: CKRecord.ID
        let projectTitle: String
        var id: UUID { rfi.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Metric strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    metricCard("Open", value: "\(openCount)", color: .blue, icon: "questionmark.bubble.fill")
                    metricCard("Overdue", value: "\(overdueCount)", color: .red, icon: "exclamationmark.triangle.fill")
                    metricCard("Responded", value: "\(respondedCount)", color: .orange, icon: "checkmark.circle.fill")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            // Filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RFIStatusFilter.allCases) { filter in
                        Button {
                            statusFilter = filter
                        } label: {
                            Text(filter.rawValue)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(
                                        statusFilter == filter
                                            ? AppTheme.primaryOrange
                                            : Color.gray.opacity(0.15)
                                    )
                                )
                                .foregroundColor(statusFilter == filter ? .white : AppTheme.primaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)

            if filteredRFIs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.bubble")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(emptyTitle)
                        .font(.headline)
                    Text("RFIs are created inside a project on Mac or iPad.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredRFIs) { entry in
                        PhoneRFIRow(entry: entry)
                            .contentShape(Rectangle())
                            .onTapGesture { editingRFI = entry }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $searchText, prompt: "Search subject, recipient, project")
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("RFIs")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingRFI) { entry in
            EditRFISheet(rfi: entry.rfi, projectID: entry.projectID)
                .environmentObject(dataStore)
        }
    }

    // MARK: - Metric card

    private func metricCard(_ title: String, value: String, color: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.title3.monospacedDigit())
                    .fontWeight(.bold)
                    .foregroundColor(color)
            }
        }
        .padding(12)
        .frame(width: 150, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppTheme.secondaryBackground)
        )
    }

    // MARK: - Computed

    private var allRFIs: [ProjectRFI] {
        var result: [ProjectRFI] = []
        for project in dataStore.projects {
            for rfi in dataStore.rfis(for: project.id) {
                result.append(ProjectRFI(rfi: rfi, projectID: project.id, projectTitle: project.title))
            }
        }
        return result
    }

    private var openCount: Int { allRFIs.filter { $0.rfi.status != .closed }.count }
    private var overdueCount: Int { allRFIs.filter { $0.rfi.isOverdue }.count }
    private var respondedCount: Int { allRFIs.filter { $0.rfi.status == .responded }.count }

    private var filteredRFIs: [ProjectRFI] {
        var result = allRFIs
        switch statusFilter {
        case .all: break
        case .open: result = result.filter { $0.rfi.status != .closed }
        case .overdue: result = result.filter { $0.rfi.isOverdue }
        case .responded: result = result.filter { $0.rfi.status == .responded }
        case .closed: result = result.filter { $0.rfi.status == .closed }
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

    private var emptyTitle: String {
        switch statusFilter {
        case .all: return "No RFIs yet"
        case .open: return "No open RFIs"
        case .overdue: return "Nothing overdue"
        case .responded: return "None responded"
        case .closed: return "None closed"
        }
    }
}

// MARK: - Row

private struct PhoneRFIRow: View {
    let entry: PhoneRFILogView.ProjectRFI

    private var statusColor: Color {
        switch entry.rfi.status {
        case .draft: return .gray
        case .submitted: return .blue
        case .responded: return .orange
        case .closed: return .green
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("#\(entry.rfi.number)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                StatusBadge(text: entry.rfi.status.rawValue, color: statusColor)
                if entry.rfi.isOverdue {
                    Text("late")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red.opacity(0.12)))
                }
            }
            Text(entry.rfi.subject)
                .font(.callout)
                .fontWeight(.semibold)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(entry.projectTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if !entry.rfi.submittedTo.isEmpty {
                    Text("·").foregroundColor(.secondary).font(.caption)
                    Text("To \(entry.rfi.submittedTo)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("Due \(entry.rfi.responseDueDate.shortDate)")
                    .font(.caption2)
                    .foregroundColor(entry.rfi.isOverdue ? .red : .secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
