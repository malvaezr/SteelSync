import SwiftUI
#if os(iOS)
import VisionKit
import UIKit

/// SwiftUI wrapper around `VNDocumentCameraViewController` (VisionKit's
/// document scanner — multi-page capture with auto edge detection and
/// perspective correction). Presented as a full-screen cover from the
/// Capture sheet's "Scan Document" tile.
struct DocumentScannerView: UIViewControllerRepresentable {
    let onComplete: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) { }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(_ parent: DocumentScannerView) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            var pages: [UIImage] = []
            pages.reserveCapacity(scan.pageCount)
            for i in 0..<scan.pageCount {
                pages.append(scan.imageOfPage(at: i))
            }
            parent.onComplete(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            // Common failures: camera unavailable (Simulator), permission
            // denied. Caller can react to dismissal; we surface as cancel.
            print("[DocumentScanner] failed: \(error)")
            parent.onCancel()
        }
    }
}

#endif
