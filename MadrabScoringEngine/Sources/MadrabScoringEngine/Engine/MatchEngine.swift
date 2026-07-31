/// Stateful convenience wrapper around the event log for live scoring.
/// Event history remains the source of truth — `submit` never patches
/// `state` in place; it always re-derives it via `MatchReplayer.replay`.
/// Correctness over optimization for Milestone 1: a full replay per
/// submission is acceptable at padel-match event-log sizes.
public struct MatchEngine: Sendable {
    public let configuration: MatchConfiguration
    public private(set) var events: [ScoringEvent]
    public private(set) var state: MatchState

    /// Starts a brand-new match with no history.
    public init(configuration: MatchConfiguration) {
        self.configuration = configuration
        self.events = []
        self.state = ScoreBuilder.score(for: [], configuration: configuration, isTerminal: false)
    }

    /// Restores a match purely by replaying a previously persisted log.
    /// Throws the exact `MatchError` if that history turns out to be invalid
    /// (for example, a distinct event stored after an effective `FinishMatch`).
    public init(configuration: MatchConfiguration, events: [ScoringEvent]) throws(MatchError) {
        self.configuration = configuration
        switch MatchReplayer.replay(events, configuration: configuration) {
        case .success(let state):
            self.events = events
            self.state = state
        case .failure(let error):
            throw error
        }
    }

    /// Submits a single new event. Rejects any reused `EventID` outright —
    /// even if its content is identical to what's already stored — since
    /// live submission never tolerates re-delivery the way whole-log replay
    /// of a persisted history does. Otherwise, re-derives state by replaying
    /// the full candidate history; on success the new event and state are
    /// kept, on failure the engine is left completely unchanged.
    @discardableResult
    public mutating func submit(
        _ event: ScoringEvent
    ) -> Result<MatchState, MatchError> {
        guard !events.contains(where: { $0.id == event.id }) else {
            return .failure(.duplicateEventID)
        }

        let candidateHistory = events + [event]

        switch MatchReplayer.replay(
            candidateHistory,
            configuration: configuration
        ) {
        case .success(let newState):
            events = candidateHistory
            state = newState
            return .success(newState)

        case .failure(let error):
            return .failure(error)
        }
    }
}
