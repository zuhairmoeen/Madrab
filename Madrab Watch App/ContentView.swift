import SwiftUI
import MadrabScoringEngine
import MadrabSyncKit

/// Temporary connectivity diagnostic, not the final scoring interface.
///
/// Its only job is to make the sync foundation observable on a real screen:
/// activation, reachability, which match is live, the phone's revision, and
/// the score the phone reports. The polished layout comes in a later pass.
struct ContentView: View {
    let client: WatchSyncClient

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                statusRow("Activated", client.isActivated ? "yes" : "no")
                statusRow("Reachable", client.isReachable ? "yes" : "no")
                statusRow("Mode", client.isReadOnly ? "read-only" : "live")

                Divider()

                if let snapshot = client.latestSnapshot {
                    statusRow("Match", snapshot.matchID.map { String($0.uuidString.prefix(8)) } ?? "none")
                    statusRow("Revision", "\(snapshot.stateRevision)")
                    statusRow("Score", Self.scoreText(for: snapshot))
                    statusRow("Serving", snapshot.servingTeam.map { Self.teamName($0) } ?? "—")
                    statusRow("Winner", snapshot.matchWinner.map { Self.teamName($0) } ?? "—")
                } else {
                    Text("No snapshot yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Divider()

                if client.hasPendingCommand {
                    Text("Command pending…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let rejection = client.lastRejection {
                    Text("Rejected: \(Self.rejectionText(rejection))")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if let transportError = client.lastTransportError {
                    Text("Transport: \(transportError)")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                HStack {
                    Button("A") { client.recordPoint(for: .teamA) }
                    Button("B") { client.recordPoint(for: .teamB) }
                }
                .disabled(client.isReadOnly || client.hasPendingCommand)

                Button("Undo") { client.undo() }
                    .disabled(client.isReadOnly || client.hasPendingCommand)

                Button("Refresh") { client.requestLatestState() }
                    .disabled(client.isReadOnly)
            }
            .padding(.horizontal, 4)
        }
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.footnote.monospacedDigit())
        }
    }

    private static func teamName(_ team: Team) -> String {
        team == .teamA ? "A" : "B"
    }

    /// Renders whatever the phone says is being played. The Watch derives no
    /// scoring itself — this only formats the snapshot's own numbers.
    private static func scoreText(for snapshot: SyncSnapshot) -> String {
        guard let phase = snapshot.currentPhase else { return "—" }
        switch phase {
        case .game(let game):
            return "\(game.points.teamA) – \(game.points.teamB)"
        case .setTieBreak(let tieBreak):
            return "TB \(tieBreak.points.teamA) – \(tieBreak.points.teamB)"
        case .matchTieBreak(let tieBreak):
            return "MTB \(tieBreak.points.teamA) – \(tieBreak.points.teamB)"
        }
    }

    private static func rejectionText(_ reason: SyncRejectionReason) -> String {
        switch reason {
        case .malformedCommand: return "malformed"
        case .wrongMatch: return "wrong match"
        case .noLiveMatch: return "no live match"
        case .staleRevision: return "stale revision"
        case .matchFinished: return "match finished"
        case .invalidUndo: return "invalid undo"
        case .persistenceFailed: return "persistence failed"
        }
    }
}
