import Testing
import Foundation
@testable import Madrab
import MadrabScoringEngine

@MainActor
struct ProfilesViewModelTests {
    private func makeTemporaryFileURL(name: String = "profiles.json") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
    }

    /// A file (not a directory) occupying `fileURL`'s parent path forces
    /// every `save` to throw when it tries to create that directory,
    /// deterministically simulating a persistence failure.
    private func makeUnwritableFileURL() throws -> URL {
        let blockedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try Data().write(to: blockedDirectory)
        return blockedDirectory.appendingPathComponent("profiles.json")
    }

    private struct ThrowingStatsPurger: LeaderboardStatsPurging {
        struct PurgeFailure: Error {}
        func removeStats(forProfileID profileID: UUID) throws {
            throw PurgeFailure()
        }
    }

    // MARK: - Loading

    @Test func loadsProfilesFromStoreOnInit() throws {
        let store = ProfileStore(fileURL: makeTemporaryFileURL())
        try store.save(ProfilesFile(profiles: [PlayerProfile(displayName: "Alex")]))

        let viewModel = ProfilesViewModel(store: store)

        #expect(viewModel.profiles.map(\.displayName) == ["Alex"])
    }

    // MARK: - Create

    @Test func createProfilePersistsAndTrimsWhitespace() throws {
        let store = ProfileStore(fileURL: makeTemporaryFileURL())
        let viewModel = ProfilesViewModel(store: store)

        let created = viewModel.createProfile(displayName: "  Alex  ")

        #expect(created?.displayName == "Alex")
        #expect(viewModel.profiles.map(\.displayName) == ["Alex"])
        #expect(store.load().profiles.map(\.displayName) == ["Alex"])
    }

    @Test func createProfileRejectsBlankName() {
        let viewModel = ProfilesViewModel(store: ProfileStore(fileURL: makeTemporaryFileURL()))

        let created = viewModel.createProfile(displayName: "   ")

        #expect(created == nil)
        #expect(viewModel.profiles.isEmpty)
        #expect(viewModel.lastError as? ProfileValidationError == .blankName)
    }

    @Test func createProfileRejectsDuplicateNameCaseInsensitivelyAndTrimmed() {
        let viewModel = ProfilesViewModel(store: ProfileStore(fileURL: makeTemporaryFileURL()))
        viewModel.createProfile(displayName: "Alex")

        let duplicate = viewModel.createProfile(displayName: "  ALEX  ")

        #expect(duplicate == nil)
        #expect(viewModel.profiles.count == 1)
        #expect(viewModel.lastError as? ProfileValidationError == .duplicateName("ALEX"))
    }

    // MARK: - Edit

    @Test func editProfilePreservesIDAndPersists() throws {
        let store = ProfileStore(fileURL: makeTemporaryFileURL())
        let viewModel = ProfilesViewModel(store: store)
        let created = try #require(viewModel.createProfile(displayName: "Alex"))

        let didUpdate = viewModel.updateProfile(id: created.id, displayName: "  Alexandra  ", avatarImageData: nil)

        #expect(didUpdate)
        #expect(viewModel.profiles.first?.id == created.id)
        #expect(viewModel.profiles.first?.displayName == "Alexandra")
        #expect(store.load().profiles.first?.id == created.id)
        #expect(store.load().profiles.first?.displayName == "Alexandra")
    }

    @Test func editProfileAllowsKeepingItsOwnName() throws {
        let viewModel = ProfilesViewModel(store: ProfileStore(fileURL: makeTemporaryFileURL()))
        let created = try #require(viewModel.createProfile(displayName: "Alex"))

        let didUpdate = viewModel.updateProfile(id: created.id, displayName: "Alex", avatarImageData: nil)

        #expect(didUpdate)
    }

    @Test func editProfileRejectsBlankName() throws {
        let viewModel = ProfilesViewModel(store: ProfileStore(fileURL: makeTemporaryFileURL()))
        let created = try #require(viewModel.createProfile(displayName: "Alex"))

        let didUpdate = viewModel.updateProfile(id: created.id, displayName: "  ", avatarImageData: nil)

        #expect(!didUpdate)
        #expect(viewModel.profiles.first?.displayName == "Alex")
        #expect(viewModel.lastError as? ProfileValidationError == .blankName)
    }

    @Test func editProfileRejectsDuplicateOfAnotherProfile() throws {
        let viewModel = ProfilesViewModel(store: ProfileStore(fileURL: makeTemporaryFileURL()))
        viewModel.createProfile(displayName: "Alex")
        let sam = try #require(viewModel.createProfile(displayName: "Sam"))

        let didUpdate = viewModel.updateProfile(id: sam.id, displayName: "alex", avatarImageData: nil)

        #expect(!didUpdate)
        #expect(viewModel.lastError as? ProfileValidationError == .duplicateName("alex"))
    }

    // MARK: - Delete

    @Test func deleteProfilePersists() throws {
        let store = ProfileStore(fileURL: makeTemporaryFileURL())
        let viewModel = ProfilesViewModel(store: store)
        let created = try #require(viewModel.createProfile(displayName: "Alex"))

        let didDelete = viewModel.deleteProfile(id: created.id)

        #expect(didDelete)
        #expect(viewModel.profiles.isEmpty)
        #expect(store.load().profiles.isEmpty)
    }

    @Test func cannotDeleteProfileReferencedByActiveMatch() throws {
        let profileStore = ProfileStore(fileURL: makeTemporaryFileURL())
        let matchStore = MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json"))
        let viewModel = ProfilesViewModel(store: profileStore, activeMatchStore: matchStore)
        let created = try #require(viewModel.createProfile(displayName: "Alex"))

        try matchStore.save(PersistedMatch(
            configuration: try MatchConfiguration(),
            events: [],
            teamALabel: "Alex",
            teamBLabel: "Sam",
            teamAProfileID: created.id,
            teamBProfileID: nil
        ))

        let didDelete = viewModel.deleteProfile(id: created.id)

        #expect(!didDelete)
        #expect(viewModel.profiles.contains(where: { $0.id == created.id }))
        #expect(viewModel.lastError as? ProfileDeletionError == .inUseByActiveMatch)
    }

    @Test func successfulDeletionRemovesLeaderboardStatsButKeepsProcessedMatchIDs() throws {
        let leaderboardStore = LeaderboardStore(fileURL: makeTemporaryFileURL(name: "leaderboard.json"))
        let matchID = UUID()
        let profileID = UUID()
        let otherProfileID = UUID()
        try leaderboardStore.save(LeaderboardFile(
            statsByProfileID: [
                profileID: PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1, losses: 0),
                otherProfileID: PlayerStats(totalPoints: 1, matchesPlayed: 1, wins: 0, losses: 1)
            ],
            processedMatchIDs: [matchID]
        ))

        let store = ProfileStore(fileURL: makeTemporaryFileURL())
        try store.save(ProfilesFile(profiles: [
            PlayerProfile(id: profileID, displayName: "Alex"),
            PlayerProfile(id: otherProfileID, displayName: "Sam")
        ]))
        let purger = LeaderboardStatsPurger(store: leaderboardStore)
        let viewModel = ProfilesViewModel(store: store, statsPurger: purger)

        let didDelete = viewModel.deleteProfile(id: profileID)

        #expect(didDelete)
        let file = leaderboardStore.load()
        #expect(file.statsByProfileID[profileID] == nil)
        #expect(file.statsByProfileID[otherProfileID] != nil)
        #expect(file.processedMatchIDs == [matchID])
    }

    @Test func failedStatsPurgeDoesNotReportSuccessOrRemoveProfile() throws {
        let store = ProfileStore(fileURL: makeTemporaryFileURL())
        let viewModel = ProfilesViewModel(store: store, statsPurger: ThrowingStatsPurger())
        let created = try #require(viewModel.createProfile(displayName: "Alex"))

        let didDelete = viewModel.deleteProfile(id: created.id)

        #expect(!didDelete)
        #expect(viewModel.profiles.contains(where: { $0.id == created.id }))
        #expect(store.load().profiles.contains(where: { $0.id == created.id }))
        #expect(viewModel.lastError as? ProfileDeletionError == .persistenceFailed)
    }

    @Test func failedCreatePersistenceDoesNotReportSuccess() throws {
        let fileURL = try makeUnwritableFileURL()
        let viewModel = ProfilesViewModel(store: ProfileStore(fileURL: fileURL))

        let created = viewModel.createProfile(displayName: "Alex")

        #expect(created == nil)
        #expect(viewModel.profiles.isEmpty)
        #expect(viewModel.lastError != nil)
    }
}
