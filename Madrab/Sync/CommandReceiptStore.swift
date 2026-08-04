import Foundation

enum CommandReceiptStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

protocol CommandReceipting {
    func contains(matchID: UUID, commandID: UUID) throws -> Bool
    func promote(matchID: UUID, commandIDs: Set<UUID>) throws
}

/// Small, bounded, durable record of which Watch commands have already been
/// accepted for a match — including a match that has since finished or been
/// discarded and whose `active-match.json` has been cleared. Retains at most
/// `maxRetainedMatches` matches, oldest evicted first.
struct CommandReceiptStore: CommandReceipting {
    static let maxRetainedMatches = 20

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.resolveDefaultFileURL()
    }

    func contains(matchID: UUID, commandID: UUID) throws -> Bool {
        let file = try loadFile()
        return file.receiptsByMatchID[matchID]?.contains(commandID) ?? false
    }

    /// Idempotent: unions `commandIDs` into whatever set already exists for
    /// `matchID` rather than overwriting it, so calling this again after a
    /// crash/retry — with the same or a larger set — never loses a
    /// previously-recorded receipt. An empty `commandIDs` is a no-op before
    /// any file I/O happens at all — it neither creates a file nor touches
    /// `matchOrder`/pruning. `matchID` is appended to `matchOrder` only the
    /// first time it's seen; once more than `maxRetainedMatches` distinct
    /// matches are tracked, the oldest is evicted from both `matchOrder` and
    /// `receiptsByMatchID` together.
    func promote(matchID: UUID, commandIDs: Set<UUID>) throws {
        guard !commandIDs.isEmpty else { return }

        var file = try loadFile()

        let existing = file.receiptsByMatchID[matchID] ?? []
        file.receiptsByMatchID[matchID] = existing.union(commandIDs)

        if !file.matchOrder.contains(matchID) {
            file.matchOrder.append(matchID)
        }

        while file.matchOrder.count > Self.maxRetainedMatches {
            let oldest = file.matchOrder.removeFirst()
            file.receiptsByMatchID.removeValue(forKey: oldest)
        }

        try save(file)
    }

    /// A missing file is a valid empty store (first launch, no receipts yet).
    /// Any other read/decode failure — corrupt JSON, or a schema version
    /// this build doesn't recognize — propagates as a thrown error rather
    /// than being silently treated as empty, since silently discarding a
    /// receipt could let a duplicate command through undetected.
    private func loadFile() throws -> CommandReceiptFile {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return CommandReceiptFile()
        }
        let data = try Data(contentsOf: fileURL)
        let file = try JSONDecoder().decode(CommandReceiptFile.self, from: data)
        guard file.schemaVersion == CommandReceiptFile.currentSchemaVersion else {
            throw CommandReceiptStoreError.unsupportedSchemaVersion(file.schemaVersion)
        }
        return file
    }

    private func save(_ file: CommandReceiptFile) throws {
        let data = try JSONEncoder().encode(file)
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func resolveDefaultFileURL() -> URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Madrab", isDirectory: true)
            .appendingPathComponent("command-receipts.json")
    }
}
