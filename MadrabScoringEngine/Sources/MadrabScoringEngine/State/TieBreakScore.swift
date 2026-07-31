/// Raw points won by each team within a tie-break (standard set tie-break or
/// final-set match tie-break — both share this shape, only the target differs).
public struct TieBreakScore: Sendable, Equatable, Hashable {
    public let points: TeamPair<Int>

    public static let initial = TieBreakScore(points: TeamPair(both: 0))

    public init(points: TeamPair<Int>) {
        self.points = points
    }

    public func applyingPoint(wonBy team: Team) -> TieBreakScore {
        var points = self.points
        points[team] += 1
        return TieBreakScore(points: points)
    }

    /// The team that has won the tie-break at this score, if any. Always
    /// win-by-two and uncapped — reaching `targetPoints` alone is not enough.
    public func winner(targetPoints: Int) -> Team? {
        for team in Team.allCases {
            let mine = points[team]
            let theirs = points[team.opponent]
            if mine >= targetPoints && mine - theirs >= 2 {
                return team
            }
        }
        return nil
    }
}
