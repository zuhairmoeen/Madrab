/// A player's position within a team's own pairing. Milestone 1 has no player
/// identity/profile model — only which of a team's two slots is serving.
public enum TeamPlayer: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case first
    case second

    public var other: TeamPlayer {
        switch self {
        case .first: return .second
        case .second: return .first
        }
    }
}
