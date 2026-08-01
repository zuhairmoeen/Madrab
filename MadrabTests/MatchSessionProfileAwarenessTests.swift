import Testing
import Foundation
@testable import Madrab
import MadrabScoringEngine

@MainActor
struct MatchSessionProfileAwarenessTests {
    private func makeTemporaryFileURL(name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
    }

    /// A file (not a directory) occupying the parent path forces every
    /// `save` under it to throw when it tries to create that directory,
    /// deterministically simulating a persistence failure.
    private func makeUnwritableFileURL(name: String) throws -> URL {
        let blockedDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try Data().write(to: blockedDirectory)
        return blockedDirectory.appendingPathComponent(name)
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

    // MARK: - Profile-aware start

    @Test func profileLinkedStartPersistsMatchIDAndProfileIDs() throws {
        let matchStore = MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json"))
        let session = MatchSessionViewModel(store: matchStore)
        let teamA = PlayerProfile(displayName: "Alex")
        let teamB = PlayerProfile(displayName: "Sam")

        let started = session.startMatch(configuration: try MatchConfiguration(), teamAProfile: teamA, teamBProfile: teamB)

        #expect(started)
        let persisted = try #require(matchStore.load())
        #expect(persisted.matchID != nil)
        #expect(persisted.teamAProfileID == teamA.id)
        #expect(persisted.teamBProfileID == teamB.id)
        #expect(persisted.teamALabel == "Alex")
        #expect(persisted.teamBLabel == "Sam")
    }

    @Test func identicalProfileIDsAreRejected() throws {
        let session = MatchSessionViewModel(store: MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json")))
        let profile = PlayerProfile(displayName: "Alex")

        let started = session.startMatch(configuration: try MatchConfiguration(), teamAProfile: profile, teamBProfile: profile)

        #expect(!started)
        #expect(session.state == nil)
    }

    @Test func legacyStartStillWorksAndPersistsNilIDs() throws {
        let matchStore = MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json"))
        let session = MatchSessionViewModel(store: matchStore)

        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "Alex", teamBLabel: "Sam")

        let persisted = try #require(matchStore.load())
        #expect(persisted.matchID == nil)
        #expect(persisted.teamAProfileID == nil)
        #expect(persisted.teamBProfileID == nil)
    }

    @Test func scoringAndUndoPreserveProfileIDs() throws {
        let matchStore = MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json"))
        let session = MatchSessionViewModel(store: matchStore)
        let teamA = PlayerProfile(displayName: "Alex")
        let teamB = PlayerProfile(displayName: "Sam")
        session.startMatch(configuration: try MatchConfiguration(), teamAProfile: teamA, teamBProfile: teamB)
        let matchIDAfterStart = try #require(matchStore.load()).matchID

        session.recordPoint(for: .teamA)
        let afterPoint = try #require(matchStore.load())
        #expect(afterPoint.matchID == matchIDAfterStart)
        #expect(afterPoint.teamAProfileID == teamA.id)
        #expect(afterPoint.teamBProfileID == teamB.id)

        session.undoLastEffectivePoint()
        let afterUndo = try #require(matchStore.load())
        #expect(afterUndo.matchID == matchIDAfterStart)
        #expect(afterUndo.teamAProfileID == teamA.id)
        #expect(afterUndo.teamBProfileID == teamB.id)
    }

    // MARK: - Completion

    @Test func successfulFinishAwardsExactlyOnceAndClearsActiveMatch() throws {
        let matchStore = MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json"))
        let leaderboardStore = LeaderboardStore(fileURL: makeTemporaryFileURL(name: "leaderboard.json"))
        let session = MatchSessionViewModel(store: matchStore, resultRecorder: MatchResultRecorder(store: leaderboardStore))
        let teamA = PlayerProfile(displayName: "Winner")
        let teamB = PlayerProfile(displayName: "Loser")
        session.startMatch(configuration: try winningConfiguration(), teamAProfile: teamA, teamBProfile: teamB)
        winTwoGames(for: .teamA, on: session)

        session.finishMatch()

        #expect(session.sessionError == nil)
        guard case .finished(let winner) = session.phase else {
            Issue.record("expected finished phase")
            return
        }
        #expect(winner == .teamA)
        #expect(matchStore.load() == nil)

        let file = leaderboardStore.load()
        #expect(file.statsByProfileID[teamA.id] == PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1, losses: 0))
        #expect(file.statsByProfileID[teamB.id] == PlayerStats(totalPoints: 1, matchesPlayed: 1, wins: 0, losses: 1))

        // A duplicate call (e.g. a repeated UI tap) must not double-award.
        session.finishMatch()
        #expect(leaderboardStore.load() == file)
    }

    @Test func discardedMatchAwardsNothing() throws {
        let leaderboardStore = LeaderboardStore(fileURL: makeTemporaryFileURL(name: "leaderboard.json"))
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json")),
            resultRecorder: MatchResultRecorder(store: leaderboardStore)
        )
        let teamA = PlayerProfile(displayName: "Alex")
        let teamB = PlayerProfile(displayName: "Sam")
        session.startMatch(configuration: try MatchConfiguration(), teamAProfile: teamA, teamBProfile: teamB)
        session.recordPoint(for: .teamA)

        session.returnToSetup()

        #expect(leaderboardStore.load() == LeaderboardFile())
    }

    @Test func inProgressMatchAwardsNothing() throws {
        let leaderboardStore = LeaderboardStore(fileURL: makeTemporaryFileURL(name: "leaderboard.json"))
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json")),
            resultRecorder: MatchResultRecorder(store: leaderboardStore)
        )
        let teamA = PlayerProfile(displayName: "Alex")
        let teamB = PlayerProfile(displayName: "Sam")
        session.startMatch(configuration: try MatchConfiguration(), teamAProfile: teamA, teamBProfile: teamB)
        session.recordPoint(for: .teamA)
        session.recordPoint(for: .teamB)

        #expect(leaderboardStore.load() == LeaderboardFile())
    }

    // MARK: - Crash-safe failure / retry

    @Test func finishMatchRecordingFailureRetainsActiveMatchAndExposesError() throws {
        let matchStore = MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json"))
        let unwritableLeaderboardURL = try makeUnwritableFileURL(name: "leaderboard.json")
        let session = MatchSessionViewModel(
            store: matchStore,
            resultRecorder: MatchResultRecorder(store: LeaderboardStore(fileURL: unwritableLeaderboardURL))
        )
        let teamA = PlayerProfile(displayName: "Winner")
        let teamB = PlayerProfile(displayName: "Loser")
        session.startMatch(configuration: try winningConfiguration(), teamAProfile: teamA, teamBProfile: teamB)
        winTwoGames(for: .teamA, on: session)

        session.finishMatch()

        #expect(session.sessionError == .pointsRecordingFailed)
        guard case .live = session.phase else {
            Issue.record("expected phase to remain live pending retry")
            return
        }
        #expect(matchStore.load() != nil)
    }

    @Test func retryAfterRecordingFailureSucceedsAndDoesNotDoubleAward() throws {
        let matchStore = MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json"))
        let leaderboardFileURL = try makeUnwritableFileURL(name: "leaderboard.json")
        let session = MatchSessionViewModel(
            store: matchStore,
            resultRecorder: MatchResultRecorder(store: LeaderboardStore(fileURL: leaderboardFileURL))
        )
        let teamA = PlayerProfile(displayName: "Winner")
        let teamB = PlayerProfile(displayName: "Loser")
        session.startMatch(configuration: try winningConfiguration(), teamAProfile: teamA, teamBProfile: teamB)
        winTwoGames(for: .teamA, on: session)

        session.finishMatch()
        #expect(session.sessionError == .pointsRecordingFailed)

        // Simulate the underlying issue being resolved.
        try FileManager.default.removeItem(at: leaderboardFileURL.deletingLastPathComponent())

        session.finishMatch()

        #expect(session.sessionError == nil)
        guard case .finished(let winner) = session.phase else {
            Issue.record("expected finished phase after successful retry")
            return
        }
        #expect(winner == .teamA)
        #expect(matchStore.load() == nil)

        let file = LeaderboardStore(fileURL: leaderboardFileURL).load()
        #expect(file.statsByProfileID[teamA.id] == PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1, losses: 0))
        #expect(file.statsByProfileID[teamB.id] == PlayerStats(totalPoints: 1, matchesPlayed: 1, wins: 0, losses: 1))
    }

    // MARK: - Restore

    @Test func restoredTerminalLinkedMatchRetriesAndAwardsExactlyOnce() throws {
        let matchStore = MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json"))
        let leaderboardStore = LeaderboardStore(fileURL: makeTemporaryFileURL(name: "leaderboard.json"))
        let winnerID = UUID()
        let loserID = UUID()
        let matchID = UUID()

        // Simulate a match whose result was already successfully recorded,
        // but the process crashed before active-match.json could be cleared.
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

        let session = MatchSessionViewModel(store: matchStore, resultRecorder: MatchResultRecorder(store: leaderboardStore))
        session.restoreIfNeeded()

        #expect(session.sessionError == nil)
        guard case .finished(let winner) = session.phase else {
            Issue.record("expected finished phase")
            return
        }
        #expect(winner == .teamA)
        #expect(matchStore.load() == nil)

        let file = leaderboardStore.load()
        #expect(file.statsByProfileID[winnerID] == PlayerStats(totalPoints: 3, matchesPlayed: 1, wins: 1, losses: 0))
        #expect(file.statsByProfileID[loserID] == PlayerStats(totalPoints: 1, matchesPlayed: 1, wins: 0, losses: 1))
    }

    @Test func restoredTerminalRecordingFailureRetainsActiveMatch() throws {
        let matchStore = MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json"))
        let unwritableLeaderboardURL = try makeUnwritableFileURL(name: "leaderboard.json")
        let winnerID = UUID()
        let loserID = UUID()
        let matchID = UUID()

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

        let session = MatchSessionViewModel(
            store: matchStore,
            resultRecorder: MatchResultRecorder(store: LeaderboardStore(fileURL: unwritableLeaderboardURL))
        )
        session.restoreIfNeeded()

        #expect(session.sessionError == .pointsRecordingFailed)
        #expect(matchStore.load() != nil)
        guard case .live = session.phase else {
            Issue.record("expected live phase to remain, awaiting retry")
            return
        }
    }

    @Test func restoredTerminalLegacyMatchClearsWithoutAwardingPoints() throws {
        let matchStore = MatchStore(fileURL: makeTemporaryFileURL(name: "active-match.json"))
        let leaderboardStore = LeaderboardStore(fileURL: makeTemporaryFileURL(name: "leaderboard.json"))

        var engine = MatchEngine(configuration: try winningConfiguration())
        for _ in 0..<2 {
            for _ in 0..<4 {
                _ = engine.submit(.pointWon(PointWonEvent(winningTeam: .teamA)))
            }
        }
        _ = engine.submit(.finishMatch(FinishMatchEvent()))

        // No profile IDs -> legacy match.
        try matchStore.save(PersistedMatch(
            configuration: engine.configuration,
            events: engine.events,
            teamALabel: "A",
            teamBLabel: "B"
        ))

        let session = MatchSessionViewModel(store: matchStore, resultRecorder: MatchResultRecorder(store: leaderboardStore))
        session.restoreIfNeeded()

        #expect(session.sessionError == nil)
        guard case .finished(let winner) = session.phase else {
            Issue.record("expected finished phase")
            return
        }
        #expect(winner == .teamA)
        #expect(matchStore.load() == nil)
        #expect(leaderboardStore.load() == LeaderboardFile())
    }

    @Test func preMilestone3PersistedJSONStillDecodesAndRestores() throws {
        let fileURL = makeTemporaryFileURL(name: "active-match.json")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let configuration = try MatchConfiguration()
        let configData = try JSONEncoder().encode(configuration)
        let configObject = try JSONSerialization.jsonObject(with: configData)

        // Deliberately omits matchID/teamAProfileID/teamBProfileID entirely,
        // matching the on-disk shape written before Milestone 3.
        let legacyJSONObject: [String: Any] = [
            "configuration": configObject,
            "events": [],
            "teamALabel": "Alex",
            "teamBLabel": "Sam"
        ]
        let legacyData = try JSONSerialization.data(withJSONObject: legacyJSONObject)
        try legacyData.write(to: fileURL)

        let session = MatchSessionViewModel(store: MatchStore(fileURL: fileURL))
        session.restoreIfNeeded()

        guard case .live(let state) = session.phase else {
            Issue.record("expected live phase for restored legacy match")
            return
        }
        #expect(state.currentPhase == .game(.initial))
        #expect(session.teamALabel == "Alex")
        #expect(session.teamBLabel == "Sam")
    }
}
