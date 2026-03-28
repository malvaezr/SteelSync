#if STEELSYNC_IPHONE
import SwiftUI

struct IPhoneBidDetailView: View {
    @EnvironmentObject var dataStore: DataStore
    let bid: BidProject

    private func statusColor(for status: BidProject.BidStatus) -> Color {
        switch status {
        case .pending: return AppTheme.BidStatus.open
        case .readyToSubmit: return AppTheme.BidStatus.ready
        case .submitted: return AppTheme.BidStatus.submitted
        case .awarded: return AppTheme.BidStatus.won
        case .lost: return AppTheme.BidStatus.lost
        }
    }

    var body: some View {
        List {
            // MARK: - Details
            Section("Details") {
                InfoRow(label: "Client", value: bid.clientName, icon: "person.fill")
                if !bid.address.isEmpty {
                    InfoRow(label: "Address", value: bid.address, icon: "mappin.and.ellipse")
                }
                InfoRow(label: "Bid Amount", value: bid.bidAmount.currencyFormatted, icon: "dollarsign.circle")
                InfoRow(label: "Due Date", value: bid.bidDueDate.shortDate, icon: "calendar")
                HStack {
                    if let icon = statusIcon(for: bid.status) {
                        Image(systemName: icon)
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                    }
                    Text("Status")
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    StatusBadge(text: bid.status.rawValue, color: statusColor(for: bid.status))
                }
                if let submitted = bid.submittedDate {
                    InfoRow(label: "Submitted", value: submitted.shortDate, icon: "paperplane")
                }
            }

            // MARK: - Structure
            Section("Structure") {
                if bid.squareFeet > 0 {
                    InfoRow(label: "Square Feet", value: "\(bid.squareFeet.formatted()) sqft", icon: "square.dashed")
                }
                if bid.numberOfBeams > 0 {
                    InfoRow(label: "Beams", value: "\(bid.numberOfBeams)", icon: "rectangle.split.3x1")
                }
                if bid.numberOfColumns > 0 {
                    InfoRow(label: "Columns", value: "\(bid.numberOfColumns)", icon: "rectangle.portrait")
                }
                if bid.numberOfJoists > 0 {
                    InfoRow(label: "Joists", value: "\(bid.numberOfJoists)", icon: "line.3.horizontal")
                }
                if bid.numberOfWallPanels > 0 {
                    InfoRow(label: "Wall Panels", value: "\(bid.numberOfWallPanels)", icon: "rectangle.grid.1x2")
                }
                if bid.estimatedTons > 0 {
                    InfoRow(label: "Estimated Tons", value: String(format: "%.1f", bid.estimatedTons), icon: "scalemass")
                }
            }

            // MARK: - Touchpoints
            if !bid.touchpoints.isEmpty {
                Section("Touchpoints") {
                    ForEach(bid.touchpoints) { touchpoint in
                        HStack(spacing: AppTheme.Spacing.sm) {
                            Image(systemName: touchpoint.type.icon)
                                .foregroundColor(AppTheme.primaryOrange)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(touchpoint.type.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(touchpoint.date.shortDate)
                                    .font(.caption)
                                    .foregroundColor(AppTheme.tertiaryText)
                                if !touchpoint.notes.isEmpty {
                                    Text(touchpoint.notes)
                                        .font(.caption)
                                        .foregroundColor(AppTheme.secondaryText)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            // MARK: - Notes
            if !bid.notes.isEmpty {
                Section("Notes") {
                    Text(bid.notes)
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(bid.projectName)
        .navigationBarTitleDisplayMode(.large)
    }

    private func statusIcon(for status: BidProject.BidStatus) -> String? {
        switch status {
        case .pending: return "clock"
        case .readyToSubmit: return "checkmark.circle"
        case .submitted: return "paperplane.fill"
        case .awarded: return "trophy.fill"
        case .lost: return "xmark.circle"
        }
    }
}
#endif
