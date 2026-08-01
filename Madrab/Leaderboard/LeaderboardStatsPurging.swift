import Foundation

@MainActor
protocol LeaderboardStatsPurging {
    func removeStats(forProfileID profileID: UUID) throws
}

/// Removes a single profile's leaderboard statistics without touching
/// `processedMatchIDs` — deleting a profile must never let an old completed
/// match award points again.
@MainActor
final class LeaderboardStatsPurger: LeaderboardStatsPurging {
    private let store: LeaderboardStore

    init(store: LeaderboardStore? = nil) {
        self.store = store ?? LeaderboardStore()
    }

    func removeStats(forProfileID profileID: UUID) throws {
        var file = store.load()
        guard file.statsByProfileID[profileID] != nil else { return }
        file.statsByProfileID.removeValue(forKey: profileID)
        try store.save(file)
    }
}
