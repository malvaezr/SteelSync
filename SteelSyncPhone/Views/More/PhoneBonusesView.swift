import SwiftUI

/// Phone-side foreman bonus estimator. Calls the same `DataStore.computeBonuses`
/// the Mac/iPad Reports → Bonuses tab uses, so numbers stay in lock-step.
/// Year + basis + multiplier controls at the top; per-foreman cards below
/// with expandable per-project breakdown.
struct PhoneBonusesView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var basis: BonusBasis = .revenue
    @State private var multiplier: Double = 2.0

    var body: some View {
        let breakdowns = dataStore.computeBonuses(year: year, basis: basis, multiplierPct: multiplier)
        let pool = breakdowns.reduce(Decimal.zero) { $0 + $1.total }

        return ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {

                // Parameters block
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    HStack {
                        Text("Year")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 78, alignment: .leading)
                        Picker("Year", selection: $year) {
                            ForEach(dataStore.availableBonusYears, id: \.self) { yr in
                                Text(verbatim: "\(yr)").tag(yr)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        Spacer()
                    }
                    HStack {
                        Text("Basis")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 78, alignment: .leading)
                        Picker("Basis", selection: $basis) {
                            ForEach(BonusBasis.allCases, id: \.self) { b in
                                Text(b.rawValue).tag(b)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    HStack {
                        Text("Multiplier")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .frame(width: 78, alignment: .leading)
                        TextField("0.0", value: $multiplier, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 90)
                        Text("% of \(basis.rawValue.lowercased())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.secondaryBackground))

                // Summary card — total estimated pool.
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Estimated Pool")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(pool.currencyFormatted)
                            .font(.title2.monospacedDigit().weight(.semibold))
                            .foregroundColor(AppTheme.primaryOrange)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Foremen")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(breakdowns.filter { $0.total > 0 }.count) / \(breakdowns.count)")
                            .font(.title3.monospacedDigit().weight(.semibold))
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.secondaryBackground))

                // Per-foreman list — DisclosureGroup for per-project detail.
                if breakdowns.isEmpty {
                    Text("No foremen on file. Add crew and mark them as Foreman.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(breakdowns) { b in
                        foremanCard(b)
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.bottom, AppTheme.Spacing.lg)
        }
        .navigationTitle("Bonuses")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func foremanCard(_ b: BonusBreakdown) -> some View {
        DisclosureGroup {
            if b.perProject.isEmpty {
                Text("No completed tasks ended in \(String(year)).")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(b.perProject) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.project.title)
                                    .font(.callout)
                                    .lineLimit(1)
                                Spacer()
                                Text(item.contribution.currencyFormatted)
                                    .font(.callout.monospacedDigit())
                            }
                            HStack(spacing: 6) {
                                Text("\(Int(item.completionPct * 100))%")
                                Text("·")
                                Text("\(item.foremanDays.formatted(.number.precision(.fractionLength(0...1)))) / \(item.projectTotalDays) d")
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.foreman.fullName)
                        .font(.headline)
                    Text("\(b.perProject.count) project\(b.perProject.count == 1 ? "" : "s") · \(b.totalCompletionDays.formatted(.number.precision(.fractionLength(0...1)))) d")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(b.total.currencyFormatted)
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundColor(AppTheme.primaryOrange)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(AppTheme.secondaryBackground))
    }
}
