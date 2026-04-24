import SwiftUI
import UniformTypeIdentifiers

/// Adds drag-and-drop support for files (images + PDFs) to any view.
/// Dropped files are imported via `FileStorageService.importFile` and handed back
/// as `Attachment` records, so callers don't need to know about URLs, security
/// scopes, or file copying — just set up the `onImport` handler.
///
/// Visual feedback: an orange outline pulses while a file is hovering over the
/// target. An overlay hint can be injected via `showHint: true`.
///
/// Usage:
///   someView.fileDrop(folderID: "payment-\(uuid)") { attachment in
///       attachments.append(attachment)
///   }
struct FileDropModifier: ViewModifier {
    let folderID: String
    let showHint: Bool
    let onImport: (Attachment) -> Void

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .center) {
                if isTargeted && showHint {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppTheme.primaryOrange.opacity(0.08))
                        .overlay(
                            VStack(spacing: 6) {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.title2)
                                Text("Drop to attach")
                                    .font(.callout)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(AppTheme.primaryOrange)
                        )
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isTargeted ? AppTheme.primaryOrange : Color.clear, lineWidth: 2)
                    .animation(.easeInOut(duration: 0.15), value: isTargeted)
                    .allowsHitTesting(false)
            )
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers)
            }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var acceptedAny = false
        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                continue
            }
            acceptedAny = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var resolved: URL?
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    resolved = url
                } else if let url = item as? URL {
                    resolved = url
                }
                guard let url = resolved else { return }

                // Filter to supported types up front. onDrop registered
                // .fileURL broadly; we still reject non-image/PDF drops so
                // payment proofs stay clean.
                let ext = url.pathExtension.lowercased()
                let allowed = ["png", "jpg", "jpeg", "heic", "gif", "pdf"]
                guard allowed.contains(ext) else { return }

                DispatchQueue.main.async {
                    switch FileStorageService.importFile(from: url, bidID: folderID) {
                    case .success(let attachment):
                        onImport(attachment)
                    case .failure:
                        break
                    }
                }
            }
        }
        return acceptedAny
    }
}

extension View {
    /// Adds file drag-and-drop support to this view. Dropped images/PDFs are
    /// imported through `FileStorageService` into a folder keyed by `folderID`
    /// and passed to `onImport` as ready-to-use Attachments.
    ///
    /// - Parameters:
    ///   - folderID: Storage folder identifier (usually the parent record's UUID).
    ///   - showHint: Whether to show an "Drop to attach" overlay while targeted.
    ///   - onImport: Called on the main thread for each successful import.
    func fileDrop(
        folderID: String,
        showHint: Bool = true,
        onImport: @escaping (Attachment) -> Void
    ) -> some View {
        modifier(FileDropModifier(folderID: folderID, showHint: showHint, onImport: onImport))
    }
}
