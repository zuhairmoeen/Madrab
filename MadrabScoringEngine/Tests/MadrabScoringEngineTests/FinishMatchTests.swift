import Testing

import MadrabScoringEngine

struct FinishMatchTests {
    @Test func finishRejectedBeforeMatchDecided() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        expectFailure(engine.submit(finishEvent()), .matchNotYetDecided)
    }

    @Test func finishAcceptedWhenMatchDecided() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(gameWinners(Array(repeating: Team.teamA, count: 12)), to: &engine)

        guard let state = expectSuccess(engine.submit(finishEvent())) else {
            return
        }

        #expect(state.isTerminal == true)
    }

    @Test func pointRejectedAfterFinish() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(gameWinners(Array(repeating: Team.teamA, count: 12)), to: &engine)
        engine.submit(finishEvent())

        expectFailure(engine.submit(pointEvent(.teamA)), .matchAlreadyFinished)
    }

    @Test func undoAllowedBeforeFinishButRejectedAfter() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(gameWinners(Array(repeating: Team.teamA, count: 12)), to: &engine)
        let winningPointID = engine.events.last!.id

        // Before finish: undoing the winning point still works (checked on
        // an independent copy, since MatchEngine is a value type).
        var probe = engine
        #expect(expectSuccess(probe.submit(undoEvent(winningPointID))) != nil)

        // After finish: the same undo is rejected.
        engine.submit(finishEvent())
        expectFailure(engine.submit(undoEvent(winningPointID)), .matchAlreadyFinished)
    }

    @Test func secondDistinctFinishRejected() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(
            gameWinners(Array(repeating: Team.teamA, count: 12)),
            to: &engine
        )
        engine.submit(finishEvent())

        expectFailure(
            engine.submit(finishEvent()),
            .matchAlreadyFinished
        )
    }

    @Test func duplicateFinishIdempotentOnReplay() throws {
        let configuration = try MatchConfiguration()
        var events = gameWinners(Array(repeating: Team.teamA, count: 12))
        let finish = finishEvent()
        events.append(finish)
        events.append(finish)

        guard let state = expectSuccess(
            MatchReplayer.replay(events, configuration: configuration)
        ) else {
            return
        }

        #expect(state.isTerminal == true)
        #expect(state.matchWinner == .teamA)
    }

    @Test func replayRejectsTrailingEventAfterFinish() throws {
        let configuration = try MatchConfiguration()
        var events = gameWinners(Array(repeating: Team.teamA, count: 12))
        events.append(finishEvent())
        events.append(pointEvent(.teamB))

        expectFailure(
            MatchReplayer.replay(events, configuration: configuration),
            .matchAlreadyFinished
        )
    }

    @Test func replayReconstructsTerminalStateWithNoTrailingEvents() throws {
        let configuration = try MatchConfiguration()
        var events = gameWinners(Array(repeating: Team.teamA, count: 12))
        events.append(finishEvent())

        guard let state = expectSuccess(
            MatchReplayer.replay(events, configuration: configuration)
        ) else {
            return
        }

        #expect(state.isTerminal == true)
        #expect(state.matchWinner == .teamA)
    }
}
