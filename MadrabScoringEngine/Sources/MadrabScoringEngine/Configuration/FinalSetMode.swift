/// Configurable behavior for the deciding (final) set of the match.
public enum FinalSetMode: Sendable, Equatable, Hashable, Codable {
    /// The final set is played as a full set, including a standard tie-break at 6-6.
    case fullSet
    /// The final set is replaced entirely by a single match tie-break (a "super
    /// tie-break") played to the given number of points, win by two.
    case matchTiebreak(points: Int)
}
