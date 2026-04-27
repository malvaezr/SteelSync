import SwiftUI
import CloudKit

struct BiddingView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedFilter = "Pending"
    @State private var searchText = ""
    @State private var showAddBid = false
    @State private var selectedBid: BidProject?
    @State private var bidToDelete: BidProject?
    @State private var bidToConvert: BidProject?

    private let filters = ["All", "Pending", "Working On", "Ready", "Submitted", "Awarded", "Lost"]

    var filteredBids: [BidProject] {
        var result = dataStore.bids
        switch selectedFilter {
        case "Pending": result = result.filter { $0.status == .pending }
        case "Working On": result = result.filter { $0.status == .workingOn }
        case "Ready": result = result.filter { $0.status == .readyToSubmit }
        case "Submitted": result = result.filter { $0.status == .submitted }
        case "Awarded": result = result.filter { $0.status == .awarded }
        case "Lost": result = result.filter { $0.status == .lost }
        default: break
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.projectName.localizedCaseInsensitiveContains(searchText) ||
                $0.clientName.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result.sorted { $0.bidDueDate < $1.bidDueDate }
    }

    var body: some View {
        PlatformSplitView {
            VStack(spacing: 0) {
                ScreenHeader(
                    title: "Bidding Pipeline",
                    subtitle: "\(dataStore.pendingBids.count) pending · \(dataStore.submittedBids.count) submitted",
                    icon: AppIcons.document
                ) {
                    Button { showAddBid = true } label: {
                        Label("New Bid", systemImage: AppIcons.add)
                    }
                    .buttonStyle(.appPrimary)
                }

                // Pipeline metrics
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        MetricCard(title: "Pipeline Value", value: dataStore.totalBidPipeline.currencyFormatted,
                                   icon: "chart.bar.fill", color: .blue)
                        MetricCard(title: "Win Rate", value: String(format: "%.0f%%", dataStore.bidWinRate),
                                   icon: "trophy.fill", color: .green)
                        MetricCard(title: "Open Bids", value: "\(dataStore.pendingBids.count + dataStore.bids.filter { $0.status == .readyToSubmit }.count)",
                                   icon: AppIcons.document, color: AppTheme.primaryOrange)
                        MetricCard(title: "Submitted", value: "\(dataStore.submittedBids.count)",
                                   icon: "paperplane.fill", color: .purple)
                    }
                    .padding(AppTheme.Spacing.md)
                }
                .frame(height: 120)

                // Filters
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(filters, id: \.self) { filter in
                            FilterPill(filter, isSelected: selectedFilter == filter) {
                                selectedFilter = filter
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.sm)

                // Bid list
                List(selection: $selectedBid) {
                    ForEach(filteredBids) { bid in
                        BidRow(bid: bid, clientType: dataStore.client(for: bid.clientRef)?.preferredRateType)
                            .tag(bid)
                            .contextMenu {
                                if !bid.isSubmitted && !bid.isAwarded {
                                    if !bid.isWorkingOn && !bid.isReadyToSubmit {
                                        Button("Mark as Working On") {
                                            var updated = bid
                                            updated.isWorkingOn = true
                                            dataStore.updateBid(updated)
                                        }
                                    }
                                    Button("Mark as Ready") {
                                        var updated = bid
                                        updated.isReadyToSubmit = true
                                        updated.isWorkingOn = false
                                        dataStore.updateBid(updated)
                                    }
                                    Button("Mark as Submitted") {
                                        var updated = bid
                                        updated.isSubmitted = true
                                        updated.submittedDate = Date()
                                        updated.isWorkingOn = false
                                        dataStore.updateBid(updated)
                                    }
                                }
                                if bid.isSubmitted && !bid.isAwarded && !bid.isLost {
                                    Button("Mark as Awarded…") {
                                        bidToConvert = bid
                                    }
                                    Button("Mark as Lost") {
                                        var updated = bid
                                        updated.isLost = true
                                        dataStore.updateBid(updated)
                                    }
                                }
                                if bid.isLost || bid.isAwarded {
                                    Button("Revert to Ready") {
                                        var updated = bid
                                        updated.isLost = false
                                        updated.awardedProjectID = nil
                                        updated.isSubmitted = false
                                        updated.submittedDate = nil
                                        updated.isReadyToSubmit = true
                                        updated.isWorkingOn = false
                                        dataStore.updateBid(updated)
                                    }
                                }
                                Divider()
                                Button("Delete…", role: .destructive) { bidToDelete = bid }
                            }
                    }
                }
                .listStyle(.inset)
                .searchable(text: $searchText, prompt: "Search bids...")
            }
            #if os(macOS)
            .frame(minWidth: 280, idealWidth: 480)
            #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: { showAddBid = true }) {
                        Label("New Bid", systemImage: "plus")
                    }
                }
            }

            // Detail pane
            if let bid = selectedBid {
                BidDetailView(bidID: bid.id)
                    #if os(macOS)
                    .frame(minWidth: 250, idealWidth: 450)
                    #endif
            } else {
                EmptyStateView(icon: "doc.text", title: "No Bid Selected",
                               message: "Select a bid from the list to view details.",
                               buttonTitle: "Add Bid") { showAddBid = true }
                #if os(macOS)
                .frame(minWidth: 250, idealWidth: 450)
                #endif
            }
        }
        .sheet(isPresented: $showAddBid) {
            AddBidView()
        }
        .sheet(item: $bidToConvert) { bid in
            ConvertBidToProjectView(bid: bid)
        }
        .confirmationDialog(
            "Delete bid?",
            isPresented: Binding(
                get: { bidToDelete != nil },
                set: { if !$0 { bidToDelete = nil } }
            ),
            presenting: bidToDelete
        ) { bid in
            Button("Delete", role: .destructive) {
                dataStore.deleteBid(bid)
                if selectedBid?.id == bid.id { selectedBid = nil }
                bidToDelete = nil
            }
            Button("Cancel", role: .cancel) { bidToDelete = nil }
        } message: { bid in
            Text("\"\(bid.projectName)\" for \(bid.clientName) will be removed. This cannot be undone.")
        }
        .navigationTitle("Bidding")
    }
}

// MARK: - Bid Row
struct BidRow: View {
    let bid: BidProject
    var clientType: RateType? = nil

    var statusColor: Color {
        switch bid.status {
        case .pending: return AppTheme.BidStatus.open
        case .workingOn: return AppTheme.BidStatus.workingOn
        case .readyToSubmit: return AppTheme.BidStatus.ready
        case .submitted: return AppTheme.BidStatus.submitted
        case .awarded: return AppTheme.BidStatus.won
        case .lost: return AppTheme.BidStatus.lost
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                Text(bid.projectName)
                    .font(.headline)
                Spacer()
                StatusBadge(text: bid.status.rawValue, color: statusColor)
            }

            HStack {
                Label(bid.clientName, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let type = clientType {
                    StatusBadge(text: type == .generalContractor ? "GC" : "Sub",
                                color: type == .generalContractor ? AppTheme.primaryOrange : .purple)
                }
                Spacer()
                Text(bid.bidAmount.currencyFormatted)
                    .font(.callout)
                    .fontWeight(.semibold)
            }

            HStack {
                if !bid.address.isEmpty {
                    Label(bid.address, systemImage: AppIcons.location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Label(bid.bidDueDate.shortDate, systemImage: "calendar")
                    .font(.caption)
                    .foregroundColor(bid.bidDueDate < Date() && !bid.isSubmitted ? .red : .secondary)
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}
