import SwiftUI
import UniformTypeIdentifiers

/// Generic id-based drag-to-reorder drop delegate for custom (non-List) row
/// layouts. The dragged row sets `draggingID`; while it hovers a different
/// row, `onReorder(from, to)` moves it. `performDrop` clears state and runs
/// `onDropped` (e.g. persist).
struct RowReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingID: UUID?
    let onReorder: (_ from: UUID, _ to: UUID) -> Void
    var onDropped: () -> Void = {}

    func dropEntered(info: DropInfo) {
        guard let from = draggingID, from != targetID else { return }
        onReorder(from, targetID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        onDropped()
        return true
    }
}
