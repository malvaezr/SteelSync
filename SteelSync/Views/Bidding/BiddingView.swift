import SwiftUI
import CloudKit

enum BidSortMode: String, CaseIterable, Hashable {
    case priority = "Priority"
    case dueDate = "Due Date"
    case bidAmount = "Bid Amount"
    case projectName = "Project Name"

    var icon: String {
        switch self {
        case .priority: return "exclamationmark.circle"
        case .dueDate: return "calendar"
        case .bidAmount: return "dollarsign.circle"
        case .projectName: return "textformat"
        }
    }
}

struct BiddingView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedFilter = "Pending"
    @State private var searchText = ""
    @State private var showAddBid = false
    @State private var selectedBid: BidProject?
    @State private var bidToDelete: BidProject?
    @State private var bidToConvert: BidProject?
    @State private var sortMode: BidSortMode = .priority
    @State private var showExportSheet = false

    private let filters = ["All", "Pending", "Working On", "Ready", "Submitted", "Awarded", "Lost"]

    private func count(for filter: String) -> Int {
        switch filter {
        case "All": return dataStore.bids.count
        case "Pending": return dataStore.bids.filter { $0.status == .pending }.count
        case "Working On": return dataStore.bids.filter { $0.status == .workingOn }.count
        case "Ready": return dataStore.bids.filter { $0.status == .readyToSubmit }.count
        case "Submitted": return dataStore.bids.filter { $0.status == .submitted }.count
        case "Awarded": return dataStore.bids.filter { $0.status == .awarded }.count
        case "Lost": return dataStore.bids.filter { $0.status == .lost }.count
        default: return 0
        }
    }

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
        switch sortMode {
        case .priority:
            return result.sorted {
                if $0.priority.sortOrder != $1.priority.sortOrder {
                    return $0.priority.sortOrder < $1.priority.sortOrder
                }
                return $0.bidDueDate < $1.bidDueDate
            }
        case .dueDate:
            return result.sorted { $0.bidDueDate < $1.bidDueDate }
        case .bidAmount:
            return result.sorted { $0.bidAmount > $1.bidAmount }
        case .projectName:
            return result.sorted { $0.projectName.localizedCaseInsensitiveCompare($1.projectName) == .orderedAscending }
        }
    }

    var body: some View {
        Group {
            #if os(iOS)
            // Compact iPad (portrait full-screen, Slide Over, narrow Stage
            // Manager) is too narrow for a side-by-side list+detail — drop
            // to a list-only view that opens detail in a full-screen cover.
            // Regular width keeps the existing two-pane HStack.
            GeometryReader { proxy in
                if proxy.size.width < 800 {
                    bidListPane
                        .fullScreenCover(item: $selectedBid) { bid in
                            NavigationStack {
                                BidDetailView(bidID: bid.id)
                                    .navigationTitle(bid.projectName)
                                    .navigationBarTitleDisplayMode(.inline)
                                    .toolbar {
                                        ToolbarItem(placement: .cancellationAction) {
                                            Button("Done") { selectedBid = nil }
                                        }
                                    }
                            }
                        }
                } else {
                    PlatformSplitView {
                        bidListPane
                        bidDetailPane
                    }
                }
            }
            #else
            PlatformSplitView {
                bidListPane
                bidDetailPane
            }
            #endif
        }
        .inlineForm(isPresented: $showAddBid) {
            AddBidView()
        }
        .sheet(isPresented: $showExportSheet) {
            ExportBidsSheet()
        }
        .sheet(item: $bidToConvert) { bid in
            ConvertBidToProjectView(bid: bid)
        }
        .sheet(item: $bidToDelete) { bid in
            ConfirmationPinSheet(
                title: "Delete Bid",
                detail: "\(bid.projectName)\nfor \(bid.clientName)\n\(bid.bidAmount.currencyFormatted)\n\nThis cannot be undone.",
                confirmLabel: "Delete",
                onConfirm: {
                    dataStore.deleteBid(bid)
                    if selectedBid?.id == bid.id { selectedBid = nil }
                }
            )
        }
        .navigationTitle("Bidding")
    }

    // MARK: - Panes (factored so the body can branch on width)

    @ViewBuilder
    private var bidListPane: some View {
            VStack(spacing: 0) {
                ScreenHeader(
                    title: "Bidding Pipeline",
                    subtitle: "\(dataStore.pendingBids.count) pending · \(dataStore.submittedBids.count) submitted",
                    icon: AppIcons.document
                ) {
                    Button { showExportSheet = true } label: {
                        Label("Export PDF", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.appSecondary)
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

                // Filters + Sort
                HStack(spacing: AppTheme.Spacing.sm) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: AppTheme.Spacing.sm) {
                            ForEach(filters, id: \.self) { filter in
                                FilterPill(filter, isSelected: selectedFilter == filter, count: count(for: filter)) {
                                    selectedFilter = filter
                                }
                            }
                        }
                    }

                    Menu {
                        Picker("Sort", selection: $sortMode) {
                            ForEach(BidSortMode.allCases, id: \.self) { mode in
                                Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                            }
                        }
                    } label: {
                        Label("Sort: \(sortMode.rawValue)", systemImage: "arrow.up.arrow.down")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.bottom, AppTheme.Spacing.sm)

                // Bid list
                List(selection: $selectedBid) {
                    ForEach(filteredBids) { bid in
                        BidRow(bid: bid, clientType: dataStore.client(for: bid.clientRef)?.preferredRateType)
                            .tag(bid)
                            .contextMenu {
                                Menu("Set Priority") {
                                    ForEach(BidPriority.allCases, id: \.self) { p in
                                        Button {
                                            var updated = bid
                                            updated.priority = p
                                            dataStore.updateBid(updated)
                                        } label: {
                                            Label(p.rawValue, systemImage: p.icon)
                                        }
                                    }
                                }
                                Divider()
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
    }

    @ViewBuilder
    private var bidDetailPane: some View {
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
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Image(systemName: bid.priority.icon)
                .foregroundColor(bid.priority.color)
                .font(.callout)
                .frame(width: 18)
                .padding(.top, 2)
                .help("Priority: \(bid.priority.rawValue)")

            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(spacing: 6) {
                    Text(bid.projectName)
                        .font(.headline)
                    if !bid.attachments.isEmpty {
                        HStack(spacing: 2) {
                            Image(systemName: "paperclip")
                                .font(.caption2)
                            Text("\(bid.attachments.count)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(AppTheme.primaryOrange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppTheme.primaryOrange.opacity(0.15))
                        .clipShape(Capsule())
                        .help("\(bid.attachments.count) plan\(bid.attachments.count == 1 ? "" : "s") uploaded")
                    }
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
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}
