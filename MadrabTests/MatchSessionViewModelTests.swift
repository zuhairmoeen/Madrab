import Testing
import Foundation
@testable import Madrab
import MadrabScoringEngine

struct MatchSessionViewModelTests {
    private func makeTemporaryStore() -> MatchStore {
        MatchStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent("active-match.json")
        )
    }

    @Test func startingMatchEntersLivePhaseWithInitialState() throws {
        let session = MatchSessionViewModel(store: makeTemporaryStore())
        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "", teamBLabel: "")

        #expect(session.state?.currentPhase == .game(.initial))
        #expect(session.teamALabel == "Team A")
        #expect(session.teamBLabel == "Team B")
    }

    @Test func blankLabelsFallBackToDefaults() throws {
        let session = MatchSessionViewModel(store: makeTemporaryStore())
        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "   ", teamBLabel: "")

        #expect(session.teamALabel == "Team A")
        #expect(session.teamBLabel == "Team B")
    }

    @Test func customLabelsAreTrimmedAndKept() throws {
        let session = MatchSessionViewModel(store: makeTemporaryStore())
        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "  Us  ", teamBLabel: "Them")

        #expect(session.teamALabel == "Us")
        #expect(session.teamBLabel == "Them")
    }

    @Test func recordingPointsUpdatesScore() throws {
        let session = MatchSessionViewModel(store: makeTemporaryStore())
        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "", teamBLabel: "")

        session.recordPoint(for: .teamA)

        let expected = GameScore(points: TeamPair(teamA: 1, teamB: 0))
        #expect(session.state?.currentPhase == .game(expected))
    }

    @Test func canUndoReflectsEffectivePoints() throws {
        let session = MatchSessionViewModel(store: makeTemporaryStore())
        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "", teamBLabel: "")

        #expect(session.canUndo == false)

        session.recordPoint(for: .teamA)
        #expect(session.canUndo == true)

        session.undoLastEffectivePoint()
        #expect(session.canUndo == false)
    }

    @Test func undoRestoresPreviousScore() throws {
        let session = MatchSessionViewModel(store: makeTemporaryStore())
        session.startMatch(
            configuration: try MatchConfiguration(),
            teamALabel: "",
            teamBLabel: ""
        )

        session.recordPoint(for: .teamA)
        session.recordPoint(for: .teamB)
        session.undoLastEffectivePoint()

        let expected = GameScore(
            points: TeamPair(teamA: 1, teamB: 0)
        )
        #expect(session.state?.currentPhase == .game(expected))
    }

    @Test func lastEffectivePointIDIgnoresFinishMatchAndTracksUndo() throws {
        let pointA = PointWonEvent(winningTeam: .teamA)
        let pointB = PointWonEvent(winningTeam: .teamB)
        let events: [ScoringEvent] = [
            .pointWon(pointA),
            .pointWon(pointB),
            .undo(UndoEvent(targetEventID: pointB.id))
        ]

        #expect(MatchSessionViewModel.lastEffectivePointID(in: events) == pointA.id)
    }

    @Test func lastEffectivePointIDIsNilWithNoPoints() throws {
        #expect(MatchSessionViewModel.lastEffectivePointID(in: []) == nil)
    }

    // MARK: - Persistence behavior

    @Test func startingMatchPersistsConfigurationAndLabels() throws {
        let store = makeTemporaryStore()
        let session = MatchSessionViewModel(store: store)

        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "Us", teamBLabel: "Them")

        let persisted = try #require(store.load())
        #expect(persisted.events.isEmpty)
        #expect(persisted.teamALabel == "Us")
        #expect(persisted.teamBLabel == "Them")
    }

    @Test func recordingAPointPersistsTheUpdatedEventLog() throws {
        let store = makeTemporaryStore()
        let session = MatchSessionViewModel(store: store)
        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "", teamBLabel: "")

        session.recordPoint(for: .teamA)

        let persisted = try #require(store.load())
        #expect(persisted.events.count == 1)
    }

    @Test func undoPersistsTheUpdatedEventLog() throws {
        let store = makeTemporaryStore()
        let session = MatchSessionViewModel(store: store)
        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "", teamBLabel: "")
        session.recordPoint(for: .teamA)

        session.undoLastEffectivePoint()

        let persisted = try #require(store.load())
        #expect(persisted.events.count == 2)
    }

    @Test func discardingClearsThePersistedMatch() throws {
        let store = makeTemporaryStore()
        let session = MatchSessionViewModel(store: store)
        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "", teamBLabel: "")
        session.recordPoint(for: .teamA)
        #expect(store.load() != nil)

        session.returnToSetup()

        #expect(store.load() == nil)
    }

    @Test func finishingTheMatchClearsThePersistedMatch() throws {
        let store = makeTemporaryStore()
        let session = MatchSessionViewModel(store: store)
        let configuration = try MatchConfiguration(
            setsToWin: 1,
            gamesToWinSet: 2,
            finalSetMode: .fullSet
        )

        session.startMatch(
            configuration: configuration,
            teamALabel: "",
            teamBLabel: ""
        )

        for _ in 0..<2 {
            for _ in 0..<4 {
                session.recordPoint(for: .teamA)
            }
        }

        #expect(session.state?.matchWinner == .teamA)
        #expect(store.load() != nil)

        session.finishMatch()

        #expect(store.load() == nil)
    }

    @Test func restoreIfNeededDoesNothingWithNoPersistedMatch() {
        let session = MatchSessionViewModel(store: makeTemporaryStore())

        session.restoreIfNeeded()

        #expect(session.state == nil)
    }

    @Test func restoreIfNeededReconstructsANonTerminalMatch() throws {
        let store = makeTemporaryStore()
        let configuration = try MatchConfiguration()
        var engine = MatchEngine(configuration: configuration)
        _ = engine.submit(.pointWon(PointWonEvent(winningTeam: .teamA)))
        _ = engine.submit(.pointWon(PointWonEvent(winningTeam: .teamA)))

        try store.save(PersistedMatch(
            configuration: configuration,
            events: engine.events,
            teamALabel: "Us",
            teamBLabel: "Them"
        ))

        let session = MatchSessionViewModel(store: store)
        session.restoreIfNeeded()

        #expect(session.teamALabel == "Us")
        #expect(session.teamBLabel == "Them")
        #expect(session.state?.currentPhase == engine.state.currentPhase)
    }

    @Test func restoreIfNeededDiscardsAndStaysAtSetupWhenReplayFails() throws {
        let store = makeTemporaryStore()
        let unreplayableEvents: [ScoringEvent] = [
            .undo(UndoEvent(targetEventID: EventID()))
        ]

        try store.save(PersistedMatch(
            configuration: try MatchConfiguration(),
            events: unreplayableEvents,
            teamALabel: "Us",
            teamBLabel: "Them"
        ))

        let session = MatchSessionViewModel(store: store)
        session.restoreIfNeeded()

        #expect(session.state == nil)
        #expect(store.load() == nil)
    }

    @Test func restoreIfNeededDiscardsAndStaysAtSetupWhenMatchIsAlreadyTerminal() throws {
        let store = makeTemporaryStore()
        let configuration = try MatchConfiguration(setsToWin: 1, gamesToWinSet: 2, finalSetMode: .fullSet)
        var engine = MatchEngine(configuration: configuration)
        for _ in 0..<2 {
            for _ in 0..<4 {
                _ = engine.submit(.pointWon(PointWonEvent(winningTeam: .teamA)))
            }
        }
        _ = engine.submit(.finishMatch(FinishMatchEvent()))
        #expect(engine.state.isTerminal)

        try store.save(PersistedMatch(
            configuration: configuration,
            events: engine.events,
            teamALabel: "Us",
            teamBLabel: "Them"
        ))

        let session = MatchSessionViewModel(store: store)
        session.restoreIfNeeded()

        #expect(session.state == nil)
        #expect(store.load() == nil)
    }
}
