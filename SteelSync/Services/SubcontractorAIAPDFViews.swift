import SwiftUI

/// Two-page subcontractor application format that mirrors Ruben's UT
/// Boiler / Carrillo Steel template. Plain black-on-white styling, yellow
/// highlight on Current Payment Due, red text on negative change-order
/// rows, and a SUMMARY block at the bottom of the schedule page.
///
/// The data inputs are the same `PayApplication` + `Project` + `Client`
/// model the other formats consume, so toggling format in the export
/// sheet just swaps the visual layout.
///
/// ## Layout notes for future maintainers
///
/// **Character-wrap bug history.** Every label in the lien-release column
/// uses `.fixedSize()` deliberately. When the labels are allowed to flex,
/// SwiftUI's `ImageRenderer` rasterizes them character-by-character
/// vertically inside the narrow ~358pt right column — producing the
/// "S/U/B/C/O/N/T/R/A/C/T/O/R:" stack Ruben flagged as the most
/// critical bug to fix. The fix is:
/// 1. Block-style labels (e.g. "SUBCONTRACTOR:") get their own line.
/// 2. Inline labels ("By:", "Date:", "State of:", …) sit alongside an
///    elastic `signatureLine().frame(maxWidth: .infinity)` so the line
///    absorbs slack rather than the label being squeezed.
/// If you add a new lien-block row, follow that pattern.
///
/// **Page size.** All page views render at 792×1008 pt = US Letter @
/// 96 dpi, matching `PayAppPDFRenderer.proposedSize`.

// MARK: - Lien release style

/// Which lien-release block to render in the right-hand column of the
/// cover page. The rest of the cover (info grid, lines 1-9, CO summary)
/// is identical between styles — only the right column swaps, which is
/// why we use an enum on a single shared view instead of two parallel
/// view structs.
///
/// - `.standard` — Certification paragraph + Architect's Certificate
///   for Payment. Matches the original UT Boiler / Carrillo template.
/// - `.fullWithRelease` — Same top certification, then a full WAIVER &
///   RELEASE OF LIEN block citing the McGregor Act and Miller Act,
///   plus a payment-record footer (PM / CODE / DATE PAID / CHECK # /
///   AMOUNT) that the GC's AP team fills in.
enum SubcontractorLienStyle {
    case standard
    case fullWithRelease
}

// MARK: - Page 1: Application & Certificate for Payment

struct SubcontractorAIACoverView: View {
    let payApp: PayApplication
    let project: Project
    let client: Client?
    var lienStyle: SubcontractorLienStyle = .standard

    private var contractToDate: Decimal { payApp.totalScheduledValue }
    private var netChangeByCO: Decimal { contractToDate - project.contractAmount }
    private var totalEarnedLessRetainage: Decimal { payApp.totalCompletedToDate - payApp.totalRetainage }
    private var currentPaymentDue: Decimal { totalEarnedLessRetainage - payApp.totalPreviousCompleted }
    private var balanceToFinishIncludingRetainage: Decimal { contractToDate - totalEarnedLessRetainage }

    private var retainagePctText: String {
        String(format: "%.0f%%", Double(truncating: payApp.retainageRate * 100 as NSDecimalNumber))
    }

    private var changeOrderItems: [SOVLineItem] {
        payApp.lineItems.filter { $0.isChangeOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            Divider().background(Color.black)

            infoGrid
                .padding(.top, 8)

            Divider().background(Color.black).padding(.top, 4)

            HStack(alignment: .top, spacing: 16) {
                summaryColumn
                    .frame(width: 320, alignment: .topLeading)
                certColumn
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.top, 8)

            changeOrderSummary
                .padding(.top, 6)

            Spacer(minLength: 0)
        }
        .font(.system(size: 9))
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(width: 792, height: 1008, alignment: .topLeading)
        .background(Color.white)
    }

    // MARK: Title bar

    private var titleBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("SUBCONTRACTOR'S APPLICATION AND CERTIFICATE FOR PAYMENT")
                .font(.system(size: 12, weight: .bold))
            Spacer()
            Text("Page 1 of 2 pages")
                .font(.system(size: 9))
        }
        .padding(.bottom, 4)
    }

    // MARK: Top info grid

    private var infoGrid: some View {
        HStack(alignment: .top, spacing: 16) {
            // Column 1: TO / FROM
            VStack(alignment: .leading, spacing: 8) {
                labelValueBlock("TO:", lines: [
                    client?.name ?? "—",
                    client?.billingAddress ?? ""
                ])
                labelValueBlock("FROM:", lines: ["J & R WELDING LLC"], highlight: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Column 2: PROJECT info
            VStack(alignment: .leading, spacing: 4) {
                fieldRow("PROJECT:", project.title)
                fieldRow("CONTRACT FOR:", "Ruben Malvaez", highlight: true)
                fieldRow("PHONE NO.:", "")
                fieldRow("FAX NO.:", "")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("TAX ID NO.:").font(.system(size: 8, weight: .semibold))
                    Spacer()
                    Text("Code").font(.system(size: 8))
                    Text("N/A").font(.system(size: 8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            // Column 3: APPLICATION info
            VStack(alignment: .leading, spacing: 4) {
                fieldRow("APPLICATION DATE:", payApp.applicationDate.shortDate)
                fieldRow("APPLICATION NO.:", "\(payApp.applicationNumber)")
                fieldRow("PERIOD TO:", payApp.periodTo.shortDate, highlight: true)
                fieldRow("PROJECT NO.:", project.title)
                // Contract date intentionally blank — the GC fills this in.
                fieldRow("CONTRACT DATE:", "", highlight: true)
                fieldRow("INVOICE #", "\(payApp.applicationNumber)", highlight: true)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Summary column (lines 1–9)

    private var summaryColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Application for payment is made as shown below, in connection with the Contract.")
                .font(.system(size: 8))
                .padding(.bottom, 6)

            summaryLine("1.  ORIGINAL CONTRACT SUM", value: project.contractAmount, underline: true)
            summaryLine("2.  Net Change by Change Orders", value: netChangeByCO, underline: true)
            summaryLine("3.  CONTRACT SUM TO DATE", value: contractToDate, underline: true)
            summaryLine("4.  TOTAL COMPLETED & STORED TO DATE", value: payApp.totalCompletedToDate, underline: true)
            summaryLine("5.  LESS RETAINAGE   \(retainagePctText)",
                        value: payApp.totalRetainage, underline: true, bold: true)
            summaryLine("6.  TOTAL EARNED LESS RETAINAGE", value: totalEarnedLessRetainage, underline: true)
            Text("        (Line 4 Less Line 5 Total)")
                .font(.system(size: 7))
                .foregroundColor(.gray)
                .padding(.bottom, 2)
            summaryLine("7.  LESS PREVIOUS CERTIFICATES", value: payApp.totalPreviousCompleted, underline: true)
            Text("        (Line 6 from prior Certificate)")
                .font(.system(size: 7))
                .foregroundColor(.gray)
                .padding(.bottom, 2)

            // Line 8 — yellow-highlighted "CURRENT PAYMENT DUE"
            HStack {
                Text("8.  CURRENT PAYMENT DUE")
                    .font(.system(size: 9, weight: .bold))
                Spacer()
                Text(currentPaymentDue.currencyWithCents)
                    .font(.system(size: 9, weight: .bold))
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.yellow)

            summaryLine("9.  Balance to Finish, Including Retainage",
                        value: balanceToFinishIncludingRetainage, underline: true)
                .padding(.top, 4)
        }
    }

    // MARK: Certification column

    @ViewBuilder
    private var certColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The undersigned Contractor certifies that to the best of the Contractor's knowledge, information and belief the Work covered by this Application for Payment has been completed in accordance with the Contract Documents, that all amounts have been paid by the Contractor for Work for which previous Certificates for Payment were issued and payments received from the Owner, and that current payment shown herein is now due.")
                .font(.system(size: 7.5))
                .fixedSize(horizontal: false, vertical: true)

            switch lienStyle {
            case .standard:
                standardLienBlock
            case .fullWithRelease:
                fullReleaseLienBlock
            }
        }
    }

    // MARK: Standard lien (Architect's Certificate)
    //
    // Every Text below uses `.fixedSize()` and every signature line uses
    // `.frame(maxWidth: .infinity)` (or a fixed width when several share
    // a row) to defeat the character-wrap rendering bug — see the
    // file-level doc comment for the full story.

    @ViewBuilder
    private var standardLienBlock: some View {
        // SUBCONTRACTOR signature block — label on its own line so it
        // never gets character-wrapped when the column is narrow.
        Text("SUBCONTRACTOR:")
            .font(.system(size: 8, weight: .bold))
            .fixedSize()
            .padding(.top, 6)

        HStack(alignment: .bottom, spacing: 6) {
            Text("By:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
            Text("Date:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(width: 70)
        }

        // State of / County of are intentionally blank for the notary
        // to fill in by hand.
        HStack(alignment: .bottom, spacing: 6) {
            Text("State of:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
            Text("County of:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
        }
        .padding(.top, 6)

        // Subscribed-and-sworn date is blank as well — notary fills in.
        HStack(alignment: .bottom, spacing: 4) {
            Text("Subscribed and sworn to before me this")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(width: 32)
            Text("day of")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
        }
        .padding(.top, 4)

        HStack(alignment: .bottom, spacing: 6) {
            Text("Notary Public:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
        }
        .padding(.top, 4)

        HStack(alignment: .bottom, spacing: 6) {
            Text("My Commission Expires:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
        }
        .padding(.top, 2)

        Text("ARCHITECT'S CERTIFICATE FOR PAYMENT")
            .font(.system(size: 9, weight: .bold))
            .fixedSize()
            .padding(.top, 10)

        Text("In accordance with the Contract Documents, based on on-site observations and the data comprising this application, the Architect certifies to the Owner that to the best of the Architect's knowledge, information and belief the Work has progressed as indicated, the quality of the Work is in accordance with the Contract Documents, and the Contractor is entitled to payment of the AMOUNT CERTIFIED.")
            .font(.system(size: 7.5))
            .fixedSize(horizontal: false, vertical: true)

        HStack(alignment: .bottom, spacing: 4) {
            Text("AMOUNT CERTIFIED")
                .font(.system(size: 8, weight: .bold))
                .fixedSize()
            Text("…………………… $")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
        }
        .padding(.top, 6)

        Text("(Attached explanation if amount certified differs from the amount applied for. Initial all figures on this Application and on the Continuation Sheet that are changed to conform to the amount certified.)")
            .font(.system(size: 7))
            .foregroundColor(.gray)
            .fixedSize(horizontal: false, vertical: true)

        // ARCHITECT signature block — same pattern: label on its own line.
        Text("ARCHITECT:")
            .font(.system(size: 8, weight: .bold))
            .fixedSize()
            .padding(.top, 6)

        HStack(alignment: .bottom, spacing: 6) {
            Text("By:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
            Text("Date:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(width: 70)
        }

        Text("This Certificate is not negotiable. The AMOUNT CERTIFIED is payable only to the Contractor named herein. Issuance, payment and acceptance of payment are without prejudice to any rights of the Owner or Contractor under this Contract.")
            .font(.system(size: 7))
            .foregroundColor(.gray)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
    }

    // MARK: Full Waiver & Release of Lien
    //
    // The legal paragraphs in this block are taken verbatim from the
    // template Ruben's GC (Carrillo Steel) requires for partial-payment
    // lien releases. References to the McGregor Act (Texas public-works
    // bond claims) and the federal Miller Act are intentional and must
    // not be paraphrased — substitute wording can void the release.
    // If the template ever changes, replace the literal Text() strings
    // below with the new wording and re-export a test PDF to verify
    // wrapping still looks right.

    @ViewBuilder
    private var fullReleaseLienBlock: some View {
        Text("WAIVER & RELEASE OF LIEN")
            .font(.system(size: 10, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)

        Text("Whereas the undersigned Subcontractor has provided labor, services, materials, or equipment for the above project, under an agreement with the Contractor.")
            .font(.system(size: 7.5))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)

        Text("In Consideration for the payment requested in the Application for Payment, the undersigned SUBCONTRACTOR HEARBY RELEASES ALL MECHANIC'S LIEN RIGHTS, McGREGOR ACT BOND CLAIMS, MILLER ACT BOND CLAIMS, EQUITABLE LIENS, AND ALL OTHER CLAIMS FOR PAYMENT ARISING OUT OF LABOR, MATERIAL, EQUIPMENT, SUBCONTRACT WORK, SERVICES, DELAYS, EXTRA WORK AND/OR CHANGES, RELATED TO THE SUBCONTRACT WORK AT THE PROJECT UNLESS SPECIFICALLY LISTED BELOW. UPON PAYMENT OF THE SUBCONTRACTOR'S APPLICATION FOR PAYMENT, THIS INSTRUMENT SHALL CONSTITUTE A FULL RELEASE OF ALL RIGHTS, CLAIMS AND DEMANDS THROUGH THE DATE OF THIS APPLICATION, EXCEPT AS LISTED BELOW:")
            .font(.system(size: 7.5))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)

        Text("SUBCONTRACTOR:")
            .font(.system(size: 8, weight: .bold))
            .fixedSize()
            .padding(.top, 8)

        HStack(alignment: .bottom, spacing: 6) {
            Text("By:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
            Text("Date:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(width: 70)
        }

        // All notary fields blank — to be hand-filled.
        HStack(alignment: .bottom, spacing: 6) {
            Text("State of:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
            Text("County of:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
        }
        .padding(.top, 4)

        HStack(alignment: .bottom, spacing: 4) {
            Text("Subscribed and sworn to before me this")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(width: 32)
            Text("day of")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
        }
        .padding(.top, 4)

        HStack(alignment: .bottom, spacing: 6) {
            Text("Notary Public:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
        }
        .padding(.top, 4)

        HStack(alignment: .bottom, spacing: 6) {
            Text("My Commission Expires:")
                .font(.system(size: 8))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
        }
        .padding(.top, 2)

        // Payment-record footer
        Rectangle().fill(Color.black).frame(height: 0.6).padding(.top, 8)

        HStack(alignment: .bottom, spacing: 6) {
            Text("PM:")
                .font(.system(size: 8, weight: .bold))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
            Text("CODE:")
                .font(.system(size: 8, weight: .bold))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
        }
        .padding(.top, 6)

        HStack(alignment: .bottom, spacing: 6) {
            Text("DATE PAID:")
                .font(.system(size: 8, weight: .bold))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
            Text("CHECK #:")
                .font(.system(size: 8, weight: .bold))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
        }
        .padding(.top, 4)

        HStack(alignment: .bottom, spacing: 6) {
            Text("AMOUNT:")
                .font(.system(size: 8, weight: .bold))
                .fixedSize()
            signatureLine().frame(maxWidth: .infinity)
        }
        .padding(.top, 4)

        // Two extra blank lines like the template.
        signatureLine().frame(maxWidth: .infinity).padding(.top, 6)
        signatureLine().frame(maxWidth: .infinity).padding(.top, 4)
    }

    // MARK: Change Order Summary table

    private var changeOrderSummary: some View {
        let additions = changeOrderItems.filter { $0.scheduledValue > 0 }
        let deductions = changeOrderItems.filter { $0.scheduledValue < 0 }
        let totalAdditions = additions.reduce(Decimal(0)) { $0 + $1.scheduledValue }
        let totalDeductions = deductions.reduce(Decimal(0)) { $0 + $1.scheduledValue }
        let net = totalAdditions + totalDeductions

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                cell("CHANGE ORDER SUMMARY", width: 220, isHeader: true, alignment: .center)
                cell("ADDITIONS", width: 80, isHeader: true, alignment: .center)
                cell("DEDUCTIONS", width: 80, isHeader: true, alignment: .center)
            }
            ForEach(changeOrderItems) { co in
                HStack(spacing: 0) {
                    cell(co.description, width: 220, alignment: .leading)
                    cell(co.scheduledValue > 0 ? co.scheduledValue.currencyWithCents : "",
                         width: 80, alignment: .trailing)
                    cell(co.scheduledValue < 0 ? co.scheduledValue.currencyWithCents : "",
                         width: 80, alignment: .trailing,
                         color: co.scheduledValue < 0 ? .red : .black)
                }
            }
            // Pad to at least 5 rows to match the template's blank rows look
            ForEach(0..<max(0, 5 - changeOrderItems.count), id: \.self) { _ in
                HStack(spacing: 0) {
                    cell("", width: 220, alignment: .leading)
                    cell("", width: 80, alignment: .trailing)
                    cell("", width: 80, alignment: .trailing)
                }
            }
            HStack(spacing: 0) {
                cell("TOTALS", width: 220, alignment: .leading, bold: true)
                cell(totalAdditions.currencyWithCents, width: 80, alignment: .trailing, bold: true)
                cell(totalDeductions.currencyWithCents,
                     width: 80, alignment: .trailing, bold: true)
            }
            HStack(spacing: 0) {
                cell("NET CHANGES by Change Order", width: 220, alignment: .leading)
                cell("", width: 80, alignment: .trailing)
                cell(net.currencyWithCents, width: 80, alignment: .trailing, bold: true)
            }
        }
        .frame(width: 380, alignment: .topLeading)
    }

    // MARK: Helpers

    private func notaryLine() -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        let day = f.string(from: payApp.applicationDate)
        f.dateFormat = "MMMM yyyy"
        let monthYear = f.string(from: payApp.applicationDate)
        let suffix = ordinalSuffix(forDay: Int(day) ?? 1)
        return "Subscribed and sworn to before me this \(day)\(suffix) day of \(monthYear)"
    }

    private func ordinalSuffix(forDay d: Int) -> String {
        let mod100 = d % 100
        if mod100 >= 11 && mod100 <= 13 { return "th" }
        switch d % 10 {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }

    private func labelValueBlock(_ label: String, lines: [String], highlight: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .bold))
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    if !line.isEmpty {
                        Text(line).font(.system(size: 9))
                    }
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(highlight ? Color.yellow.opacity(0.45) : Color.clear)
        }
    }

    private func fieldRow(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(size: 9))
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(highlight ? Color.yellow.opacity(0.45) : Color.clear)
        }
    }

    private func summaryLine(_ label: String, value: Decimal, underline: Bool = false, bold: Bool = false) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: bold ? .bold : .regular))
            Spacer()
            Text(value.currencyWithCents)
                .font(.system(size: 9, weight: .medium))
        }
        .padding(.bottom, underline ? 2 : 0)
        .overlay(
            Rectangle()
                .fill(Color.black.opacity(underline ? 1 : 0))
                .frame(height: 0.6),
            alignment: .bottom
        )
        .padding(.bottom, underline ? 4 : 2)
    }

    /// A 0.6pt black underline used everywhere notary/signature info is
    /// hand-filled. Callers set the width — use `.frame(maxWidth: .infinity)`
    /// for the elastic case (single line spanning remaining row width) or
    /// a fixed `.frame(width:)` when multiple lines share one row.
    private func signatureLine() -> some View {
        Rectangle()
            .fill(Color.black)
            .frame(height: 0.6)
            .padding(.bottom, 1)
    }

    private func cell(_ text: String,
                      width: CGFloat,
                      isHeader: Bool = false,
                      alignment: Alignment = .center,
                      bold: Bool = false,
                      color: Color = .black) -> some View {
        Text(text)
            .font(.system(size: 8, weight: (isHeader || bold) ? .bold : .regular))
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .frame(width: width, alignment: alignment)
            .background(isHeader ? Color(white: 0.92) : Color.clear)
            .border(Color.black, width: 0.5)
    }
}

// MARK: - Page 2: Schedule of Values continuation

struct SubcontractorAIAScheduleView: View {
    let payApp: PayApplication
    let project: Project
    let client: Client?

    private var baseLineItems: [SOVLineItem] {
        payApp.lineItems.filter { !$0.isChangeOrder }
    }

    private var changeOrderItems: [SOVLineItem] {
        payApp.lineItems.filter { $0.isChangeOrder }
    }

    private var contractSumToDate: Decimal { payApp.totalScheduledValue }
    private var changeOrdersToDate: Decimal {
        changeOrderItems.reduce(Decimal(0)) { $0 + $1.scheduledValue }
    }
    private var totalEarnedLessRetainage: Decimal {
        payApp.totalCompletedToDate - payApp.totalRetainage
    }
    private var netDueThisApplication: Decimal {
        totalEarnedLessRetainage - payApp.totalPreviousCompleted
    }

    // Column widths — sum to ~672pt (out of 728 available)
    private let wNo: CGFloat = 24
    private let wDesc: CGFloat = 162
    private let wSched: CGFloat = 70
    private let wPrev: CGFloat = 60
    private let wThis: CGFloat = 60
    private let wMat: CGFloat = 55
    private let wTotal: CGFloat = 70
    private let wPct: CGFloat = 45
    private let wBal: CGFloat = 64
    private let wRet: CGFloat = 64

    /// 24-row minimum on the original SOV section so the table looks
    /// dense and matches the user's template, which has many blank rows.
    /// (The change-order section has its own 4-row minimum below.)
    private static let minBaseRows: Int = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            tableHeader
            baseSection
            subtotalsRow
            changeOrderSection
            coSubtotalRow
            totalAmountRow
            summaryBlock
                .padding(.top, 14)
            Spacer(minLength: 0)
        }
        .font(.system(size: 8))
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(width: 792, height: 1008, alignment: .topLeading)
        .background(Color.white)
    }

    // MARK: Header strip

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(client?.name ?? "Contractor")
                    .font(.system(size: 10, weight: .bold))
                Spacer()
                Text("SCHEDULE OF VALUES")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Text("Page 2 of 2")
                    .font(.system(size: 9))
            }
            HStack {
                Spacer()
                Text("Pay Application #")
                    .font(.system(size: 9, weight: .bold))
                Text("\(payApp.applicationNumber)")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .background(Color.yellow.opacity(0.45))
            }
            .padding(.bottom, 4)
        }
    }

    // MARK: Table header (two-row, mimics the template)

    private var tableHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                headerCell("", width: wNo, isHeader: true)
                headerCell("", width: wDesc, isHeader: true)
                headerCell("", width: wSched, isHeader: true)
                headerCell("Work Completed", width: wPrev + wThis, isHeader: true)
                    .border(Color.black, width: 0.5)
                headerCell("", width: wMat, isHeader: true)
                headerCell("Total", width: wTotal, isHeader: true)
                headerCell("", width: wPct, isHeader: true)
                headerCell("", width: wBal, isHeader: true)
                headerCell("", width: wRet, isHeader: true)
            }
            HStack(spacing: 0) {
                headerCell("No.", width: wNo, isHeader: true)
                headerCell("Description of Work", width: wDesc, isHeader: true)
                headerCell("Scheduled Value", width: wSched, isHeader: true)
                headerCell("Previous Applications", width: wPrev, isHeader: true)
                headerCell("Work in Place", width: wThis, isHeader: true)
                headerCell("Stored Materials", width: wMat, isHeader: true)
                headerCell("Completed & Stored", width: wTotal, isHeader: true)
                headerCell("Percent Completed", width: wPct, isHeader: true)
                headerCell("Balance To Finish", width: wBal, isHeader: true)
                headerCell("Retainage 10%", width: wRet, isHeader: true)
            }
        }
    }

    // MARK: Base SOV section

    private var baseSection: some View {
        let blankRows = max(0, Self.minBaseRows - baseLineItems.count)
        return VStack(spacing: 0) {
            ForEach(baseLineItems) { item in
                row(item: item, color: .black)
            }
            ForEach(0..<blankRows, id: \.self) { idx in
                blankRow(number: baseLineItems.count + idx + 1)
            }
        }
    }

    private var subtotalsRow: some View {
        HStack(spacing: 0) {
            dataCell("", width: wNo, bold: true)
            dataCell("SUBTOTALS", width: wDesc, alignment: .leading, bold: true)
            dataCell(sum(\.scheduledValue, in: baseLineItems).currencyWithCents, width: wSched, alignment: .trailing, bold: true)
            dataCell(zeroOrMoney(sum(\.previousCompleted, in: baseLineItems)), width: wPrev, alignment: .trailing, bold: true)
            dataCell(zeroOrMoney(sum(\.thisPeriodCompleted, in: baseLineItems)), width: wThis, alignment: .trailing, bold: true)
            dataCell(zeroOrMoney(sum(\.materialsStored, in: baseLineItems)), width: wMat, alignment: .trailing, bold: true)
            dataCell(zeroOrMoney(sum(\.totalCompletedToDate, in: baseLineItems)), width: wTotal, alignment: .trailing, bold: true)
            dataCell("", width: wPct, alignment: .center, bold: true)
            dataCell("", width: wBal, alignment: .trailing, bold: true)
            dataCell(retainageSum(items: baseLineItems).currencyWithCents, width: wRet, alignment: .trailing, bold: true)
        }
        .background(Color(white: 0.92))
    }

    // MARK: Change order section

    private var changeOrderSection: some View {
        VStack(spacing: 0) {
            ForEach(changeOrderItems) { item in
                row(item: item, color: item.scheduledValue < 0 ? .red : Color(red: 0.85, green: 0, blue: 0))
            }
            // Pad to at least 4 rows
            ForEach(0..<max(0, 4 - changeOrderItems.count), id: \.self) { _ in
                blankRow(number: nil)
            }
        }
    }

    private var coSubtotalRow: some View {
        let coScheduled = sum(\.scheduledValue, in: changeOrderItems)
        return HStack(spacing: 0) {
            dataCell("", width: wNo, bold: true)
            dataCell("Sub Total", width: wDesc, alignment: .leading, bold: true)
            dataCell(coScheduled.currencyWithCents, width: wSched, alignment: .trailing, bold: true)
            dataCell(zeroOrMoney(sum(\.previousCompleted, in: changeOrderItems)), width: wPrev, alignment: .trailing, bold: true)
            dataCell(zeroOrMoney(sum(\.thisPeriodCompleted, in: changeOrderItems)), width: wThis, alignment: .trailing, bold: true)
            dataCell(zeroOrMoney(sum(\.materialsStored, in: changeOrderItems)), width: wMat, alignment: .trailing, bold: true)
            dataCell(zeroOrMoney(sum(\.totalCompletedToDate, in: changeOrderItems)), width: wTotal, alignment: .trailing, bold: true)
            dataCell("", width: wPct, bold: true)
            dataCell("", width: wBal, alignment: .trailing, bold: true)
            dataCell(retainageSum(items: changeOrderItems).currencyWithCents, width: wRet, alignment: .trailing, bold: true)
        }
    }

    // MARK: TOTAL AMOUNT (combined)

    private var totalAmountRow: some View {
        HStack(spacing: 0) {
            dataCell("", width: wNo, bold: true)
            dataCell("TOTAL AMOUNT", width: wDesc, alignment: .leading, bold: true)
            dataCell(payApp.totalScheduledValue.currencyWithCents, width: wSched, alignment: .trailing, bold: true)
            dataCell(zeroOrMoney(payApp.totalPreviousCompleted), width: wPrev, alignment: .trailing, bold: true)
            dataCell(zeroOrMoney(payApp.totalThisPeriod), width: wThis, alignment: .trailing, bold: true)
            dataCell(zeroOrMoney(payApp.totalMaterialsStored), width: wMat, alignment: .trailing, bold: true)
            dataCell(zeroOrMoney(payApp.totalCompletedToDate), width: wTotal, alignment: .trailing, bold: true)
            dataCell(String(format: "%.0f%%", payApp.overallPercentComplete), width: wPct, bold: true)
            dataCell(zeroOrMoney(payApp.totalBalanceToFinish), width: wBal, alignment: .trailing, bold: true)
            dataCell(payApp.totalRetainage.currencyWithCents, width: wRet, alignment: .trailing, bold: true)
        }
        .background(Color(white: 0.85))
    }

    // MARK: Summary block

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SUMMARY")
                .font(.system(size: 9, weight: .bold))
                .padding(.bottom, 2)
            summaryFieldHighlighted("Original Contract", value: project.contractAmount,
                                    note: "enter at beginning of project")
            summaryField("Change Orders to Date", value: changeOrdersToDate)
            summaryField("Contract Sum To Date", value: contractSumToDate)
            summaryField("Completed to Date", value: payApp.totalCompletedToDate)
            summaryField("Retainage", value: payApp.totalRetainage)
            summaryFieldHighlighted("Previous Applications", value: payApp.totalPreviousCompleted,
                                    note: "Use last app's NET DUE here next month")
            HStack(spacing: 8) {
                Text("NET DUE THIS APPLICATION")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 200, alignment: .leading)
                Text(netDueThisApplication.currencyWithCents)
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 100, alignment: .trailing)
            }
            .padding(.top, 2)
        }
    }

    // MARK: Row helpers

    private func row(item: SOVLineItem, color: Color) -> some View {
        HStack(spacing: 0) {
            dataCell("\(item.itemNumber)", width: wNo, color: color)
            dataCell(item.description, width: wDesc, alignment: .leading, color: color)
            dataCell(item.scheduledValue.currencyWithCents, width: wSched, alignment: .trailing, color: color)
            dataCell(blankIfZero(item.previousCompleted), width: wPrev, alignment: .trailing, color: color)
            dataCell(blankIfZero(item.thisPeriodCompleted), width: wThis, alignment: .trailing, color: color)
            dataCell(blankIfZero(item.materialsStored), width: wMat, alignment: .trailing, color: color)
            dataCell(blankIfZero(item.totalCompletedToDate), width: wTotal, alignment: .trailing, color: color)
            dataCell(String(format: "%.0f%%", item.percentComplete), width: wPct, color: color)
            dataCell(blankIfZero(item.balanceToFinish), width: wBal, alignment: .trailing, color: color)
            dataCell(blankIfZero(item.retainage(at: payApp.retainageRate)), width: wRet, alignment: .trailing, color: color)
        }
    }

    private func blankRow(number: Int?) -> some View {
        HStack(spacing: 0) {
            dataCell(number.map { "\($0)" } ?? "", width: wNo)
            dataCell("", width: wDesc, alignment: .leading)
            dataCell("", width: wSched, alignment: .trailing)
            dataCell("", width: wPrev, alignment: .trailing)
            dataCell("", width: wThis, alignment: .trailing)
            dataCell("", width: wMat, alignment: .trailing)
            dataCell("", width: wTotal, alignment: .trailing)
            dataCell("", width: wPct)
            dataCell("", width: wBal, alignment: .trailing)
            dataCell("", width: wRet, alignment: .trailing)
        }
    }

    // MARK: Cell helpers

    private func headerCell(_ text: String, width: CGFloat, isHeader: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 7.5, weight: .bold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 2)
            .padding(.vertical, 3)
            .frame(width: width, height: 24)
            .background(Color(white: 0.92))
            .border(Color.black, width: 0.5)
    }

    private func dataCell(_ text: String,
                          width: CGFloat,
                          alignment: Alignment = .center,
                          bold: Bool = false,
                          color: Color = .black) -> some View {
        Text(text)
            .font(.system(size: 7.5, weight: bold ? .bold : .regular))
            .foregroundColor(color)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .frame(width: width, height: 18, alignment: alignment)
            .border(Color.black, width: 0.4)
    }

    private func summaryField(_ label: String, value: Decimal) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 8))
                .frame(width: 200, alignment: .leading)
            Text(value.currencyWithCents)
                .font(.system(size: 8))
                .frame(width: 100, alignment: .trailing)
        }
    }

    private func summaryFieldHighlighted(_ label: String, value: Decimal, note: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 8))
                .padding(.horizontal, 2)
                .frame(width: 200, alignment: .leading)
                .background(Color.yellow.opacity(0.45))
            Text(value.currencyWithCents)
                .font(.system(size: 8))
                .frame(width: 100, alignment: .trailing)
            Text(note)
                .font(.system(size: 7))
                .foregroundColor(.gray)
        }
    }

    // MARK: Math helpers

    private func sum(_ keyPath: KeyPath<SOVLineItem, Decimal>, in items: [SOVLineItem]) -> Decimal {
        items.reduce(Decimal(0)) { $0 + $1[keyPath: keyPath] }
    }

    private func retainageSum(items: [SOVLineItem]) -> Decimal {
        items.reduce(Decimal(0)) { $0 + $1.retainage(at: payApp.retainageRate) }
    }

    private func blankIfZero(_ d: Decimal) -> String {
        d == 0 ? "" : d.currencyWithCents
    }

    private func zeroOrMoney(_ d: Decimal) -> String {
        d.currencyWithCents
    }
}
