import SwiftUI

struct WorkOrderInvoicePDFView: View {
    let changeOrder: ChangeOrder
    let project: Project
    let client: Client?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("J&R Steel Welding LLC")
                        .font(.system(size: 18, weight: .bold))
                    Text("Steel Erection Services")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("WORK ORDER INVOICE")
                    .font(.system(size: 16, weight: .bold))
            }
            .padding(.bottom, 12)

            // Invoice details + Project info
            HStack(alignment: .top, spacing: 24) {
                // Left: Bill To
                VStack(alignment: .leading, spacing: 4) {
                    Text("Bill To:").font(.system(size: 10, weight: .bold))
                    if let client = client {
                        Text(client.name).font(.system(size: 10))
                        if !client.billingAddress.isEmpty {
                            Text(client.billingAddress).font(.system(size: 9)).foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right: Invoice details
                VStack(alignment: .leading, spacing: 3) {
                    detailRow("Invoice #:", changeOrder.invoiceNumber)
                    detailRow("Invoice Date:", changeOrder.invoiceDate.shortDate)
                    detailRow("Work Order #:", changeOrder.workOrderNumber)
                    detailRow("PO Number:", changeOrder.poNumber)
                    Divider().padding(.vertical, 2)
                    detailRow("Project Name:", project.title)
                    detailRow("Job Location:", project.location)
                }
                .frame(width: 220)
            }
            .padding(.bottom, 12)

            dividerLine

            // Scope
            VStack(alignment: .leading, spacing: 4) {
                Text("Work Description / Scope Performed:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "#2C3E50"))
                Text(changeOrder.scope.isEmpty ? changeOrder.description : changeOrder.scope)
                    .font(.system(size: 9))
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
            }
            .padding(.vertical, 6)

            dividerLine

            // Labor & Equipment Charges
            VStack(alignment: .leading, spacing: 2) {
                Text("Labor & Equipment Charges:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "#2C3E50"))
                    .padding(.bottom, 2)

                tableHeader

                ForEach(changeOrder.laborLineItems) { item in
                    tableRow(
                        desc: item.category.displayName,
                        qty: item.quantity,
                        hours: item.hours,
                        rate: item.rate,
                        total: item.lineTotal
                    )
                }
            }
            .padding(.vertical, 6)

            // Additional Charges
            if !changeOrder.additionalCharges.isEmpty {
                dividerLine

                VStack(alignment: .leading, spacing: 2) {
                    Text("Additional Charges / Materials:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "#2C3E50"))
                        .padding(.bottom, 2)

                    tableHeader

                    ForEach(changeOrder.additionalCharges) { item in
                        tableRow(
                            desc: item.description,
                            qty: item.quantity,
                            hours: item.hours,
                            rate: item.rate,
                            total: item.lineTotal
                        )
                    }
                }
                .padding(.vertical, 6)
            }

            dividerLine

            // Totals
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Payment Terms:").font(.system(size: 9, weight: .bold))
                    Text(changeOrder.paymentTerms).font(.system(size: 9))
                    Text("Make checks payable to: J&R Steel Welding LLC")
                        .font(.system(size: 8)).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    totalRow("Subtotal:", changeOrder.subtotal)
                    if changeOrder.taxAmount > 0 {
                        totalRow("Tax (\(changeOrder.taxRate)%):", changeOrder.taxAmount)
                    }
                    HStack(spacing: 8) {
                        Text("TOTAL DUE:").font(.system(size: 11, weight: .bold))
                        Text(changeOrder.totalDue.currencyWithCents)
                            .font(.system(size: 12, weight: .bold))
                    }
                }
            }
            .padding(.vertical, 8)

            // Notes
            if !changeOrder.additionalNotes.isEmpty {
                dividerLine
                VStack(alignment: .leading, spacing: 2) {
                    Text("Additional Notes:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(hex: "#2C3E50"))
                    Text(changeOrder.additionalNotes)
                        .font(.system(size: 9))
                }
                .padding(.vertical, 6)
            }

            Spacer()

            // Authorization
            dividerLine
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Authorized By:").font(.system(size: 9, weight: .bold))
                    Text("Project Manager").font(.system(size: 9, weight: .regular)).italic()
                    Text("Ruben Malvaez").font(.system(size: 9))
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Date:").font(.system(size: 9, weight: .bold))
                    Text(changeOrder.invoiceDate.shortDate).font(.system(size: 9))
                    if changeOrder.isSigned, let signed = changeOrder.signedDate {
                        Text("Signed: \(signed.shortDate)")
                            .font(.system(size: 8)).foregroundColor(.green)
                    }
                }
            }
            .padding(.top, 6)
        }
        .padding(36)
        .frame(width: 612, height: 792)
        .background(.white)
        .foregroundColor(.black)
    }

    // MARK: - Helpers

    private var dividerLine: some View {
        Rectangle()
            .fill(Color.black.opacity(0.3))
            .frame(height: 1)
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 9, weight: .bold))
            Text(value).font(.system(size: 9))
            Spacer()
        }
    }

    private var tableHeader: some View {
        HStack {
            Text("Description").frame(width: 150, alignment: .leading)
            Text("Qty").frame(width: 40, alignment: .trailing)
            Text("Hours").frame(width: 50, alignment: .trailing)
            Text("Rate").frame(width: 70, alignment: .trailing)
            Text("Total").frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .bold))
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.05))
    }

    private func tableRow(desc: String, qty: Decimal, hours: Decimal, rate: Decimal, total: Decimal) -> some View {
        HStack {
            Text(desc).frame(width: 150, alignment: .leading)
            Text(qty > 0 ? "\(qty)" : "").frame(width: 40, alignment: .trailing)
            Text(hours > 0 ? "\(hours)" : "").frame(width: 50, alignment: .trailing)
            Text(rate.currencyWithCents).frame(width: 70, alignment: .trailing)
            Text(total.currencyWithCents).frame(width: 80, alignment: .trailing)
        }
        .font(.system(size: 9))
        .padding(.vertical, 1)
    }

    private func totalRow(_ label: String, _ amount: Decimal) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 9, weight: .semibold))
            Text(amount.currencyWithCents).font(.system(size: 10, weight: .semibold))
        }
    }
}
