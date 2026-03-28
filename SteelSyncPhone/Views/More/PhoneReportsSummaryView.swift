import SwiftUI

struct PhoneReportsSummaryView: View {
    @EnvironmentObject var dataStore: DataStore

    private let columns = [
        GridItem(.flexible(), spacing: AppTheme.Spacing.sm),
        GridItem(.flexible(), spacing: AppTheme.Spacing.sm)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: AppTheme.Spacing.sm) {
                MetricCard(
                    title: "Pipeline Value",
                    value: dataStore.totalBidPipeline.currencyFormatted,
                    icon: "chart.line.uptrend.xyaxis",
                    color: AppTheme.info
                )

                MetricCard(
                    title: "Win Rate",
                    value: String(format: "%.0f%%", dataStore.bidWinRate),
                    icon: "trophy.fill",
                    color: AppTheme.success
                )

                MetricCard(
                    title: "Active Projects",
                    value: "\(dataStore.activeProjects.count)",
                    icon: "building.2.fill",
                    color: AppTheme.primaryOrange
                )

                MetricCard(
                    title: "Contract Value",
                    value: dataStore.totalContractValue.currencyFormatted,
                    icon: "doc.text.fill",
                    color: AppTheme.primaryGreen
                )

                MetricCard(
                    title: "Total Revenue",
                    value: dataStore.totalRevenue.currencyFormatted,
                    icon: "banknote.fill",
                    color: AppTheme.success
                )

                MetricCard(
                    title: "Total Profit",
                    value: dataStore.totalProfit.currencyFormatted,
                    icon: "arrow.up.right",
                    color: dataStore.totalProfit >= 0 ? AppTheme.success : AppTheme.error
                )

                MetricCard(
                    title: "Total Costs",
                    value: dataStore.totalCosts.currencyFormatted,
                    icon: "creditcard.fill",
                    color: AppTheme.warning
                )

                MetricCard(
                    title: "Remaining Balance",
                    value: dataStore.totalRemainingBalance.currencyFormatted,
                    icon: "wallet.bifold.fill",
                    color: AppTheme.info
                )
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
    }
}
