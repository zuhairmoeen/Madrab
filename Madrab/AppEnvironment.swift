import Foundation

/// The app's single composition root: constructs each persistence store and
/// the shared leaderboard-writing services exactly once, then wires the
/// three screen-level view models to those same instances so Match,
/// Profiles, and Leaderboard never observe divergent state.
@MainActor
final class AppEnvironment {
    let matchStore: MatchStore
    let profileStore: ProfileStore
    let leaderboardStore: LeaderboardStore
    let resultRecorder: MatchResultRecording
    let statsPurger: LeaderboardStatsPurging

    let session: MatchSessionViewModel
    let profilesViewModel: ProfilesViewModel
    let leaderboardViewModel: LeaderboardViewModel

    init(
        matchStore: MatchStore? = nil,
        profileStore: ProfileStore? = nil,
        leaderboardStore: LeaderboardStore? = nil
    ) {
        let resolvedMatchStore = matchStore ?? MatchStore()
        let resolvedProfileStore = profileStore ?? ProfileStore()
        let resolvedLeaderboardStore = leaderboardStore ?? LeaderboardStore()

        self.matchStore = resolvedMatchStore
        self.profileStore = resolvedProfileStore
        self.leaderboardStore = resolvedLeaderboardStore

        let recorder = MatchResultRecorder(store: resolvedLeaderboardStore)
        let purger = LeaderboardStatsPurger(store: resolvedLeaderboardStore)
        self.resultRecorder = recorder
        self.statsPurger = purger

        self.session = MatchSessionViewModel(store: resolvedMatchStore, resultRecorder: recorder)
        self.profilesViewModel = ProfilesViewModel(
            store: resolvedProfileStore,
            activeMatchStore: resolvedMatchStore,
            statsPurger: purger
        )
        self.leaderboardViewModel = LeaderboardViewModel(
            leaderboardStore: resolvedLeaderboardStore,
            profileStore: resolvedProfileStore
        )
    }
}
