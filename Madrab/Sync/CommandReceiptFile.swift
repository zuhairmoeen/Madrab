import Foundation

/// On-disk shape of the durable command-receipt ledger. Holds no scoring
/// state — only which (matchID, commandID) pairs have already been accepted
/// — so it can never become a second authority over match state.
nonisolated struct CommandReceiptFile: Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion = 1
    var receiptsByMatchID: [UUID: Set<UUID>] = [:]
    /// Insertion order, oldest first. Drives bounded pruning.
    var matchOrder: [UUID] = []
}
