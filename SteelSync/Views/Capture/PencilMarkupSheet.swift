import SwiftUI
#if os(iOS)
import PencilKit
import UIKit

// MARK: - Pencil Markup Sheet (Glass spec §6.4)
//
// Standalone PKCanvasView surface for Apple Pencil markup. Wired to the
// previously-disabled "Pencil Markup" tile in CaptureSheet + the same tile
// in portrait Today.
//
// MVP scope: blank canvas → draw → render to image → Share / save to Files.
// The full spec wants markup OVER an existing document (RFI / drawing /
// photo viewer), but the app has no in-place document viewer yet, so this
// ships as a standalone whiteboard for redlines / quick sketches. When a
// viewer comes online, swap the blank `Color.white` background for the
// document image and the rest of this flow stays unchanged.

struct PencilMarkupSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var drawing = PKDrawing()
    @State private var canvasSize: CGSize = .zero
    @State private var showResult = false
    @State private var resultImage: UIImage?
    @State private var isToolPickerVisible = true

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    Color.white  // future: swap for the document being annotated
                        .ignoresSafeArea(edges: .bottom)
                    // Reuses the existing PlanningPad PencilCanvasView, which
                    // already wires up PKToolPicker for full pen / marker /
                    // color controls.
                    PencilCanvasView(drawing: $drawing, isToolPickerVisible: $isToolPickerVisible)
                        .background(Color.clear)
                        .ignoresSafeArea(edges: .bottom)
                }
                .onAppear { canvasSize = proxy.size }
                .onChange(of: proxy.size) { _, newValue in canvasSize = newValue }
            }
            .navigationTitle("Pencil Markup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        drawing = PKDrawing()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(drawing.strokes.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        resultImage = renderImage(in: canvasSize)
                        showResult = (resultImage != nil)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(drawing.strokes.isEmpty)
                }
            }
            .sheet(isPresented: $showResult, onDismiss: { resultImage = nil }) {
                if let img = resultImage {
                    MarkupResultView(image: img)
                }
            }
        }
    }

    /// Render the current `PKDrawing` into a UIImage at the canvas size so
    /// the share sheet has a fully composed page to export, not just the
    /// bounding rect of the strokes.
    private func renderImage(in size: CGSize) -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let rect = CGRect(origin: .zero, size: size)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(rect)
            let strokeImage = drawing.image(from: rect, scale: UIScreen.main.scale)
            strokeImage.draw(in: rect)
        }
    }
}

// (PencilCanvasView lives in Views/PlanningPad/PencilCanvasView.swift —
// we reuse it instead of re-declaring; the PlanningPad one already wires
// the system PKToolPicker for full pen/marker/eraser/color controls.)

// MARK: - Result preview + share

private struct MarkupResultView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Markup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(item: MarkupSharePayload(image),
                              preview: SharePreview("Markup", image: Image(uiImage: image))) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}

private struct MarkupSharePayload: Transferable {
    let image: UIImage
    init(_ image: UIImage) { self.image = image }
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { payload in
            payload.image.pngData() ?? Data()
        }
    }
}

#endif
