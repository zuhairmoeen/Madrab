import SwiftUI
import MadrabScoringEngine

struct LiveMatchView: View {
    let session: MatchSessionViewModel

    var body: some View {
        VStack {
            Text(session.label(for: .teamA))
            Text(ScoreFormatting.pointText(for: .teamA, phase: session.state?.currentPhase, deuceRule: session.deuceRule))
            Button("Point for \(session.label(for: .teamA))") {
                session.recordPoint(for: .teamA)
            }

            Text(session.label(for: .teamB))
            Text(ScoreFormatting.pointText(for: .teamB, phase: session.state?.currentPhase, deuceRule: session.deuceRule))
            Button("Point for \(session.label(for: .teamB))") {
                session.recordPoint(for: .teamB)
            }

            Button("Undo") {
                session.undoLastEffectivePoint()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    session.returnToSetup()
                }
            }
        }
    }
}
