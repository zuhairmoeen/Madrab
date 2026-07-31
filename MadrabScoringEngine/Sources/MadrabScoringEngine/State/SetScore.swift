/// A completed or in-progress set: games won by each team, the tie-break that
/// decided it (if any), and its winner once decided.
public struct SetScore: Sendable, Equatable, Hashable {
    public let games: TeamPair<Int>
    public let tieBreak: TieBreakScore?
    public let winner: Team?

    public init(games: TeamPair<Int>, tieBreak: TieBreakScore? = nil, winner: Team? = nil) {
        self.games = games
        self.tieBreak = tieBreak
        self.winner = winner
    }
}
