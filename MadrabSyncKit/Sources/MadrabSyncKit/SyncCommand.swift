import Foundation
import MadrabScoringEngine

/// A command sent from the Watch to the iPhone. The iPhone is the sole
/// scoring authority: this type only ever describes a request, never an
/// applied state change.
public struct SyncCommand: Codable, Equatable, Sendable {
    /// Required for `.recordPoint`/`.undo`. Advisory/ignored for
    /// `.requestLatestState`, so a Watch with no known match can still ask
    /// what the current truth is.
    public let matchID: UUID?
    public let commandID: UUID
    /// Ignored for `.requestLatestState`.
    public let expectedStateRevision: Int
    public let kind: SyncCommandKind
    public let sentAt: Date?

    public init(
        matchID: UUID?,
        commandID: UUID,
        expectedStateRevision: Int,
        kind: SyncCommandKind,
        sentAt: Date? = nil
    ) {
        self.matchID = matchID
        self.commandID = commandID
        self.expectedStateRevision = expectedStateRevision
        self.kind = kind
        self.sentAt = sentAt
    }
}

public enum SyncCommandKind: Codable, Equatable, Sendable {
    case recordPoint(Team)
    case undo
    case requestLatestState
}
