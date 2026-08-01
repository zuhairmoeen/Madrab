import SwiftUI

struct ContentView: View {
    @State private var session = MatchSessionViewModel()

    var body: some View {
        switch session.phase {
        case .setup:
            MatchSetupView { configuration, teamALabel, teamBLabel in
                session.startMatch(
                    configuration: configuration,
                    teamALabel: teamALabel,
                    teamBLabel: teamBLabel
                )
            }

        case .live:
            NavigationStack {
                LiveMatchView(session: session)
            }
        }
    }
}

#Preview {
    ContentView()
}
