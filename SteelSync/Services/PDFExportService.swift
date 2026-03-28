import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
struct PDFExportService {
    static func exportWorkOrderInvoice(changeOrder: ChangeOrder, project: Project, client: Client?) {
        let view = WorkOrderInvoicePDFView(changeOrder: changeOrder, project: project, client: client)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0

        let filename = "WO_Invoice_\(changeOrder.invoiceNumber.isEmpty ? "CO\(changeOrder.number)" : changeOrder.invoiceNumber).pdf"

        #if os(macOS)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = filename
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            renderer.render { size, context in
                var box = CGRect(origin: .zero, size: size)
                guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                pdf.beginPDFPage(nil)
                context(pdf)
                pdf.endPDFPage()
                pdf.closePDF()
            }
        }
        #else
        // On iPad: render to temp file, then share
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        renderer.render { size, context in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(tempURL as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            context(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        PlatformService.shareItems([tempURL])
        #endif
    }
}
