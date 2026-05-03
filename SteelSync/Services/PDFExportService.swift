import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
struct PDFExportService {
    /// Renders the Work Order Invoice to a temp file and returns the URL.
    /// Callers handle the user-facing handoff (save panel, share sheet,
    /// share button, etc.) — this used to short-circuit straight to Save
    /// or Share, which made it impossible to surface a "Share with client"
    /// affordance from a sheet.
    static func renderWorkOrderInvoiceToTempFile(changeOrder: ChangeOrder, project: Project, client: Client?) -> URL? {
        let view = WorkOrderInvoicePDFView(changeOrder: changeOrder, project: project, client: client)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        let filename = "WO_Invoice_\(changeOrder.invoiceNumber.isEmpty ? "CO\(changeOrder.number)" : changeOrder.invoiceNumber).pdf"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: tempURL)

        var produced = false
        renderer.render { size, context in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(tempURL as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            produced = true
        }
        return produced ? tempURL : nil
    }

    /// Legacy single-shot export: renders the WO invoice and immediately
    /// presents the save panel (macOS) or share sheet (iOS). Kept so
    /// existing call sites keep compiling; new code should prefer
    /// `renderWorkOrderInvoiceToTempFile` + a `PDFShareButton`.
    static func exportWorkOrderInvoice(changeOrder: ChangeOrder, project: Project, client: Client?) {
        guard let tempURL = renderWorkOrderInvoiceToTempFile(
            changeOrder: changeOrder, project: project, client: client
        ) else { return }

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = tempURL.lastPathComponent
        panel.begin { result in
            guard result == .OK, let dest = panel.url else { return }
            try? FileManager.default.removeItem(at: dest)
            try? FileManager.default.copyItem(at: tempURL, to: dest)
        }
        #else
        PlatformService.shareItems([tempURL])
        #endif
    }
}
