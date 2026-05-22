import Foundation
import CloudKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Platform app-delegate adaptor whose only job is to receive CloudKit
/// share-acceptance callbacks from the OS and route the metadata to
/// `DataStore.shared.acceptShare(metadata:)`.
///
/// When a user taps a SteelSync share URL (sent via the owner's
/// `CloudShareSheet`), the OS launches or foregrounds the app and calls the
/// delegate method below with the parsed `CKShare.Metadata`. We dispatch
/// onto the main actor because `DataStore` is `@MainActor`-isolated.
#if os(macOS)
final class ShareAcceptanceDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in
            await DataStore.shared.acceptShare(metadata: metadata)
        }
    }
}
#else
final class ShareAcceptanceDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { @MainActor in
            await DataStore.shared.acceptShare(metadata: metadata)
        }
    }
}
#endif
