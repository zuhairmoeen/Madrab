import Testing
@testable import Madrab
import MadrabScoringEngine

struct MatchSessionViewModelTests {
    @Test func startingMatchEntersLivePhaseWithInitialState() throws {
        let session = MatchSessionViewModel()
        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "", teamBLabel: "")

        #expect(session.state?.currentPhase == .game(.initial))
        #expect(session.teamALabel == "Team A")
        #expect(session.teamBLabel == "Team B")
    }

    @Test func blankLabelsFallBackToDefaults() throws {
        let session = MatchSessionViewModel()
        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "   ", teamBLabel: "")

        #expect(session.teamALabel == "Team A")
        #expect(session.teamBLabel == "Team B")
    }

    @Test func customLabelsAreTrimmedAndKept() throws {
        let session = MatchSessionViewModel()
        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "  Us  ", teamBLabel: "Them")

        #expect(session.teamALabel == "Us")
        #expect(session.teamBLabel == "Them")
    }

    @Test func recordingPointsUpdatesScore() throws {
        let session = MatchSessionViewModel()
        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "", teamBLabel: "")

        session.recordPoint(for: .teamA)

        let expected = GameScore(points: TeamPair(teamA: 1, teamB: 0))
        #expect(session.state?.currentPhase == .game(expected))
    }

    @Test func canUndoReflectsEffectivePoints() throws {
        let session = MatchSessionViewModel()
        session.startMatch(configuration: try MatchConfiguration(), teamALabel: "", teamBLabel: "")

        #expect(session.canUndo == false)

        session.recordPoint(for: .teamA)
        #expect(session.canUndo == true)

        session.undoLastEffectivePoint()
        #expect(session.canUndo == false)
    }

    @Test func undoRestoresPreviousScore() throws {
        let session = MatchSessionViewModel()
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
}
