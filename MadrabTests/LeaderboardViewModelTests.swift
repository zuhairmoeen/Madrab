import Testing
import Foundation
@testable import Madrab

@MainActor
struct LeaderboardViewModelTests {
    private func makeTemporaryFileURL(name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
    }

    private func makeStores() -> (leaderboard: LeaderboardStore, profiles: ProfileStore) {
        (
            LeaderboardStore(fileURL: makeTemporaryFileURL(name: "leaderboard.json")),
            ProfileStore(fileURL: makeTemporaryFileURL(name: "profiles.json"))
        )
    }

    // MARK: - Initial load / empty state

    @Test func initialLoadPopulatesEntriesFromStores() throws {
        let (leaderboardStore, profileStore) = makeStores()
        let profile = PlayerProfile(displayName: "Alex")
        try profileStore.save(ProfilesFile(profiles: [profile]))
        try leaderboardStore.save(LeaderboardFile(
            statsByProfileID: [profile.id: PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1)]
        ))

        let viewModel = LeaderboardViewModel(leaderboardStore: leaderboardStore, profileStore: profileStore)

        #expect(viewModel.entries.count == 1)
        #expect(viewModel.entries.first?.displayName == "Alex")
        #expect(viewModel.entries.first?.rank == 1)
    }

    @Test func emptyStateWhenNoDataExists() {
        let (leaderboardStore, profileStore) = makeStores()

        let viewModel = LeaderboardViewModel(leaderboardStore: leaderboardStore, profileStore: profileStore)

        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.isEmpty)
        #expect(viewModel.lastError == nil)
    }

    // MARK: - Ranking / tie-breaks (integration through the view model)

    @Test func rankingAppliesFullDeterministicTieBreakChain() throws {
        let (leaderboardStore, profileStore) = makeStores()

        let p1 = PlayerProfile(displayName: "P1")
        let p2 = PlayerProfile(displayName: "P2")
        let p3 = PlayerProfile(displayName: "P3")
        let p4 = PlayerProfile(displayName: "P4")
        let p5 = PlayerProfile(displayName: "P5")
        let p6Zoe = PlayerProfile(displayName: "Zoe")
        let p7Amy = PlayerProfile(displayName: "Amy")
        let lowID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let highID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let p8Low = PlayerProfile(id: lowID, displayName: "Sam")
        let p9High = PlayerProfile(id: highID, displayName: "Sam")

        try profileStore.save(ProfilesFile(profiles: [p1, p2, p3, p4, p5, p6Zoe, p7Amy, p8Low, p9High]))

        try leaderboardStore.save(LeaderboardFile(statsByProfileID: [
            p1.id: PlayerStats(totalPoints: 10, matchesPlayed: 1, wins: 1, losses: 0),
            p2.id: PlayerStats(totalPoints: 5, matchesPlayed: 1, wins: 3, losses: 0),
            p3.id: PlayerStats(totalPoints: 5, matchesPlayed: 1, wins: 1, losses: 0),
            p4.id: PlayerStats(totalPoints: 3, matchesPlayed: 5, wins: 2, losses: 0),
            p5.id: PlayerStats(totalPoints: 3, matchesPlayed: 2, wins: 2, losses: 0),
            p6Zoe.id: PlayerStats(totalPoints: 1, matchesPlayed: 1, wins: 0, losses: 1),
            p7Amy.id: PlayerStats(totalPoints: 1, matchesPlayed: 1, wins: 0, losses: 1),
            p8Low.id: PlayerStats(totalPoints: 0, matchesPlayed: 0, wins: 0, losses: 0),
            p9High.id: PlayerStats(totalPoints: 0, matchesPlayed: 0, wins: 0, losses: 0)
        ]))

        let viewModel = LeaderboardViewModel(leaderboardStore: leaderboardStore, profileStore: profileStore)

        let expectedOrder = [p1.id, p2.id, p3.id, p4.id, p5.id, p7Amy.id, p6Zoe.id, p8Low.id, p9High.id]
        #expect(viewModel.entries.map(\.profileID) == expectedOrder)
        #expect(viewModel.entries.map(\.rank) == Array(1...9))
    }

    // MARK: - Profile integration

    @Test func orphanedStatsAreIgnored() throws {
        let (leaderboardStore, profileStore) = makeStores()
        try leaderboardStore.save(LeaderboardFile(statsByProfileID: [UUID(): PlayerStats(totalPoints: 100)]))
        try profileStore.save(ProfilesFile(profiles: []))

        let viewModel = LeaderboardViewModel(leaderboardStore: leaderboardStore, profileStore: profileStore)

        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.isEmpty)
    }

    @Test func profilesWithoutStatsAreExcluded() throws {
        let (leaderboardStore, profileStore) = makeStores()
        try profileStore.save(ProfilesFile(profiles: [PlayerProfile(displayName: "Alex")]))

        let viewModel = LeaderboardViewModel(leaderboardStore: leaderboardStore, profileStore: profileStore)

        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.isEmpty)
    }

    @Test func reloadReflectsProfileRenameWithoutChangingStats() throws {
        let (leaderboardStore, profileStore) = makeStores()
        let profile = PlayerProfile(displayName: "Alex")
        try profileStore.save(ProfilesFile(profiles: [profile]))
        let stats = PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1)
        try leaderboardStore.save(LeaderboardFile(statsByProfileID: [profile.id: stats]))

        let viewModel = LeaderboardViewModel(leaderboardStore: leaderboardStore, profileStore: profileStore)
        #expect(viewModel.entries.first?.displayName == "Alex")

        try profileStore.save(ProfilesFile(profiles: [
            PlayerProfile(id: profile.id, displayName: "Alexandra")
        ]))
        viewModel.reload()

        #expect(viewModel.entries.first?.displayName == "Alexandra")
        #expect(viewModel.entries.first?.stats == stats)
    }

    @Test func avatarDataPropagatesIntoEntries() throws {
        let (leaderboardStore, profileStore) = makeStores()
        let avatarData = Data([1, 2, 3, 4])
        let profile = PlayerProfile(displayName: "Alex", avatarImageData: avatarData)
        try profileStore.save(ProfilesFile(profiles: [profile]))
        try leaderboardStore.save(LeaderboardFile(
            statsByProfileID: [profile.id: PlayerStats(totalPoints: 1, matchesPlayed: 1, wins: 1)]
        ))

        let viewModel = LeaderboardViewModel(leaderboardStore: leaderboardStore, profileStore: profileStore)

        #expect(viewModel.entries.first?.avatarImageData == avatarData)
    }

    // MARK: - reload()

    @Test func explicitReloadPicksUpNewlySavedData() throws {
        let (leaderboardStore, profileStore) = makeStores()
        let viewModel = LeaderboardViewModel(leaderboardStore: leaderboardStore, profileStore: profileStore)
        #expect(viewModel.isEmpty)

        let profile = PlayerProfile(displayName: "Alex")
        try profileStore.save(ProfilesFile(profiles: [profile]))
        try leaderboardStore.save(LeaderboardFile(
            statsByProfileID: [profile.id: PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1)]
        ))

        viewModel.reload()

        #expect(!viewModel.isEmpty)
        #expect(viewModel.entries.first?.profileID == profile.id)
    }

    // MARK: - Error / safe-state behavior

    @Test func corruptLeaderboardFileProducesEmptyStateNotError() throws {
        let fileURL = makeTemporaryFileURL(name: "leaderboard.json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        let viewModel = LeaderboardViewModel(
            leaderboardStore: LeaderboardStore(fileURL: fileURL),
            profileStore: ProfileStore(fileURL: makeTemporaryFileURL(name: "profiles.json"))
        )

        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.isEmpty)
        #expect(viewModel.lastError == nil)
    }

    @Test func unsupportedSchemaVersionProducesEmptyStateNotError() throws {
        let fileURL = makeTemporaryFileURL(name: "leaderboard.json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(LeaderboardFile(schemaVersion: 999)).write(to: fileURL)

        let viewModel = LeaderboardViewModel(
            leaderboardStore: LeaderboardStore(fileURL: fileURL),
            profileStore: ProfileStore(fileURL: makeTemporaryFileURL(name: "profiles.json"))
        )

        #expect(viewModel.entries.isEmpty)
        #expect(viewModel.isEmpty)
        #expect(viewModel.lastError == nil)
    }

    // MARK: - processedMatchIDs isolation

    @Test func processedMatchIDsDoNotAffectDisplayedRanking() throws {
        let (leaderboardStore, profileStore) = makeStores()
        let profile = PlayerProfile(displayName: "Alex")
        try profileStore.save(ProfilesFile(profiles: [profile]))
        let stats = PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1)
        try leaderboardStore.save(LeaderboardFile(
            statsByProfileID: [profile.id: stats],
            processedMatchIDs: [UUID(), UUID(), UUID()]
        ))

        let viewModel = LeaderboardViewModel(leaderboardStore: leaderboardStore, profileStore: profileStore)

        #expect(viewModel.entries.count == 1)
        #expect(viewModel.entries.first?.profileID == profile.id)
        #expect(viewModel.entries.first?.stats == stats)
    }
}
