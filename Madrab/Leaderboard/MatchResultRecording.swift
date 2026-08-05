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

    /// Dependencies default to `nil` rather than to concrete instances
    /// because a default-argument expression is evaluated in a nonisolated
    /// context, where referencing these main-actor-isolated values would
    /// warn. Resolving them inside this `@MainActor` body is equivalent for
    /// every caller, including tests that inject a temporary store.
    init(store: LeaderboardStore? = nil, formula: PointsFormula? = nil) {
        self.store = store ?? LeaderboardStore()
        self.formula = formula ?? .default
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
