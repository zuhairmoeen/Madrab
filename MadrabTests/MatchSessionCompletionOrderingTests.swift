import Testing
import Foundation
@testable import Madrab
import MadrabScoringEngine
import MadrabSyncKit

/// Shared ordered record of the side effects a completion or discard runs,
/// so tests can prove the sequence, not merely that each step happened.
private final class CallLog {
    private(set) var calls: [String] = []

    func record(_ name: String) {
        calls.append(name)
    }
}

private struct FakeFailure: Error {}

/// Result recorder double. Records its invocation in the shared log and can
/// be told to fail, so a leaderboard failure can be observed in isolation.
private final class OrderedFakeResultRecorder: MatchResultRecording {
    let log: CallLog
    var shouldThrow = false
    private(set) var recordedMatchIDs: [UUID] = []

    init(log: CallLog) {
        self.log = log
    }

    func recordCompletedMatch(matchID: UUID, winnerProfileID: UUID, loserProfileID: UUID) throws {
        log.record("recorder")
        if shouldThrow { throw FakeFailure() }
        recordedMatchIDs.append(matchID)
    }
}

/// Receipt-store double that separates *attempted* promotions from
/// *successful* ones, so a retry after a thrown attempt can be shown to
/// commit exactly once.
private final class OrderedFakeReceiptStore: CommandReceipting {
    struct Key: Hashable {
        let matchID: UUID
        let commandID: UUID
    }

    let log: CallLog
    var shouldThrowOnPromote = false
    var shouldThrowOnContains = false
    private(set) var receipts: Set<Key> = []
    private(set) var promotionAttempts: [(matchID: UUID, commandIDs: Set<UUID>)] = []
    private(set) var successfulPromotions: [(matchID: UUID, commandIDs: Set<UUID>)] = []

    init(log: CallLog) {
        self.log = log
    }

    func contains(matchID: UUID, commandID: UUID) throws -> Bool {
        if shouldThrowOnContains { throw FakeFailure() }
        return receipts.contains(Key(matchID: matchID, commandID: commandID))
    }

    func promote(matchID: UUID, commandIDs: Set<UUID>) throws {
        log.record("promote")
        promotionAttempts.append((matchID, commandIDs))
        if shouldThrowOnPromote { throw FakeFailure() }
        successfulPromotions.append((matchID, commandIDs))
        for commandID in commandIDs {
            receipts.insert(Key(matchID: matchID, commandID: commandID))
        }
    }
}

@MainActor
struct MatchSessionCompletionOrderingTests {

    // MARK: - Helpers

    private func makeTemporaryFileURL(name: String = "active-match.json") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
    }

    /// A file occupying the parent path forces every save beneath it to throw
    /// when it tries to create that directory.
    private func makeUnwritableFileURL(name: String = "active-match.json") throws -> URL {
        let blocked = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try Data().write(to: blocked)
        return blocked.appendingPathComponent(name)
    }

    private func winningConfiguration() throws -> MatchConfiguration {
        try MatchConfiguration(setsToWin: 1, gamesToWinSet: 2, finalSetMode: .fullSet)
    }

    @discardableResult
    private func startLinkedMatch(
        on session: MatchSessionViewModel,
        configuration: MatchConfiguration
    ) -> Bool {
        session.startMatch(
            configuration: configuration,
            teamAProfile: PlayerProfile(displayName: "Alex"),
            teamBProfile: PlayerProfile(displayName: "Sam")
        )
    }

    private func winMatch(for team: Team, on session: MatchSessionViewModel) {
        for _ in 0..<2 {
            for _ in 0..<4 {
                session.recordPoint(for: team)
            }
        }
    }

    /// Applies one accepted remote command so the session holds a command
    /// receipt that completion or discard must promote.
    @discardableResult
    private func applyOneRemoteCommand(on session: MatchSessionViewModel) -> UUID {
        let commandID = UUID()
        let snapshot = session.currentSnapshot()
        _ = session.applyRemoteCommand(
            SyncCommand(
                matchID: snapshot.matchID,
                commandID: commandID,
                expectedStateRevision: snapshot.stateRevision,
                kind: .recordPoint(.teamA)
            )
        )
        return commandID
    }

    // MARK: - FinishMatch persistence gate

    @Test func finishPersistenceFailureDoesNotCallResultRecorder() throws {
        let log = CallLog()
        let recorder = OrderedFakeResultRecorder(log: log)
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: try makeUnwritableFileURL()),
            resultRecorder: recorder,
            commandReceiptStore: OrderedFakeReceiptStore(log: log)
        )
        startLinkedMatch(on: session, configuration: try winningConfiguration())
        winMatch(for: .teamA, on: session)

        session.finishMatch()

        #expect(session.sessionError == .finishPersistenceFailed)
        #expect(recorder.recordedMatchIDs.isEmpty)
        #expect(log.calls.isEmpty)
    }

    @Test func finishPersistenceFailureDoesNotPromoteReceipts() throws {
        let log = CallLog()
        let receipts = OrderedFakeReceiptStore(log: log)
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: try makeUnwritableFileURL()),
            resultRecorder: OrderedFakeResultRecorder(log: log),
            commandReceiptStore: receipts
        )
        startLinkedMatch(on: session, configuration: try winningConfiguration())
        winMatch(for: .teamA, on: session)

        session.finishMatch()

        #expect(session.sessionError == .finishPersistenceFailed)
        #expect(receipts.promotionAttempts.isEmpty)
        #expect(receipts.successfulPromotions.isEmpty)
    }

    @Test func finishPersistenceFailureDoesNotClearTheActiveFile() throws {
        let log = CallLog()
        let fileURL = makeTemporaryFileURL()
        let store = MatchStore(fileURL: fileURL)
        let session = MatchSessionViewModel(
            store: store,
            resultRecorder: OrderedFakeResultRecorder(log: log),
            commandReceiptStore: OrderedFakeReceiptStore(log: log)
        )
        startLinkedMatch(on: session, configuration: try winningConfiguration())
        winMatch(for: .teamA, on: session)
        #expect(store.load() != nil)

        // Block the directory only now, so the match persisted normally first
        // and only the terminal save fails.
        try FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        try Data().write(to: fileURL.deletingLastPathComponent())

        session.finishMatch()

        #expect(session.sessionError == .finishPersistenceFailed)
        #expect(FileManager.default.fileExists(atPath: fileURL.deletingLastPathComponent().path))
    }

    @Test func retryAfterFinishPersistenceFailureSucceeds() throws {
        let log = CallLog()
        let recorder = OrderedFakeResultRecorder(log: log)
        let receipts = OrderedFakeReceiptStore(log: log)
        let fileURL = try makeUnwritableFileURL()
        let store = MatchStore(fileURL: fileURL)
        let session = MatchSessionViewModel(
            store: store,
            resultRecorder: recorder,
            commandReceiptStore: receipts
        )
        startLinkedMatch(on: session, configuration: try winningConfiguration())
        winMatch(for: .teamA, on: session)

        session.finishMatch()
        #expect(session.sessionError == .finishPersistenceFailed)

        // Resolve the underlying problem and retry.
        try FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        session.finishMatch()

        #expect(session.sessionError == nil)
        guard case .finished(let winner) = session.phase else {
            Issue.record("expected the retried finish to reach .finished")
            return
        }
        #expect(winner == .teamA)
        #expect(recorder.recordedMatchIDs.count == 1)
    }

    // MARK: - Completion ordering

    @Test func successfulFinishRecordsThenPromotesThenClears() throws {
        let log = CallLog()
        let recorder = OrderedFakeResultRecorder(log: log)
        let receipts = OrderedFakeReceiptStore(log: log)
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        let session = MatchSessionViewModel(
            store: store,
            resultRecorder: recorder,
            commandReceiptStore: receipts
        )
        startLinkedMatch(on: session, configuration: try winningConfiguration())
        let commandID = applyOneRemoteCommand(on: session)
        winMatch(for: .teamA, on: session)

        session.finishMatch()

        #expect(log.calls == ["recorder", "promote"])
        #expect(receipts.successfulPromotions.count == 1)
        #expect(receipts.successfulPromotions[0].commandIDs.contains(commandID))
        // Clearing is proven to come last: the file is gone only after both
        // side effects succeeded.
        #expect(store.load() == nil)
        #expect(session.sessionError == nil)
    }

    @Test func receiptPromotionFailureKeepsTheTerminalFileAndLedger() throws {
        let log = CallLog()
        let recorder = OrderedFakeResultRecorder(log: log)
        let receipts = OrderedFakeReceiptStore(log: log)
        receipts.shouldThrowOnPromote = true
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        let session = MatchSessionViewModel(
            store: store,
            resultRecorder: recorder,
            commandReceiptStore: receipts
        )
        startLinkedMatch(on: session, configuration: try winningConfiguration())
        let commandID = applyOneRemoteCommand(on: session)
        winMatch(for: .teamA, on: session)

        session.finishMatch()

        #expect(session.sessionError == .activeMatchCleanupFailed)
        #expect(log.calls == ["recorder", "promote"])
        #expect(receipts.promotionAttempts.count == 1)
        #expect(receipts.successfulPromotions.isEmpty)

        // The terminal active file survives, and still carries the ledger.
        let persisted = try #require(store.load())
        #expect(persisted.processedCommandIDs.contains(commandID))
    }

    @Test func leaderboardFailureLeavesTerminalStateRetryable() throws {
        let log = CallLog()
        let recorder = OrderedFakeResultRecorder(log: log)
        recorder.shouldThrow = true
        let receipts = OrderedFakeReceiptStore(log: log)
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        let session = MatchSessionViewModel(
            store: store,
            resultRecorder: recorder,
            commandReceiptStore: receipts
        )
        startLinkedMatch(on: session, configuration: try winningConfiguration())
        let commandID = applyOneRemoteCommand(on: session)
        winMatch(for: .teamA, on: session)

        session.finishMatch()

        #expect(session.sessionError == .pointsRecordingFailed)
        #expect(log.calls == ["recorder"])           // promotion never reached
        #expect(receipts.promotionAttempts.isEmpty)
        let persisted = try #require(store.load())
        #expect(persisted.processedCommandIDs.contains(commandID))
    }

    @Test func relaunchRetriesTerminalCompletionAndPromotesExactlyOnce() throws {
        let fileURL = makeTemporaryFileURL()
        let log = CallLog()
        let firstReceipts = OrderedFakeReceiptStore(log: log)
        firstReceipts.shouldThrowOnPromote = true
        let firstRecorder = OrderedFakeResultRecorder(log: log)

        do {
            let session = MatchSessionViewModel(
                store: MatchStore(fileURL: fileURL),
                resultRecorder: firstRecorder,
                commandReceiptStore: firstReceipts
            )
            startLinkedMatch(on: session, configuration: try winningConfiguration())
            applyOneRemoteCommand(on: session)
            winMatch(for: .teamA, on: session)
            session.finishMatch()
            #expect(session.sessionError == .activeMatchCleanupFailed)
            #expect(firstReceipts.promotionAttempts.count == 1)
            #expect(firstReceipts.successfulPromotions.isEmpty)
        }

        // Relaunch over the same file with a working receipt store.
        let secondLog = CallLog()
        let secondReceipts = OrderedFakeReceiptStore(log: secondLog)
        let secondRecorder = OrderedFakeResultRecorder(log: secondLog)
        let store = MatchStore(fileURL: fileURL)
        let relaunched = MatchSessionViewModel(
            store: store,
            resultRecorder: secondRecorder,
            commandReceiptStore: secondReceipts
        )

        relaunched.restoreIfNeeded()

        // Exactly one successful promotion, despite the earlier thrown attempt.
        #expect(secondReceipts.successfulPromotions.count == 1)
        #expect(relaunched.sessionError == nil)
        #expect(store.load() == nil)
        guard case .finished = relaunched.phase else {
            Issue.record("expected the relaunched terminal match to complete")
            return
        }
    }

    // MARK: - Discard ordering

    @Test func successfulDiscardPromotesBeforeClearing() throws {
        let log = CallLog()
        let receipts = OrderedFakeReceiptStore(log: log)
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        let session = MatchSessionViewModel(
            store: store,
            resultRecorder: OrderedFakeResultRecorder(log: log),
            commandReceiptStore: receipts
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let commandID = applyOneRemoteCommand(on: session)

        session.returnToSetup()

        #expect(log.calls == ["promote"])
        #expect(receipts.successfulPromotions.count == 1)
        #expect(receipts.successfulPromotions[0].commandIDs.contains(commandID))
        #expect(store.load() == nil)
        guard case .setup = session.phase else {
            Issue.record("expected phase to return to .setup")
            return
        }
    }

    @Test func discardPromotionFailurePreservesTheEntireActiveSession() throws {
        let log = CallLog()
        let receipts = OrderedFakeReceiptStore(log: log)
        receipts.shouldThrowOnPromote = true
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        let session = MatchSessionViewModel(
            store: store,
            resultRecorder: OrderedFakeResultRecorder(log: log),
            commandReceiptStore: receipts
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let commandID = applyOneRemoteCommand(on: session)
        let snapshotBefore = session.currentSnapshot()

        session.returnToSetup()

        #expect(session.sessionError == .activeMatchCleanupFailed)

        // Every active-session field except sessionError is unchanged.
        let snapshotAfter = session.currentSnapshot()
        #expect(snapshotAfter.matchID == snapshotBefore.matchID)
        #expect(snapshotAfter.stateRevision == snapshotBefore.stateRevision)
        #expect(snapshotAfter.currentPhase == snapshotBefore.currentPhase)
        #expect(snapshotAfter.sessionPhase == snapshotBefore.sessionPhase)
        #expect(snapshotAfter.teamAPair == snapshotBefore.teamAPair)
        #expect(snapshotAfter.teamBPair == snapshotBefore.teamBPair)
        #expect(snapshotAfter.canUndo == snapshotBefore.canUndo)
        #expect(session.teamALabel == "Alex")
        #expect(session.teamBLabel == "Sam")

        // The persisted match and its ledger both survive.
        let persisted = try #require(store.load())
        #expect(persisted.processedCommandIDs.contains(commandID))
    }

    @Test func retryingDiscardAfterPromotionFailureSucceeds() throws {
        let log = CallLog()
        let receipts = OrderedFakeReceiptStore(log: log)
        receipts.shouldThrowOnPromote = true
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        let session = MatchSessionViewModel(
            store: store,
            resultRecorder: OrderedFakeResultRecorder(log: log),
            commandReceiptStore: receipts
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        applyOneRemoteCommand(on: session)

        session.returnToSetup()
        #expect(session.sessionError == .activeMatchCleanupFailed)

        receipts.shouldThrowOnPromote = false
        session.returnToSetup()

        #expect(session.sessionError == nil)
        #expect(receipts.promotionAttempts.count == 2)
        #expect(receipts.successfulPromotions.count == 1)
        #expect(store.load() == nil)
        guard case .setup = session.phase else {
            Issue.record("expected phase to return to .setup after the retry")
            return
        }
    }

    // MARK: - Matches with no remote commands

    @Test func matchWithNoRemoteCommandIDsFinishesAndDiscardsNormally() throws {
        let log = CallLog()
        let receipts = OrderedFakeReceiptStore(log: log)
        let recorder = OrderedFakeResultRecorder(log: log)
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        let session = MatchSessionViewModel(
            store: store,
            resultRecorder: recorder,
            commandReceiptStore: receipts
        )

        // Finish with an empty ledger: promotion is skipped entirely.
        startLinkedMatch(on: session, configuration: try winningConfiguration())
        winMatch(for: .teamA, on: session)
        session.finishMatch()

        #expect(session.sessionError == nil)
        #expect(log.calls == ["recorder"])
        #expect(receipts.promotionAttempts.isEmpty)
        #expect(store.load() == nil)

        // Discard with an empty ledger: likewise skipped, and still clears.
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        session.returnToSetup()

        #expect(session.sessionError == nil)
        #expect(receipts.promotionAttempts.isEmpty)
        #expect(store.load() == nil)
    }
}
