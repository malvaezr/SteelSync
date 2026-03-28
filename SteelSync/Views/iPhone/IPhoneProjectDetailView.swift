#if STEELSYNC_IPHONE
import SwiftUI

struct IPhoneProjectDetailView: View {
    @EnvironmentObject var dataStore: DataStore
    let project: Project

    private var changeOrdersList: [ChangeOrder] {
        dataStore.changeOrders(for: project.id)
    }

    private var paymentsList: [Payment] {
        dataStore.payments(for: project.id)
    }

    private var changeOrderTotal: Decimal {
        changeOrdersList.reduce(0) { $0 + $1.amount }
    }

    private var paymentsTotal: Decimal {
        paymentsList.reduce(0) { $0 + $1.amount }
    }

    private var balance: ProjectBalanceSummary {
        project.balanceSummary
    }

    private var margin: Double {
        project.profitMargin
    }

    var body: some View {
        List {
            // MARK: - Details
            Section("Details") {
                if let clientName = dataStore.clientName(for: project) {
                    InfoRow(label: "Client", value: clientName, icon: "person.fill")
                }
                if !project.location.isEmpty {
                    InfoRow(label: "Location", value: project.location, icon: "mappin.and.ellipse")
                }
                if let start = project.startDate {
                    InfoRow(label: "Start Date", value: start.shortDate, icon: "calendar")
                }
                if let end = project.endDate {
                    InfoRow(label: "End Date", value: end.shortDate, icon: "calendar.badge.checkmark")
                }
                if let completed = project.actualCompletionDate {
                    InfoRow(label: "Completed", value: completed.shortDate, icon: "checkmark.circle")
                }
                InfoRow(label: "Status", value: project.computedStatus, icon: "circle.fill")
            }

            // MARK: - Financials
            Section("Financials") {
                InfoRow(label: "Contract", value: balance.contractAmount.currencyFormatted, icon: "doc.text")
                InfoRow(label: "Change Orders", value: balance.changeOrderTotal.currencyFormatted, icon: "arrow.triangle.branch")
                InfoRow(label: "Total Revenue", value: project.totalRevenue.currencyFormatted, icon: "arrow.up.circle")
                InfoRow(label: "Total Costs", value: balance.totalCosts.currencyFormatted, icon: "arrow.down.circle")
                InfoRow(label: "Payments", value: balance.paymentsTotal.currencyFormatted, icon: "creditcard")
                InfoRow(label: "Profit", value: balance.profit.currencyFormatted, icon: "chart.line.uptrend.xyaxis")
                InfoRow(label: "Margin", value: String(format: "%.1f%%", margin), icon: "percent")
            }

            // MARK: - Change Orders
            Section("Change Orders") {
                InfoRow(label: "Count", value: "\(changeOrdersList.count)", icon: "doc.badge.plus")
                InfoRow(label: "Total", value: changeOrderTotal.currencyFormatted, icon: "dollarsign.circle")
            }

            // MARK: - Payments
            Section("Payments") {
                InfoRow(label: "Count", value: "\(paymentsList.count)", icon: "banknote")
                InfoRow(label: "Total", value: paymentsTotal.currencyFormatted, icon: "dollarsign.circle")
            }

            // MARK: - Notes
            if !project.notes.isEmpty {
                Section("Notes") {
                    Text(project.notes)
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.large)
    }
}
#endif
