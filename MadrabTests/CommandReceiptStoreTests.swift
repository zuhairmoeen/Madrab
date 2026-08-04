import Testing
import Foundation
@testable import Madrab

struct CommandReceiptStoreTests {
    private func makeTemporaryFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("command-receipts.json")
    }

    @Test func missingFileIsTreatedAsEmptyStore() throws {
        let store = CommandReceiptStore(fileURL: makeTemporaryFileURL())
        #expect(try store.contains(matchID: UUID(), commandID: UUID()) == false)
    }

    @Test func containsBeforeAndAfterPromotion() throws {
        let store = CommandReceiptStore(fileURL: makeTemporaryFileURL())
        let matchID = UUID()
        let commandID = UUID()

        #expect(try store.contains(matchID: matchID, commandID: commandID) == false)

        try store.promote(matchID: matchID, commandIDs: [commandID])

        #expect(try store.contains(matchID: matchID, commandID: commandID) == true)
    }

    @Test func receiptsPersistAcrossANewStoreInstance() throws {
        let fileURL = makeTemporaryFileURL()
        let matchID = UUID()
        let commandID = UUID()

        try CommandReceiptStore(fileURL: fileURL).promote(matchID: matchID, commandIDs: [commandID])

        let reopened = CommandReceiptStore(fileURL: fileURL)
        #expect(try reopened.contains(matchID: matchID, commandID: commandID) == true)
    }

    @Test func repeatedPromotionIsIdempotent() throws {
        let fileURL = makeTemporaryFileURL()
        let store = CommandReceiptStore(fileURL: fileURL)
        let matchID = UUID()
        let commandID = UUID()

        try store.promote(matchID: matchID, commandIDs: [commandID])
        try store.promote(matchID: matchID, commandIDs: [commandID])
        try store.promote(matchID: matchID, commandIDs: [commandID])

        let data = try Data(contentsOf: fileURL)
        let file = try JSONDecoder().decode(CommandReceiptFile.self, from: data)

        #expect(file.matchOrder == [matchID])
        #expect(file.receiptsByMatchID[matchID] == [commandID])
    }

    @Test func promotionWithAdditionalIDsUnionsTheSets() throws {
        let store = CommandReceiptStore(fileURL: makeTemporaryFileURL())
        let matchID = UUID()
        let first = UUID()
        let second = UUID()

        try store.promote(matchID: matchID, commandIDs: [first])
        try store.promote(matchID: matchID, commandIDs: [second])

        #expect(try store.contains(matchID: matchID, commandID: first) == true)
        #expect(try store.contains(matchID: matchID, commandID: second) == true)
    }

    @Test func pruningRetainsAtMost20Matches() throws {
        let fileURL = makeTemporaryFileURL()
        let store = CommandReceiptStore(fileURL: fileURL)
        let matchIDs = (0..<21).map { _ in UUID() }

        for matchID in matchIDs {
            try store.promote(matchID: matchID, commandIDs: [UUID()])
        }

        let data = try Data(contentsOf: fileURL)
        let file = try JSONDecoder().decode(CommandReceiptFile.self, from: data)

        #expect(file.matchOrder.count == CommandReceiptStore.maxRetainedMatches)
        #expect(file.receiptsByMatchID.count == CommandReceiptStore.maxRetainedMatches)
    }

    @Test func pruningRemovesBothOrderAndReceiptData() throws {
        let fileURL = makeTemporaryFileURL()
        let store = CommandReceiptStore(fileURL: fileURL)
        let entries = (0..<21).map { _ in (matchID: UUID(), commandID: UUID()) }

        for entry in entries {
            try store.promote(matchID: entry.matchID, commandIDs: [entry.commandID])
        }

        let data = try Data(contentsOf: fileURL)
        let file = try JSONDecoder().decode(CommandReceiptFile.self, from: data)

        let oldest = entries[0].matchID
        #expect(!file.matchOrder.contains(oldest))
        #expect(file.receiptsByMatchID[oldest] == nil)

        let stillRetained = entries[1]
        let newest = entries[20]
        #expect(file.receiptsByMatchID[stillRetained.matchID]?.contains(stillRetained.commandID) == true)
        #expect(file.receiptsByMatchID[newest.matchID]?.contains(newest.commandID) == true)
    }

    @Test func corruptJSONThrows() throws {
        let fileURL = makeTemporaryFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not valid json".utf8).write(to: fileURL)

        let store = CommandReceiptStore(fileURL: fileURL)

        do {
            _ = try store.contains(matchID: UUID(), commandID: UUID())
            Issue.record("expected corrupt JSON to throw")
        } catch {
            // Propagated, as required.
        }
    }

    @Test func unsupportedSchemaVersionThrows() throws {
        let fileURL = makeTemporaryFileURL()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var file = CommandReceiptFile()
        file.schemaVersion = CommandReceiptFile.currentSchemaVersion + 1
        try JSONEncoder().encode(file).write(to: fileURL)

        let store = CommandReceiptStore(fileURL: fileURL)

        do {
            _ = try store.contains(matchID: UUID(), commandID: UUID())
            Issue.record("expected unsupported schemaVersion to throw")
        } catch let error as CommandReceiptStoreError {
            #expect(error == .unsupportedSchemaVersion(CommandReceiptFile.currentSchemaVersion + 1))
        }
    }

    @Test func emptyCommandIDPromotionBehavesSafely() throws {
        let fileURL = makeTemporaryFileURL()
        let store = CommandReceiptStore(fileURL: fileURL)
        let matchID = UUID()

        try store.promote(matchID: matchID, commandIDs: [])

        #expect(try store.contains(matchID: matchID, commandID: UUID()) == false)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }
}
