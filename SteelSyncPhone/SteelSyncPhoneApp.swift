import SwiftUI

@main
struct SteelSyncPhoneApp: App {
    @StateObject private var dataStore = DataStore.shared

    var body: some Scene {
        WindowGroup {
            PhoneContentView()
                .environmentObject(dataStore)
                .preferredColorScheme(.dark)
                .task {
                    WidgetDataPublisher.publish(from: dataStore)
                    NotificationService.shared.requestPermission()
                    NotificationService.shared.scheduleMorningBatch(from: dataStore)
                }
                .onChange(of: dataStore.projects.count) { _, _ in
                    WidgetDataPublisher.publish(from: dataStore)
                    NotificationService.shared.scheduleMorningBatch(from: dataStore)
                }
                .onChange(of: dataStore.todos.count) { _, _ in
                    WidgetDataPublisher.publish(from: dataStore)
                    NotificationService.shared.scheduleMorningBatch(from: dataStore)
                }
        }
    }
}
