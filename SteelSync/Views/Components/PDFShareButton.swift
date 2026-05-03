import SwiftUI

/// Cross-platform "Send to client" button that wraps SwiftUI's `ShareLink`.
/// Targets the system share sheet — Mail.app, Messages, AirDrop, etc. —
/// with subject and a short message body pre-filled so the user just
/// adds a recipient (or it's already filled in if they pick Mail and
/// have the contact known).
///
/// Use anywhere a generated PDF URL is on hand.
struct PDFShareButton: View {
    let url: URL
    let subject: String
    let message: String
    var label: String = "Share PDF"
    var systemImage: String = "square.and.arrow.up"
    var style: Style = .secondary

    enum Style {
        case primary
        case secondary
        case outline
    }

    var body: some View {
        ShareLink(
            item: url,
            subject: Text(subject),
            message: Text(message)
        ) {
            Label(label, systemImage: systemImage)
        }
        .modifier(PDFShareStyleModifier(style: style))
    }
}

private struct PDFShareStyleModifier: ViewModifier {
    let style: PDFShareButton.Style

    func body(content: Content) -> some View {
        switch style {
        case .primary:
            content.buttonStyle(.appPrimary)
        case .secondary:
            content.buttonStyle(.appSecondary)
        case .outline:
            content.buttonStyle(.appOutline)
        }
    }
}

// MARK: - Convenience builders for common SteelSync entities

extension PDFShareButton {
    /// Subject + body for change-order / work-order invoices.
    static func workOrderInvoice(url: URL, changeOrder: ChangeOrder, project: Project, client: Client?) -> PDFShareButton {
        let subject = "Work Order Invoice — \(project.title) — CO #\(changeOrder.number)"
        var lines: [String] = []
        if let name = client?.contactName, !name.isEmpty {
            lines.append("Hi \(name),")
        } else {
            lines.append("Hi,")
        }
        lines.append("")
        lines.append("Attached is the work order invoice for \(project.title) — Change Order #\(changeOrder.number) (\(changeOrder.amount.currencyFormatted)).")
        if !changeOrder.description.isEmpty {
            lines.append("Scope: \(changeOrder.description)")
        }
        lines.append("")
        lines.append("Please let me know if you have any questions.")
        lines.append("")
        lines.append("— Ruben")
        return PDFShareButton(url: url, subject: subject, message: lines.joined(separator: "\n"))
    }

    /// Subject + body for Pay Application exports.
    static func payApp(url: URL, payApp: PayApplication, project: Project, client: Client?) -> PDFShareButton {
        let subject = "Pay Application #\(payApp.applicationNumber) — \(project.title)"
        var lines: [String] = []
        if let name = client?.contactName, !name.isEmpty {
            lines.append("Hi \(name),")
        } else {
            lines.append("Hi,")
        }
        lines.append("")
        lines.append("Attached is Pay Application #\(payApp.applicationNumber) for \(project.title).")
        lines.append("Net amount this period: \(payApp.netAmountThisPeriod.currencyFormatted).")
        lines.append("Period ending: \(payApp.periodTo.shortDate).")
        lines.append("")
        lines.append("Please review and let me know if anything needs adjusting.")
        lines.append("")
        lines.append("— Ruben")
        return PDFShareButton(url: url, subject: subject, message: lines.joined(separator: "\n"))
    }

    /// Subject + body for the Gantt schedule export.
    static func ganttSchedule(url: URL, projectTitles: [String], dateRange: ClosedRange<Date>) -> PDFShareButton {
        let projectsLabel: String
        switch projectTitles.count {
        case 0: projectsLabel = "Schedule"
        case 1: projectsLabel = projectTitles[0]
        default: projectsLabel = "\(projectTitles.count) projects"
        }
        let subject = "\(projectsLabel) — Schedule"
        let f = DateFormatter()
        f.dateStyle = .medium
        let body = "Schedule for \(projectsLabel)\n\nWindow: \(f.string(from: dateRange.lowerBound)) → \(f.string(from: dateRange.upperBound))\n\nPDF attached.\n\n— Ruben"
        return PDFShareButton(url: url, subject: subject, message: body)
    }
}
