#if os(iOS)
import Foundation
import PencilKit
import Vision
import UIKit

/// Converts PencilKit drawings to text using Apple Vision framework (on-device OCR).
enum HandwritingRecognitionService {

    /// Recognizes handwritten text from a PKDrawing.
    /// Pipeline: PKDrawing -> create dark-stroke copy -> render on white background -> VNRecognizeTextRequest -> text
    static func recognizeText(from drawing: PKDrawing) async -> String {
        guard !drawing.strokes.isEmpty else { return "" }

        let bounds = drawing.bounds
        guard bounds.width > 0, bounds.height > 0 else { return "" }

        // Add padding around the drawing, clamp to prevent OOM
        let padding: CGFloat = 40
        let maxDimension: CGFloat = 4096
        let renderBounds = CGRect(
            x: bounds.origin.x - padding,
            y: bounds.origin.y - padding,
            width: min(bounds.width + padding * 2, maxDimension),
            height: min(bounds.height + padding * 2, maxDimension)
        )
        let scale: CGFloat = 3.0 // High resolution for OCR accuracy

        // Render the drawing as-is, then invert colors for OCR
        // Vision works best with dark text on white background
        let rawImage = drawing.image(from: renderBounds, scale: scale)

        // Invert: white strokes on transparent -> dark strokes on white
        guard let ciInput = CIImage(image: rawImage) else { return "" }
        let inverted = ciInput.applyingFilter("CIColorInvert")
        // Composite onto white so transparent areas become white
        let white = CIImage(color: CIColor.white).cropped(to: inverted.extent)
        let composited = inverted.composited(over: white)
        let ciCtx = CIContext()
        guard let cgImage = ciCtx.createCGImage(composited, from: composited.extent) else { return "" }

        // Run Vision text recognition
        // Use a boolean flag to guarantee single resume of the continuation
        return await withCheckedContinuation { continuation in
            var hasResumed = false
            let resumeOnce: (String) -> Void = { result in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(returning: result)
            }

            let request = VNRecognizeTextRequest { request, error in
                guard error == nil,
                      let observations = request.results as? [VNRecognizedTextObservation] else {
                    resumeOnce("")
                    return
                }

                // Collect the top candidate from each observation, sorted top-to-bottom
                let sorted = observations.sorted { $0.boundingBox.origin.y > $1.boundingBox.origin.y }
                let lines = sorted.compactMap { observation -> String? in
                    observation.topCandidates(1).first?.string
                }

                resumeOnce(lines.joined(separator: "\n"))
            }

            // Configure for handwriting recognition
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                resumeOnce("")
            }
        }
    }
}
#endif
