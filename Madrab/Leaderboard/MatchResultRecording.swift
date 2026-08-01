import Foundation

@MainActor
protocol MatchResultRecording {
    func recordCompletedMatch(matchID: UUID, winnerProfileID: UUID, loserProfileID: UUID) throws
}

/// Serializes the read-modify-write of leaderboard data on the main actor.
/// Because this method contains no suspension point, two calls can never
/// interleave their load/apply/save steps, which keeps `recordCompletedMatch`
/// safe to call from any main-actor context without an explicit lock.
@MainActor
final class MatchResultRecorder: MatchResultRecording {
    private let store: LeaderboardStore
    private let formula: PointsFormula

    init(store: LeaderboardStore = LeaderboardStore(), formula: PointsFormula = .default) {
        self.store = store
        self.formula = formula
    }

    func recordCompletedMatch(matchID: UUID, winnerProfileID: UUID, loserProfileID: UUID) throws {
        var file = store.load()
        guard !file.processedMatchIDs.contains(matchID) else { return }

        applyMatchResult(
            winnerID: winnerProfileID,
            loserID: loserProfileID,
            formula: formula,
            to: &file.statsByProfileID
        )
        file.processedMatchIDs.insert(matchID)

        try store.save(file)
    }
}
