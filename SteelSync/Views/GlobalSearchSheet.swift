import SwiftUI

/// Spotlight-style global search.
///
/// Presented from anywhere via `⌘K`. Single text field at top, grouped
/// results below. Up/Down arrows move the selection, Enter dispatches the
/// result's action (which calls `NavigationState` to jump to the right
/// section). Esc / Cancel dismisses without navigating.
struct GlobalSearchSheet: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var navigationState: NavigationState
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var highlightedIndex: Int = 0
    @FocusState private var queryFocused: Bool

    private var results: [SearchResult] {
        GlobalSearchService.search(query, in: dataStore, navigation: navigationState)
    }

    /// Results regrouped by kind, preserving the insertion order from the
    /// search service (which already sorts within each kind).
    private var groupedResults: [(kind: ResultKind, items: [SearchResult])] {
        var seenKinds: [ResultKind] = []
        var bucket: [ResultKind: [SearchResult]] = [:]
        for result in results {
            if bucket[result.kind] == nil {
                seenKinds.append(result.kind)
                bucket[result.kind] = []
            }
            bucket[result.kind]?.append(result)
        }
        return seenKinds.map { ($0, bucket[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                emptyState
            } else if results.isEmpty {
                noMatchesState
            } else {
                resultsList
            }
        }
        .background(AppTheme.background)
        #if os(macOS)
        .frame(width: 640, height: 480)
        #endif
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                queryFocused = true
            }
        }
    }

    @ViewBuilder private var searchBar: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundColor(AppTheme.secondaryText)
            TextField("Search projects, bids, RFIs, invoices, tasks…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($queryFocused)
                .onSubmit { runHighlighted() }
                .onChange(of: query) { _, _ in
                    highlightedIndex = 0
                }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            Button("Cancel") { dismiss() }
                .buttonStyle(.appGhost)
                .keyboardShortcut(.cancelAction)
        }
        .padding(AppTheme.Spacing.md)
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(AppTheme.secondaryText.opacity(0.4))
            Text("Search across everything")
                .font(.headline)
                .foregroundColor(AppTheme.secondaryText)
            Text("Projects, bids, RFIs, invoices, change orders, tasks, employees, and more.")
                .font(.caption)
                .foregroundColor(AppTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var noMatchesState: some View {
        VStack(spacing: 6) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 32))
                .foregroundColor(AppTheme.secondaryText.opacity(0.4))
            Text("No matches for \"\(query)\"")
                .font(.callout)
                .foregroundColor(AppTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groupedResults.enumerated()), id: \.element.kind) { _, group in
                    sectionHeader(group.kind, count: group.items.count)
                    ForEach(group.items) { result in
                        let globalIndex = results.firstIndex(where: { $0.id == result.id }) ?? 0
                        resultRow(result, isHighlighted: globalIndex == highlightedIndex)
                            .onTapGesture {
                                run(result)
                            }
                    }
                    Divider().padding(.vertical, 4)
                }
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.bottom, AppTheme.Spacing.md)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ kind: ResultKind, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: kind.icon)
                .font(.caption)
                .foregroundColor(kind.tint)
            Text(kind.rawValue.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(AppTheme.secondaryText)
                .tracking(0.5)
            Text("\(count)")
                .font(.caption2)
                .foregroundColor(AppTheme.tertiaryText)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func resultRow(_ result: SearchResult, isHighlighted: Bool) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: result.kind.icon)
                .foregroundColor(result.kind.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.callout)
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(1)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.caption)
                        .foregroundColor(AppTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "return")
                .font(.caption2)
                .foregroundColor(.secondary)
                .opacity(isHighlighted ? 1 : 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHighlighted ? AppTheme.primaryOrange.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    private func runHighlighted() {
        guard results.indices.contains(highlightedIndex) else { return }
        run(results[highlightedIndex])
    }

    private func run(_ result: SearchResult) {
        result.action()
        dismiss()
    }
}
