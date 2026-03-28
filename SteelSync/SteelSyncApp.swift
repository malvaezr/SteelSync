import SwiftUI

#if !STEELSYNC_IPHONE && !STEELSYNC_PHONE
@main
#endif
struct SteelSyncApp: App {
    @StateObject private var dataStore = DataStore()
    @StateObject private var navigationState = NavigationState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStore)
                .environmentObject(navigationState)
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1400, height: 900)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Menu("New") {
                    Button("New Project") {
                        navigationState.selectedSection = .dashboard
                    }
                    .keyboardShortcut("n", modifiers: [.command])

                    Button("New Client") {
                        navigationState.selectedSection = .clients
                    }
                    .keyboardShortcut("k", modifiers: [.command, .shift])

                    Button("New Bid") {
                        navigationState.selectedSection = .bidding
                    }
                    .keyboardShortcut("b", modifiers: [.command, .shift])

                    Button("New Employee") {
                        navigationState.selectedSection = .timekeeping
                    }

                    Button("New Todo") {
                        navigationState.selectedSection = .todo
                    }
                    .keyboardShortcut("t", modifiers: [.command, .shift])

                    Button("New Task (Gantt)") {
                        navigationState.selectedSection = .schedule
                    }
                }
            }

            CommandGroup(after: .sidebar) {
                Button("Dashboard") { navigationState.selectedSection = .dashboard }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Clients") { navigationState.selectedSection = .clients }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Bidding") { navigationState.selectedSection = .bidding }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Timekeeping") { navigationState.selectedSection = .timekeeping }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Schedule") { navigationState.selectedSection = .schedule }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Equipment") { navigationState.selectedSection = .equipment }
                    .keyboardShortcut("6", modifiers: .command)
                Button("To-Do") { navigationState.selectedSection = .todo }
                    .keyboardShortcut("7", modifiers: .command)
                Button("Reports") { navigationState.selectedSection = .reports }
                    .keyboardShortcut("8", modifiers: .command)
                Button("Activity") { navigationState.selectedSection = .activity }
                    .keyboardShortcut("9", modifiers: .command)
            }
        }
    }
}
