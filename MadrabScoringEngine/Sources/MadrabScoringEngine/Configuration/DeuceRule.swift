/// Match-wide rule for what happens once a game reaches 40-40 ("deuce" points).
/// Applies to games only — tie-breaks always continue win-by-two regardless of
/// this setting.
public enum DeuceRule: Sendable, Equatable, Hashable, Codable {
    /// Standard advantage scoring: a 2-point lead is required to win the game.
    case advantage
    /// Sudden death: the next point after 40-40 wins the game outright.
    case goldenPoint
}
