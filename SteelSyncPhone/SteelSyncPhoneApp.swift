import SwiftUI

@main
struct SteelSyncPhoneApp: App {
    @StateObject private var dataStore = DataStore.shared

    var body: some Scene {
        WindowGroup {
            PhoneContentView()
                .environmentObject(dataStore)
                .preferredColorScheme(.dark)
        }
    }
}
