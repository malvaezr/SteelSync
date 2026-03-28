import SwiftUI
import CloudKit

struct BidDetailView: View {
    let bidID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore

    private var bid: BidProject {
        dataStore.bids.first { $0.id == bidID } ?? BidProject(projectName: "", clientName: "")
    }
    @State private var showEditBid = false
    @State private var showAddTouchpoint = false
    @State private var showConvert = false
    @State private var isUploading = false
    @State private var uploadMessage = ""
    @State private var showUploadAlert = false

    var statusColor: Color {
        switch bid.status {
        case .pending: return AppTheme.BidStatus.open
        case .readyToSubmit: return AppTheme.BidStatus.ready
        case .submitted: return AppTheme.BidStatus.submitted
        case .awarded: return AppTheme.BidStatus.won
        case .lost: return AppTheme.BidStatus.lost
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bid.projectName)
                            .font(AppTheme.Typography.title2)
                        HStack(spacing: 4) {
                            Text(bid.clientName)
                                .font(.callout)
                                .foregroundColor(.secondary)
                            if let client = dataStore.client(for: bid.clientRef) {
                                StatusBadge(text: client.preferredRateType == .generalContractor ? "GC" : "Sub",
                                            color: client.preferredRateType == .generalContractor ? AppTheme.primaryOrange : .purple)
                            }
                        }
                    }
                    Spacer()
                    StatusBadge(text: bid.status.rawValue, color: statusColor)

                    Menu {
                        Button("Edit") { showEditBid = true }
                        if bid.isSubmitted && !bid.isAwarded && !bid.isLost {
                            Button("Convert to Project") { showConvert = true }
                        }
                        if !bid.isSubmitted {
                            Button("Mark Ready") {
                                var updated = bid
                                updated.isReadyToSubmit = true
                                dataStore.updateBid(updated)
                            }
                            Button("Mark Submitted") {
                                var updated = bid
                                updated.isSubmitted = true
                                updated.submittedDate = Date()
                                dataStore.updateBid(updated)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 30)
                }

                // Bid Info
                GroupBox("Bid Information") {
                    VStack(spacing: AppTheme.Spacing.sm) {
                        InfoRow(label: "Bid Amount", value: bid.bidAmount.currencyFormatted, icon: "dollarsign.circle")
                        Divider()
                        InfoRow(label: "Due Date", value: bid.bidDueDate.shortDate, icon: "calendar")
                        Divider()
                        if !bid.address.isEmpty {
                            InfoRow(label: "Location", value: bid.address, icon: "mappin")
                            Divider()
                        }
                        InfoRow(label: "Created", value: bid.createdDate.shortDate, icon: "clock")
                        if let submitted = bid.submittedDate {
                            Divider()
                            InfoRow(label: "Submitted", value: submitted.shortDate, icon: "paperplane")
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // Construction Metrics
                if bid.squareFeet > 0 || bid.estimatedTons > 0 {
                    GroupBox("Construction Metrics") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: AppTheme.Spacing.sm) {
                            if bid.squareFeet > 0 { metricItem("Square Feet", "\(bid.squareFeet.formatted())", "ruler") }
                            if bid.numberOfBeams > 0 { metricItem("Beams", "\(bid.numberOfBeams)", "line.diagonal") }
                            if bid.numberOfColumns > 0 { metricItem("Columns", "\(bid.numberOfColumns)", "rectangle.split.1x2") }
                            if bid.numberOfJoists > 0 { metricItem("Joists", "\(bid.numberOfJoists)", "line.3.horizontal") }
                            if bid.numberOfWallPanels > 0 { metricItem("Wall Panels", "\(bid.numberOfWallPanels)", "rectangle.grid.1x2") }
                            if bid.estimatedTons > 0 { metricItem("Est. Tons", String(format: "%.1f", bid.estimatedTons), "scalemass") }
                        }
                        .padding(.vertical, AppTheme.Spacing.sm)
                    }
                }

                // Plans & Documents
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        HStack {
                            Text("Plans & Documents")
                                .font(AppTheme.Typography.headline)
                            Spacer()
                            Text("\(bid.attachments.count) file\(bid.attachments.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if isUploading {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                                Text("Uploading...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Button { uploadFiles() } label: {
                                    Label("Upload", systemImage: "plus")
                                        .font(.callout)
                                }
                                .buttonStyle(.borderless)
                            }
                        }

                        if bid.attachments.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "doc.badge.plus")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                    Text("No plans uploaded yet")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Upload PDF plans, drawings, or images")
                                        .font(.caption2)
                                        .foregroundColor(AppTheme.tertiaryText)
                                }
                                .padding(.vertical, AppTheme.Spacing.md)
                                Spacer()
                            }
                        } else {
                            ForEach(bid.attachments) { attachment in
                                HStack(spacing: AppTheme.Spacing.sm) {
                                    Image(systemName: FileStorageService.iconName(for: attachment.filename))
                                        .foregroundColor(AppTheme.primaryOrange)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(attachment.filename)
                                            .fontWeight(.medium)
                                            .lineLimit(1)
                                        HStack(spacing: AppTheme.Spacing.sm) {
                                            Text(FileStorageService.fileTypeLabel(for: attachment.filename))
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(AppTheme.primaryOrange.opacity(0.15))
                                                .foregroundColor(AppTheme.primaryOrange)
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                            Text(attachment.fileSizeFormatted)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(attachment.uploadedDate.shortDate)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Button { FileStorageService.openFile(attachment) } label: {
                                        Image(systemName: "eye.fill")
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Open")

                                    Button { FileStorageService.revealInFinder(attachment) } label: {
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Show in Finder")

                                    Button {
                                        dataStore.removeAttachment(attachment, from: bid.id)
                                    } label: {
                                        Image(systemName: "trash.fill")
                                            .foregroundColor(.red.opacity(0.6))
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Delete")
                                }
                                .padding(.vertical, 4)

                                if attachment.id != bid.attachments.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // Touchpoints
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        HStack {
                            Text("Communication Log")
                                .font(AppTheme.Typography.headline)
                            Spacer()
                            Button(action: { showAddTouchpoint = true }) {
                                Label("Add", systemImage: "plus")
                                    .font(.callout)
                            }
                            .buttonStyle(.borderless)
                        }

                        if bid.touchpoints.isEmpty {
                            Text("No touchpoints recorded yet.")
                                .foregroundColor(.secondary)
                                .padding(.vertical, AppTheme.Spacing.sm)
                        } else {
                            ForEach(bid.touchpoints.sorted(by: { $0.date > $1.date })) { tp in
                                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                                    Image(systemName: tp.type.icon)
                                        .foregroundColor(AppTheme.primaryOrange)
                                        .frame(width: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(tp.type.rawValue)
                                                .fontWeight(.medium)
                                            Spacer()
                                            Text(tp.date.shortDate)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        if !tp.notes.isEmpty {
                                            Text(tp.notes)
                                                .font(.callout)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                if tp.id != bid.touchpoints.sorted(by: { $0.date > $1.date }).last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // Notes
                if !bid.notes.isEmpty {
                    GroupBox("Notes") {
                        Text(bid.notes)
                            .padding(.vertical, AppTheme.Spacing.sm)
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .sheet(isPresented: $showEditBid) {
            EditBidView(bid: bid)
        }
        .sheet(isPresented: $showAddTouchpoint) {
            AddTouchpointView(bid: bid)
        }
        .sheet(isPresented: $showConvert) {
            ConvertBidToProjectView(bid: bid)
        }
        .alert("File Upload", isPresented: $showUploadAlert) {
            Button("OK") { }
        } message: {
            Text(uploadMessage)
        }
    }

    private func uploadFiles() {
        #if os(macOS)
        let urls = FileStorageService.presentFilePicker()
        guard !urls.isEmpty else { return }
        #else
        // On iPad, file picking is handled via UIDocumentPickerViewController
        // For now, show a placeholder message
        uploadMessage = "Use the Files app to import documents on iPad."
        showUploadAlert = true
        return
        let urls: [URL] = []
        #endif

        isUploading = true
        var successes = 0
        var errors: [String] = []

        for url in urls {
            let result = FileStorageService.importFile(from: url, bidID: bid.recordID.recordName)
            switch result {
            case .success(let attachment):
                dataStore.addAttachment(attachment, to: bid.id)
                successes += 1
            case .failure(let error):
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        isUploading = false

        if !errors.isEmpty {
            uploadMessage = "Failed to upload \(errors.count) file(s):\n\n" + errors.joined(separator: "\n")
            showUploadAlert = true
        } else if successes > 0 {
            uploadMessage = "Successfully uploaded \(successes) file(s)."
            showUploadAlert = true
        }
    }

    private func metricItem(_ label: String, _ value: String, _ icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(AppTheme.primaryOrange)
                .frame(width: 20)
            VStack(alignment: .leading) {
                Text(value).fontWeight(.semibold)
                Text(label).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
