/// Standard tennis/padel point label: love, 15, 30, or 40, capped at 40 (a
/// value of 3+ raw points displays as 40 regardless of magnitude).
public enum RawPoint: Int, Sendable, Equatable, Hashable, CaseIterable {
    case love = 0
    case fifteen = 1
    case thirty = 2
    case forty = 3

    public init(clamping value: Int) {
        self = RawPoint(rawValue: min(max(value, 0), 3)) ?? .love
    }
}

/// Human-readable derived label for a `GameScore`, computed fresh from the raw
/// points and the match's `DeuceRule` — never stored independently.
public enum GamePointLabel: Sendable, Equatable, Hashable {
    case raw(TeamPair<RawPoint>)
    case deuce
    case advantage(Team)
    case goldenPoint

    public init(score: GameScore, deuceRule: DeuceRule) {
        let a = score.points.teamA
        let b = score.points.teamB

        guard a >= 3, b >= 3 else {
            self = .raw(TeamPair(teamA: RawPoint(clamping: a), teamB: RawPoint(clamping: b)))
            return
        }

        switch deuceRule {
        case .goldenPoint:
            self = .goldenPoint
        case .advantage:
            if a == b {
                self = .deuce
            } else {
                self = .advantage(a > b ? .teamA : .teamB)
            }
        }
    }
}
