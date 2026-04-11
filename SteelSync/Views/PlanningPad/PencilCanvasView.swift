#if os(iOS)
import SwiftUI
import PencilKit

/// UIViewRepresentable wrapping PKCanvasView for Apple Pencil drawing.
struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var isToolPickerVisible: Bool

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.tool = PKInkingTool(.pen, color: .white, width: 3)
        canvas.overrideUserInterfaceStyle = .dark

        // Set up tool picker
        let toolPicker = PKToolPicker()
        context.coordinator.toolPicker = toolPicker
        toolPicker.setVisible(isToolPickerVisible, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        canvas.becomeFirstResponder()

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
        if let toolPicker = context.coordinator.toolPicker {
            toolPicker.setVisible(isToolPickerVisible, forFirstResponder: canvas)
            if isToolPickerVisible { canvas.becomeFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasView
        var toolPicker: PKToolPicker?

        init(_ parent: PencilCanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}
#endif
