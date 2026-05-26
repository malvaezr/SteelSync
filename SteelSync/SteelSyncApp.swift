import SwiftUI

private extension Notification.Name {
    #if os(macOS)
    static let willTerminate = NSApplication.willTerminateNotification
    #else
    static let willTerminate = UIApplication.willTerminateNotification
    #endif
}

#if !STEELSYNC_IPHONE && !STEELSYNC_PHONE
@main
#endif
struct SteelSyncApp: App {
    @StateObject private var dataStore = DataStore.shared
    @StateObject private var navigationState = NavigationState()
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var notificationService = NotificationService.shared

    #if os(macOS)
    @NSApplicationDelegateAdaptor(ShareAcceptanceDelegate.self) private var shareDelegate
    #else
    @UIApplicationDelegateAdaptor(ShareAcceptanceDelegate.self) private var shareDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(dataStore)
                .environmentObject(navigationState)
                .environmentObject(themeManager)
                .tint(AppTheme.primaryOrange)
                .background {
                    // Glass revamp: the graphite/forge "wallpaper" sits at the
                    // true window root so frosted chrome (sidebar, top bar)
                    // blurs over its gradient. Legacy themes keep their flat fill.
                    if themeManager.glassEnabled {
                        GlassWallpaper()
                    } else {
                        themeManager.current.background(dark: themeManager.isDarkMode)
                    }
                }
                .preferredColorScheme(themeManager.colorScheme)
                .onReceive(NotificationCenter.default.publisher(for: .willTerminate)) { _ in
                    dataStore.persistNow()
                }
                .task {
                    notificationService.requestPermission()
                    notificationService.scheduleMorningBatch(from: dataStore)
                    // Catch up any recurring overhead expenses whose next
                    // occurrence is now past-due. Idempotent.
                    dataStore.generateRecurringOverhead()
                }
                #if os(macOS)
                .frame(minWidth: 900, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .defaultSize(width: 1400, height: 900)
        #endif
        .commands {
            // Global search — ⌘K opens the Spotlight-style search sheet.
            CommandGroup(after: .toolbar) {
                Button("Find Anything…") {
                    navigationState.showGlobalSearch = true
                }
                .keyboardShortcut("k", modifiers: [.command])
            }

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

                    Button("New RFI") {
                        navigationState.selectedSection = .rfis
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])

                    Button("New Task") {
                        navigationState.selectedSection = .todo
                    }
                    .keyboardShortcut("t", modifiers: [.command, .shift])

                    Button("New Schedule Item") {
                        navigationState.selectedSection = .schedule
                    }

                    Button("New Employee") {
                        navigationState.selectedSection = .timekeeping
                    }
                }
            }

            // Jump-to-section shortcuts, ordered to match the new sidebar IA.
            // (TODAY first, PROJECTS, OPERATIONS, PIPELINE.)
            CommandGroup(after: .sidebar) {
                Button("Today") { navigationState.selectedSection = .today }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Schedule") { navigationState.selectedSection = .schedule }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Tasks") { navigationState.selectedSection = .todo }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Active Projects") { navigationState.selectedSection = .dashboard }
                    .keyboardShortcut("4", modifiers: .command)
                Button("RFIs") { navigationState.selectedSection = .rfis }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Reports") { navigationState.selectedSection = .reports }
                    .keyboardShortcut("6", modifiers: .command)
                Button("Crew & Timesheets") { navigationState.selectedSection = .timekeeping }
                    .keyboardShortcut("7", modifiers: .command)
                Button("Equipment") { navigationState.selectedSection = .equipment }
                    .keyboardShortcut("8", modifiers: .command)
                Button("Bidding") { navigationState.selectedSection = .bidding }
                    .keyboardShortcut("9", modifiers: .command)
                Button("Clients") { navigationState.selectedSection = .clients }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
