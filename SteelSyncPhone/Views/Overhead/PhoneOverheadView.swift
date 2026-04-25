import SwiftUI
import CloudKit

/// Phone-side overhead tracker. Mobile-optimized variant of the macOS
/// `OverheadView`: scrollable list grouped by month, quick-add button for
/// entering receipts in the field, and a running total for the selected
/// range. Heavier surfaces (category grid, per-project allocation table,
/// Company P&L) stay on macOS / iPad.
struct PhoneOverheadView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var rangePreset: OverheadRangePreset = .thisMonth
    @State private var showAddSheet = false
    @State private var editingExpense: OverheadExpense?
    @State private var expenseToDelete: OverheadExpense?
    @State private var searchText = ""

    private var activeRange: ClosedRange<Date> { rangePreset.range() }

    private var filteredEntries: [OverheadExpense] {
        var result = dataStore.overheadEntries(in: activeRange)
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

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Total")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(periodTotal.currencyFormatted)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(AppTheme.primaryOrange)
                }
                .padding(.vertical, 4)

                Picker("Range", selection: $rangePreset) {
                    ForEach(OverheadRangePreset.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            } header: {
                Text(rangePreset.rawValue)
                    .foregroundColor(AppTheme.secondaryText)
            }

            Section {
                if filteredEntries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "briefcase")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No overhead in this range.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Button("Add Expense") { showAddSheet = true }
                            .buttonStyle(.appPrimary)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(filteredEntries) { entry in
                        Button { editingExpense = entry } label: {
                            PhoneOverheadRow(entry: entry)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                expenseToDelete = entry
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            } header: {
                Text("\(filteredEntries.count) entr\(filteredEntries.count == 1 ? "y" : "ies")")
                    .foregroundColor(AppTheme.secondaryText)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search overhead")
        .navigationTitle("Overhead")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            NavigationStack {
                AddOverheadExpenseView()
            }
        }
        .sheet(item: $editingExpense) { expense in
            NavigationStack {
                EditOverheadExpenseView(expense: expense)
            }
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
                expenseToDelete = nil
            }
            Button("Cancel", role: .cancel) { expenseToDelete = nil }
        } message: { e in
            Text("\"\(e.expenseDescription.isEmpty ? e.category.rawValue : e.expenseDescription)\" will be removed.")
        }
    }
}

// MARK: - Row

private struct PhoneOverheadRow: View {
    let entry: OverheadExpense

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.primaryOrange.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: entry.category.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryOrange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLabel)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(entry.category.rawValue)
                    if !entry.vendor.isEmpty {
                        Text("·").foregroundColor(.secondary)
                        Text(entry.vendor).lineLimit(1)
                    }
                    Text("·").foregroundColor(.secondary)
                    Text(entry.date.shortDate)
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.amount.currencyFormatted)
                    .font(.callout)
                    .fontWeight(.semibold)
                if entry.isRecurringTemplate {
                    Image(systemName: "repeat")
                        .font(.caption2)
                        .foregroundColor(.purple)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var primaryLabel: String {
        entry.expenseDescription.isEmpty ? entry.category.rawValue : entry.expenseDescription
    }
}
