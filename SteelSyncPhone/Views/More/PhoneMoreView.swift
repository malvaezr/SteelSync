import SwiftUI

struct PhoneMoreView: View {
    @EnvironmentObject var dataStore: DataStore

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PhoneEquipmentView()
                            .environmentObject(dataStore)
                    } label: {
                        Label("Equipment", systemImage: "shippingbox.fill")
                            
                    }

                    NavigationLink {
                        PhoneEmployeeDirectoryView()
                            .environmentObject(dataStore)
                    } label: {
                        Label("Employee Directory", systemImage: "person.crop.rectangle.stack.fill")
                            
                    }
                } header: {
                    Text("Operations")
                        .foregroundColor(AppTheme.secondaryText)
                }

                Section {
                    NavigationLink {
                        PhoneReportsSummaryView()
                            .environmentObject(dataStore)
                    } label: {
                        Label("Financial Summary", systemImage: "chart.bar.fill")
                            
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
                            
                    }
                } header: {
                    Text("Settings")
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
