import Testing

import MadrabScoringEngine

struct ReplayAndValidationTests {
    @Test func deterministicReplay() throws {
        let configuration = try MatchConfiguration()
        let events: [ScoringEvent] = [
            pointEvent(.teamA),
            pointEvent(.teamB),
            pointEvent(.teamA),
        ]

        let first = expectSuccess(MatchReplayer.replay(events, configuration: configuration))
        let second = expectSuccess(MatchReplayer.replay(events, configuration: configuration))

        #expect(first == second)
    }

    @Test func duplicateEventRejectedOnSubmit() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        let event = pointEvent(.teamA)

        #expect(engine.submit(event).isSuccess)
        expectFailure(engine.submit(event), .duplicateEventID)
    }

    @Test func duplicateEventToleratedIdempotentlyOnReplay() throws {
        let configuration = try MatchConfiguration()
        let event = pointEvent(.teamA)
        let events = [event, event]

        guard let state = expectSuccess(
            MatchReplayer.replay(events, configuration: configuration)
        ) else {
            return
        }

        let expectedScore = GameScore(
            points: TeamPair(teamA: 1, teamB: 0)
        )
        #expect(state.currentPhase == .game(expectedScore))
    }

    @Test func invalidSequenceRejectionOnSubmit() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())

        expectFailure(engine.submit(undoEvent(EventID())), .undoTargetNotFound)

        submitAll(gameWinners(Array(repeating: Team.teamA, count: 12)), to: &engine)
        #expect(engine.state.matchWinner == .teamA)

        expectFailure(engine.submit(pointEvent(.teamB)), .matchAlreadyDecided)
    }

    @Test func restorationThroughReplay() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(gameWinners([.teamA, .teamB, .teamA]), to: &engine)

        let restored = try MatchEngine(configuration: engine.configuration, events: engine.events)

        #expect(restored.state == engine.state)
        #expect(restored.events == engine.events)
    }

    @Test func eventAfterTerminalFinishRejectedOnSubmit() throws {
        var engine = MatchEngine(configuration: try MatchConfiguration())
        submitAll(gameWinners(Array(repeating: Team.teamA, count: 12)), to: &engine)
        let winningPointID = engine.events.last!.id

        #expect(expectSuccess(engine.submit(finishEvent())) != nil)

        expectFailure(engine.submit(pointEvent(.teamA)), .matchAlreadyFinished)
        expectFailure(engine.submit(undoEvent(winningPointID)), .matchAlreadyFinished)
        expectFailure(engine.submit(finishEvent()), .matchAlreadyFinished)
    }

    @Test func replayFailsOnDistinctEventAfterFinish() throws {
        let configuration = try MatchConfiguration()
        var events = gameWinners(Array(repeating: Team.teamA, count: 12))
        events.append(finishEvent())
        events.append(pointEvent(.teamB))

        expectFailure(MatchReplayer.replay(events, configuration: configuration), .matchAlreadyFinished)
    }

    @Test func replayToleratesDuplicateFinishAfterFinish() throws {
        let configuration = try MatchConfiguration()
        var events = gameWinners(Array(repeating: Team.teamA, count: 12))
        let finish = finishEvent()
        events.append(finish)
        events.append(finish)

        guard let state = expectSuccess(MatchReplayer.replay(events, configuration: configuration)) else {
            return
        }

        #expect(state.isTerminal == true)
        #expect(state.matchWinner == .teamA)
    }

    @Test func replayFailsOnUndoTargetNotFound() throws {
        let configuration = try MatchConfiguration()
        let events: [ScoringEvent] = [undoEvent(EventID())]

        expectFailure(MatchReplayer.replay(events, configuration: configuration), .undoTargetNotFound)
    }

    @Test func replayFailsOnUndoTargetAlreadyUndone() throws {
        let configuration = try MatchConfiguration()
        let point = pointEvent(.teamA)
        let events: [ScoringEvent] = [
            point,
            undoEvent(point.id),
            undoEvent(point.id),
        ]

        expectFailure(
            MatchReplayer.replay(events, configuration: configuration),
            .undoTargetAlreadyUndone
        )
    }

    @Test func replayFailsOnUndoTargetNotMostRecent() throws {
        let configuration = try MatchConfiguration()
        let firstPoint = pointEvent(.teamA)
        let secondPoint = pointEvent(.teamB)
        let events: [ScoringEvent] = [
            firstPoint,
            secondPoint,
            undoEvent(firstPoint.id),
        ]

        expectFailure(
            MatchReplayer.replay(events, configuration: configuration),
            .undoTargetNotMostRecent
        )
    }

    @Test func replayFailsOnPointAfterMatchDecided() throws {
        let configuration = try MatchConfiguration()
        var events = gameWinners(Array(repeating: Team.teamA, count: 12))
        events.append(pointEvent(.teamB))

        expectFailure(
            MatchReplayer.replay(events, configuration: configuration),
            .matchAlreadyDecided
        )
    }

    @Test func replayFailsOnFinishBeforeMatchDecided() throws {
        let configuration = try MatchConfiguration()
        let events: [ScoringEvent] = [finishEvent()]

        expectFailure(
            MatchReplayer.replay(events, configuration: configuration),
            .matchNotYetDecided
        )
    }

    @Test func replayFailsOnConflictingDuplicateEventID() throws {
        let configuration = try MatchConfiguration()
        let id = EventID()

        let firstEvent = ScoringEvent.pointWon(
            PointWonEvent(id: id, winningTeam: .teamA)
        )
        let conflictingEvent = ScoringEvent.pointWon(
            PointWonEvent(id: id, winningTeam: .teamB)
        )

        expectFailure(
            MatchReplayer.replay(
                [firstEvent, conflictingEvent],
                configuration: configuration
            ),
            .duplicateEventID
        )
    }
}
