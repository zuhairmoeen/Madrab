import SwiftUI
import MadrabScoringEngine

struct MatchFinishedView: View {
    let session: MatchSessionViewModel
    let winner: Team
    let onNewMatch: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("\(session.label(for: winner)) wins!")
                .font(.largeTitle.bold())

            Button("New Match") {
                onNewMatch()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
