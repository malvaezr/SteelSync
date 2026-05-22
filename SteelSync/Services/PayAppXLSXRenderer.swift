import Foundation

/// Writes a Pay Application to a real .xlsx file matching the UT Boiler /
/// Carrillo Steel template. Two sheets:
///
/// - "Application" — page-1 cover with TO / FROM / project info, lines 1-9
///   (with line 8 highlighted yellow), and a CO summary table.
/// - "Schedule of Values" — page-2 SOV table with subtotals, change-order
///   section, total row, and bottom SUMMARY block.
///
/// All numbers are written as proper currency-formatted numeric cells (so
/// you can edit them in Excel and formulas/recalcs work) — not text.
///
/// Backed by `XLSXWorkbook` (see `MinimalXLSXWriter.swift`). The "cells"
/// here are laid out by absolute column position: A, B, C, … with empty
/// `.empty` placeholders for skipped columns, because XLSXWorkbook does
/// not auto-skip — every row's nth entry goes into spreadsheet column n.
struct PayAppXLSXRenderer {
    let payApp: PayApplication
    let project: Project
    let client: Client?

    private var contractToDate: Decimal { payApp.totalScheduledValue }
    private var netChangeByCO: Decimal { contractToDate - project.contractAmount }
    private var totalEarnedLessRetainage: Decimal { payApp.totalCompletedToDate - payApp.totalRetainage }
    private var currentPaymentDue: Decimal { totalEarnedLessRetainage - payApp.totalPreviousCompleted }
    private var balanceToFinishIncludingRetainage: Decimal { contractToDate - totalEarnedLessRetainage }

    private var baseLineItems: [SOVLineItem] {
        payApp.lineItems.filter { !$0.isChangeOrder }
    }
    private var changeOrderItems: [SOVLineItem] {
        payApp.lineItems.filter { $0.isChangeOrder }
    }

    func render() -> URL? {
        var book = XLSXWorkbook()
        book.addSheet(name: "Application", rows: applicationRows())
        book.addSheet(name: "Schedule of Values", rows: scheduleOfValuesRows())

        let safeTitle = project.title.replacingOccurrences(of: " ", with: "_")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "_")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubApp-\(safeTitle)-App\(payApp.applicationNumber).xlsx")

        do {
            return try book.write(to: url)
        } catch {
            return nil
        }
    }

    // MARK: - Sheet 1: Application

    private func applicationRows() -> [[XLSXCell]] {
        var rows: [[XLSXCell]] = []

        // Row 1: title
        rows.append([
            .bold("SUBCONTRACTOR'S APPLICATION AND CERTIFICATE FOR PAYMENT"),
            .empty, .empty, .empty, .empty,
            .string("Page 1 of 2 pages")
        ])
        rows.append([])

        // Header info — three "columns" laid out as adjacent cells:
        // A=label B=value | C=label D=value | E=label F=value
        rows.append([
            .bold("TO:"), .string(client?.name ?? ""),
            .bold("PROJECT:"), .string(project.title),
            .bold("APPLICATION DATE:"), .string(payApp.applicationDate.shortDate)
        ])
        rows.append([
            .empty, .string(client?.billingAddress ?? ""),
            .bold("CONTRACT FOR:"), .boldYellow("Ruben Malvaez"),
            .bold("APPLICATION NO.:"), .string("\(payApp.applicationNumber)")
        ])
        rows.append([
            .bold("FROM:"), .boldYellow("J & R WELDING LLC"),
            .bold("PHONE NO.:"), .empty,
            .bold("PERIOD TO:"), .boldYellow(payApp.periodTo.shortDate)
        ])
        rows.append([
            .empty, .empty,
            .bold("FAX NO.:"), .empty,
            .bold("PROJECT NO.:"), .string(project.title)
        ])
        rows.append([
            .empty, .empty,
            .bold("TAX ID NO.:"), .string("Code N/A"),
            // Contract date is intentionally blank — GC fills in.
            .bold("CONTRACT DATE:"), .boldYellow("")
        ])
        rows.append([
            .empty, .empty, .empty, .empty,
            .bold("INVOICE #"), .boldYellow("\(payApp.applicationNumber)")
        ])
        rows.append([])

        // Application narrative
        rows.append([.string("Application for payment is made as shown below, in connection with the Contract.")])
        rows.append([])

        // Lines 1–9
        rows.append([
            .string("1.  ORIGINAL CONTRACT SUM"),
            .currency(project.contractAmount, bold: true)
        ])
        rows.append([
            .string("2.  Net Change by Change Orders"),
            .currency(netChangeByCO)
        ])
        rows.append([
            .string("3.  CONTRACT SUM TO DATE"),
            .currency(contractToDate, bold: true)
        ])
        rows.append([
            .string("4.  TOTAL COMPLETED & STORED TO DATE"),
            .currency(payApp.totalCompletedToDate, bold: true)
        ])
        rows.append([
            .bold("5.  LESS RETAINAGE \(retainagePctText)"),
            .currency(payApp.totalRetainage, bold: true)
        ])
        rows.append([
            .string("6.  TOTAL EARNED LESS RETAINAGE   (Line 4 Less Line 5 Total)"),
            .currency(totalEarnedLessRetainage, bold: true)
        ])
        rows.append([
            .string("7.  LESS PREVIOUS CERTIFICATES   (Line 6 from prior Certificate)"),
            .currency(payApp.totalPreviousCompleted)
        ])
        rows.append([
            .boldYellow("8.  CURRENT PAYMENT DUE"),
            .currency(currentPaymentDue, yellow: true)
        ])
        rows.append([
            .string("9.  Balance to Finish, Including Retainage"),
            .currency(balanceToFinishIncludingRetainage)
        ])
        rows.append([])

        // CHANGE ORDER SUMMARY TABLE
        rows.append([
            .boldCenter("CHANGE ORDER SUMMARY"),
            .boldCenter("ADDITIONS"),
            .boldCenter("DEDUCTIONS")
        ])

        let additionItems = changeOrderItems.filter { $0.scheduledValue > 0 }
        let deductionItems = changeOrderItems.filter { $0.scheduledValue < 0 }
        let totalAdditions = additionItems.reduce(Decimal(0)) { $0 + $1.scheduledValue }
        let totalDeductions = deductionItems.reduce(Decimal(0)) { $0 + $1.scheduledValue }
        let net = totalAdditions + totalDeductions

        for co in changeOrderItems {
            let isDeduction = co.scheduledValue < 0
            rows.append([
                .string(co.description),
                isDeduction ? .empty : .currency(co.scheduledValue),
                isDeduction ? .currency(co.scheduledValue, bold: true, red: true) : .empty
            ])
        }
        // pad to 5 rows if needed
        for _ in 0..<max(0, 5 - changeOrderItems.count) {
            rows.append([.empty, .empty, .empty])
        }

        rows.append([
            .bold("TOTALS"),
            .currency(totalAdditions, bold: true),
            .currency(totalDeductions, bold: true)
        ])
        rows.append([
            .bold("NET CHANGES by Change Order"),
            .empty,
            .currency(net, bold: true)
        ])
        rows.append([])

        // SUBCONTRACTOR / NOTARY / ARCHITECT BLOCK (lien release)
        rows.append([.bold("SUBCONTRACTOR'S CERTIFICATION:")])
        rows.append([.string("The undersigned Contractor certifies that to the best of the Contractor's knowledge,")])
        rows.append([.string("information and belief the Work covered by this Application for Payment has been completed")])
        rows.append([.string("in accordance with the Contract Documents, that all amounts have been paid by the Contractor")])
        rows.append([.string("for Work for which previous Certificates for Payment were issued and payments received from")])
        rows.append([.string("the Owner, and that current payment shown herein is now due.")])
        rows.append([])
        rows.append([
            .bold("SUBCONTRACTOR:"),
            .string("By: ____________________________"),
            .string("Date: ______________")
        ])
        rows.append([])
        // State of / County of left blank for the notary to fill in.
        rows.append([
            .string("State of: ____________________"),
            .empty,
            .string("County of: ____________________")
        ])
        rows.append([.string("Subscribed and sworn to before me this _____ day of _______________")])
        rows.append([.string("Notary Public: __________________________________")])
        rows.append([.string("My Commission Expires: __________________________")])
        rows.append([])
        rows.append([.bold("ARCHITECT'S CERTIFICATE FOR PAYMENT")])
        rows.append([.string("In accordance with the Contract Documents, based on on-site observations and the data")])
        rows.append([.string("comprising this application, the Architect certifies to the Owner that to the best of the")])
        rows.append([.string("Architect's knowledge, information and belief the Work has progressed as indicated, the")])
        rows.append([.string("quality of the Work is in accordance with the Contract Documents, and the Contractor is")])
        rows.append([.string("entitled to payment of the AMOUNT CERTIFIED.")])
        rows.append([])
        rows.append([
            .bold("AMOUNT CERTIFIED:"),
            .string("$ _________________________")
        ])
        rows.append([.string("(Attached explanation if amount certified differs from the amount applied for. Initial all")])
        rows.append([.string("figures on this Application and on the Continuation Sheet that are changed to conform to the")])
        rows.append([.string("amount certified.)")])
        rows.append([])
        rows.append([
            .bold("ARCHITECT:"),
            .string("By: ____________________________"),
            .string("Date: ______________")
        ])
        rows.append([])
        rows.append([.string("This Certificate is not negotiable. The AMOUNT CERTIFIED is payable only to the Contractor")])
        rows.append([.string("named herein. Issuance, payment and acceptance of payment are without prejudice to any")])
        rows.append([.string("rights of the Owner or Contractor under this Contract.")])

        return rows
    }

    // MARK: - Sheet 2: Schedule of Values

    private func scheduleOfValuesRows() -> [[XLSXCell]] {
        var rows: [[XLSXCell]] = []

        // Header row
        rows.append([
            .bold(client?.name ?? "Contractor"),
            .empty, .empty,
            .bold("SCHEDULE OF VALUES"),
            .empty, .empty, .empty, .empty, .empty,
            .string("Page 2 of 2")
        ])
        rows.append([
            .empty, .empty, .empty, .empty, .empty, .empty, .empty,
            .bold("Pay Application #"),
            .boldYellow("\(payApp.applicationNumber)")
        ])
        rows.append([])

        // Two-row header
        rows.append([
            .empty, .empty, .empty,
            .boldCenter("Work Completed"), .empty,
            .empty,
            .boldCenter("Total"),
            .empty, .empty, .empty
        ])
        rows.append([
            .boldCenter("No."),
            .boldCenter("Description of Work"),
            .boldCenter("Scheduled Value"),
            .boldCenter("Previous Applications"),
            .boldCenter("Work in Place"),
            .boldCenter("Stored Materials"),
            .boldCenter("Completed & Stored"),
            .boldCenter("Percent Completed"),
            .boldCenter("Balance To Finish"),
            .boldCenter("Retainage 10%")
        ])

        // Base SOV
        for item in baseLineItems {
            rows.append(itemRow(item, red: false))
        }
        let blankCount = max(0, 24 - baseLineItems.count)
        for _ in 0..<blankCount {
            rows.append([.empty, .empty, .empty, .empty, .empty, .empty, .empty, .empty, .empty, .empty])
        }

        // Subtotals row
        let baseSched = baseLineItems.reduce(Decimal(0)) { $0 + $1.scheduledValue }
        let basePrev = baseLineItems.reduce(Decimal(0)) { $0 + $1.previousCompleted }
        let baseThis = baseLineItems.reduce(Decimal(0)) { $0 + $1.thisPeriodCompleted }
        let baseStored = baseLineItems.reduce(Decimal(0)) { $0 + $1.materialsStored }
        let baseTotal = baseLineItems.reduce(Decimal(0)) { $0 + $1.totalCompletedToDate }
        let baseRet = baseLineItems.reduce(Decimal(0)) { $0 + $1.retainage(at: payApp.retainageRate) }

        rows.append([
            .empty,
            .bold("SUBTOTALS"),
            .currency(baseSched, bold: true),
            .currency(basePrev, bold: true),
            .currency(baseThis, bold: true),
            .currency(baseStored, bold: true),
            .currency(baseTotal, bold: true),
            .empty,
            .empty,
            .currency(baseRet, bold: true)
        ])

        // Change orders
        for item in changeOrderItems {
            rows.append(itemRow(item, red: true))
        }
        for _ in 0..<max(0, 4 - changeOrderItems.count) {
            rows.append([.empty, .empty, .empty, .empty, .empty, .empty, .empty, .empty, .empty, .empty])
        }

        // CO subtotal row
        let coSched = changeOrderItems.reduce(Decimal(0)) { $0 + $1.scheduledValue }
        let coPrev = changeOrderItems.reduce(Decimal(0)) { $0 + $1.previousCompleted }
        let coThis = changeOrderItems.reduce(Decimal(0)) { $0 + $1.thisPeriodCompleted }
        let coStored = changeOrderItems.reduce(Decimal(0)) { $0 + $1.materialsStored }
        let coTotal = changeOrderItems.reduce(Decimal(0)) { $0 + $1.totalCompletedToDate }
        let coRet = changeOrderItems.reduce(Decimal(0)) { $0 + $1.retainage(at: payApp.retainageRate) }

        rows.append([
            .empty,
            .bold("Sub Total"),
            .currency(coSched, bold: true),
            .currency(coPrev, bold: true),
            .currency(coThis, bold: true),
            .currency(coStored, bold: true),
            .currency(coTotal, bold: true),
            .empty,
            .empty,
            .currency(coRet, bold: true)
        ])

        // TOTAL AMOUNT row
        rows.append([
            .empty,
            .bold("TOTAL AMOUNT"),
            .currency(payApp.totalScheduledValue, bold: true),
            .currency(payApp.totalPreviousCompleted, bold: true),
            .currency(payApp.totalThisPeriod, bold: true),
            .currency(payApp.totalMaterialsStored, bold: true),
            .currency(payApp.totalCompletedToDate, bold: true),
            .percent(payApp.overallPercentComplete / 100.0),
            .currency(payApp.totalBalanceToFinish, bold: true),
            .currency(payApp.totalRetainage, bold: true)
        ])

        // Summary block
        rows.append([])
        rows.append([.bold("SUMMARY")])
        rows.append([
            .boldYellow("Original Contract"),
            .currency(project.contractAmount),
            .string("enter at beginning of project")
        ])
        rows.append([.string("Change Orders to Date"), .currency(coSched)])
        rows.append([.string("Contract Sum To Date"), .currency(contractToDate)])
        rows.append([.string("Completed to Date"), .currency(payApp.totalCompletedToDate)])
        rows.append([.string("Retainage"), .currency(payApp.totalRetainage)])
        rows.append([
            .boldYellow("Previous Applications"),
            .currency(payApp.totalPreviousCompleted),
            .string("Use last app's NET DUE here next month")
        ])
        rows.append([
            .bold("NET DUE THIS APPLICATION"),
            .currency(currentPaymentDue, bold: true)
        ])

        return rows
    }

    /// Builds one SOV row. Pass `red: true` for change-order rows — the
    /// description, this-period, scheduled value, and retainage cells
    /// will then render bold red to match the template's visual cue for
    /// CO line items.
    private func itemRow(_ item: SOVLineItem, red: Bool) -> [XLSXCell] {
        let pct = item.percentComplete / 100.0
        return [
            .string("\(item.itemNumber)"),
            red ? .boldRed(item.description) : .string(item.description),
            .currency(item.scheduledValue, bold: red, red: red),
            item.previousCompleted == 0 ? .empty : .currency(item.previousCompleted),
            item.thisPeriodCompleted == 0 ? .empty : .currency(item.thisPeriodCompleted, bold: red, red: red),
            item.materialsStored == 0 ? .empty : .currency(item.materialsStored),
            item.totalCompletedToDate == 0 ? .empty : .currency(item.totalCompletedToDate),
            .percent(pct),
            item.balanceToFinish == 0 ? .empty : .currency(item.balanceToFinish),
            .currency(item.retainage(at: payApp.retainageRate), bold: red, red: red)
        ]
    }

    // MARK: - Helpers

    private var retainagePctText: String {
        String(format: "%.0f%%", Double(truncating: payApp.retainageRate * 100 as NSDecimalNumber))
    }

    private func notaryLine() -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        let day = f.string(from: payApp.applicationDate)
        f.dateFormat = "MMMM yyyy"
        let monthYear = f.string(from: payApp.applicationDate)
        return "Subscribed and sworn to before me this \(day)\(ordinalSuffix(forDay: Int(day) ?? 1)) day of \(monthYear)"
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
}
