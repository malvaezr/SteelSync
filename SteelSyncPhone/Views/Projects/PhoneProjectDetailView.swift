import SwiftUI

struct PhoneProjectDetailView: View {
    @EnvironmentObject var dataStore: DataStore
    let project: Project

    private var liveProject: Project {
        dataStore.projects.first(where: { $0.id == project.id }) ?? project
    }

    private var changeOrderList: [ChangeOrder] {
        dataStore.changeOrders(for: liveProject.id)
    }

    private var paymentList: [Payment] {
        dataStore.payments(for: liveProject.id)
    }

    private var costList: [Cost] {
        dataStore.costs(for: liveProject.id)
    }

    var body: some View {
        List {
            // MARK: - Details
            Section("Details") {
                InfoRow(label: "Status", value: liveProject.computedStatus, icon: "circle.fill")
                if !liveProject.location.isEmpty {
                    InfoRow(label: "Location", value: liveProject.location, icon: "mappin.and.ellipse")
                }
                if let start = liveProject.startDate {
                    InfoRow(label: "Start Date", value: start.shortDate, icon: "calendar")
                }
                if let end = liveProject.endDate {
                    InfoRow(label: "End Date", value: end.shortDate, icon: "calendar.badge.clock")
                }
                if let completion = liveProject.actualCompletionDate {
                    InfoRow(label: "Completed", value: completion.shortDate, icon: "checkmark.circle")
                }
                if let gcName = dataStore.gcClient(for: liveProject)?.name {
                    InfoRow(label: "GC", value: gcName, icon: "building.2")
                }
                if let subName = dataStore.subClient(for: liveProject)?.name {
                    InfoRow(label: "Subcontractor", value: subName, icon: "person.2")
                }
                if let legacyName = dataStore.clientName(for: liveProject),
                   dataStore.gcClient(for: liveProject) == nil,
                   dataStore.subClient(for: liveProject) == nil {
                    InfoRow(label: "Client", value: legacyName, icon: "person.crop.circle")
                }
            }

            // MARK: - Financials
            Section("Financials") {
                InfoRow(label: "Contract", value: liveProject.contractAmount.currencyFormatted)
                InfoRow(label: "Change Orders", value: liveProject.balanceSummary.changeOrderTotal.currencyFormatted)
                InfoRow(label: "Total Revenue", value: liveProject.totalRevenue.currencyFormatted)

                Divider()

                InfoRow(label: "Costs", value: liveProject.totalCosts.currencyFormatted)
                InfoRow(label: "Payments Received", value: liveProject.totalPayments.currencyFormatted)
                InfoRow(label: "Remaining Balance", value: liveProject.remainingBalance.currencyFormatted)

                Divider()

                HStack {
                    Text("Profit")
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    Text(liveProject.profit.currencyFormatted)
                        .fontWeight(.bold)
                        .foregroundColor(liveProject.profit >= 0 ? .green : .red)
                }

                HStack {
                    Text("Margin")
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    Text(String(format: "%.1f%%", liveProject.profitMargin))
                        .fontWeight(.bold)
                        .foregroundColor(liveProject.profitMargin >= 0 ? .green : .red)
                }
            }

            // MARK: - Change Orders
            Section {
                HStack {
                    Label("Count", systemImage: "doc.text")
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    Text("\(changeOrderList.count)")
                        .fontWeight(.medium)
                }
                HStack {
                    Label("Total", systemImage: "dollarsign.circle")
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    Text(changeOrderList.reduce(Decimal.zero) { $0 + $1.amount }.currencyFormatted)
                        .fontWeight(.medium)
                        .foregroundColor(AppTheme.primaryOrange)
                }
            } header: {
                Text("Change Orders")
            }

            // MARK: - Payments
            Section {
                HStack {
                    Label("Count", systemImage: "creditcard")
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    Text("\(paymentList.count)")
                        .fontWeight(.medium)
                }
                HStack {
                    Label("Total", systemImage: "dollarsign.circle")
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    Text(paymentList.reduce(Decimal.zero) { $0 + $1.amount }.currencyFormatted)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
            } header: {
                Text("Payments")
            }

            // MARK: - Costs
            Section {
                HStack {
                    Label("Count", systemImage: "cart")
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    Text("\(costList.count)")
                        .fontWeight(.medium)
                }
                HStack {
                    Label("Total", systemImage: "dollarsign.circle")
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                    Text(costList.reduce(Decimal.zero) { $0 + $1.amount }.currencyFormatted)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                }
            } header: {
                Text("Costs")
            }

            // MARK: - Notes
            if !liveProject.notes.isEmpty {
                Section("Notes") {
                    Text(liveProject.notes)
                        .font(AppTheme.Typography.body)
                        
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(liveProject.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
