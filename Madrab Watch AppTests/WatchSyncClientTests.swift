import Testing
import Foundation
@testable import Madrab_Watch_App
import MadrabScoringEngine
import MadrabSyncKit

/// Fake transport. Captures every outgoing payload and lets a test deliver
/// replies, errors, and application-context snapshots on demand — no paired
/// device, no radio, fully deterministic.
@MainActor
private final class FakeConnectivitySession: WatchConnectivitySession {
    var isReachable = false
    var isActivated = false
    weak var events: WatchConnectivitySessionEvents?

    private(set) var activateCallCount = 0
    private(set) var sentPayloads: [[String: Any]] = []
    private var replyHandlers: [([String: Any]) -> Void] = []
    private var errorHandlers: [(Error) -> Void] = []

    struct TransportFailure: Error {}

    var sentCommands: [SyncCommand] {
        sentPayloads.compactMap { SyncPayload.decodeCommand(from: $0) }
    }

    func activate() {
        activateCallCount += 1
    }

    func sendMessage(
        _ payload: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) {
        sentPayloads.append(payload)
        replyHandlers.append(replyHandler)
        errorHandlers.append(errorHandler)
    }

    /// Discards captured sends so a test can assert only on what happens
    /// after the setup it just performed.
    func clearSentPayloads() {
        sentPayloads.removeAll()
    }

    /// Simulates the phone answering the most recent send.
    func deliverReply(_ payload: [String: Any]) {
        guard !replyHandlers.isEmpty else { return }
        replyHandlers.removeLast()(payload)
    }

    /// Simulates a lost reply / radio failure for the most recent send.
    func deliverTransportFailure() {
        guard !errorHandlers.isEmpty else { return }
        errorHandlers.removeLast()(TransportFailure())
    }

    func simulateActivation(isReachable: Bool) {
        isActivated = true
        self.isReachable = isReachable
        events?.sessionActivationDidChange(isActivated: true)
        events?.sessionReachabilityDidChange(isReachable: isReachable)
    }

    func simulateReachability(_ reachable: Bool) {
        isReachable = reachable
        events?.sessionReachabilityDidChange(isReachable: reachable)
    }

    func simulateApplicationContext(_ payload: [String: Any]) {
        events?.sessionDidReceiveSnapshotPayload(payload)
    }
}

@MainActor
struct WatchSyncClientTests {

    // MARK: - Helpers

    private func makeSnapshot(
        matchID: UUID?,
        revision: Int,
        teamAPoints: Int = 0,
        teamBPoints: Int = 0,
        sessionPhase: SyncSessionPhase = .live,
        lastAcknowledgedCommandID: UUID? = nil
    ) -> SyncSnapshot {
        SyncSnapshot(
            matchID: matchID,
            stateRevision: revision,
            teamAPair: PairNames(first: "Alex", second: ""),
            teamBPair: PairNames(first: "Sam", second: ""),
            sets: [],
            currentPhase: .game(SyncGameScore(points: TeamPair(teamA: teamAPoints, teamB: teamBPoints))),
            servingTeam: .teamA,
            servingPlayer: nil,
            matchWinner: nil,
            sessionPhase: sessionPhase,
            canUndo: true,
            lastAcknowledgedCommandID: lastAcknowledgedCommandID
        )
    }

    private func replyPayload(
        commandID: UUID,
        outcome: SyncCommandOutcome,
        snapshot: SyncSnapshot
    ) throws -> [String: Any] {
        try SyncPayload.encodeResponse(
            SyncCommandResponse(commandID: commandID, outcome: outcome, snapshot: snapshot)
        )
    }

    /// A client already activated, reachable, and holding one snapshot.
    private func makeLiveClient(
        matchID: UUID = UUID(),
        revision: Int = 4,
        commandIDs: [UUID] = []
    ) async throws -> (WatchSyncClient, FakeConnectivitySession, UUID) {
        let session = FakeConnectivitySession()
        var queue = commandIDs
        let client = WatchSyncClient(
            session: session,
            makeCommandID: { queue.isEmpty ? UUID() : queue.removeFirst() }
        )
        session.simulateActivation(isReachable: true)
        // Activation triggers a state request; answer it with a snapshot.
        try session.deliverReply(
            SyncPayload.encodeSnapshot(
                makeSnapshot(matchID: matchID, revision: revision)
            )
        )
        // The production reply handler hops with `Task { @MainActor in … }`,
        // so the snapshot is only queued at this point. Yield to let that
        // hop run before any caller inspects the client's state.
        await Task.yield()
        return (client, session, matchID)
    }

    // MARK: - Activation

    @Test func activateStartsTheSession() {
        let session = FakeConnectivitySession()
        let client = WatchSyncClient(session: session)

        client.activate()

        #expect(session.activateCallCount == 1)
        #expect(client.isActivated == false)
    }

    @Test func activationRequestsLatestState() throws {
        let session = FakeConnectivitySession()
        // The session holds `events` weakly, so the client must be retained
        // for the duration of the test or it deallocates before the
        // activation callback can reach it.
        let client = WatchSyncClient(session: session)

        session.simulateActivation(isReachable: true)

        let command = try #require(session.sentCommands.first)
        #expect(session.sentCommands.count == 1)
        #expect(command.kind == .requestLatestState)
        #expect(command.matchID == nil)
        withExtendedLifetime(client) {}
    }

    // MARK: - Snapshot reception

    @Test func applicationContextSnapshotIsAdopted() throws {
        let session = FakeConnectivitySession()
        let client = WatchSyncClient(session: session)
        let matchID = UUID()

        try session.simulateApplicationContext(
            SyncPayload.encodeSnapshot(makeSnapshot(matchID: matchID, revision: 7))
        )

        #expect(client.latestSnapshot?.matchID == matchID)
        #expect(client.latestSnapshot?.stateRevision == 7)
    }

    @Test func directReplySnapshotIsAdopted() async throws {
        let (client, session, matchID) = try await makeLiveClient(revision: 3)

        try session.simulateApplicationContext(
            SyncPayload.encodeSnapshot(makeSnapshot(matchID: matchID, revision: 9))
        )

        #expect(client.latestSnapshot?.stateRevision == 9)
    }

    @Test func staleSnapshotForTheSameMatchIsIgnored() async throws {
        let (client, session, matchID) = try await makeLiveClient(revision: 10)

        try session.simulateApplicationContext(
            SyncPayload.encodeSnapshot(makeSnapshot(matchID: matchID, revision: 4))
        )

        #expect(client.latestSnapshot?.stateRevision == 10)
    }

    @Test func snapshotForADifferentMatchIsAdoptedRegardlessOfRevision() async throws {
        let (client, session, _) = try await makeLiveClient(revision: 20)
        let newMatchID = UUID()

        // Lower revision, but a different match: revisions are not comparable.
        try session.simulateApplicationContext(
            SyncPayload.encodeSnapshot(makeSnapshot(matchID: newMatchID, revision: 1))
        )

        #expect(client.latestSnapshot?.matchID == newMatchID)
        #expect(client.latestSnapshot?.stateRevision == 1)
    }

    // MARK: - Command construction

    @Test func scoringCommandCarriesMatchIDRevisionAndKind() async throws {
        let session = FakeConnectivitySession()
        let matchID = UUID()
        let activationCommandID = UUID()
        let scoringCommandID = UUID()
        let sentAt = Date(timeIntervalSince1970: 1_700_000_000)

        // The first generated ID is consumed by the activation state request;
        // the second belongs to the scoring command under test.
        var queue = [activationCommandID, scoringCommandID]
        let client = WatchSyncClient(
            session: session,
            makeCommandID: { queue.isEmpty ? UUID() : queue.removeFirst() },
            now: { sentAt }
        )

        session.simulateActivation(isReachable: true)
        try session.deliverReply(
            SyncPayload.encodeSnapshot(makeSnapshot(matchID: matchID, revision: 6))
        )
        await Task.yield()
        session.clearSentPayloads()

        client.recordPoint(for: .teamB)

        let command = try #require(session.sentCommands.last)
        #expect(command.commandID == scoringCommandID)
        #expect(command.matchID == matchID)
        #expect(command.expectedStateRevision == 6)
        #expect(command.kind == .recordPoint(.teamB))
        #expect(command.sentAt == sentAt)
    }

    @Test func aSecondCommandIsBlockedWhileOneIsPending() async throws {
        let (client, session, _) = try await makeLiveClient()
        session.clearSentPayloads()

        client.recordPoint(for: .teamA)
        client.recordPoint(for: .teamB)
        client.undo()

        #expect(session.sentCommands.count == 1)
        #expect(client.hasPendingCommand)
    }

    @Test func retryReusesTheSameCommandID() async throws {
        let (client, session, _) = try await makeLiveClient()
        session.clearSentPayloads()

        client.recordPoint(for: .teamA)
        let originalID = try #require(session.sentCommands.last).commandID

        session.deliverTransportFailure()
        await Task.yield()
        #expect(client.hasPendingCommand)

        client.retryPendingCommand()

        try #require(session.sentCommands.count == 2)
        let retried = try #require(session.sentCommands.last)
        #expect(retried.commandID == originalID)
    }

    // MARK: - Response handling

    @Test func acceptedResponseClearsPendingAndAdoptsSnapshot() async throws {
        let (client, session, matchID) = try await makeLiveClient(revision: 4)
        session.clearSentPayloads()
        client.recordPoint(for: .teamA)
        let commandID = try #require(session.sentCommands.last).commandID

        try session.deliverReply(
            replyPayload(
                commandID: commandID,
                outcome: .accepted,
                snapshot: makeSnapshot(matchID: matchID, revision: 5, teamAPoints: 1)
            )
        )
        await Task.yield()

        #expect(client.hasPendingCommand == false)
        #expect(client.lastRejection == nil)
        #expect(client.latestSnapshot?.stateRevision == 5)
    }

    @Test func alreadyAppliedResponseClearsPendingWithoutRejection() async throws {
        let (client, session, matchID) = try await makeLiveClient(revision: 4)
        session.clearSentPayloads()
        client.recordPoint(for: .teamA)
        let commandID = try #require(session.sentCommands.last).commandID

        try session.deliverReply(
            replyPayload(
                commandID: commandID,
                outcome: .alreadyApplied,
                snapshot: makeSnapshot(matchID: matchID, revision: 5)
            )
        )
        await Task.yield()

        #expect(client.hasPendingCommand == false)
        #expect(client.lastRejection == nil)
    }

    @Test(arguments: [
        SyncRejectionReason.malformedCommand,
        .wrongMatch,
        .noLiveMatch,
        .staleRevision,
        .matchFinished,
        .invalidUndo,
        .persistenceFailed,
    ])
    func everyRejectionReasonIsSurfacedAndClearsPending(_ reason: SyncRejectionReason) async throws {
        let (client, session, matchID) = try await makeLiveClient(revision: 4)
        session.clearSentPayloads()
        client.recordPoint(for: .teamA)
        let commandID = try #require(session.sentCommands.last).commandID

        try session.deliverReply(
            replyPayload(
                commandID: commandID,
                outcome: .rejected(reason),
                snapshot: makeSnapshot(matchID: matchID, revision: 4)
            )
        )
        await Task.yield()

        #expect(client.lastRejection == reason)
        #expect(client.hasPendingCommand == false)
    }

    // MARK: - Reachability

    @Test func losingReachabilityMakesTheClientReadOnly() async throws {
        let (client, session, _) = try await makeLiveClient()
        #expect(client.isReadOnly == false)

        session.simulateReachability(false)

        #expect(client.isReadOnly)
    }

    @Test func scoringIsRefusedWhileUnreachableAndTheSnapshotIsKept() async throws {
        let (client, session, _) = try await makeLiveClient(revision: 4)
        session.simulateReachability(false)
        session.clearSentPayloads()

        client.recordPoint(for: .teamA)

        #expect(session.sentPayloads.isEmpty)
        #expect(client.hasPendingCommand == false)
        // The last known score stays on screen rather than blanking.
        #expect(client.latestSnapshot?.stateRevision == 4)
    }

    @Test func regainingReachabilityRequestsLatestState() async throws {
        let (client, session, _) = try await makeLiveClient()
        session.clearSentPayloads()

        // The session references the client weakly, so it must stay alive
        // across the whole simulate/assert sequence.
        withExtendedLifetime(client) {
            session.simulateReachability(false)
            session.simulateReachability(true)

            #expect(session.sentCommands.count == 1)
        }

        let command = try #require(session.sentCommands.first)
        #expect(command.kind == .requestLatestState)
    }
}
