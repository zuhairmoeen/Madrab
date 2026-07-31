public enum Team: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case teamA
    case teamB

    public var opponent: Team {
        switch self {
        case .teamA: return .teamB
        case .teamB: return .teamA
        }
    }
}
