import SwiftUI
import MadrabScoringEngine

struct LiveMatchView: View {
    let session: MatchSessionViewModel

    @State private var showingDiscardConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            scoreboardHeader

            if let winner = session.state?.matchWinner {
                VStack(spacing: 8) {
                    Text("\(session.label(for: winner)) wins the match!")
                        .font(.title3.bold())
                    Button("Finish Match") {
                        session.finishMatch()
                    }
                }
                .padding(.vertical, 8)
            }

            VStack(spacing: 0) {
                Button {
                    session.recordPoint(for: .teamA)
                } label: {
                    VStack {
                        Text(session.label(for: .teamA))
                        Text(ScoreFormatting.pointText(for: .teamA, phase: session.state?.currentPhase, deuceRule: session.deuceRule))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .disabled(session.state?.matchWinner != nil)

                Divider()

                Button {
                    session.recordPoint(for: .teamB)
                } label: {
                    VStack {
                        Text(session.label(for: .teamB))
                        Text(ScoreFormatting.pointText(for: .teamB, phase: session.state?.currentPhase, deuceRule: session.deuceRule))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .disabled(session.state?.matchWinner != nil)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Discard") {
                    showingDiscardConfirmation = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Undo") {
                    session.undoLastEffectivePoint()
                }
            }
        }
        .alert("Discard Match?", isPresented: $showingDiscardConfirmation) {
            Button("Discard", role: .destructive) {
                session.returnToSetup()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current match will be lost. This cannot be undone.")
        }
    }

    private var scoreboardHeader: some View {
        VStack(spacing: 4) {
            Text(ScoreFormatting.setsScoreText(setsWon: session.state?.setsWon ?? TeamPair(both: 0)))
                .font(.headline)

            if let games = session.state?.currentSet?.games {
                Text("\(games.teamA)-\(games.teamB)")
                    .font(.subheadline)
            }

            Text("Serving: \(session.label(for: session.state?.servingTeam ?? .teamA))")
                .font(.caption)

            if let caption = ScoreFormatting.caption(phase: session.state?.currentPhase, deuceRule: session.deuceRule) {
                Text(caption)
                    .font(.caption.bold())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
