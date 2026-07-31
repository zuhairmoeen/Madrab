/// Bookkeeping folded across an event log. Not itself the source of truth —
/// it's rebuilt from scratch by every `replay` call and never persisted;
/// "effectiveness" is a structural property of the fold, not a stored flag
/// on any event.
struct ReplayAccumulator: Equatable {
    /// Every event accepted so far, keyed by ID, with its full content — so a
    /// later event reusing an ID can be checked for exact equality (an
    /// idempotent re-delivery) rather than just presence.
    var seenEvents: [EventID: ScoringEvent] = [:]
    /// Currently-effective, non-undone points, in the order they were applied.
    var effectivePointStack: [PointWonEvent] = []
    /// Every point ID ever effectively applied, whether still on the stack or
    /// since undone. Lets `evaluate` distinguish "never existed" from
    /// "already undone" from "real but not most recent".
    var allEffectivePointIDs: Set<EventID> = []
    var undoneEventIDs: Set<EventID> = []
    var isTerminal = false

    static let empty = ReplayAccumulator()

    func matchWinner(configuration: MatchConfiguration) -> Team? {
        ScoreBuilder.score(
            for: effectivePointStack.map(\.winningTeam),
            configuration: configuration,
            isTerminal: isTerminal
        ).matchWinner
    }
}

enum EventOutcome {
    case effective(ReplayAccumulator)
    /// The exact same event (same ID *and* same content) was already applied.
    /// The only outcome `replay` tolerates as a no-op; `submit` still rejects it.
    case duplicate
    case ineffective(MatchError)
}

/// Replays event history against `MatchConfiguration` to derive `MatchState`.
/// Event history is the source of truth; this type never stores anything —
/// every call recomputes state from scratch.
public enum MatchReplayer {
    /// Decides whether a single event is effective against the accumulator
    /// built from everything before it. Shared by `replay`'s fold and
    /// `MatchEngine.submit` so acceptance rules are defined exactly once.
    static func evaluate(
        _ event: ScoringEvent,
        in accumulator: ReplayAccumulator,
        configuration: MatchConfiguration
    ) -> EventOutcome {
        if let existing = accumulator.seenEvents[event.id] {
            return existing == event ? .duplicate : .ineffective(.duplicateEventID)
        }
        if accumulator.isTerminal {
            return .ineffective(.matchAlreadyFinished)
        }

        switch event {
        case .pointWon(let point):
            guard accumulator.matchWinner(configuration: configuration) == nil else {
                return .ineffective(.matchAlreadyDecided)
            }
            var next = accumulator
            next.seenEvents[event.id] = event
            next.effectivePointStack.append(point)
            next.allEffectivePointIDs.insert(point.id)
            return .effective(next)

        case .undo(let undo):
            if let top = accumulator.effectivePointStack.last, top.id == undo.targetEventID {
                var next = accumulator
                next.seenEvents[event.id] = event
                next.effectivePointStack.removeLast()
                next.undoneEventIDs.insert(top.id)
                return .effective(next)
            }
            if accumulator.undoneEventIDs.contains(undo.targetEventID) {
                return .ineffective(.undoTargetAlreadyUndone)
            }
            if accumulator.allEffectivePointIDs.contains(undo.targetEventID) {
                return .ineffective(.undoTargetNotMostRecent)
            }
            return .ineffective(.undoTargetNotFound)

        case .finishMatch:
            guard accumulator.matchWinner(configuration: configuration) != nil else {
                return .ineffective(.matchNotYetDecided)
            }
            var next = accumulator
            next.seenEvents[event.id] = event
            next.isTerminal = true
            return .effective(next)
        }
    }

    /// Pure, whole-array replay. A persisted history is expected to be
    /// entirely valid: the only thing tolerated as a no-op is the exact same
    /// event (same ID *and* identical content) appearing again, which can
    /// legitimately happen under at-least-once delivery. Every other invalid
    /// event — a reused ID with different content, an out-of-place undo, a
    /// point/finish submitted at the wrong time, or any distinct event after
    /// an effective `FinishMatch` — fails the whole replay with the specific
    /// `MatchError` that made it invalid, rather than silently dropping it.
    public static func replay(
        _ events: [ScoringEvent],
        configuration: MatchConfiguration
    ) -> Result<MatchState, MatchError> {
        var accumulator = ReplayAccumulator.empty

        for event in events {
            switch evaluate(event, in: accumulator, configuration: configuration) {
            case .effective(let next):
                accumulator = next
            case .duplicate:
                continue
            case .ineffective(let reason):
                return .failure(reason)
            }
        }

        let state = ScoreBuilder.score(
            for: accumulator.effectivePointStack.map(\.winningTeam),
            configuration: configuration,
            isTerminal: accumulator.isTerminal
        )
        return .success(state)
    }
}
