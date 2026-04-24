import SwiftUI
import PDFKit

/// Renders a Pay Application to PDF in one of two formats:
/// - `.g703`: AIA G702/G703 replica (traditional construction form)
/// - `.steelSync`: Clean SteelSync-branded invoice (modern alternative)
///
/// Uses SwiftUI's ImageRenderer (iOS 16+/macOS 13+) to rasterize a laid-out
/// view to PDF data, then writes the result to a temporary file and returns
/// the URL so the caller can save/share/reveal it.
@MainActor
struct PayAppPDFRenderer {
    let payApp: PayApplication
    let project: Project
    let client: Client?
    let format: ExportPayAppSheet.PDFFormat
    /// Only consulted for `.g703`. When true, prepends a G702 cover sheet to
    /// the G703 continuation sheet (combined into one multi-page PDF).
    let includeG702Cover: Bool

    func render() -> URL? {
        // Build the page list per format. Each page renders independently, then
        // gets stamped into the same CGPDFContext to produce a multi-page PDF.
        let pages: [AnyView]
        switch format {
        case .g703:
            if includeG702Cover {
                pages = [
                    AnyView(G702CoverPageView(payApp: payApp, project: project, client: client)),
                    AnyView(G703ContinuationSheetView(payApp: payApp, project: project, client: client))
                ]
            } else {
                pages = [AnyView(G703ContinuationSheetView(payApp: payApp, project: project, client: client))]
            }
        case .steelSync:
            pages = [AnyView(SteelSyncInvoiceView(payApp: payApp, project: project, client: client))]
        }

        let tmpDir = FileManager.default.temporaryDirectory
        let safeTitle = project.title.filenameSafe
        let filename: String
        switch format {
        case .g703:
            filename = includeG702Cover
                ? "G702-G703-\(safeTitle)-App\(payApp.applicationNumber).pdf"
                : "G703-\(safeTitle)-App\(payApp.applicationNumber).pdf"
        case .steelSync:
            filename = "Invoice-\(safeTitle)-App\(payApp.applicationNumber).pdf"
        }
        let outputURL = tmpDir.appendingPathComponent(filename)

        guard let cgContext = CGContext(
            outputURL as CFURL,
            mediaBox: nil,
            [kCGPDFContextAuthor as String: "SteelSync",
             kCGPDFContextTitle as String: filename] as CFDictionary
        ) else {
            return nil
        }

        for page in pages {
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = .init(width: 792, height: 1008)  // US Letter @ 96 dpi
            renderer.scale = 2.0
            renderer.render { size, renderAction in
                var mediaBox = CGRect(origin: .zero, size: size)
                cgContext.beginPage(mediaBox: &mediaBox)
                renderAction(cgContext)
                cgContext.endPage()
            }
        }
        cgContext.closePDF()

        return outputURL
    }
}

private extension String {
    var filenameSafe: String {
        components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "_")
    }
}

// MARK: - Shared brand color

private let aiaFlameOrange = Color(red: 1.0, green: 0.42, blue: 0.21)

// MARK: - G702 Cover Page (Application and Certificate for Payment)

private struct G702CoverPageView: View {
    let payApp: PayApplication
    let project: Project
    let client: Client?

    private var contractToDate: Decimal { payApp.totalScheduledValue }
    private var netChangeByCO: Decimal { contractToDate - project.contractAmount }
    private var totalEarnedLessRetainage: Decimal { payApp.totalCompletedToDate - payApp.totalRetainage }
    private var currentPaymentDue: Decimal { totalEarnedLessRetainage - payApp.totalPreviousCompleted }
    private var balanceToFinishIncludingRetainage: Decimal { contractToDate - totalEarnedLessRetainage }
    private var retainagePercentLabel: String {
        String(format: "%.0f%%", Double(truncating: payApp.retainageRate * 100 as NSDecimalNumber))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Orange brand band
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("APPLICATION AND CERTIFICATE FOR PAYMENT")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text("AIA Document G702")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("J&R STEEL WELDING LLC")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white)
                    Text("Steel Erection · Texas")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(aiaFlameOrange)

            // Project info grid
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    fieldLabel("TO (OWNER/GC)")
                    Text(client?.name ?? project.title).font(.system(size: 10, weight: .semibold))
                    if let address = client?.billingAddress, !address.isEmpty {
                        Text(address).font(.system(size: 9)).foregroundColor(.gray)
                    }
                    fieldLabel("PROJECT")
                        .padding(.top, 4)
                    Text(project.title).font(.system(size: 10, weight: .semibold))
                    if !project.location.isEmpty {
                        Text(project.location).font(.system(size: 9)).foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    fieldLabel("FROM (CONTRACTOR)")
                    Text("J&R Steel Welding LLC").font(.system(size: 10, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    fieldLabel("APPLICATION NO.")
                    Text("\(payApp.applicationNumber)").font(.system(size: 10, weight: .semibold))
                    fieldLabel("PERIOD TO")
                    Text(payApp.periodTo.shortDate).font(.system(size: 10))
                    fieldLabel("APPLICATION DATE")
                    Text(payApp.applicationDate.shortDate).font(.system(size: 10))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Accent divider
            Rectangle()
                .fill(aiaFlameOrange)
                .frame(height: 2)
                .padding(.bottom, 12)

            // Summary block (lines 1–9) — wide card, centered
            VStack(alignment: .trailing, spacing: 6) {
                summaryLine("1. ORIGINAL CONTRACT SUM", value: project.contractAmount)
                summaryLine("2. NET CHANGE BY CHANGE ORDERS", value: netChangeByCO)
                summaryLine("3. CONTRACT SUM TO DATE (1 + 2)", value: contractToDate)
                summaryLine("4. TOTAL COMPLETED & STORED TO DATE", value: payApp.totalCompletedToDate)
                summaryLine("5. RETAINAGE (\(retainagePercentLabel))", value: payApp.totalRetainage)
                summaryLine("6. TOTAL EARNED LESS RETAINAGE (4 − 5)", value: totalEarnedLessRetainage)
                summaryLine("7. LESS PREVIOUS CERTIFICATES FOR PAYMENT", value: payApp.totalPreviousCompleted)
                Rectangle()
                    .fill(aiaFlameOrange.opacity(0.4))
                    .frame(height: 1)
                    .padding(.vertical, 3)
                summaryLine("8. CURRENT PAYMENT DUE", value: currentPaymentDue, emphasize: true)
                summaryLine("9. BALANCE TO FINISH, INCLUDING RETAINAGE (3 − 6)", value: balanceToFinishIncludingRetainage)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(aiaFlameOrange.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(aiaFlameOrange.opacity(0.3), lineWidth: 1)
                    )
            )

            // Change order summary
            HStack(spacing: 0) {
                changeOrderCell("CHANGE ORDER SUMMARY", value: nil, isHeader: true)
                changeOrderCell("ADDITIONS", value: max(netChangeByCO, 0))
                changeOrderCell("DEDUCTIONS", value: min(netChangeByCO, 0))
                changeOrderCell("NET CHANGE", value: netChangeByCO)
            }
            .padding(.top, 16)

            Spacer(minLength: 12)

            // Contractor's certification
            VStack(alignment: .leading, spacing: 8) {
                fieldLabel("CONTRACTOR'S CERTIFICATION")
                Text("The undersigned Contractor certifies that to the best of the Contractor's knowledge, information and belief, the Work covered by this Application for Payment has been completed in accordance with the Contract Documents, that all amounts have been paid by the Contractor for Work for which previous Certificates for Payment were issued and payments received from the Owner, and that current payment shown herein is now due.")
                    .font(.system(size: 8))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Rectangle().fill(Color.black).frame(height: 0.6)
                        Text("Contractor Signature")
                            .font(.system(size: 7))
                            .foregroundColor(.gray)
                    }
                    .frame(width: 240)
                    VStack(alignment: .leading, spacing: 2) {
                        Rectangle().fill(Color.black).frame(height: 0.6)
                        Text("Date")
                            .font(.system(size: 7))
                            .foregroundColor(.gray)
                    }
                    .frame(width: 110)
                    Spacer()
                }
                .padding(.top, 18)
            }
        }
        .font(.system(size: 9))
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(width: 792, height: 1008, alignment: .topLeading)
        .background(Color.white)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .bold))
            .foregroundColor(aiaFlameOrange)
    }

    private func summaryLine(_ label: String, value: Decimal, emphasize: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10, weight: emphasize ? .bold : .regular))
            Spacer()
            Text(value.currencyFormatted)
                .font(.system(size: 10, weight: emphasize ? .bold : .medium))
                .foregroundColor(emphasize ? .black : .primary)
        }
    }

    private func changeOrderCell(_ label: String, value: Decimal?, isHeader: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(isHeader ? .white : aiaFlameOrange)
            if let value = value {
                Text(value.currencyFormatted)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(isHeader ? aiaFlameOrange : aiaFlameOrange.opacity(0.06))
    }
}

// MARK: - G703 Continuation Sheet (Schedule of Values table)

private struct G703ContinuationSheetView: View {
    let payApp: PayApplication
    let project: Project
    let client: Client?

    // Column widths — must sum to <= 728 (US Letter 792 - 32pt padding each side)
    private let wA: CGFloat = 20
    private let wDesc: CGFloat = 170
    private let wC: CGFloat = 72       // Scheduled Value
    private let wD: CGFloat = 62       // From Previous
    private let wE: CGFloat = 62       // This Period
    private let wF: CGFloat = 62       // Materials Stored
    private let wG: CGFloat = 72       // Total Completed
    private let wPct: CGFloat = 42     // % G/C
    private let wH: CGFloat = 72       // Balance to Finish
    private let wI: CGFloat = 62       // Retainage

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Orange brand band
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONTINUATION SHEET")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    Text("AIA Document G703 · Schedule of Values")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("J&R STEEL WELDING LLC")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundColor(.white)
                    Text("Steel Erection · Texas")
                        .font(.system(size: 8))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(aiaFlameOrange)

            // Compact project info bar
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    fieldLabel("TO (OWNER/GC)")
                    Text(client?.name ?? project.title).font(.system(size: 10, weight: .semibold))
                    fieldLabel("PROJECT")
                        .padding(.top, 4)
                    Text(project.title).font(.system(size: 10, weight: .semibold))
                    if !project.location.isEmpty {
                        Text(project.location).font(.system(size: 9)).foregroundColor(.gray)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    fieldLabel("FROM (CONTRACTOR)")
                    Text("J&R Steel Welding LLC").font(.system(size: 10, weight: .semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    fieldLabel("APPLICATION NO.")
                    Text("\(payApp.applicationNumber)").font(.system(size: 10, weight: .semibold))
                    fieldLabel("PERIOD TO")
                    Text(payApp.periodTo.shortDate).font(.system(size: 10))
                    fieldLabel("APPLICATION DATE")
                    Text(payApp.applicationDate.shortDate).font(.system(size: 10))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Accent divider
            Rectangle()
                .fill(aiaFlameOrange)
                .frame(height: 2)
                .padding(.bottom, 6)

            // Column headers
            HStack(spacing: 0) {
                Text("A").g703Header(width: wA)
                Text("DESCRIPTION OF WORK").g703Header(width: wDesc, alignment: .leading)
                Text("C\nSCHEDULED\nVALUE").g703Header(width: wC)
                Text("D\nFROM\nPREVIOUS").g703Header(width: wD)
                Text("E\nTHIS\nPERIOD").g703Header(width: wE)
                Text("F\nMATERIALS\nSTORED").g703Header(width: wF)
                Text("G\nTOTAL\nCOMPLETED").g703Header(width: wG)
                Text("% G/C").g703Header(width: wPct)
                Text("H\nBALANCE\nTO FINISH").g703Header(width: wH)
                Text("I\nRETAINAGE").g703Header(width: wI)
            }
            .background(aiaFlameOrange.opacity(0.12))
            .overlay(
                Rectangle().fill(aiaFlameOrange.opacity(0.35)).frame(height: 0.5),
                alignment: .bottom
            )

            // Line items
            ForEach(payApp.lineItems) { item in
                HStack(spacing: 0) {
                    Text("\(item.itemNumber)").g703Cell(width: wA)
                    Text(item.description).g703Cell(width: wDesc, alignment: .leading)
                    Text(item.scheduledValue.currencyFormatted).g703Cell(width: wC)
                    Text(item.previousCompleted.currencyFormatted).g703Cell(width: wD)
                    Text(item.thisPeriodCompleted.currencyFormatted).g703Cell(width: wE)
                    Text(item.materialsStored.currencyFormatted).g703Cell(width: wF)
                    Text(item.totalCompletedToDate.currencyFormatted).g703Cell(width: wG)
                    Text(String(format: "%.0f%%", item.percentComplete)).g703Cell(width: wPct)
                    Text(item.balanceToFinish.currencyFormatted).g703Cell(width: wH)
                    Text(item.retainage(at: payApp.retainageRate).currencyFormatted).g703Cell(width: wI)
                }
                Rectangle()
                    .fill(Color.gray.opacity(0.25))
                    .frame(height: 0.5)
            }

            // Grand total — orange bar
            HStack(spacing: 0) {
                Text("").g703Cell(width: wA)
                Text("GRAND TOTAL").g703Cell(width: wDesc, alignment: .leading).fontWeight(.bold)
                Text(payApp.totalScheduledValue.currencyFormatted).g703Cell(width: wC).fontWeight(.bold)
                Text(payApp.totalPreviousCompleted.currencyFormatted).g703Cell(width: wD).fontWeight(.bold)
                Text(payApp.totalThisPeriod.currencyFormatted).g703Cell(width: wE).fontWeight(.bold)
                Text(payApp.totalMaterialsStored.currencyFormatted).g703Cell(width: wF).fontWeight(.bold)
                Text(payApp.totalCompletedToDate.currencyFormatted).g703Cell(width: wG).fontWeight(.bold)
                Text(String(format: "%.0f%%", payApp.overallPercentComplete)).g703Cell(width: wPct).fontWeight(.bold)
                Text(payApp.totalBalanceToFinish.currencyFormatted).g703Cell(width: wH).fontWeight(.bold)
                Text(payApp.totalRetainage.currencyFormatted).g703Cell(width: wI).fontWeight(.bold)
            }
            .foregroundColor(.white)
            .background(aiaFlameOrange)

            Spacer(minLength: 0)
        }
        .font(.system(size: 8))
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(width: 792, height: 1008, alignment: .topLeading)
        .background(Color.white)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 7, weight: .bold))
            .foregroundColor(aiaFlameOrange)
    }
}

// MARK: - SteelSync Branded Invoice View

private struct SteelSyncInvoiceView: View {
    let payApp: PayApplication
    let project: Project
    let client: Client?

    private var netAmount: Decimal {
        payApp.netAmountThisPeriod - payApp.totalRetainage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Orange header band
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("INVOICE")
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(.white)
                    Text("J&R STEEL WELDING LLC")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("APP #\(payApp.applicationNumber)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                    Text(payApp.applicationDate.shortDate)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(24)
            .background(Color(red: 1.0, green: 0.42, blue: 0.21))  // Flame orange

            VStack(alignment: .leading, spacing: 16) {
                // Project info
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BILL TO")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                        Text(client?.name ?? project.title)
                            .font(.system(size: 12, weight: .semibold))
                        if let address = client?.billingAddress, !address.isEmpty {
                            Text(address)
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PROJECT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                        Text(project.title)
                            .font(.system(size: 12, weight: .semibold))
                        if !project.location.isEmpty {
                            Text(project.location)
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("BILLING PERIOD")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                        Text("Through \(payApp.periodTo.shortDate)")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }

                Divider()

                // Line items (compact)
                VStack(spacing: 4) {
                    HStack {
                        Text("DESCRIPTION")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                        Spacer()
                        Text("AMOUNT")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    .padding(.bottom, 4)
                    ForEach(payApp.lineItems) { item in
                        if item.thisPeriodCompleted > 0 || item.materialsStored > 0 {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.description)
                                        .font(.system(size: 10))
                                    if item.materialsStored > 0 {
                                        Text("Includes materials stored: \(item.materialsStored.currencyFormatted)")
                                            .font(.system(size: 8))
                                            .foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                                Text((item.thisPeriodCompleted + item.materialsStored).currencyFormatted)
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .padding(.vertical, 2)
                            Divider()
                        }
                    }
                }

                // Totals
                VStack(alignment: .trailing, spacing: 6) {
                    totalRow("Work This Period", payApp.totalThisPeriod)
                    totalRow("Materials Stored", payApp.totalMaterialsStored)
                    totalRow("Subtotal", payApp.netAmountThisPeriod)
                    totalRow("Retainage (\(Int(Double(truncating: payApp.retainageRate * 100 as NSDecimalNumber)))%)", -payApp.totalRetainage)
                    Divider().frame(maxWidth: 250)
                    HStack {
                        Spacer()
                        Text("AMOUNT DUE")
                            .font(.system(size: 12, weight: .bold))
                        Text(netAmount.currencyFormatted)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.21))
                    }
                    .frame(maxWidth: 280)
                }
                .padding(.top, 8)

                Spacer()

                // Footer
                VStack(alignment: .leading, spacing: 4) {
                    Text("PAYMENT TERMS")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.gray)
                    Text("Net 30 days from invoice date. Payable to J&R Steel Welding LLC.")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
            }
            .padding(24)
        }
        .frame(width: 792, height: 1008, alignment: .topLeading)
        .background(Color.white)
    }

    private func totalRow(_ label: String, _ value: Decimal) -> some View {
        HStack {
            Spacer()
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.gray)
            Text(value.currencyFormatted)
                .font(.system(size: 10, weight: .medium))
                .frame(width: 90, alignment: .trailing)
        }
        .frame(maxWidth: 280)
    }
}

// MARK: - G703 Cell Modifiers

private extension Text {
    func g703Header(width: CGFloat, alignment: Alignment = .center) -> some View {
        self.font(.system(size: 7, weight: .bold))
            .multilineTextAlignment(.center)
            .frame(width: width, alignment: alignment)
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
    }

    func g703Cell(width: CGFloat, alignment: Alignment = .trailing) -> some View {
        self.font(.system(size: 8))
            .frame(width: width, alignment: alignment)
            .padding(.vertical, 3)
            .padding(.horizontal, 2)
    }
}
