import SwiftUI
import MadrabScoringEngine

struct LiveMatchView: View {
    let session: MatchSessionViewModel

    @State private var showingDiscardConfirmation = false

    var body: some View {
        VStack(spacing: 12) {
            scoreboardHeader

            if let winner = session.state?.matchWinner {
                VStack(spacing: 10) {
                    Text("\(session.label(for: winner)) wins the match!")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Button {
                        session.finishMatch()
                    } label: {
                        Text("Finish Match")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .controlSize(.large)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            VStack(spacing: 12) {
                teamSection(for: .teamA, background: Color.accentColor.opacity(0.16))
                teamSection(for: .teamB, background: Color(.secondarySystemBackground))
            }
            .padding(.horizontal)
            .padding(.bottom)
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

    private func teamSection(for team: Team, background: Color) -> some View {
        Button {
            session.recordPoint(for: team)
        } label: {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    if session.state?.servingTeam == team {
                        Image(systemName: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(session.label(for: team))
                        .font(.title3.bold())
                }

                Text(ScoreFormatting.pointText(for: team, phase: session.state?.currentPhase, deuceRule: session.deuceRule))
                    .font(.system(size: 84, weight: .heavy, design: .rounded))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(session.state?.matchWinner != nil)
    }

    private var scoreboardHeader: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("SETS")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(ScoreFormatting.setsScoreText(setsWon: session.state?.setsWon ?? TeamPair(both: 0)))
                    .font(.title3.bold())
            }

            if let games = session.state?.currentSet?.games {
                Text("\(games.teamA)-\(games.teamB)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
            }

            if let caption = ScoreFormatting.caption(phase: session.state?.currentPhase, deuceRule: session.deuceRule) {
                Text(caption)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.16))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}
