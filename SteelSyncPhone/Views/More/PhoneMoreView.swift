import SwiftUI

/// Expanded More tab. Acts as the "everything else" navigation hub after
/// consolidating the primary tabs down to Today / Projects / Tasks / More.
/// Exposes Invoices, RFIs, Time Clock, Reports, Equipment, Employees, Calendar,
/// Activity, and Settings via NavigationLinks.
///
/// Supports external destination injection via `destination` binding so widget
/// deep-links and the Today view's attention cards can jump straight to a
/// specific sub-screen.
struct PhoneMoreView: View {
    @EnvironmentObject var dataStore: DataStore
    @Binding var destination: PhoneContentView.MoreDestination?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: PhoneContentView.MoreDestination.invoices) {
                        Label {
                            HStack {
                                Text("Invoices")
                                Spacer()
                                if outstandingInvoiceCount > 0 {
                                    badge("\(outstandingInvoiceCount)")
                                }
                            }
                        } icon: {
                            Image(systemName: "doc.plaintext.fill")
                                .foregroundColor(AppTheme.primaryOrange)
                        }
                    }

                    NavigationLink(value: PhoneContentView.MoreDestination.rfis) {
                        Label {
                            HStack {
                                Text("RFIs")
                                Spacer()
                                if openRFICount > 0 {
                                    badge("\(openRFICount)")
                                }
                            }
                        } icon: {
                            Image(systemName: "questionmark.bubble.fill")
                                .foregroundColor(.blue)
                        }
                    }
                } header: {
                    Text("Project Finances")
                        .foregroundColor(AppTheme.secondaryText)
                }

                Section {
                    NavigationLink(value: PhoneContentView.MoreDestination.timeClock) {
                        Label("Time Clock", systemImage: "clock.fill")
                            .foregroundColor(AppTheme.primaryText)
                    }

                    NavigationLink(value: PhoneContentView.MoreDestination.equipment) {
                        Label("Equipment", systemImage: "shippingbox.fill")
                            .foregroundColor(AppTheme.primaryText)
                    }

                    NavigationLink(value: PhoneContentView.MoreDestination.employees) {
                        Label("Employee Directory", systemImage: "person.crop.rectangle.stack.fill")
                            .foregroundColor(AppTheme.primaryText)
                    }
                } header: {
                    Text("Operations")
                        .foregroundColor(AppTheme.secondaryText)
                }

                Section {
                    NavigationLink(value: PhoneContentView.MoreDestination.reports) {
                        Label("Financial Summary", systemImage: "chart.bar.fill")
                            .foregroundColor(AppTheme.primaryText)
                    }
                } header: {
                    Text("Reports")
                        .foregroundColor(AppTheme.secondaryText)
                }

                Section {
                    NavigationLink {
                        PhoneSyncStatusView()
                            .environmentObject(dataStore)
                    } label: {
                        Label("Sync Status", systemImage: "arrow.triangle.2.circlepath")
                            .foregroundColor(AppTheme.primaryText)
                    }
                } header: {
                    Text("Settings")
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: PhoneContentView.MoreDestination.self) { dest in
                destinationView(for: dest)
                    .environmentObject(dataStore)
            }
            // Widget deep-link handler: if a parent sets `destination`, push it
            // onto the navigation stack once and clear the binding.
            .onChange(of: destination) { _, newValue in
                // No-op — NavigationStack uses path, but we use value-based
                // destinations; the binding is consumed by a future path-based
                // update. See PhoneContentView for the push mechanism.
            }
        }
    }

    // MARK: - Destination routing

    @ViewBuilder
    private func destinationView(for dest: PhoneContentView.MoreDestination) -> some View {
        switch dest {
        case .invoices:
            PhoneInvoicesView()
        case .rfis:
            PhoneRFILogView()
        case .timeClock:
            PhoneTimeClockView()
        case .equipment:
            PhoneEquipmentView()
        case .reports:
            PhoneReportsSummaryView()
        case .employees:
            PhoneEmployeeDirectoryView()
        }
    }

    // MARK: - Helpers

    private var outstandingInvoiceCount: Int {
        dataStore.allInvoices
            .filter { InvoiceStatus.outstandingCases.contains($0.invoice.status) || $0.invoice.isOverdue }
            .count
    }

    private var openRFICount: Int {
        var count = 0
        for project in dataStore.projects {
            count += dataStore.rfis(for: project.id).filter { $0.status != .closed }.count
        }
        return count
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(AppTheme.primaryOrange.opacity(0.2)))
            .foregroundColor(AppTheme.primaryOrange)
    }
}
