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
    // Fires only when the app is already running on some iOS versions; for
    // scene-based SwiftUI apps the cold-launch path goes through the scene
    // delegate below instead. Kept as a belt-and-suspenders path.
    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        print("🔗 [Share] APP-delegate userDidAcceptCloudKitShareWith fired (owner zone: \(metadata.share.recordID.zoneID.ownerName))")
        Task { @MainActor in
            await DataStore.shared.acceptShare(metadata: metadata)
        }
    }

    // Route scene connections to ShareSceneDelegate so the CloudKit share
    // metadata is captured on cold launch (`connectionOptions`) and while
    // running. SwiftUI continues to host the WindowGroup — the scene delegate
    // below deliberately does NOT create a window.
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if options.cloudKitShareMetadata != nil {
            print("🔗 [Share] configurationForConnecting carries cloudKitShareMetadata (cold launch)")
        }
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = ShareSceneDelegate.self
        return config
    }
}

/// Captures CloudKit share acceptance in the scene lifecycle. Handles cold
/// launch (metadata in `connectionOptions`) and the running case
/// (`windowScene(_:userDidAcceptCloudKitShareWith:)`). It does not manage a
/// window, so SwiftUI's `WindowGroup` still renders the UI.
final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let metadata = connectionOptions.cloudKitShareMetadata else { return }
        print("🔗 [Share] SCENE willConnectTo: cold-launch share (owner zone: \(metadata.share.recordID.zoneID.ownerName))")
        Task { @MainActor in
            await DataStore.shared.acceptShare(metadata: metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        print("🔗 [Share] SCENE userDidAcceptCloudKitShareWith fired (owner zone: \(cloudKitShareMetadata.share.recordID.zoneID.ownerName))")
        Task { @MainActor in
            await DataStore.shared.acceptShare(metadata: cloudKitShareMetadata)
        }
    }
}
#endif
