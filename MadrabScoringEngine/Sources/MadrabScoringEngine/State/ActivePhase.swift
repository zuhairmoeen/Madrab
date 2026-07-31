/// What kind of point-counting is currently active for the in-progress set.
/// `nil` on `MatchState.currentPhase` once the match is decided — there is
/// nothing left to play.
public enum ActivePhase: Sendable, Equatable {
    case game(GameScore)
    case setTieBreak(TieBreakScore)
    case matchTieBreak(TieBreakScore)
}
