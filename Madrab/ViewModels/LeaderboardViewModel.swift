import Foundation
import Observation

@MainActor
@Observable
final class LeaderboardViewModel {
    private(set) var entries: [LeaderboardEntry] = []
    private(set) var lastError: (any Error)?

    var isEmpty: Bool { entries.isEmpty }

    private let leaderboardStore: LeaderboardStore
    private let profileStore: ProfileStore

    init(leaderboardStore: LeaderboardStore? = nil, profileStore: ProfileStore? = nil) {
        self.leaderboardStore = leaderboardStore ?? LeaderboardStore()
        self.profileStore = profileStore ?? ProfileStore()
        reload()
    }

    /// Re-reads both persisted files and recomputes the ranked entries in
    /// one pass, so partial/stale state is never assigned. `LeaderboardStore`
    /// and `ProfileStore` already normalize missing/corrupt/unsupported-
    /// version data to an empty default rather than throwing, so that is the
    /// "safe state" this produces today; `lastError` exists so a future
    /// failure mode has somewhere clear to surface instead of being hidden
    /// behind stale-looking entries.
    func reload() {
        lastError = nil
        let leaderboardFile = leaderboardStore.load()
        let profilesFile = profileStore.load()
        entries = rankedEntries(
            statsByProfileID: leaderboardFile.statsByProfileID,
            profiles: profilesFile.profiles
        )
    }
}
