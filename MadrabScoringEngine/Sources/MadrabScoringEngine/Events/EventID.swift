import Foundation

/// Unique identifier for a `ScoringEvent`. Order is never derived from this —
/// only from an event's position in the caller-supplied array.
public struct EventID: Hashable, Sendable, Codable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
