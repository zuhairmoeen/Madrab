import Foundation

/// The iPhone's reply to a `SyncCommand`. A bare `SyncSnapshot` reply is
/// insufficient because the Watch can't distinguish why a command did or
/// didn't change anything — this drives Watch haptics, error messaging,
/// and reconciliation.
public struct SyncCommandResponse: Codable, Equatable, Sendable {
    public let commandID: UUID
    public let outcome: SyncCommandOutcome
    public let snapshot: SyncSnapshot

    public init(commandID: UUID, outcome: SyncCommandOutcome, snapshot: SyncSnapshot) {
        self.commandID = commandID
        self.outcome = outcome
        self.snapshot = snapshot
    }
}

public enum SyncCommandOutcome: Codable, Equatable, Sendable {
    case accepted
    case alreadyApplied
    case rejected(SyncRejectionReason)
}

public enum SyncRejectionReason: Codable, Equatable, Sendable {
    case malformedCommand
    case wrongMatch
    case noLiveMatch
    case staleRevision
    case matchFinished
    case invalidUndo
    case persistenceFailed
}
