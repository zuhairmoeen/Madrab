import Testing
import Foundation
@testable import Madrab
import MadrabScoringEngine
import MadrabSyncKit

/// In-memory `CommandReceipting` double. Lets a test preload durable receipts
/// or force read/write failures without touching the filesystem.
private final class FakeCommandReceiptStore: CommandReceipting {
    struct Key: Hashable {
        let matchID: UUID
        let commandID: UUID
    }

    struct Failure: Error {}

    var receipts: Set<Key> = []
    var shouldThrowOnContains = false
    var shouldThrowOnPromote = false
    private(set) var promotions: [(matchID: UUID, commandIDs: Set<UUID>)] = []

    func contains(matchID: UUID, commandID: UUID) throws -> Bool {
        if shouldThrowOnContains { throw Failure() }
        return receipts.contains(Key(matchID: matchID, commandID: commandID))
    }

    func promote(matchID: UUID, commandIDs: Set<UUID>) throws {
        if shouldThrowOnPromote { throw Failure() }
        promotions.append((matchID, commandIDs))
        for commandID in commandIDs {
            receipts.insert(Key(matchID: matchID, commandID: commandID))
        }
    }
}

@MainActor
struct MatchSessionRemoteCommandTests {

    // MARK: - Helpers

    private func makeTemporaryFileURL(name: String = "active-match.json") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
    }

    /// A file occupying the parent path forces every `save` beneath it to
    /// throw when it tries to create that directory — a deterministic
    /// persistence failure, matching the technique already used elsewhere in
    /// this suite.
    private func makeUnwritableFileURL(name: String = "active-match.json") throws -> URL {
        let blocked = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try Data().write(to: blocked)
        return blocked.appendingPathComponent(name)
    }

    private func winningConfiguration() throws -> MatchConfiguration {
        try MatchConfiguration(setsToWin: 1, gamesToWinSet: 2, finalSetMode: .fullSet)
    }

    /// Starts a profile-linked match, which is the only kind that carries a
    /// `matchID` and can therefore be addressed by a remote command.
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

    private func command(
        matchID: UUID?,
        commandID: UUID = UUID(),
        revision: Int,
        kind: SyncCommandKind
    ) -> SyncCommand {
        SyncCommand(
            matchID: matchID,
            commandID: commandID,
            expectedStateRevision: revision,
            kind: kind
        )
    }

    private func rejection(_ response: SyncCommandResponse) -> SyncRejectionReason? {
        guard case .rejected(let reason) = response.outcome else { return nil }
        return reason
    }

    // MARK: - requestLatestState

    @Test func requestLatestStateWithNilMatchIDIsAcceptedAndMutatesNothing() throws {
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        let session = MatchSessionViewModel(store: store, commandReceiptStore: FakeCommandReceiptStore())
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        session.recordPoint(for: .teamA)
        let revisionBefore = session.currentSnapshot().stateRevision

        let response = session.applyRemoteCommand(
            command(matchID: nil, revision: 0, kind: .requestLatestState)
        )

        #expect(response.outcome == .accepted)
        #expect(response.snapshot.stateRevision == revisionBefore)
        #expect(session.currentSnapshot().stateRevision == revisionBefore)
    }

    @Test func requestLatestStateDoesNotConsultTheReceiptStore() throws {
        let receipts = FakeCommandReceiptStore()
        receipts.shouldThrowOnContains = true
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: receipts
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())

        let response = session.applyRemoteCommand(
            command(matchID: nil, revision: 0, kind: .requestLatestState)
        )

        #expect(response.outcome == .accepted)
    }

    // MARK: - Accepted commands

    @Test func acceptedTeamAPoint() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID

        let response = session.applyRemoteCommand(
            command(matchID: matchID, revision: 0, kind: .recordPoint(.teamA))
        )

        #expect(response.outcome == .accepted)
        #expect(session.state?.currentPhase == .game(GameScore(points: TeamPair(teamA: 1, teamB: 0))))
        #expect(session.currentSnapshot().stateRevision == 1)
    }

    @Test func acceptedTeamBPoint() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID

        let response = session.applyRemoteCommand(
            command(matchID: matchID, revision: 0, kind: .recordPoint(.teamB))
        )

        #expect(response.outcome == .accepted)
        #expect(session.state?.currentPhase == .game(GameScore(points: TeamPair(teamA: 0, teamB: 1))))
    }

    @Test func acceptedUndo() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID
        session.recordPoint(for: .teamA)

        let response = session.applyRemoteCommand(
            command(matchID: matchID, revision: 1, kind: .undo)
        )

        #expect(response.outcome == .accepted)
        #expect(session.state?.currentPhase == .game(.initial))
    }

    @Test func acceptedResponseCarriesTheAcknowledgedCommandID() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID
        let commandID = UUID()

        let response = session.applyRemoteCommand(
            command(matchID: matchID, commandID: commandID, revision: 0, kind: .recordPoint(.teamA))
        )

        #expect(response.commandID == commandID)
        #expect(response.snapshot.lastAcknowledgedCommandID == commandID)
    }

    // MARK: - Rejections

    @Test func nilMatchIDOnScoringCommandIsMalformed() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())

        let response = session.applyRemoteCommand(
            command(matchID: nil, revision: 0, kind: .recordPoint(.teamA))
        )

        #expect(rejection(response) == .malformedCommand)
        #expect(response.snapshot.lastAcknowledgedCommandID == nil)
    }

    @Test func noActiveMatchIsRejectedAsNoLiveMatch() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )

        let response = session.applyRemoteCommand(
            command(matchID: UUID(), revision: 0, kind: .recordPoint(.teamA))
        )

        #expect(rejection(response) == .noLiveMatch)
    }

    @Test func differentMatchIDIsRejectedAsWrongMatch() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())

        let response = session.applyRemoteCommand(
            command(matchID: UUID(), revision: 0, kind: .recordPoint(.teamA))
        )

        #expect(rejection(response) == .wrongMatch)
    }

    @Test func staleRevisionIsRejected() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID
        session.recordPoint(for: .teamA)

        let response = session.applyRemoteCommand(
            command(matchID: matchID, revision: 0, kind: .recordPoint(.teamA))
        )

        #expect(rejection(response) == .staleRevision)
        #expect(session.currentSnapshot().stateRevision == 1)
    }

    @Test func aheadRevisionIsAlsoRejected() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID

        let response = session.applyRemoteCommand(
            command(matchID: matchID, revision: 5, kind: .recordPoint(.teamA))
        )

        #expect(rejection(response) == .staleRevision)
    }

    @Test func terminalMatchRejectsScoringCommands() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            resultRecorder: MatchResultRecorder(
                store: LeaderboardStore(fileURL: makeTemporaryFileURL(name: "leaderboard.json"))
            ),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try winningConfiguration())
        let matchID = session.currentSnapshot().matchID
        winMatch(for: .teamA, on: session)
        session.finishMatch()

        let response = session.applyRemoteCommand(
            command(matchID: matchID, revision: 9, kind: .recordPoint(.teamA))
        )

        #expect(rejection(response) == .matchFinished)
    }

    @Test func scoringAfterAWinnerExistsIsRejected() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try winningConfiguration())
        let matchID = session.currentSnapshot().matchID
        winMatch(for: .teamA, on: session)

        let snapshot = session.currentSnapshot()
        #expect(snapshot.matchWinner == .teamA)

        let response = session.applyRemoteCommand(
            command(matchID: matchID, revision: snapshot.stateRevision, kind: .recordPoint(.teamB))
        )

        #expect(rejection(response) == .matchFinished)
        #expect(session.currentSnapshot().stateRevision == snapshot.stateRevision)
    }

    @Test func undoOfTheWinningPointIsAcceptedAndClearsTheWinner() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try winningConfiguration())
        let matchID = session.currentSnapshot().matchID
        winMatch(for: .teamA, on: session)
        let revision = session.currentSnapshot().stateRevision

        let response = session.applyRemoteCommand(
            command(matchID: matchID, revision: revision, kind: .undo)
        )

        #expect(response.outcome == .accepted)
        #expect(session.currentSnapshot().matchWinner == nil)
    }

    @Test func undoWithNothingToUndoIsRejectedAsInvalidUndo() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID

        let response = session.applyRemoteCommand(
            command(matchID: matchID, revision: 0, kind: .undo)
        )

        #expect(rejection(response) == .invalidUndo)
    }

    // MARK: - Duplicates

    @Test func duplicateInActiveLedgerReturnsAlreadyApplied() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID
        let commandID = UUID()
        let first = session.applyRemoteCommand(
            command(matchID: matchID, commandID: commandID, revision: 0, kind: .recordPoint(.teamA))
        )
        #expect(first.outcome == .accepted)

        let repeated = session.applyRemoteCommand(
            command(matchID: matchID, commandID: commandID, revision: 1, kind: .recordPoint(.teamA))
        )

        #expect(repeated.outcome == .alreadyApplied)
        #expect(session.currentSnapshot().stateRevision == 1)
    }

    @Test func activeDuplicateIsScopedToTheMatchingMatchID() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID
        let commandID = UUID()
        _ = session.applyRemoteCommand(
            command(matchID: matchID, commandID: commandID, revision: 0, kind: .recordPoint(.teamA))
        )

        let response = session.applyRemoteCommand(
            command(matchID: UUID(), commandID: commandID, revision: 1, kind: .recordPoint(.teamA))
        )

        #expect(response.outcome != .alreadyApplied)
        #expect(rejection(response) == .wrongMatch)
    }

    @Test func duplicateInDurableReceiptStoreReturnsAlreadyApplied() throws {
        let receipts = FakeCommandReceiptStore()
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: receipts
        )
        let matchID = UUID()
        let commandID = UUID()
        receipts.receipts.insert(FakeCommandReceiptStore.Key(matchID: matchID, commandID: commandID))

        let response = session.applyRemoteCommand(
            command(matchID: matchID, commandID: commandID, revision: 0, kind: .recordPoint(.teamA))
        )

        #expect(response.outcome == .alreadyApplied)
    }

    @Test func receiptStoreReadFailureIsReportedAsPersistenceFailed() throws {
        let receipts = FakeCommandReceiptStore()
        receipts.shouldThrowOnContains = true
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: receipts
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID

        let response = session.applyRemoteCommand(
            command(matchID: matchID, revision: 0, kind: .recordPoint(.teamA))
        )

        #expect(rejection(response) == .persistenceFailed)
        #expect(session.currentSnapshot().stateRevision == 0)
    }

    @Test func lostReplyRetryReturnsAlreadyAppliedWithoutScoringTwice() throws {
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        let session = MatchSessionViewModel(store: store, commandReceiptStore: FakeCommandReceiptStore())
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID
        let commandID = UUID()

        _ = session.applyRemoteCommand(
            command(matchID: matchID, commandID: commandID, revision: 0, kind: .recordPoint(.teamA))
        )
        let retry = session.applyRemoteCommand(
            command(matchID: matchID, commandID: commandID, revision: 0, kind: .recordPoint(.teamA))
        )

        #expect(retry.outcome == .alreadyApplied)
        #expect(session.state?.currentPhase == .game(GameScore(points: TeamPair(teamA: 1, teamB: 0))))
        #expect(session.currentSnapshot().stateRevision == 1)
    }

    // MARK: - Persistence

    @Test func scoringEventAndCommandIDAreSavedTogether() throws {
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        let session = MatchSessionViewModel(store: store, commandReceiptStore: FakeCommandReceiptStore())
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID
        let commandID = UUID()

        let response = session.applyRemoteCommand(
            command(matchID: matchID, commandID: commandID, revision: 0, kind: .recordPoint(.teamA))
        )
        #expect(response.outcome == .accepted)

        let persisted = try #require(store.load())
        #expect(persisted.events.count == 1)
        #expect(persisted.processedCommandIDs == [commandID])
    }

    @Test func persistenceFailureRollsBackEveryTouchedValue() throws {
        let store = MatchStore(fileURL: try makeUnwritableFileURL())
        let session = MatchSessionViewModel(store: store, commandReceiptStore: FakeCommandReceiptStore())
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID
        let snapshotBefore = session.currentSnapshot()
        let errorBefore = session.sessionError

        let response = session.applyRemoteCommand(
            command(matchID: matchID, revision: 0, kind: .recordPoint(.teamA))
        )

        #expect(rejection(response) == .persistenceFailed)
        let snapshotAfter = session.currentSnapshot()
        #expect(snapshotAfter.stateRevision == snapshotBefore.stateRevision)
        #expect(snapshotAfter.currentPhase == snapshotBefore.currentPhase)
        #expect(snapshotAfter.sessionPhase == snapshotBefore.sessionPhase)
        #expect(session.sessionError == errorBefore)
        #expect(store.load() == nil)
    }

    @Test func rollbackLeavesTheLedgerClearSoARetryCanSucceed() throws {
        let fileURL = try makeUnwritableFileURL()
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: fileURL),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        let matchID = session.currentSnapshot().matchID
        let commandID = UUID()

        let failed = session.applyRemoteCommand(
            command(matchID: matchID, commandID: commandID, revision: 0, kind: .recordPoint(.teamA))
        )
        #expect(rejection(failed) == .persistenceFailed)

        try FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        let retry = session.applyRemoteCommand(
            command(matchID: matchID, commandID: commandID, revision: 0, kind: .recordPoint(.teamA))
        )

        #expect(retry.outcome == .accepted)
        #expect(session.currentSnapshot().stateRevision == 1)
    }

    // MARK: - Ledger lifecycle

    @Test func processedCommandIDsAreRestoredAfterRelaunch() throws {
        let fileURL = makeTemporaryFileURL()
        let commandID = UUID()
        var matchID: UUID?

        do {
            let session = MatchSessionViewModel(
                store: MatchStore(fileURL: fileURL),
                commandReceiptStore: FakeCommandReceiptStore()
            )
            startLinkedMatch(on: session, configuration: try MatchConfiguration())
            matchID = session.currentSnapshot().matchID
            _ = session.applyRemoteCommand(
                command(matchID: matchID, commandID: commandID, revision: 0, kind: .recordPoint(.teamA))
            )
        }

        let relaunched = MatchSessionViewModel(
            store: MatchStore(fileURL: fileURL),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        relaunched.restoreIfNeeded()

        let response = relaunched.applyRemoteCommand(
            command(matchID: matchID, commandID: commandID, revision: 1, kind: .recordPoint(.teamA))
        )

        #expect(response.outcome == .alreadyApplied)
        #expect(relaunched.currentSnapshot().stateRevision == 1)
    }

    @Test func aNewMatchStartsWithAnEmptyProcessedLedger() throws {
        let store = MatchStore(fileURL: makeTemporaryFileURL())
        let session = MatchSessionViewModel(store: store, commandReceiptStore: FakeCommandReceiptStore())
        startLinkedMatch(on: session, configuration: try MatchConfiguration())
        _ = session.applyRemoteCommand(
            command(matchID: session.currentSnapshot().matchID, revision: 0, kind: .recordPoint(.teamA))
        )
        #expect(try #require(store.load()).processedCommandIDs.isEmpty == false)

        startLinkedMatch(on: session, configuration: try MatchConfiguration())

        #expect(try #require(store.load()).processedCommandIDs.isEmpty)
    }

    // MARK: - Engine-level safety

    @Test func aCommandTheEngineWouldRejectNeverReturnsAccepted() throws {
        let session = MatchSessionViewModel(
            store: MatchStore(fileURL: makeTemporaryFileURL()),
            commandReceiptStore: FakeCommandReceiptStore()
        )
        startLinkedMatch(on: session, configuration: try winningConfiguration())
        let matchID = session.currentSnapshot().matchID
        winMatch(for: .teamA, on: session)
        let before = session.currentSnapshot()

        // The engine itself would reject this with `.matchAlreadyDecided`.
        // `applyRemoteCommand`'s own winner check fires first, so this asserts
        // the guarantee that matters — never `.accepted`, and no state change —
        // rather than which layer refused it.
        let response = session.applyRemoteCommand(
            command(matchID: matchID, revision: before.stateRevision, kind: .recordPoint(.teamA))
        )

        #expect(response.outcome != .accepted)
        #expect(session.currentSnapshot().stateRevision == before.stateRevision)
        #expect(session.currentSnapshot().matchWinner == before.matchWinner)
    }
}
