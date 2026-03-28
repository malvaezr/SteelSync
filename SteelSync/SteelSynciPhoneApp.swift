#if STEELSYNC_IPHONE
import SwiftUI

@main
struct SteelSynciPhoneApp: App {
    @StateObject private var dataStore = DataStore()

    var body: some Scene {
        WindowGroup {
            IPhoneRootView()
                .environmentObject(dataStore)
        }
    }
}
#endif
