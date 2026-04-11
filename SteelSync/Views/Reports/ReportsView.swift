import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ReportsView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedReport = "Overview"

    private let reports = ["Overview", "Projects", "Bidding", "Clients", "Financial"]

    var body: some View {
        VStack(spacing: 0) {
            // Report selector
            HStack(spacing: AppTheme.Spacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(reports, id: \.self) { report in
                            FilterPill(report, isSelected: selectedReport == report) {
                                selectedReport = report
                            }
                        }
                    }
                }
                Spacer()

                Button(action: exportCSV) {
                    Label("Export CSV", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)

                Button(action: exportPDF) {
                    Label("Export PDF", systemImage: "doc.richtext")
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.primaryOrange)
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.secondaryBackground)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    switch selectedReport {
                    case "Overview":
                        overviewReport
                    case "Projects":
                        projectsReport
                    case "Bidding":
                        biddingReport
                    case "Clients":
                        clientsReport
                    case "Financial":
                        financialReport
                    default:
                        EmptyView()
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
        }
        .navigationTitle("Reports")
    }

    // MARK: - Overview
    private var overviewReport: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Business Overview")
                .font(AppTheme.Typography.title2)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: AppTheme.Spacing.md) {
                MetricCard(title: "Bid Pipeline", value: dataStore.totalBidPipeline.currencyFormatted, icon: "chart.bar.fill", color: .blue)
                MetricCard(title: "Win Rate", value: String(format: "%.0f%%", dataStore.bidWinRate), icon: "trophy.fill", color: .green)
                MetricCard(title: "Active Projects", value: "\(dataStore.activeProjects.count)", icon: "hammer.fill", color: AppTheme.primaryOrange)
                MetricCard(title: "Total Contract Value", value: dataStore.totalContractValue.currencyFormatted, icon: "building.2.fill", color: .purple)
                MetricCard(title: "Total Revenue", value: dataStore.totalRevenue.currencyFormatted, icon: "dollarsign.circle.fill", color: .green)
                MetricCard(title: "Total Profit", value: dataStore.totalProfit.currencyFormatted, icon: "chart.line.uptrend.xyaxis",
                           color: dataStore.totalProfit >= 0 ? .green : .red)
                MetricCard(title: "Total Costs", value: dataStore.totalCosts.currencyFormatted, icon: "cart.fill", color: .orange)
                MetricCard(title: "Remaining Balance", value: dataStore.totalRemainingBalance.currencyFormatted, icon: "banknote.fill", color: .blue)
            }

            GroupBox("Workforce") {
                HStack(spacing: AppTheme.Spacing.xl) {
                    InfoRow(label: "Total Employees", value: "\(dataStore.employees.count)", icon: "person.2.fill")
                    InfoRow(label: "Active", value: "\(dataStore.activeEmployees.count)", icon: "checkmark.circle")
                    InfoRow(label: "Foremen", value: "\(dataStore.foremen.count)", icon: "person.fill.checkmark")
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            GroupBox("Clients") {
                HStack(spacing: AppTheme.Spacing.xl) {
                    InfoRow(label: "Total Clients", value: "\(dataStore.clients.count)", icon: "person.2.fill")
                    InfoRow(label: "General Contractors", value: "\(dataStore.gcClients.count)", icon: "building.2.fill")
                    InfoRow(label: "Subcontractors", value: "\(dataStore.subcontractorClients.count)", icon: "wrench.and.screwdriver.fill")
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            GroupBox("Tasks") {
                HStack(spacing: AppTheme.Spacing.xl) {
                    InfoRow(label: "Active Tasks", value: "\(dataStore.activeTodos.count)", icon: "checklist")
                    InfoRow(label: "Overdue", value: "\(dataStore.overdueTodos.count)", icon: "exclamationmark.triangle")
                    InfoRow(label: "Upcoming Events", value: "\(dataStore.upcomingEvents.count)", icon: "calendar")
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }
        }
    }

    // MARK: - Projects Report
    private var projectsReport: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Project Performance")
                .font(AppTheme.Typography.title2)

            Table(dataStore.projects) {
                TableColumn("Project") { p in Text(p.title).fontWeight(.medium) }
                TableColumn("Client") { p in
                    Text(dataStore.clientName(for: p) ?? "-")
                        .foregroundColor(.secondary)
                }
                TableColumn("Type") { p in
                    if let client = dataStore.client(for: p.clientRef) {
                        StatusBadge(text: client.preferredRateType == .generalContractor ? "GC" : "Sub",
                                    color: client.preferredRateType == .generalContractor ? AppTheme.primaryOrange : .purple)
                    } else {
                        Text("-").foregroundColor(.secondary)
                    }
                }.width(min: 50, max: 70)
                TableColumn("Status") { p in StatusBadge(text: p.computedStatus, color: statusColor(p)) }
                    .width(min: 80, max: 120)
                TableColumn("Contract") { p in Text(p.contractAmount.currencyFormatted) }
                    .width(min: 90, max: 120)
                TableColumn("Revenue") { p in Text(p.totalRevenue.currencyFormatted) }
                    .width(min: 90, max: 120)
                TableColumn("Profit") { p in
                    Text(p.profit.currencyFormatted)
                        .foregroundColor(p.profit >= 0 ? .green : .red)
                }.width(min: 90, max: 120)
                TableColumn("Margin") { p in Text(String(format: "%.1f%%", p.profitMargin)) }
                    .width(min: 60, max: 80)
            }
            .frame(minHeight: 300)
        }
    }

    // MARK: - Bidding Report
    private var biddingReport: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Bid Pipeline Analysis")
                .font(AppTheme.Typography.title2)

            HStack(spacing: AppTheme.Spacing.md) {
                MetricCard(title: "Total Bids", value: "\(dataStore.bids.count)", icon: "doc.text.fill", color: .blue)
                MetricCard(title: "Pipeline Value", value: dataStore.totalBidPipeline.currencyFormatted, icon: "chart.bar.fill", color: AppTheme.primaryOrange)
                MetricCard(title: "Win Rate", value: String(format: "%.0f%%", dataStore.bidWinRate), icon: "trophy.fill", color: .green)
                MetricCard(title: "Avg Bid Size", value: {
                    let avg = dataStore.bids.isEmpty ? Decimal(0) : dataStore.bids.reduce(0) { $0 + $1.bidAmount } / Decimal(dataStore.bids.count)
                    return avg.currencyFormatted
                }(), icon: "equal.circle.fill", color: .purple)
            }

            Table(dataStore.bids.sorted { $0.bidDueDate < $1.bidDueDate }) {
                TableColumn("Project") { b in Text(b.projectName).fontWeight(.medium) }
                TableColumn("Client") { b in Text(b.clientName) }
                TableColumn("Type") { b in
                    if let client = dataStore.client(for: b.clientRef) {
                        StatusBadge(text: client.preferredRateType == .generalContractor ? "GC" : "Sub",
                                    color: client.preferredRateType == .generalContractor ? AppTheme.primaryOrange : .purple)
                    } else {
                        Text("-").foregroundColor(.secondary)
                    }
                }.width(min: 50, max: 70)
                TableColumn("Amount") { b in Text(b.bidAmount.currencyFormatted) }
                    .width(min: 90, max: 120)
                TableColumn("Due") { b in Text(b.bidDueDate.shortDate) }
                    .width(min: 90, max: 120)
                TableColumn("Status") { b in
                    StatusBadge(text: b.status.rawValue, color: bidStatusColor(b))
                }.width(min: 90, max: 120)
            }
            .frame(minHeight: 250)
        }
    }

    // MARK: - Clients Report
    private var clientsReport: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Client Analysis")
                .font(AppTheme.Typography.title2)

            HStack(spacing: AppTheme.Spacing.md) {
                MetricCard(title: "General Contractors", value: "\(dataStore.gcClients.count)",
                           icon: "building.2.fill", color: AppTheme.primaryOrange)
                MetricCard(title: "Subcontractors", value: "\(dataStore.subcontractorClients.count)",
                           icon: "wrench.and.screwdriver.fill", color: .purple)
                MetricCard(title: "Total Clients", value: "\(dataStore.clients.count)",
                           icon: "person.2.fill", color: .blue)
            }

            GroupBox("Revenue by Client Type") {
                VStack(spacing: AppTheme.Spacing.md) {
                    clientTypeRow(.generalContractor)
                    Divider()
                    clientTypeRow(.subcontractor)
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            GroupBox("Client Performance") {
                Table(dataStore.clients.sorted { $0.name < $1.name }) {
                    TableColumn("Client") { c in Text(c.name).fontWeight(.medium) }
                    TableColumn("Type") { c in
                        StatusBadge(text: c.preferredRateType == .generalContractor ? "GC" : "Sub",
                                    color: c.preferredRateType == .generalContractor ? AppTheme.primaryOrange : .purple)
                    }.width(min: 60, max: 80)
                    TableColumn("Projects") { c in Text("\(dataStore.projects(for: c).count)") }
                        .width(min: 60, max: 80)
                    TableColumn("Bids") { c in Text("\(dataStore.bids(for: c).count)") }
                        .width(min: 50, max: 70)
                    TableColumn("Revenue") { c in
                        Text(dataStore.projects(for: c).reduce(Decimal(0)) { $0 + $1.totalRevenue }.currencyFormatted)
                    }.width(min: 90, max: 120)
                    TableColumn("Profit") { c in
                        let profit = dataStore.projects(for: c).reduce(Decimal(0)) { $0 + $1.profit }
                        Text(profit.currencyFormatted).foregroundColor(profit >= 0 ? .green : .red)
                    }.width(min: 90, max: 120)
                    TableColumn("Margin") { c in
                        let projects = dataStore.projects(for: c)
                        let rev = projects.reduce(Decimal(0)) { $0 + $1.totalRevenue }
                        let prof = projects.reduce(Decimal(0)) { $0 + $1.profit }
                        let margin = rev > 0 ? Double(truncating: (prof / rev * 100) as NSDecimalNumber) : 0
                        Text(String(format: "%.1f%%", margin))
                    }.width(min: 60, max: 80)
                }
                .frame(minHeight: 250)
            }
        }
    }

    private func clientTypeRow(_ type: RateType) -> some View {
        let typeClients = dataStore.clients.filter { $0.preferredRateType == type }
        let typeProjects = typeClients.flatMap { dataStore.projects(for: $0) }
        let revenue = typeProjects.reduce(Decimal(0)) { $0 + $1.totalRevenue }
        let profit = typeProjects.reduce(Decimal(0)) { $0 + $1.profit }
        let costs = typeProjects.reduce(Decimal(0)) { $0 + $1.totalCosts }

        return HStack {
            StatusBadge(text: type.displayName,
                        color: type == .generalContractor ? AppTheme.primaryOrange : .purple)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Revenue: \(revenue.currencyFormatted)").font(.callout).fontWeight(.medium)
                HStack(spacing: AppTheme.Spacing.md) {
                    Text("Costs: \(costs.currencyFormatted)").font(.caption).foregroundColor(.secondary)
                    Text("Profit: \(profit.currencyFormatted)").font(.caption)
                        .foregroundColor(profit >= 0 ? .green : .red)
                }
            }
            Text("\(typeProjects.count) projects")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
    }

    // MARK: - Financial Report
    private var financialReport: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            Text("Financial Summary")
                .font(AppTheme.Typography.title2)

            let summary = dataStore.financialSummary

            GroupBox("Profit & Loss") {
                VStack(spacing: AppTheme.Spacing.md) {
                    HStack {
                        Text("Total Revenue").font(.headline)
                        Spacer()
                        Text(summary.revenue.currencyFormatted).font(.title3).fontWeight(.bold).foregroundColor(.green)
                    }
                    Divider()
                    HStack {
                        Text("Total Costs").font(.headline)
                        Spacer()
                        Text(summary.costs.currencyFormatted).font(.title3).fontWeight(.bold).foregroundColor(.red)
                    }
                    Divider()
                    HStack {
                        Text("Net Profit").font(.title3).fontWeight(.bold)
                        Spacer()
                        Text(summary.profit.currencyFormatted)
                            .font(.title2).fontWeight(.bold)
                            .foregroundColor(summary.profit >= 0 ? .green : .red)
                    }
                    HStack {
                        Text("Overall Margin")
                        Spacer()
                        Text(String(format: "%.1f%%", summary.margin))
                            .fontWeight(.semibold)
                    }
                }
                .padding(.vertical, AppTheme.Spacing.sm)
            }

            GroupBox("Per-Project Breakdown") {
                Table(dataStore.projects.filter { $0.computedStatus == "Active" || $0.computedStatus == "Completed" }) {
                    TableColumn("Project") { p in Text(p.title) }
                    TableColumn("Client") { p in
                        Text(dataStore.clientName(for: p) ?? "-").foregroundColor(.secondary)
                    }
                    TableColumn("Revenue") { p in Text(p.totalRevenue.currencyFormatted) }.width(min: 90, max: 120)
                    TableColumn("Costs") { p in Text(p.totalCosts.currencyFormatted) }.width(min: 90, max: 120)
                    TableColumn("Profit") { p in
                        Text(p.profit.currencyFormatted).foregroundColor(p.profit >= 0 ? .green : .red)
                    }.width(min: 90, max: 120)
                    TableColumn("Margin") { p in Text(String(format: "%.1f%%", p.profitMargin)) }.width(min: 60, max: 80)
                }
                .frame(minHeight: 200)
            }
        }
    }

    // MARK: - Helpers
    private func statusColor(_ project: Project) -> Color {
        switch project.computedStatus {
        case "Active": return AppTheme.ProjectStatus.active
        case "Upcoming": return AppTheme.ProjectStatus.upcoming
        case "Completed": return AppTheme.ProjectStatus.completed
        default: return AppTheme.ProjectStatus.onHold
        }
    }

    private func bidStatusColor(_ bid: BidProject) -> Color {
        switch bid.status {
        case .pending: return .blue; case .readyToSubmit: return .cyan
        case .submitted: return .purple; case .awarded: return .green; case .lost: return .red
        }
    }

    // MARK: - CSV Generation (shared between CSV and PDF export)

    private func buildCSVString() -> String {
        var csv = ""
        switch selectedReport {
        case "Clients":
            csv = "Client,Type,Projects,Bids,Revenue,Costs,Profit,Margin\n"
            for c in dataStore.clients.sorted(by: { $0.name < $1.name }) {
                let projects = dataStore.projects(for: c)
                let bids = dataStore.bids(for: c)
                let rev = projects.reduce(Decimal(0)) { $0 + $1.totalRevenue }
                let costs = projects.reduce(Decimal(0)) { $0 + $1.totalCosts }
                let prof = projects.reduce(Decimal(0)) { $0 + $1.profit }
                let margin = rev > 0 ? Double(truncating: (prof / rev * 100) as NSDecimalNumber) : 0
                csv += "\"\(c.name)\",\(c.preferredRateType.displayName),\(projects.count),\(bids.count),\(rev),\(costs),\(prof),\(String(format: "%.1f", margin))%\n"
            }
        default:
            csv = "Project,Client,Client Type,Status,Contract,Revenue,Costs,Profit,Margin\n"
            for p in dataStore.projects {
                let client = dataStore.client(for: p.clientRef)
                let clientName = client?.name ?? ""
                let clientType = client?.preferredRateType.displayName ?? ""
                csv += "\"\(p.title)\",\"\(clientName)\",\(clientType),\(p.computedStatus),\(p.contractAmount),\(p.totalRevenue),\(p.totalCosts),\(p.profit),\(String(format: "%.1f", p.profitMargin))%\n"
            }
        }
        return csv
    }

    // MARK: - Export CSV

    private func exportCSV() {
        let csv = buildCSVString()
        let csvData = csv.data(using: .utf8) ?? Data()
        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "SteelSync_\(selectedReport)_Report.csv"
        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? csvData.write(to: url)
            }
        }
        #else
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteelSync_\(selectedReport)_Report.csv")
        try? csvData.write(to: tempURL)
        PlatformService.shareItems([tempURL])
        #endif
    }

    // MARK: - Export PDF (CSV → PDF table)

    private func exportPDF() {
        let csv = buildCSVString()
        let rows = parseCSV(csv)
        guard !rows.isEmpty else { return }

        let pdfData = renderCSVToPDF(rows: rows, title: "SteelSync \(selectedReport) Report")

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "SteelSync_\(selectedReport)_Report.pdf"
        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? pdfData.write(to: url)
            }
        }
        #else
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteelSync_\(selectedReport)_Report.pdf")
        try? pdfData.write(to: tempURL)
        PlatformService.shareItems([tempURL])
        #endif
    }

    /// Parse CSV string into [[String]] rows, handling quoted fields
    private func parseCSV(_ csv: String) -> [[String]] {
        csv.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { line in
                var fields: [String] = []
                var current = ""
                var inQuotes = false
                for char in line {
                    if char == "\"" { inQuotes.toggle() }
                    else if char == "," && !inQuotes { fields.append(current); current = "" }
                    else { current.append(char) }
                }
                fields.append(current)
                return fields
            }
    }

    /// Renders CSV rows as a formatted PDF table using Core Graphics (cross-platform)
    private func renderCSVToPDF(rows: [[String]], title: String) -> Data {
        let pageWidth: CGFloat = 792  // US Letter landscape
        let pageHeight: CGFloat = 612
        let margin: CGFloat = 40
        let usableWidth = pageWidth - margin * 2
        let titleAreaHeight: CGFloat = 50
        let rowHeight: CGFloat = 20
        let fontSize: CGFloat = 9
        let headerFontSize: CGFloat = 14

        let colCount = rows.first?.count ?? 1
        let colWidth = usableWidth / CGFloat(colCount)
        let maxRowsPerPage = Int((pageHeight - margin * 2 - titleAreaHeight) / rowHeight)

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        guard let consumer = CGDataConsumer(data: pdfData),
              let cgContext = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return Data()
        }

        // On macOS, NSString.draw() requires NSGraphicsContext.current to be set
        #if os(macOS)
        let nsContext = NSGraphicsContext(cgContext: cgContext, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        #endif

        #if os(macOS)
        let titleFont = NSFont.boldSystemFont(ofSize: headerFontSize)
        let bodyFontReg = NSFont.systemFont(ofSize: fontSize)
        let bodyFontBold = NSFont.boldSystemFont(ofSize: fontSize)
        let dateFont = NSFont.systemFont(ofSize: 8)
        let textColor = NSColor.black
        let headerBg = NSColor.systemOrange.withAlphaComponent(0.15).cgColor
        let separatorColor = NSColor.gray.withAlphaComponent(0.3).cgColor
        #else
        let titleFont = UIFont.boldSystemFont(ofSize: headerFontSize)
        let bodyFontReg = UIFont.systemFont(ofSize: fontSize)
        let bodyFontBold = UIFont.boldSystemFont(ofSize: fontSize)
        let dateFont = UIFont.systemFont(ofSize: 8)
        let textColor = UIColor.black
        let headerBg = UIColor.systemOrange.withAlphaComponent(0.15).cgColor
        let separatorColor = UIColor.separator.cgColor
        #endif

        var y: CGFloat = 0

        for (rowIdx, row) in rows.enumerated() {
            if rowIdx % maxRowsPerPage == 0 {
                if rowIdx > 0 { cgContext.endPDFPage() }
                cgContext.beginPDFPage(nil)

                // Flip coordinate system for text drawing
                cgContext.textMatrix = .identity
                cgContext.translateBy(x: 0, y: pageHeight)
                cgContext.scaleBy(x: 1, y: -1)

                #if os(macOS)
                // Re-set NSGraphicsContext after new page
                NSGraphicsContext.current = NSGraphicsContext(cgContext: cgContext, flipped: true)
                #endif

                y = margin

                // Title
                let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: textColor]
                (title as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)

                let dateStr = "Generated: \(Date().shortDate)"
                let dateAttrs: [NSAttributedString.Key: Any] = [.font: dateFont, .foregroundColor: textColor]
                (dateStr as NSString).draw(at: CGPoint(x: pageWidth - margin - 120, y: y + 4), withAttributes: dateAttrs)

                y += titleAreaHeight

                // Redraw column headers on subsequent pages
                if rowIdx > 0, let header = rows.first {
                    drawPDFRow(header, at: &y, x: margin, colWidth: colWidth, isHeader: true,
                               fontReg: bodyFontReg, fontBold: bodyFontBold, textColor: textColor,
                               headerBg: headerBg, separatorColor: separatorColor,
                               context: cgContext, pageWidth: pageWidth, margin: margin)
                }
            }

            drawPDFRow(row, at: &y, x: margin, colWidth: colWidth, isHeader: (rowIdx == 0),
                       fontReg: bodyFontReg, fontBold: bodyFontBold, textColor: textColor,
                       headerBg: headerBg, separatorColor: separatorColor,
                       context: cgContext, pageWidth: pageWidth, margin: margin)
        }

        cgContext.endPDFPage()
        cgContext.closePDF()

        #if os(macOS)
        NSGraphicsContext.restoreGraphicsState()
        #endif

        return pdfData as Data
    }

    #if os(macOS)
    private typealias PlatformFont = NSFont
    private typealias PlatformColor = NSColor
    #else
    private typealias PlatformFont = UIFont
    private typealias PlatformColor = UIColor
    #endif

    private func drawPDFRow(_ fields: [String], at y: inout CGFloat, x: CGFloat, colWidth: CGFloat,
                            isHeader: Bool, fontReg: PlatformFont, fontBold: PlatformFont,
                            textColor: PlatformColor, headerBg: CGColor, separatorColor: CGColor,
                            context: CGContext, pageWidth: CGFloat, margin: CGFloat) {
        let rowHeight: CGFloat = 20

        if isHeader {
            context.setFillColor(headerBg)
            context.fill(CGRect(x: x, y: y, width: pageWidth - margin * 2, height: rowHeight))
        }

        context.setStrokeColor(separatorColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: x, y: y + rowHeight))
        context.addLine(to: CGPoint(x: pageWidth - margin, y: y + rowHeight))
        context.strokePath()

        let font = isHeader ? fontBold : fontReg
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]

        for (colIdx, field) in fields.enumerated() {
            let cellX = x + CGFloat(colIdx) * colWidth + 4
            let cellRect = CGRect(x: cellX, y: y + 3, width: colWidth - 8, height: rowHeight - 6)
            let text = field.trimmingCharacters(in: .whitespaces)
            (text as NSString).draw(in: cellRect, withAttributes: attrs)
        }
        y += rowHeight
    }

}
