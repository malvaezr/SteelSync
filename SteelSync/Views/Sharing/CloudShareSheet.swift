import SwiftUI
import CloudKit

#if os(macOS)
import AppKit

/// macOS share sheet. Apple's NSSharingServicePicker has rough edges with
/// CKShare presentation, so we show the URL + copy + ShareLink directly —
/// participants only need the link to accept.
struct CloudShareSheet: View {
    let share: CKShare
    let container: CKContainer
    let onDismiss: () -> Void

    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundColor(AppTheme.primaryOrange)
                Text("Share SteelSync Data")
                    .font(.title2.bold())
                Spacer()
            }

            Text("Anyone with this link can join your SteelSync zone using their own iCloud account. They'll see all projects, bids, and financial data.")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let url = share.url {
                GroupBox {
                    HStack {
                        Text(url.absoluteString)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                HStack(spacing: 12) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        didCopy = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
                    } label: {
                        Label(didCopy ? "Copied!" : "Copy Link",
                              systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    }

                    ShareLink(item: url) {
                        Label("Send Invitation…", systemImage: "square.and.arrow.up")
                    }

                    Spacer()
                }
            } else {
                ProgressView("Generating link…")
                    .frame(maxWidth: .infinity)
            }

            Divider()

            HStack {
                Spacer()
                Button("Done") { onDismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

#else
import UIKit

/// iOS / iPadOS share sheet. UICloudSharingController handles the entire
/// invite + permission management flow: invite via Messages/Mail, see
/// current participants, change read/write permission, revoke access.
struct CloudShareSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowReadOnly, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("[CloudKit] Share save failed: \(error.localizedDescription)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "SteelSync Data"
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onDismiss()
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            // Share saved successfully; nothing to do — the controller
            // dismisses itself.
        }
    }
}
#endif
