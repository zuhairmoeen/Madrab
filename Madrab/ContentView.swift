import SwiftUI

struct ContentView: View {
    let session: MatchSessionViewModel
    let profilesViewModel: ProfilesViewModel

    var body: some View {
        Group {
            switch session.phase {
            case .setup:
                MatchSetupView(profilesViewModel: profilesViewModel) { configuration, teamAProfile, teamBProfile in
                    session.startMatch(
                        configuration: configuration,
                        teamAProfile: teamAProfile,
                        teamBProfile: teamBProfile
                    )
                }

            case .live:
                NavigationStack {
                    LiveMatchView(session: session)
                }

            case .finished(let winner):
                MatchFinishedView(session: session, winner: winner) {
                    session.returnToSetup()
                }
            }
        }
        .task {
            session.restoreIfNeeded()
        }
    }
}

#Preview {
    ContentView(session: MatchSessionViewModel(), profilesViewModel: ProfilesViewModel())
}
