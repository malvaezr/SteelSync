import SwiftUI
import CloudKit

/// Lets the user pick which bid statuses, which clients, and which columns
/// appear in a tabular PDF export of their bid pipeline. Defaults are tuned
/// for the common case Ruben asked for: pending + working-on, all clients,
/// the high-signal columns.
struct ExportBidsSheet: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var includePending: Bool = true
    @State private var includeWorkingOn: Bool = true
    @State private var includeReady: Bool = false
    @State private var includeSubmitted: Bool = false

    @State private var selectedClientIDs: Set<String> = []
    @State private var includeOtherClient: Bool = true  // bids without a clientRef
    @State private var clientsInitialized: Bool = false

    @State private var enabledColumns: Set<BidColumn> = Set(BidColumn.allCases.filter { $0.defaultEnabled })

    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Form {
                statusSection
                clientsSection
                columnsSection

                Section {
                    HStack {
                        Text("Bids to export")
                        Spacer()
                        Text("\(matchingBids.count)")
                            .fontWeight(.semibold)
                            .foregroundColor(matchingBids.isEmpty ? .red : .primary)
                    }
                }

                if let url = exportURL {
                    Section("Exported") {
                        Text(url.lastPathComponent)
                            .font(.caption)
                            .foregroundColor(.green)
                        ShareLink(
                            item: url,
                            subject: Text("Bids Export"),
                            message: Text("Bids list export — \(matchingBids.count) bid\(matchingBids.count == 1 ? "" : "s").")
                        ) {
                            Label("Share PDF", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Export Bids")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") { export() }
                        .disabled(enabledColumns.isEmpty || matchingBids.isEmpty)
                }
            }
            .onAppear { initializeClientsIfNeeded() }
        }
        #if os(macOS)
        .frame(width: 640, height: 720)
        #endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var statusSection: some View {
        Section("Statuses") {
            Toggle("Pending", isOn: $includePending)
            Toggle("Working On", isOn: $includeWorkingOn)
            Toggle("Ready to Submit", isOn: $includeReady)
            Toggle("Submitted", isOn: $includeSubmitted)
        }
    }

    @ViewBuilder
    private var clientsSection: some View {
        Section {
            HStack {
                Button("Select All") {
                    selectedClientIDs = Set(dataStore.clients.map { $0.id.recordName })
                    includeOtherClient = true
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Select None") {
                    selectedClientIDs = []
                    includeOtherClient = false
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)

            ForEach(dataStore.clients) { client in
                Toggle(isOn: clientBinding(for: client.id.recordName)) {
                    HStack {
                        Text(client.name)
                        Spacer()
                        Text(client.preferredRateType == .generalContractor ? "GC" : "Sub")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Toggle("Bids without a linked client", isOn: $includeOtherClient)
        } header: {
            Text("Clients (\(selectedClientIDs.count + (includeOtherClient ? 1 : 0)) of \(dataStore.clients.count + 1) selected)")
        }
    }

    @ViewBuilder
    private var columnsSection: some View {
        Section {
            HStack {
                Button("Select All") {
                    enabledColumns = Set(BidColumn.allCases)
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Defaults") {
                    enabledColumns = Set(BidColumn.allCases.filter { $0.defaultEnabled })
                }
                .buttonStyle(.borderless)
                Button("None") {
                    enabledColumns = []
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)

            ForEach(BidColumn.allCases) { col in
                Toggle(col.rawValue, isOn: columnBinding(for: col))
            }
        } header: {
            Text("Columns (\(enabledColumns.count) of \(BidColumn.allCases.count) selected)")
        }
    }

    // MARK: - Bindings

    private func clientBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { selectedClientIDs.contains(id) },
            set: { isOn in
                if isOn { selectedClientIDs.insert(id) }
                else { selectedClientIDs.remove(id) }
            }
        )
    }

    private func columnBinding(for col: BidColumn) -> Binding<Bool> {
        Binding(
            get: { enabledColumns.contains(col) },
            set: { isOn in
                if isOn { enabledColumns.insert(col) }
                else { enabledColumns.remove(col) }
            }
        )
    }

    // MARK: - Filtering

    private var matchingBids: [BidProject] {
        dataStore.bids.filter { bid in
            // Status
            switch bid.status {
            case .pending where !includePending: return false
            case .workingOn where !includeWorkingOn: return false
            case .readyToSubmit where !includeReady: return false
            case .submitted where !includeSubmitted: return false
            case .awarded, .lost: return false  // not part of "pending/working" export
            default: break
            }

            // Client
            if let ref = bid.clientRef {
                if !selectedClientIDs.contains(ref.recordID.recordName) { return false }
            } else {
                if !includeOtherClient { return false }
            }

            return true
        }
        .sorted {
            if $0.priority.sortOrder != $1.priority.sortOrder {
                return $0.priority.sortOrder < $1.priority.sortOrder
            }
            return $0.bidDueDate < $1.bidDueDate
        }
    }

    private func initializeClientsIfNeeded() {
        guard !clientsInitialized else { return }
        selectedClientIDs = Set(dataStore.clients.map { $0.id.recordName })
        clientsInitialized = true
    }

    // MARK: - Export

    private var statusLabel: String {
        var parts: [String] = []
        if includePending { parts.append("Pending") }
        if includeWorkingOn { parts.append("Working On") }
        if includeReady { parts.append("Ready") }
        if includeSubmitted { parts.append("Submitted") }
        return parts.isEmpty ? "None" : parts.joined(separator: ", ")
    }

    private var clientsLabel: String {
        let total = dataStore.clients.count + 1  // +1 for "no client"
        let selected = selectedClientIDs.count + (includeOtherClient ? 1 : 0)
        if selected == total { return "All" }
        if selected == 0 { return "None" }
        return "\(selected) of \(total)"
    }

    private func export() {
        // Preserve column order based on BidColumn.allCases.
        let orderedColumns = BidColumn.allCases.filter { enabledColumns.contains($0) }
        let renderer = BidsListPDFRenderer(
            bids: matchingBids,
            columns: orderedColumns,
            statusLabel: statusLabel,
            clientsLabel: clientsLabel
        )
        if let url = renderer.render() {
            exportURL = url
            #if os(macOS)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            #endif
        }
    }
}
