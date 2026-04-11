import SwiftUI
import CloudKit

// MARK: - Pay Apps Tab (AIA G703 Schedule of Values)

struct PayAppsTab: View {
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @State private var showCreatePayApp = false
    @State private var editingPayApp: PayApplication?

    private var payApps: [PayApplication] {
        dataStore.payApps(for: project.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionHeaderView(title: "Pay Applications (G703)", action: { showCreatePayApp = true })

            if payApps.isEmpty {
                EmptyStateView(
                    icon: "doc.text.fill",
                    title: "No Pay Applications",
                    message: "Create a schedule of values to track progressive billing.",
                    buttonTitle: "Create Pay App"
                ) { showCreatePayApp = true }
                .frame(height: 200)
            } else {
                List {
                    ForEach(payApps) { payApp in
                        PayAppRow(payApp: payApp)
                            .contentShape(Rectangle())
                            .onTapGesture { editingPayApp = payApp }
                            .contextMenu {
                                Button("Edit") { editingPayApp = payApp }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    dataStore.deletePayApplication(payApp, from: project.id)
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 200)
            }
        }
        .sheet(isPresented: $showCreatePayApp) {
            CreatePayAppSheet(project: project)
        }
        .sheet(item: $editingPayApp) { payApp in
            EditPayAppSheet(payApp: payApp, project: project)
        }
    }
}

// MARK: - Pay App Row

private struct PayAppRow: View {
    let payApp: PayApplication

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Application #\(payApp.applicationNumber)")
                        .font(.headline)
                    StatusBadge(
                        text: String(format: "%.0f%%", payApp.overallPercentComplete),
                        color: payApp.overallPercentComplete >= 100 ? .green : AppTheme.primaryOrange
                    )
                }
                Text("Period to: \(payApp.periodTo.shortDate)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("This Period")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(payApp.totalThisPeriod.currencyFormatted)
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundColor(AppTheme.primaryOrange)
            }
            VStack(alignment: .trailing, spacing: 4) {
                Text("Total Completed")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(payApp.totalCompletedToDate.currencyFormatted)
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            }
            VStack(alignment: .trailing, spacing: 4) {
                Text("Retainage")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(payApp.totalRetainage.currencyFormatted)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create Pay App Sheet

struct CreatePayAppSheet: View {
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @State private var periodTo = Date()
    @State private var retainageRate = "10"

    var body: some View {
        NavigationStack {
            Form {
                Section("Application Details") {
                    let nextNum = (dataStore.payApps(for: project.id).map(\.applicationNumber).max() ?? 0) + 1
                    InfoRow(label: "Application #", value: "\(nextNum)")
                    InfoRow(label: "Project", value: project.title)
                    DatePicker("Period To", selection: $periodTo, displayedComponents: .date)
                    HStack {
                        Text("Retainage Rate")
                        Spacer()
                        TextField("10", text: $retainageRate)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                            #if !os(macOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Text("%")
                    }
                }

                Section("What will be included") {
                    let allCOs = dataStore.changeOrders(for: project.id)
                    let eligibleCOs = allCOs.filter { $0.submittedDate <= periodTo }
                    InfoRow(label: "Contract Amount", value: project.contractAmount.currencyFormatted)
                    InfoRow(label: "Change Orders (by \(periodTo.shortDate))", value: "\(eligibleCOs.count) (\(eligibleCOs.reduce(0) { $0 + $1.amount }.currencyFormatted))")
                    InfoRow(label: "Total Scheduled Value", value: (project.contractAmount + eligibleCOs.reduce(0) { $0 + $1.amount }).currencyFormatted)

                    let previousApps = dataStore.payApps(for: project.id)
                    if let last = previousApps.last {
                        InfoRow(label: "Previously Billed", value: last.totalCompletedToDate.currencyFormatted)
                        InfoRow(label: "Remaining", value: (last.totalScheduledValue - last.totalCompletedToDate).currencyFormatted)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Pay Application")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primaryOrange)
                }
            }
        }
        #if os(macOS)
        .frame(width: 500, height: 400)
        #endif
    }

    private func create() {
        let rate = Decimal(string: retainageRate).map { $0 / 100 } ?? Decimal(0.10)
        var payApp = dataStore.buildNewPayApp(for: project.id, periodTo: periodTo, retainageRate: rate)
        payApp.applicationDate = Date()
        dataStore.addPayApplication(payApp, to: project.id)
        dismiss()
    }
}

// MARK: - Edit Pay App Sheet (G703 SOV Editor)

struct EditPayAppSheet: View {
    @State var payApp: PayApplication
    let project: Project
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header info
                HStack {
                    VStack(alignment: .leading) {
                        Text("Application #\(payApp.applicationNumber)")
                            .font(.headline)
                        Text("Period to: \(payApp.periodTo.shortDate)")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Retainage: \(Int(Double(truncating: payApp.retainageRate * 100 as NSDecimalNumber)))%")
                            .font(.caption).foregroundColor(.secondary)
                        Text("Total: \(payApp.totalCompletedToDate.currencyFormatted)")
                            .font(.callout).fontWeight(.bold).foregroundColor(.green)
                    }
                }
                .padding()

                Divider()

                // G703 Column Headers
                ScrollView(.horizontal) {
                    VStack(spacing: 0) {
                        sovHeaderRow
                        Divider()

                        ForEach(Array(payApp.lineItems.enumerated()), id: \.element.id) { index, item in
                            sovDataRow(index: index, item: item)
                            Divider()
                        }

                        // Grand totals
                        sovTotalRow
                    }
                    .frame(minWidth: 800)
                }
            }
            .navigationTitle("Schedule of Values")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.primaryOrange)
                }
            }
        }
        #if os(macOS)
        .frame(width: 900, height: 600)
        #endif
    }

    // MARK: - G703 Header Row

    private var sovHeaderRow: some View {
        HStack(spacing: 0) {
            Text("A").sovHeader(width: 30)
            Text("B - Description").sovHeader(width: 160)
            Text("C - Scheduled\nValue").sovHeader(width: 100)
            Text("D - Previous\nApplication").sovHeader(width: 100)
            Text("E - This\nPeriod").sovHeader(width: 100)
            Text("F - Materials\nStored").sovHeader(width: 90)
            Text("G - Total\nCompleted").sovHeader(width: 100)
            Text("% (G÷C)").sovHeader(width: 60)
            Text("H - Balance\nTo Finish").sovHeader(width: 100)
            Text("I - Retainage").sovHeader(width: 90)
        }
        .background(Color.gray.opacity(0.15))
    }

    // MARK: - G703 Data Row

    private func sovDataRow(index: Int, item: SOVLineItem) -> some View {
        HStack(spacing: 0) {
            // A: Item number
            Text("\(item.itemNumber)")
                .sovCell(width: 30)

            // B: Description
            Text(item.description)
                .sovCell(width: 160, alignment: .leading)
                .lineLimit(2)

            // C: Scheduled value (read-only)
            Text(item.scheduledValue.currencyFormatted)
                .sovCell(width: 100)

            // D: Previous application (read-only, carried forward)
            Text(item.previousCompleted.currencyFormatted)
                .sovCell(width: 100)
                .foregroundColor(.secondary)

            // E: This period (EDITABLE)
            TextField("0", value: $payApp.lineItems[index].thisPeriodCompleted, format: .currency(code: "USD"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 95)
                .padding(.horizontal, 2)
                #if !os(macOS)
                .keyboardType(.decimalPad)
                #endif

            // F: Materials stored (EDITABLE)
            TextField("0", value: $payApp.lineItems[index].materialsStored, format: .currency(code: "USD"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 85)
                .padding(.horizontal, 2)
                #if !os(macOS)
                .keyboardType(.decimalPad)
                #endif

            // G: Total completed (calculated)
            Text(payApp.lineItems[index].totalCompletedToDate.currencyFormatted)
                .sovCell(width: 100)
                .foregroundColor(.green)

            // %: Percent complete (calculated)
            Text(String(format: "%.1f%%", payApp.lineItems[index].percentComplete))
                .sovCell(width: 60)
                .foregroundColor(payApp.lineItems[index].percentComplete >= 100 ? .green : AppTheme.primaryOrange)

            // H: Balance to finish (calculated)
            Text(payApp.lineItems[index].balanceToFinish.currencyFormatted)
                .sovCell(width: 100)

            // I: Retainage (calculated)
            Text(payApp.lineItems[index].retainage(at: payApp.retainageRate).currencyFormatted)
                .sovCell(width: 90)
                .foregroundColor(.orange)
        }
        .font(.caption)
    }

    // MARK: - Grand Total Row

    private var sovTotalRow: some View {
        HStack(spacing: 0) {
            Text("").sovCell(width: 30)
            Text("GRAND TOTALS").sovCell(width: 160, alignment: .leading).fontWeight(.bold)
            Text(payApp.totalScheduledValue.currencyFormatted).sovCell(width: 100).fontWeight(.bold)
            Text(payApp.totalPreviousCompleted.currencyFormatted).sovCell(width: 100)
            Text(payApp.totalThisPeriod.currencyFormatted).sovCell(width: 100).fontWeight(.bold).foregroundColor(AppTheme.primaryOrange)
            Text(payApp.totalMaterialsStored.currencyFormatted).sovCell(width: 90)
            Text(payApp.totalCompletedToDate.currencyFormatted).sovCell(width: 100).fontWeight(.bold).foregroundColor(.green)
            Text(String(format: "%.1f%%", payApp.overallPercentComplete)).sovCell(width: 60).fontWeight(.bold)
            Text(payApp.totalBalanceToFinish.currencyFormatted).sovCell(width: 100)
            Text(payApp.totalRetainage.currencyFormatted).sovCell(width: 90).fontWeight(.bold).foregroundColor(.orange)
        }
        .background(Color.gray.opacity(0.1))
        .font(.caption)
    }

    private func save() {
        dataStore.updatePayApplication(payApp, in: project.id)
        dismiss()
    }
}

// MARK: - SOV Cell Modifiers

extension Text {
    func sovHeader(width: CGFloat) -> some View {
        self.font(.system(size: 9, weight: .bold))
            .multilineTextAlignment(.center)
            .frame(width: width, alignment: .center)
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
    }

    func sovCell(width: CGFloat, alignment: Alignment = .trailing) -> some View {
        self.frame(width: width, alignment: alignment)
            .padding(.vertical, 8)
            .padding(.horizontal, 2)
    }
}
