/// Raw in-game points won by each team so far, before any deuce/advantage/
/// golden-point interpretation is applied.
public struct GameScore: Sendable, Equatable, Hashable {
    public let points: TeamPair<Int>

    public static let initial = GameScore(points: TeamPair(both: 0))

    public init(points: TeamPair<Int>) {
        self.points = points
    }

    public func applyingPoint(wonBy team: Team) -> GameScore {
        var points = self.points
        points[team] += 1
        return GameScore(points: points)
    }

    /// The team that has won the game at this score, if any, per `deuceRule`.
    public func winner(deuceRule: DeuceRule) -> Team? {
        let requiredMargin = deuceRule == .goldenPoint ? 1 : 2
        for team in Team.allCases {
            let mine = points[team]
            let theirs = points[team.opponent]
            if mine >= 4 && mine - theirs >= requiredMargin {
                return team
            }
        }
        return nil
    }
}
