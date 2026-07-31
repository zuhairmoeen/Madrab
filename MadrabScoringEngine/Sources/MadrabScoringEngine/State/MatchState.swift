/// Top-level derived match state. Always produced fresh by replaying the
/// event log — never mutated in place, never itself the source of truth.
public struct MatchState: Sendable, Equatable {
    /// Completed sets, in order.
    public let sets: [SetScore]
    /// The in-progress set's games (and tie-break, if one is active).
    /// `nil` when the deciding set has been replaced by a final match
    /// tie-break (`FinalSetMode.matchTiebreak`) — that "set" is never played
    /// as games, so its only visible progress is `currentPhase.matchTieBreak(_)`.
    /// Also `nil` once the match is decided.
    public let currentSet: SetScore?
    /// What's currently being played: raw game points, a set tie-break's
    /// points, or a match tie-break's points. `nil` once the match is decided.
    public let currentPhase: ActivePhase?
    public let setsWon: TeamPair<Int>
    public let servingTeam: Team
    /// `nil` unless `MatchConfiguration.servingPlayerTrackingEnabled` is true.
    public let servingPlayer: ServingPlayer?
    /// Non-nil once a team has won enough sets, independent of whether the
    /// log has been formally closed with `FinishMatch`.
    public let matchWinner: Team?
    /// True only once a `FinishMatch` event has been effectively applied.
    public let isTerminal: Bool

    public init(
        sets: [SetScore],
        currentSet: SetScore?,
        currentPhase: ActivePhase?,
        setsWon: TeamPair<Int>,
        servingTeam: Team,
        servingPlayer: ServingPlayer?,
        matchWinner: Team?,
        isTerminal: Bool
    ) {
        self.sets = sets
        self.currentSet = currentSet
        self.currentPhase = currentPhase
        self.setsWon = setsWon
        self.servingTeam = servingTeam
        self.servingPlayer = servingPlayer
        self.matchWinner = matchWinner
        self.isTerminal = isTerminal
    }
}
