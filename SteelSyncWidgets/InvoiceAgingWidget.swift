import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct InvoiceAgingEntry: TimelineEntry {
    let date: Date
    let data: WidgetData
}

// MARK: - Provider

struct InvoiceAgingProvider: TimelineProvider {
    func placeholder(in context: Context) -> InvoiceAgingEntry {
        InvoiceAgingEntry(date: Date(), data: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (InvoiceAgingEntry) -> Void) {
        let data = context.isPreview ? .placeholder : WidgetDataStore.load()
        completion(InvoiceAgingEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<InvoiceAgingEntry>) -> Void) {
        let entry = InvoiceAgingEntry(date: Date(), data: WidgetDataStore.load())
        // Refresh every 30 minutes so aging buckets stay roughly fresh.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget

struct InvoiceAgingWidget: Widget {
    let kind: String = "InvoiceAgingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: InvoiceAgingProvider()) { entry in
            InvoiceAgingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Invoice Aging")
        .description("Outstanding receivables grouped by days past due.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - View

struct InvoiceAgingWidgetView: View {
    let entry: InvoiceAgingEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemLarge:
            largeBody
        default:
            mediumBody
        }
    }

    // MARK: - Medium

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("OUTSTANDING")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(format(entry.data.outstandingInvoiced))
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.orange)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("OVERDUE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(format(entry.data.overdueInvoiced))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.red)
                }
            }

            Spacer(minLength: 4)

            // Horizontal stacked bar for aging buckets
            agingBar

            HStack(spacing: 0) {
                agingLabel("Current", .green)
                agingLabel("1-30", .yellow)
                agingLabel("31-60", .orange)
                agingLabel("61-90", .red.opacity(0.7))
                agingLabel("90+", .red)
            }
        }
        .padding(4)
        .widgetURL(URL(string: "steelsync://invoices?filter=overdue"))
    }

    // MARK: - Large

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("OUTSTANDING INVOICES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Text(format(entry.data.outstandingInvoiced))
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(.orange)
            }

            Divider()

            // Large = vertical rows instead of a single bar
            VStack(spacing: 6) {
                agingRow("Current", entry.data.agingCurrent, .green)
                agingRow("1–30 days", entry.data.aging1to30, .yellow)
                agingRow("31–60 days", entry.data.aging31to60, .orange)
                agingRow("61–90 days", entry.data.aging61to90, .red.opacity(0.7))
                agingRow("90+ days", entry.data.agingOver90, .red)
            }

            Spacer(minLength: 0)

            if entry.data.overdueInvoiced > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("\(format(entry.data.overdueInvoiced)) overdue")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(4)
        .widgetURL(URL(string: "steelsync://invoices?filter=overdue"))
    }

    // MARK: - Sub-views

    /// Proportional horizontal bar showing relative sizes of each aging bucket.
    private var agingBar: some View {
        GeometryReader { geo in
            let total = max(1, totalOutstanding)
            HStack(spacing: 0) {
                segment(width: geo.size.width * (entry.data.agingCurrent / total), color: .green)
                segment(width: geo.size.width * (entry.data.aging1to30 / total), color: .yellow)
                segment(width: geo.size.width * (entry.data.aging31to60 / total), color: .orange)
                segment(width: geo.size.width * (entry.data.aging61to90 / total), color: .red.opacity(0.7))
                segment(width: geo.size.width * (entry.data.agingOver90 / total), color: .red)
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
    }

    private func segment(width: Double, color: Color) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: max(0, width))
    }

    private func agingLabel(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func agingRow(_ label: String, _ amount: Double, _ color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Text(format(amount))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private var totalOutstanding: Double {
        entry.data.agingCurrent
            + entry.data.aging1to30
            + entry.data.aging31to60
            + entry.data.aging61to90
            + entry.data.agingOver90
    }

    private func format(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }
}
