import Testing

import MadrabScoringEngine

func pointEvent(_ team: Team) -> ScoringEvent {
    .pointWon(PointWonEvent(winningTeam: team))
}

func undoEvent(_ targetEventID: EventID) -> ScoringEvent {
    .undo(UndoEvent(targetEventID: targetEventID))
}

func finishEvent() -> ScoringEvent {
    .finishMatch(FinishMatchEvent())
}

/// `count` straight points won by `team` — a fast, deterministic way to win
/// games without deuce complications when a test only cares about a later stage.
func straightPoints(_ team: Team, count: Int) -> [ScoringEvent] {
    (0..<count).map { _ in pointEvent(team) }
}

/// Each entry wins one whole game (4 straight points) for that team, in order.
func gameWinners(_ winners: [Team]) -> [ScoringEvent] {
    winners.flatMap { straightPoints($0, count: 4) }
}

/// Submits every event in order, returning the result of the *last* submission.
@discardableResult
func submitAll(_ events: [ScoringEvent], to engine: inout MatchEngine) -> Result<MatchState, MatchError> {
    var last: Result<MatchState, MatchError> = .success(engine.state)
    for event in events {
        last = engine.submit(event)
    }
    return last
}

extension Result {
    var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}

func expectFailure(
    _ result: Result<MatchState, MatchError>,
    _ expected: MatchError,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    switch result {
    case .failure(let error):
        #expect(error == expected, sourceLocation: sourceLocation)

    case .success:
        Issue.record(
            "expected failure \(expected) but got success",
            sourceLocation: sourceLocation
        )
    }
}

@discardableResult
func expectSuccess(
    _ result: Result<MatchState, MatchError>,
    sourceLocation: SourceLocation = #_sourceLocation
) -> MatchState? {
    switch result {
    case .success(let state):
        return state
    case .failure(let error):
        Issue.record(
            "expected success but got failure \(error)",
            sourceLocation: sourceLocation
        )
        return nil
    }
}
