import Testing

import MadrabScoringEngine

struct UndoTests {
    @Test func undoLatestEffectivePoint() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        let secondPoint = pointEvent(.teamB)

        engine.submit(pointEvent(.teamA))
        engine.submit(secondPoint)

        guard let state = expectSuccess(engine.submit(undoEvent(secondPoint.id))) else {
            return
        }

        let expectedScore = GameScore(points: TeamPair(teamA: 1, teamB: 0))
        #expect(state.currentPhase == .game(expectedScore))
    }

    @Test func duplicateUndoDeliveryIsIdempotent() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        let point = pointEvent(.teamA)
        engine.submit(point)

        let undo = undoEvent(point.id)
        #expect(expectSuccess(engine.submit(undo)) != nil)

        let stateAfterFirstUndo = engine.state

        // Re-delivering the exact same undo event is rejected outright by
        // live submission -- but the *effect* is still idempotent: state is
        // unchanged after the rejected re-delivery.
        expectFailure(engine.submit(undo), .duplicateEventID)
        #expect(engine.state == stateAfterFirstUndo)
    }

    @Test func undoNonexistentEventIsRejected() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        engine.submit(pointEvent(.teamA))

        expectFailure(engine.submit(undoEvent(EventID())), .undoTargetNotFound)
    }

    @Test func undoAlreadyUndoneEventIsRejected() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        let point = pointEvent(.teamA)
        engine.submit(point)

        #expect(expectSuccess(engine.submit(undoEvent(point.id))) != nil)
        expectFailure(
            engine.submit(undoEvent(point.id)),
            .undoTargetAlreadyUndone
        )
    }

    @Test func pointAfterUndoReplaysCorrectly() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        let firstPoint = pointEvent(.teamA)
        engine.submit(firstPoint)
        engine.submit(undoEvent(firstPoint.id))
        engine.submit(pointEvent(.teamB))

        let expectedScore = GameScore(points: TeamPair(teamA: 0, teamB: 1))
        #expect(engine.state.currentPhase == .game(expectedScore))
    }

    @Test func undoGameWinningPointRestoresPreviousGameState() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(straightPoints(.teamA, count: 3), to: &engine)

        let winningPoint = pointEvent(.teamA)
        engine.submit(winningPoint)
        #expect(engine.state.currentSet?.games == TeamPair(teamA: 1, teamB: 0))

        guard let restored = expectSuccess(
            engine.submit(undoEvent(winningPoint.id))
        ) else {
            return
        }

        #expect(restored.currentSet?.games == TeamPair(teamA: 0, teamB: 0))
        let expectedScore = GameScore(points: TeamPair(teamA: 3, teamB: 0))
        #expect(restored.currentPhase == .game(expectedScore))
    }

    @Test func undoSetWinningPointRestoresPreviousSetState() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(gameWinners(Array(repeating: Team.teamA, count: 5)), to: &engine)
        submitAll(straightPoints(.teamA, count: 3), to: &engine)

        let winningPoint = pointEvent(.teamA)
        engine.submit(winningPoint)
        #expect(engine.state.sets.count == 1)

        guard let restored = expectSuccess(
            engine.submit(undoEvent(winningPoint.id))
        ) else {
            return
        }

        #expect(restored.sets.isEmpty)
        #expect(restored.currentSet?.games == TeamPair(teamA: 5, teamB: 0))
        let expectedScore = GameScore(points: TeamPair(teamA: 3, teamB: 0))
        #expect(restored.currentPhase == .game(expectedScore))
    }

    @Test func undoMatchWinningPointRestoresOpenMatch() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(
            gameWinners(Array(repeating: Team.teamA, count: 6)),
            to: &engine
        )
        submitAll(
            gameWinners(Array(repeating: Team.teamA, count: 5)),
            to: &engine
        )
        submitAll(straightPoints(.teamA, count: 3), to: &engine)

        let winningPoint = pointEvent(.teamA)
        engine.submit(winningPoint)
        #expect(engine.state.matchWinner == .teamA)

        guard let restored = expectSuccess(
            engine.submit(undoEvent(winningPoint.id))
        ) else {
            return
        }

        #expect(restored.matchWinner == nil)
        #expect(restored.sets.count == 1)
        #expect(restored.setsWon == TeamPair(teamA: 1, teamB: 0))
    }

    @Test func undoRejectedAfterTerminalFinish() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(gameWinners(Array(repeating: Team.teamA, count: 12)), to: &engine)
        let winningPointID = engine.events.last!.id

        #expect(expectSuccess(engine.submit(finishEvent())) != nil)
        expectFailure(engine.submit(undoEvent(winningPointID)), .matchAlreadyFinished)
    }
}
