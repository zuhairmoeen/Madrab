import Testing
import Foundation
@testable import Madrab
import MadrabScoringEngine
import MadrabSyncKit

/// In-memory `CommandReceipting` double, so constructing an `AppEnvironment`
/// in a test never reads or writes the real `command-receipts.json`.
private final class IsolatedCommandReceiptStore: CommandReceipting {
    struct Key: Hashable {
        let matchID: UUID
        let commandID: UUID
    }

    var receipts: Set<Key> = []

    func contains(matchID: UUID, commandID: UUID) throws -> Bool {
        receipts.contains(Key(matchID: matchID, commandID: commandID))
    }

    func promote(matchID: UUID, commandIDs: Set<UUID>) throws {
        for commandID in commandIDs {
            receipts.insert(Key(matchID: matchID, commandID: commandID))
        }
    }
}

/// Minimal phone transport double: enough to deliver one command and to see
/// what the environment's own service broadcasts. No `WCSession` involved.
@MainActor
private final class RecordingConnectivitySession: PhoneConnectivitySession {
    var isReachable = false
    var isActivated = false
    weak var events: PhoneConnectivitySessionEvents?

    private(set) var activateCallCount = 0
    private(set) var applicationContexts: [[String: Any]] = []

    var contextSnapshots: [SyncSnapshot] {
        applicationContexts.compactMap { SyncPayload.decodeSnapshot(from: $0) }
    }

    func activate() {
        activateCallCount += 1
    }

    func updateApplicationContext(_ payload: [String: Any]) throws {
        applicationContexts.append(payload)
    }

    func sendMessage(_ payload: [String: Any]) {}

    func deliverCommand(_ payload: [String: Any]) -> [SyncCommandResponse] {
        var replies: [[String: Any]] = []
        events?.sessionDidReceiveCommandPayload(payload, reply: SyncReplyHandler { replies.append($0) })
        return replies.compactMap { SyncPayload.decodeResponse(from: $0) }
    }
}

@MainActor
struct AppEnvironmentTests {
    private func makeTemporaryFileURL(name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
    }

    private func makeEnvironment(
        connectivitySession: PhoneConnectivitySession? = nil
    ) -> AppEnvironment {
        AppEnvironment(
            matchStore: MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json")),
            profileStore: ProfileStore(fileURL: makeTemporaryFileURL(name: "profiles.json")),
            leaderboardStore: LeaderboardStore(fileURL: makeTemporaryFileURL(name: "leaderboard.json")),
            commandReceiptStore: IsolatedCommandReceiptStore(),
            connectivitySession: connectivitySession ?? RecordingConnectivitySession()
        )
    }

    /// Lets the scheduled main-actor observation turn run before the newest
    /// broadcast is inspected.
    private func settle() async {
        for _ in 0..<3 {
            await Task.yield()
        }
    }

    private func winningConfiguration() throws -> MatchConfiguration {
        try MatchConfiguration(setsToWin: 1, gamesToWinSet: 2, finalSetMode: .fullSet)
    }

    private func winTwoGames(for team: Team, on session: MatchSessionViewModel) {
        for _ in 0..<2 {
            for _ in 0..<4 {
                session.recordPoint(for: team)
            }
        }
    }

    // MARK: - Shared instance / shared store wiring

    @Test func sharedMatchStoreIsConsistentBetweenSessionAndProfiles() throws {
        let environment = makeEnvironment()
        let teamA = try #require(environment.profilesViewModel.createProfile(displayName: "Alex"))
        let teamB = try #require(environment.profilesViewModel.createProfile(displayName: "Sam"))

        let started = environment.session.startMatch(
            configuration: try MatchConfiguration(),
            teamAProfile: teamA,
            teamBProfile: teamB
        )
        #expect(started)

        // ProfilesViewModel's active-match guard reads the same MatchStore
        // session just persisted to, so deleting a profile in that match
        // must be blocked.
        let didDelete = environment.profilesViewModel.deleteProfile(id: teamA.id)

        #expect(!didDelete)
        #expect(environment.profilesViewModel.lastError as? ProfileDeletionError == .inUseByActiveMatch)
    }

    @Test func finishingAMatchIsReflectedInSharedLeaderboardViewModel() throws {
        let environment = makeEnvironment()
        let teamA = try #require(environment.profilesViewModel.createProfile(displayName: "Winner"))
        let teamB = try #require(environment.profilesViewModel.createProfile(displayName: "Loser"))

        environment.session.startMatch(
            configuration: try winningConfiguration(),
            teamAProfile: teamA,
            teamBProfile: teamB
        )
        winTwoGames(for: .teamA, on: environment.session)
        environment.session.finishMatch()

        environment.leaderboardViewModel.reload()

        let winnerEntry = try #require(
            environment.leaderboardViewModel.entries.first { $0.profileID == teamA.id }
        )
        #expect(winnerEntry.stats == PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1, losses: 0))
        #expect(winnerEntry.displayName == "Winner")
    }

    // MARK: - No duplicate result-recording paths

    @Test func duplicateFinishCallsDoNotDoubleAwardThroughSharedRecorder() throws {
        let environment = makeEnvironment()
        let teamA = try #require(environment.profilesViewModel.createProfile(displayName: "Winner"))
        let teamB = try #require(environment.profilesViewModel.createProfile(displayName: "Loser"))

        environment.session.startMatch(
            configuration: try winningConfiguration(),
            teamAProfile: teamA,
            teamBProfile: teamB
        )
        winTwoGames(for: .teamA, on: environment.session)
        environment.session.finishMatch()
        environment.session.finishMatch()

        environment.leaderboardViewModel.reload()

        let winnerEntry = try #require(
            environment.leaderboardViewModel.entries.first { $0.profileID == teamA.id }
        )
        #expect(winnerEntry.stats == PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1, losses: 0))
    }

    // MARK: - Restore is safe even if triggered more than once

    @Test func restoreIfNeededIsSafeToCallMultipleTimes() throws {
        let matchStore = MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json"))
        let leaderboardStore = LeaderboardStore(fileURL: makeTemporaryFileURL(name: "leaderboard.json"))
        let winnerID = UUID()
        let loserID = UUID()
        let matchID = UUID()

        try leaderboardStore.save(LeaderboardFile(
            statsByProfileID: [
                winnerID: PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1, losses: 0),
                loserID: PlayerStats(totalPoints: 1, matchesPlayed: 1, wins: 0, losses: 1)
            ],
            processedMatchIDs: [matchID]
        ))

        var engine = MatchEngine(configuration: try winningConfiguration())
        for _ in 0..<2 {
            for _ in 0..<4 {
                _ = engine.submit(.pointWon(PointWonEvent(winningTeam: .teamA)))
            }
        }
        _ = engine.submit(.finishMatch(FinishMatchEvent()))

        try matchStore.save(PersistedMatch(
            configuration: engine.configuration,
            events: engine.events,
            teamALabel: "Winner",
            teamBLabel: "Loser",
            matchID: matchID,
            teamAProfileID: winnerID,
            teamBProfileID: loserID
        ))

        let environment = AppEnvironment(
            matchStore: matchStore,
            profileStore: ProfileStore(fileURL: makeTemporaryFileURL(name: "profiles.json")),
            leaderboardStore: leaderboardStore,
            commandReceiptStore: IsolatedCommandReceiptStore(),
            connectivitySession: RecordingConnectivitySession()
        )

        environment.session.restoreIfNeeded()
        environment.session.restoreIfNeeded()

        #expect(environment.session.sessionError == nil)
        guard case .finished(let winner) = environment.session.phase else {
            Issue.record("expected finished phase")
            return
        }
        #expect(winner == .teamA)
        #expect(matchStore.load() == nil)

        let file = leaderboardStore.load()
        #expect(file.statsByProfileID[winnerID] == PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1, losses: 0))
        #expect(file.statsByProfileID[loserID] == PlayerStats(totalPoints: 1, matchesPlayed: 1, wins: 0, losses: 1))
    }

    // MARK: - Watch sync wiring

    @Test func phoneSyncServiceDrivesTheSameMatchSessionAsTheUI() throws {
        let transport = RecordingConnectivitySession()
        let environment = makeEnvironment(connectivitySession: transport)
        let teamA = try #require(environment.profilesViewModel.createProfile(displayName: "Alex"))
        let teamB = try #require(environment.profilesViewModel.createProfile(displayName: "Sam"))

        environment.session.startMatch(
            configuration: try MatchConfiguration(),
            teamAProfile: teamA,
            teamBProfile: teamB
        )
        let matchID = environment.session.currentSnapshot().matchID

        let payload = try SyncPayload.encodeCommand(
            SyncCommand(
                matchID: matchID,
                commandID: UUID(),
                expectedStateRevision: 0,
                kind: .recordPoint(.teamA)
            )
        )
        let responses = transport.deliverCommand(payload)

        // A command routed through the environment's own service lands on the
        // very view model the Match tab renders — one instance, not two.
        #expect(responses.first?.outcome == .accepted)
        #expect(environment.session.state?.currentPhase == .game(GameScore(points: TeamPair(teamA: 1, teamB: 0))))
    }

    @Test func phoneOriginatedChangesAreBroadcastByTheEnvironmentsService() async throws {
        let transport = RecordingConnectivitySession()
        let environment = makeEnvironment(connectivitySession: transport)
        let teamA = try #require(environment.profilesViewModel.createProfile(displayName: "Alex"))
        let teamB = try #require(environment.profilesViewModel.createProfile(displayName: "Sam"))

        environment.session.startMatch(
            configuration: try MatchConfiguration(),
            teamAProfile: teamA,
            teamBProfile: teamB
        )
        await settle()

        let snapshot = try #require(transport.contextSnapshots.last)
        #expect(snapshot.matchID == environment.session.currentSnapshot().matchID)
        #expect(snapshot.teamAPair.first == "Alex")
        #expect(environment.phoneSyncService.lastTransportError == nil)
    }
}
