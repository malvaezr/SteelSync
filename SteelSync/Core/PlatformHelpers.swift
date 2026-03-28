import SwiftUI

/// Cross-platform split view: HSplitView on macOS, HStack on iPadOS
struct PlatformSplitView<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        HSplitView {
            content()
        }
        #else
        HStack(spacing: 0) {
            content()
        }
        #endif
    }
}

/// Cross-platform helpers
struct PlatformService {
    /// Present a save panel for a file. On macOS uses NSSavePanel, on iOS uses share sheet.
    #if os(macOS)
    static func saveFile(data: Data, defaultName: String, contentType: String) {
        let panel = NSSavePanel()
        if contentType == "pdf" {
            panel.allowedContentTypes = [.pdf]
        } else {
            panel.allowedContentTypes = [.commaSeparatedText]
        }
        panel.nameFieldStringValue = defaultName
        panel.begin { result in
            if result == .OK, let url = panel.url {
                try? data.write(to: url)
            }
        }
    }
    #else
    @MainActor
    static func shareItems(_ items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first,
              let rootVC = window.rootViewController else { return }
        let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
        ac.popoverPresentationController?.sourceView = window
        ac.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
        rootVC.present(ac, animated: true)
    }
    #endif
}
