import SwiftUI
#if os(iOS)
import VisionKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Photo / Scan capture sheet (Glass spec §6.5)
//
// MVP capture flow wired to the disabled "Photo / Scan" tile in CaptureSheet
// (iPadCompactRoot) and the same tile in TodayView's portrait field cockpit:
//
//   chooser → either Scan (VNDocumentCameraViewController) or
//             Choose Photo (PhotosPicker / library) →
//             result preview with ShareLink to Files / Mail / AirDrop / etc.
//
// "Attach captured pages to a project" is the eventual spec home for this,
// but that needs the project-attachment storage path to be wired through
// first. For now, capture → share is field-useful on its own (scan a
// delivery ticket on the iPad and AirDrop it to a Mac in 10 seconds).

struct CapturePhotoScanSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showScanner = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var capturedImages: [UIImage] = []
    @State private var showResult = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showScanner = true
                    } label: {
                        captureRow(
                            title: "Scan Document",
                            subtitle: "Multi-page scanner with auto edge detection",
                            icon: "doc.viewfinder.fill",
                            color: AppTheme.primaryOrange
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        // Trigger the PhotosPicker via state
                        triggerPhotoPicker = true
                    } label: {
                        captureRow(
                            title: "Choose Photo",
                            subtitle: "Pick an existing photo from your library",
                            icon: "photo.on.rectangle.angled",
                            color: Glass.info
                        )
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    Label("Captured items show a Share button to save into Files, AirDrop to a Mac, or send via Mail.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Photo / Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .photosPicker(isPresented: $triggerPhotoPicker, selection: $pickedPhoto, matching: .images)
            .onChange(of: pickedPhoto) { _, newValue in
                guard let newValue else { return }
                Task {
                    if let data = try? await newValue.loadTransferable(type: Data.self),
                       let img = UIImage(data: data) {
                        await MainActor.run {
                            capturedImages = [img]
                            pickedPhoto = nil
                            showResult = true
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScannerView(
                    onComplete: { pages in
                        capturedImages = pages
                        showScanner = false
                        showResult = true
                    },
                    onCancel: { showScanner = false }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showResult, onDismiss: { capturedImages = [] }) {
                CaptureResultView(images: capturedImages)
            }
        }
    }

    @State private var triggerPhotoPicker = false

    @ViewBuilder
    private func captureRow(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.18))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(color)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(AppTheme.tertiaryText)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

// MARK: - Result preview + share

private struct CaptureResultView: View {
    let images: [UIImage]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(images.enumerated()), id: \.offset) { idx, image in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Page \(idx + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .background(Color.black.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("\(images.count) page\(images.count == 1 ? "" : "s") captured")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    ShareLink(
                        item: pdfPayload,
                        preview: SharePreview("\(images.count) page\(images.count == 1 ? "" : "s") · SteelSync")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(images.isEmpty)
                }
            }
        }
    }

    /// Combine the captured pages into one PDF for a single, easy-to-handle
    /// artifact. Most useful for delivery tickets, receipts, etc. that get
    /// AirDropped to a desk for filing.
    private var pdfPayload: PDFSharePayload {
        PDFSharePayload(data: combinedPDFData(), filename: defaultFilename)
    }

    private var defaultFilename: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmm"
        return "SteelSync-Scan-\(f.string(from: Date())).pdf"
    }

    private func combinedPDFData() -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { ctx in
            for image in images {
                ctx.beginPage()
                let margin: CGFloat = 36
                let avail = pageRect.insetBy(dx: margin, dy: margin)
                let imgAspect = image.size.width / image.size.height
                let availAspect = avail.width / avail.height
                let drawRect: CGRect
                if imgAspect > availAspect {
                    let h = avail.width / imgAspect
                    drawRect = CGRect(x: avail.minX, y: avail.midY - h / 2, width: avail.width, height: h)
                } else {
                    let w = avail.height * imgAspect
                    drawRect = CGRect(x: avail.midX - w / 2, y: avail.minY, width: w, height: avail.height)
                }
                image.draw(in: drawRect)
            }
        }
    }
}

/// PDF share payload — one combined artifact so Files / AirDrop / Mail show
/// a single clean attachment rather than N separate images.
private struct PDFSharePayload: Transferable {
    let data: Data
    let filename: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { $0.data }
            .suggestedFileName { $0.filename }
    }
}

#endif
