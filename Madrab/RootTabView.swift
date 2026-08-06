import SwiftUI

struct RootTabView: View {
    @State private var environment: AppEnvironment

    init(environment: AppEnvironment? = nil) {
        _environment = State(initialValue: environment ?? AppEnvironment())
    }

    var body: some View {
        TabView {
            ContentView(session: environment.session, profilesViewModel: environment.profilesViewModel)
                .tabItem {
                    Label("Match", systemImage: "sportscourt")
                }

            ProfilesView(viewModel: environment.profilesViewModel)
                .tabItem {
                    Label("Profiles", systemImage: "person.2")
                }

            LeaderboardView(viewModel: environment.leaderboardViewModel)
                .tabItem {
                    Label("Leaderboard", systemImage: "trophy")
                }
        }
        .tint(.accentColor)
        // Activated once for the app's lifetime. Deliberately here rather than
        // in the Match tab: the phone must answer the Watch regardless of
        // which tab is on screen. `activate()` is idempotent, so a repeated
        // `.task` is harmless.
        .task { environment.phoneSyncService.activate() }
    }
}
