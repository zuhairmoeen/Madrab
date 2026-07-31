/// Small per-team storage reused for raw points, games won, sets won, and
/// tiebreak points instead of hand-rolling the same two-field shape repeatedly.
public struct TeamPair<Value: Sendable & Equatable>: Sendable, Equatable {
    public var teamA: Value
    public var teamB: Value

    public init(teamA: Value, teamB: Value) {
        self.teamA = teamA
        self.teamB = teamB
    }

    public init(both value: Value) {
        self.teamA = value
        self.teamB = value
    }

    public subscript(team: Team) -> Value {
        get {
            switch team {
            case .teamA: return teamA
            case .teamB: return teamB
            }
        }
        set {
            switch team {
            case .teamA: teamA = newValue
            case .teamB: teamB = newValue
            }
        }
    }
}

extension TeamPair: Hashable where Value: Hashable {}
extension TeamPair: Codable where Value: Codable {}
