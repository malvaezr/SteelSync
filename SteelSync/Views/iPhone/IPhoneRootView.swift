#if STEELSYNC_IPHONE
import SwiftUI

struct IPhoneRootView: View {
    @EnvironmentObject var dataStore: DataStore

    var body: some View {
        TabView {
            IPhoneProjectsTab()
                .tabItem {
                    Label("Projects", systemImage: "building.2.fill")
                }

            IPhoneBidsTab()
                .tabItem {
                    Label("Bids", systemImage: "doc.text.fill")
                }

            IPhoneTodoTab()
                .tabItem {
                    Label("To-Do", systemImage: "checklist")
                }

            IPhoneCrewTab()
                .tabItem {
                    Label("Crew", systemImage: "person.2.fill")
                }

            IPhoneMoreTab()
                .tabItem {
                    Label("More", systemImage: "ellipsis.circle.fill")
                }
        }
        .accentColor(AppTheme.primaryOrange)
        .onAppear {
            Task {
                await dataStore.pullFromCloud()
            }
        }
    }
}
#endif
