#if STEELSYNC_IPHONE
import SwiftUI

struct IPhoneBidsTab: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedFilter = "All"

    private let filters = ["All", "Pending", "Ready", "Submitted", "Awarded", "Lost"]

    private var filteredBids: [BidProject] {
        switch selectedFilter {
        case "Pending": return dataStore.pendingBids
        case "Ready": return dataStore.bids.filter { $0.status == .readyToSubmit }
        case "Submitted": return dataStore.submittedBids
        case "Awarded": return dataStore.awardedBids
        case "Lost": return dataStore.lostBids
        default: return dataStore.bids
        }
    }

    private func statusColor(for status: BidProject.BidStatus) -> Color {
        switch status {
        case .pending: return AppTheme.BidStatus.open
        case .readyToSubmit: return AppTheme.BidStatus.ready
        case .submitted: return AppTheme.BidStatus.submitted
        case .awarded: return AppTheme.BidStatus.won
        case .lost: return AppTheme.BidStatus.lost
        }
    }

    private func countFor(_ filter: String) -> Int? {
        switch filter {
        case "Pending": return dataStore.pendingBids.count
        case "Ready": return dataStore.bids.filter { $0.status == .readyToSubmit }.count
        case "Submitted": return dataStore.submittedBids.count
        case "Awarded": return dataStore.awardedBids.count
        case "Lost": return dataStore.lostBids.count
        case "All": return dataStore.bids.count
        default: return nil
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Filter pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(filters, id: \.self) { filter in
                            FilterPill(filter, isSelected: selectedFilter == filter,
                                       count: countFor(filter)) {
                                selectedFilter = filter
                            }
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                if filteredBids.isEmpty {
                    EmptyStateView(
                        icon: "doc.text",
                        title: "No Bids",
                        message: "No bids match your current filter."
                    )
                } else {
                    List {
                        ForEach(filteredBids) { bid in
                            NavigationLink(value: bid) {
                                BidRowView(bid: bid)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Bids")
            .refreshable {
                await dataStore.pullFromCloud()
            }
            .navigationDestination(for: BidProject.self) { bid in
                IPhoneBidDetailView(bid: bid)
            }
        }
    }

    // MARK: - Bid Row
    @ViewBuilder
    private func BidRowView(bid: BidProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(bid.projectName)
                    .font(.headline)
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                StatusBadge(
                    text: bid.status.rawValue,
                    color: statusColor(for: bid.status)
                )
            }

            Text(bid.clientName)
                .font(.subheadline)
                .foregroundColor(AppTheme.secondaryText)
                .lineLimit(1)

            HStack {
                Text(bid.bidAmount.currencyFormatted)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.primaryOrange)
                Spacer()
                Label("Due \(bid.bidDueDate.shortDate)", systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(bid.bidDueDate < Date() ? .red : AppTheme.tertiaryText)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
