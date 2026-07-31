/// A single immutable scoring event. Event history — an ordered `[ScoringEvent]`
/// array — is the source of truth; match state is always derived by replaying it.
/// No event carries a timestamp: order is purely array position.
///
/// `Codable` so a match's event log can be persisted and later restored
/// deterministically via `MatchReplayer.replay`/`MatchEngine.init(configuration:events:)`.
public enum ScoringEvent: Sendable, Equatable, Codable {
    case pointWon(PointWonEvent)
    case undo(UndoEvent)
    case finishMatch(FinishMatchEvent)

    public var id: EventID {
        switch self {
        case .pointWon(let event): return event.id
        case .undo(let event): return event.id
        case .finishMatch(let event): return event.id
        }
    }
}

/// A team won a single point.
public struct PointWonEvent: Sendable, Equatable, Codable {
    public let id: EventID
    public let winningTeam: Team

    public init(id: EventID = EventID(), winningTeam: Team) {
        self.id = id
        self.winningTeam = winningTeam
    }
}

/// Reverses the exact effective scoring event it names. Only ever effective
/// against the single most recent effective point — arbitrary historical undo
/// is not supported.
public struct UndoEvent: Sendable, Equatable, Codable {
    public let id: EventID
    public let targetEventID: EventID

    public init(id: EventID = EventID(), targetEventID: EventID) {
        self.id = id
        self.targetEventID = targetEventID
    }
}

/// Explicitly closes the match log. Valid only once a match winner has been
/// decided; once effective, the log becomes terminal and rejects every
/// subsequent distinct event.
public struct FinishMatchEvent: Sendable, Equatable, Codable {
    public let id: EventID

    public init(id: EventID = EventID()) {
        self.id = id
    }
}
