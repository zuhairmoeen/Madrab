import Testing
import Foundation
@testable import Madrab
import MadrabScoringEngine
import MadrabSyncKit

// MARK: - Doubles

/// Records every reply the service produces, so "exactly once" is directly
/// assertable rather than inferred.
private final class ReplyRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var payloads: [[String: Any]] = []

    func record(_ payload: [String: Any]) {
        lock.lock()
        defer { lock.unlock() }
        payloads.append(payload)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return payloads.count
    }

    var responses: [SyncCommandResponse] {
        lock.lock()
        defer { lock.unlock() }
        return payloads.compactMap { SyncPayload.decodeResponse(from: $0) }
    }
}

/// In-memory `CommandReceipting` double, so no test touches the real
/// `command-receipts.json` in Application Support.
private final class StubCommandReceiptStore: CommandReceipting {
    struct Key: Hashable {
        let matchID: UUID
        let commandID: UUID
    }

    var receipts: Set<Key> = []

    func contains(matchID: UUID, commandID: UUID) throws -> Bool {
        receipts.contains(Key(matchID: matchID, commandID: commandID))
    }

    func promote(matchID: UUID, commandIDs: Set<UUID>) throws {
        for commandID in commandIDs {
            receipts.insert(Key(matchID: matchID, commandID: commandID))
        }
    }
}

/// Fake transport. Captures application-context updates and messages, and
/// delivers commands both on and off the main actor — no paired device, no
/// radio, fully deterministic.
@MainActor
private final class FakePhoneConnectivitySession: PhoneConnectivitySession {
    struct TransportFailure: Error {}

    var isReachable = false
    var isActivated = false
    weak var events: PhoneConnectivitySessionEvents?

    private(set) var activateCallCount = 0
    private(set) var applicationContexts: [[String: Any]] = []
    private(set) var sentMessages: [[String: Any]] = []
    var contextUpdateError: Error?

    var contextSnapshots: [SyncSnapshot] {
        applicationContexts.compactMap { SyncPayload.decodeSnapshot(from: $0) }
    }

    var messageSnapshots: [SyncSnapshot] {
        sentMessages.compactMap { SyncPayload.decodeSnapshot(from: $0) }
    }

    func activate() {
        activateCallCount += 1
    }

    func updateApplicationContext(_ payload: [String: Any]) throws {
        if let contextUpdateError {
            throw contextUpdateError
        }
        applicationContexts.append(payload)
    }

    func sendMessage(_ payload: [String: Any]) {
        sentMessages.append(payload)
    }

    /// Discards captured traffic so a test can assert only on what happens
    /// after the setup it just performed.
    func clearCaptured() {
        applicationContexts.removeAll()
        sentMessages.removeAll()
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

    @discardableResult
    func deliverCommand(_ payload: [String: Any]) -> ReplyRecorder {
        let recorder = ReplyRecorder()
        let reply = SyncReplyHandler { recorder.record($0) }
        events?.sessionDidReceiveCommandPayload(payload, reply: reply)
        return recorder
    }

    /// Mirrors `LivePhoneConnectivitySession` exactly: the payload and the
    /// reply handler are built off the main actor and hopped on, as a real
    /// `WCSessionDelegate` callback does.
    nonisolated func deliverCommandFromBackground(_ command: SyncCommand, into recorder: ReplyRecorder) {
        guard let payload = try? SyncPayload.encodeCommand(command) else { return }
        let reply = SyncReplyHandler { recorder.record($0) }
        Task { @MainActor in
            self.events?.sessionDidReceiveCommandPayload(payload, reply: reply)
        }
    }
}

/// Holds strong references to everything under test. The transport keeps
/// `events` weakly, so the service has to be retained for the whole test.
@MainActor
private final class Fixture {
    let transport: FakePhoneConnectivitySession
    let receipts: StubCommandReceiptStore
    let matchStore: MatchStore
    let matchSession: MatchSessionViewModel
    let service: PhoneSyncService

    init(matchStoreURL: URL, leaderboardURL: URL) {
        let transport = FakePhoneConnectivitySession()
        let receipts = StubCommandReceiptStore()
        let matchStore = MatchStore(fileURL: matchStoreURL)
        let matchSession = MatchSessionViewModel(
            store: matchStore,
            resultRecorder: MatchResultRecorder(store: LeaderboardStore(fileURL: leaderboardURL)),
            commandReceiptStore: receipts
        )
        let service = PhoneSyncService(session: transport, matchSession: matchSession)

        self.transport = transport
        self.receipts = receipts
        self.matchStore = matchStore
        self.matchSession = matchSession
        self.service = service
    }
}

// MARK: - Tests

@MainActor
struct PhoneSyncServiceTests {

    // MARK: Helpers

    private func makeTemporaryFileURL(name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name)
    }

    /// A file occupying the parent path forces every `save` beneath it to
    /// throw when it tries to create that directory — the deterministic
    /// persistence failure already used elsewhere in this suite.
    private func makeUnwritableFileURL(name: String) throws -> URL {
        let blocked = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        try Data().write(to: blocked)
        return blocked.appendingPathComponent(name)
    }

    private func makeFixture(matchStoreURL: URL? = nil) -> Fixture {
        Fixture(
            matchStoreURL: matchStoreURL ?? makeTemporaryFileURL(name: "active-match.json"),
            leaderboardURL: makeTemporaryFileURL(name: "leaderboard.json")
        )
    }

    /// Lets queued main-actor work run. Both the observation broadcast and the
    /// transport's `Task { @MainActor }` hop are scheduled rather than
    /// synchronous; a handful of yields is comfortably more than the single
    /// hop any one mutation schedules.
    private func settle() async {
        for _ in 0..<3 {
            await Task.yield()
        }
    }

    private func shortMatchConfiguration() throws -> MatchConfiguration {
        try MatchConfiguration(setsToWin: 1, gamesToWinSet: 2, finalSetMode: .fullSet)
    }

    /// Only a profile-linked match carries a `matchID`, so only that kind can
    /// be addressed by a remote command.
    @discardableResult
    private func startLinkedMatch(
        on fixture: Fixture,
        configuration: MatchConfiguration
    ) -> Bool {
        fixture.matchSession.startMatch(
            configuration: configuration,
            teamAProfile: PlayerProfile(displayName: "Alex"),
            teamBProfile: PlayerProfile(displayName: "Sam")
        )
    }

    /// One mutation per turn: each point is followed by the scheduled
    /// observation hop, so no assertion depends on how many mutations happen
    /// to coalesce into one broadcast.
    private func recordPoint(for team: Team, on fixture: Fixture) async {
        fixture.matchSession.recordPoint(for: team)
        await settle()
    }

    private func winShortMatch(for team: Team, on fixture: Fixture) async {
        for _ in 0..<8 {
            await recordPoint(for: team, on: fixture)
        }
    }

    private func commandPayload(
        matchID: UUID?,
        commandID: UUID = UUID(),
        revision: Int,
        kind: SyncCommandKind
    ) throws -> [String: Any] {
        try SyncPayload.encodeCommand(
            SyncCommand(
                matchID: matchID,
                commandID: commandID,
                expectedStateRevision: revision,
                kind: kind
            )
        )
    }

    private func deliver(
        _ payload: [String: Any],
        to fixture: Fixture
    ) throws -> (response: SyncCommandResponse, replyCount: Int) {
        let recorder = fixture.transport.deliverCommand(payload)
        let response = try #require(recorder.responses.first)
        return (response, recorder.count)
    }

    private func rejection(_ response: SyncCommandResponse) -> SyncRejectionReason? {
        guard case .rejected(let reason) = response.outcome else { return nil }
        return reason
    }

    // MARK: - Activation

    @Test func activateStartsTheSession() {
        let fixture = makeFixture()

        fixture.service.activate()

        #expect(fixture.transport.activateCallCount == 1)
    }

    @Test func activateIsIdempotent() {
        let fixture = makeFixture()

        fixture.service.activate()
        fixture.service.activate()
        fixture.service.activate()

        #expect(fixture.transport.activateCallCount == 1)
    }

    @Test func activationPublishesASnapshotAndSetsFlags() throws {
        let fixture = makeFixture()

        fixture.transport.simulateActivation(isReachable: true)

        #expect(fixture.service.isActivated)
        #expect(fixture.service.isReachable)
        let snapshot = try #require(fixture.transport.contextSnapshots.last)
        #expect(snapshot.sessionPhase == .setup)
        #expect(snapshot.lastAcknowledgedCommandID == nil)
    }

    @Test func regainedReachabilityPublishesASnapshot() throws {
        let fixture = makeFixture()
        fixture.transport.simulateActivation(isReachable: false)
        fixture.transport.clearCaptured()

        fixture.transport.simulateReachability(true)

        #expect(fixture.transport.contextSnapshots.count == 1)
        #expect(fixture.service.isReachable)
    }

    // MARK: - Command forwarding

    @Test func scoreCommandForTeamAIsForwardedAndAccepted() throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        let matchID = fixture.matchSession.currentSnapshot().matchID

        let result = try deliver(
            commandPayload(matchID: matchID, revision: 0, kind: .recordPoint(.teamA)),
            to: fixture
        )

        #expect(result.response.outcome == .accepted)
        #expect(fixture.matchSession.state?.currentPhase == .game(GameScore(points: TeamPair(teamA: 1, teamB: 0))))
        #expect(result.response.snapshot.stateRevision == 1)
    }

    @Test func scoreCommandForTeamBIsForwardedAndAccepted() throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        let matchID = fixture.matchSession.currentSnapshot().matchID

        let result = try deliver(
            commandPayload(matchID: matchID, revision: 0, kind: .recordPoint(.teamB)),
            to: fixture
        )

        #expect(result.response.outcome == .accepted)
        #expect(fixture.matchSession.state?.currentPhase == .game(GameScore(points: TeamPair(teamA: 0, teamB: 1))))
    }

    @Test func undoCommandIsForwardedAndAccepted() async throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        let matchID = fixture.matchSession.currentSnapshot().matchID
        await recordPoint(for: .teamA, on: fixture)

        let result = try deliver(
            commandPayload(matchID: matchID, revision: 1, kind: .undo),
            to: fixture
        )

        #expect(result.response.outcome == .accepted)
        #expect(fixture.matchSession.state?.currentPhase == .game(.initial))
        #expect(fixture.matchSession.canUndo == false)
    }

    @Test func requestLatestStateIsAcceptedWithoutMutating() async throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        await recordPoint(for: .teamA, on: fixture)
        let revisionBefore = fixture.matchSession.currentSnapshot().stateRevision

        let result = try deliver(
            commandPayload(matchID: nil, revision: 0, kind: .requestLatestState),
            to: fixture
        )

        #expect(result.response.outcome == .accepted)
        #expect(result.response.snapshot.stateRevision == revisionBefore)
        #expect(fixture.matchSession.currentSnapshot().stateRevision == revisionBefore)
    }

    @Test func requestLatestStateIsAcceptedWithNoLiveMatch() throws {
        let fixture = makeFixture()

        let result = try deliver(
            commandPayload(matchID: nil, revision: 0, kind: .requestLatestState),
            to: fixture
        )

        #expect(result.response.outcome == .accepted)
        #expect(result.response.snapshot.sessionPhase == .setup)
    }

    // MARK: - Malformed transport input

    @Test func payloadWithoutTheCommandKeyIsRejectedAsMalformed() throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())

        let result = try deliver(["totally.unrelated.key": Data()], to: fixture)

        #expect(rejection(result.response) == .malformedCommand)
        #expect(fixture.matchSession.currentSnapshot().stateRevision == 0)
        #expect(result.response.snapshot.sessionPhase == .live)
    }

    @Test func undecodableCommandDataIsRejectedAsMalformed() throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())

        let result = try deliver(
            [SyncPayload.commandKey: Data("not json at all".utf8)],
            to: fixture
        )

        #expect(rejection(result.response) == .malformedCommand)
        #expect(fixture.matchSession.state?.currentPhase == .game(.initial))
    }

    @Test func malformedRejectionCarriesTheUnidentifiedCommandID() throws {
        let fixture = makeFixture()

        let result = try deliver([SyncPayload.commandKey: "a string, not Data"], to: fixture)

        #expect(result.response.commandID == PhoneSyncService.unidentifiedCommandID)
        #expect(result.response.snapshot.lastAcknowledgedCommandID == nil)
    }

    // MARK: - Outcomes

    @Test func acceptedResponseAcknowledgesTheCommandID() throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        let matchID = fixture.matchSession.currentSnapshot().matchID
        let commandID = UUID()

        let result = try deliver(
            commandPayload(matchID: matchID, commandID: commandID, revision: 0, kind: .recordPoint(.teamA)),
            to: fixture
        )

        #expect(result.response.commandID == commandID)
        #expect(result.response.snapshot.lastAcknowledgedCommandID == commandID)
    }

    @Test func repeatedCommandIDIsAnsweredAsAlreadyApplied() throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        let matchID = fixture.matchSession.currentSnapshot().matchID
        let payload = try commandPayload(matchID: matchID, revision: 0, kind: .recordPoint(.teamA))

        let first = try deliver(payload, to: fixture)
        let second = try deliver(payload, to: fixture)

        #expect(first.response.outcome == .accepted)
        #expect(second.response.outcome == .alreadyApplied)
    }

    @Test func durableReceiptIsAnsweredAsAlreadyApplied() throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        let matchID = try #require(fixture.matchSession.currentSnapshot().matchID)
        let commandID = UUID()
        fixture.receipts.receipts.insert(
            StubCommandReceiptStore.Key(matchID: matchID, commandID: commandID)
        )

        let result = try deliver(
            commandPayload(matchID: matchID, commandID: commandID, revision: 0, kind: .recordPoint(.teamA)),
            to: fixture
        )

        #expect(result.response.outcome == .alreadyApplied)
        #expect(fixture.matchSession.currentSnapshot().stateRevision == 0)
    }

    // MARK: - Every rejection reason

    @Test func rejectsMalformedCommandWhenMatchIDIsMissing() throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())

        let result = try deliver(
            commandPayload(matchID: nil, revision: 0, kind: .recordPoint(.teamA)),
            to: fixture
        )

        #expect(rejection(result.response) == .malformedCommand)
    }

    @Test func rejectsWrongMatch() throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())

        let result = try deliver(
            commandPayload(matchID: UUID(), revision: 0, kind: .recordPoint(.teamA)),
            to: fixture
        )

        #expect(rejection(result.response) == .wrongMatch)
    }

    @Test func rejectsNoLiveMatch() throws {
        let fixture = makeFixture()

        let result = try deliver(
            commandPayload(matchID: UUID(), revision: 0, kind: .recordPoint(.teamA)),
            to: fixture
        )

        #expect(rejection(result.response) == .noLiveMatch)
    }

    @Test func rejectsStaleRevision() async throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        let matchID = fixture.matchSession.currentSnapshot().matchID
        await recordPoint(for: .teamA, on: fixture)

        let result = try deliver(
            commandPayload(matchID: matchID, revision: 0, kind: .recordPoint(.teamA)),
            to: fixture
        )

        #expect(rejection(result.response) == .staleRevision)
        #expect(result.response.snapshot.stateRevision == 1)
    }

    @Test func rejectsMatchFinished() async throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try shortMatchConfiguration())
        let matchID = fixture.matchSession.currentSnapshot().matchID
        await winShortMatch(for: .teamA, on: fixture)

        let result = try deliver(
            commandPayload(matchID: matchID, revision: 8, kind: .recordPoint(.teamA)),
            to: fixture
        )

        #expect(rejection(result.response) == .matchFinished)
    }

    @Test func rejectsInvalidUndo() throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        let matchID = fixture.matchSession.currentSnapshot().matchID

        let result = try deliver(
            commandPayload(matchID: matchID, revision: 0, kind: .undo),
            to: fixture
        )

        #expect(rejection(result.response) == .invalidUndo)
    }

    @Test func rejectsPersistenceFailed() throws {
        let fixture = makeFixture(matchStoreURL: try makeUnwritableFileURL(name: "active-match.json"))
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        let matchID = fixture.matchSession.currentSnapshot().matchID

        let result = try deliver(
            commandPayload(matchID: matchID, revision: 0, kind: .recordPoint(.teamA)),
            to: fixture
        )

        #expect(rejection(result.response) == .persistenceFailed)
        // The rollback inside the view model must leave nothing applied.
        #expect(fixture.matchSession.currentSnapshot().stateRevision == 0)
    }

    // MARK: - Reply guarantees

    @Test func replyIsSentExactlyOnceForAnAcceptedCommand() throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        let matchID = fixture.matchSession.currentSnapshot().matchID

        let result = try deliver(
            commandPayload(matchID: matchID, revision: 0, kind: .recordPoint(.teamA)),
            to: fixture
        )

        #expect(result.replyCount == 1)
    }

    @Test func replyIsSentExactlyOnceForARejectedCommand() throws {
        let fixture = makeFixture()

        let result = try deliver(
            commandPayload(matchID: UUID(), revision: 0, kind: .undo),
            to: fixture
        )

        #expect(result.replyCount == 1)
        #expect(rejection(result.response) == .noLiveMatch)
    }

    @Test func replyIsSentExactlyOnceForAMalformedPayload() throws {
        let fixture = makeFixture()

        let result = try deliver([:], to: fixture)

        #expect(result.replyCount == 1)
        #expect(rejection(result.response) == .malformedCommand)
    }

    @Test func syncReplyHandlerDeliversOnlyTheFirstReply() {
        let recorder = ReplyRecorder()
        let handler = SyncReplyHandler { recorder.record($0) }

        handler.reply(["first": Data()])
        handler.reply(["second": Data()])
        handler.reply(["third": Data()])

        #expect(recorder.count == 1)
    }

    // MARK: - Snapshot publication (one mutation per turn)

    @Test func matchStartIsPublishedToApplicationContext() async throws {
        let fixture = makeFixture()

        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        await settle()

        let snapshot = try #require(fixture.transport.contextSnapshots.last)
        #expect(snapshot.sessionPhase == .live)
        #expect(snapshot.stateRevision == 0)
        #expect(snapshot.teamAPair.first == "Alex")
        #expect(snapshot.matchID != nil)
    }

    @Test func scoreIsPublishedToApplicationContext() async throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        await settle()
        fixture.transport.clearCaptured()

        await recordPoint(for: .teamA, on: fixture)

        let snapshot = try #require(fixture.transport.contextSnapshots.last)
        #expect(snapshot.stateRevision == 1)
        #expect(snapshot.currentPhase == .game(SyncGameScore(points: TeamPair(teamA: 1, teamB: 0))))
    }

    @Test func undoIsPublishedToApplicationContext() async throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        await settle()
        await recordPoint(for: .teamA, on: fixture)
        fixture.transport.clearCaptured()

        fixture.matchSession.undoLastEffectivePoint()
        await settle()

        let snapshot = try #require(fixture.transport.contextSnapshots.last)
        #expect(snapshot.stateRevision == 2)
        #expect(snapshot.currentPhase == .game(SyncGameScore(points: TeamPair(teamA: 0, teamB: 0))))
    }

    @Test func finishIsPublishedToApplicationContext() async throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try shortMatchConfiguration())
        await settle()
        await winShortMatch(for: .teamA, on: fixture)
        fixture.transport.clearCaptured()

        fixture.matchSession.finishMatch()
        await settle()

        let snapshot = try #require(fixture.transport.contextSnapshots.last)
        #expect(snapshot.sessionPhase == .finished)
        #expect(snapshot.matchWinner == .teamA)
    }

    @Test func discardToSetupIsPublishedToApplicationContext() async throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        await settle()
        fixture.transport.clearCaptured()

        fixture.matchSession.returnToSetup()
        await settle()

        let snapshot = try #require(fixture.transport.contextSnapshots.last)
        #expect(snapshot.sessionPhase == .setup)
        #expect(snapshot.matchID == nil)
        #expect(snapshot.stateRevision == 0)
    }

    @Test func aNewMatchPublishesANewMatchIDAndRevision() async throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        await settle()
        await recordPoint(for: .teamA, on: fixture)
        let firstMatchID = try #require(fixture.transport.contextSnapshots.last).matchID

        fixture.matchSession.returnToSetup()
        await settle()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        await settle()

        let snapshot = try #require(fixture.transport.contextSnapshots.last)
        #expect(snapshot.matchID != nil)
        #expect(snapshot.matchID != firstMatchID)
        #expect(snapshot.stateRevision == 0)
    }

    @Test func sendMessageIsUsedOnlyWhileReachable() async throws {
        let fixture = makeFixture()
        fixture.transport.isReachable = false

        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        await settle()

        #expect(fixture.transport.applicationContexts.count == 1)
        #expect(fixture.transport.sentMessages.isEmpty)

        fixture.transport.isReachable = true
        await recordPoint(for: .teamA, on: fixture)

        #expect(fixture.transport.applicationContexts.count == 2)
        #expect(fixture.transport.messageSnapshots.last?.stateRevision == 1)
    }

    @Test func applicationContextFailureIsRecordedAndLeavesMatchStateIntact() async throws {
        let fixture = makeFixture()
        fixture.transport.contextUpdateError = FakePhoneConnectivitySession.TransportFailure()

        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        await settle()

        #expect(fixture.service.lastTransportError != nil)
        #expect(fixture.transport.applicationContexts.isEmpty)
        #expect(fixture.matchSession.currentSnapshot().sessionPhase == .live)
    }

    // MARK: - Duplicate protection and concurrency

    @Test func retryOfTheSameCommandDoesNotScoreTwice() throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        let matchID = fixture.matchSession.currentSnapshot().matchID
        let payload = try commandPayload(matchID: matchID, revision: 0, kind: .recordPoint(.teamA))

        let first = try deliver(payload, to: fixture)
        let retry = try deliver(payload, to: fixture)

        #expect(first.response.outcome == .accepted)
        #expect(retry.response.outcome == .alreadyApplied)
        #expect(fixture.matchSession.state?.currentPhase == .game(GameScore(points: TeamPair(teamA: 1, teamB: 0))))
        #expect(fixture.matchSession.currentSnapshot().stateRevision == 1)
    }

    @Test func commandDeliveredOffMainReachesTheMainActor() async throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try MatchConfiguration())
        let matchID = fixture.matchSession.currentSnapshot().matchID
        let command = SyncCommand(
            matchID: matchID,
            commandID: UUID(),
            expectedStateRevision: 0,
            kind: .recordPoint(.teamA)
        )
        let recorder = ReplyRecorder()
        let transport = fixture.transport

        await Task.detached {
            transport.deliverCommandFromBackground(command, into: recorder)
        }.value
        await settle()

        #expect(recorder.count == 1)
        #expect(recorder.responses.first?.outcome == .accepted)
        #expect(fixture.matchSession.currentSnapshot().stateRevision == 1)
    }

    @Test func commandAfterFinishIsRefusedAndNothingIsPersisted() async throws {
        let fixture = makeFixture()
        startLinkedMatch(on: fixture, configuration: try shortMatchConfiguration())
        let matchID = fixture.matchSession.currentSnapshot().matchID
        await winShortMatch(for: .teamA, on: fixture)
        fixture.matchSession.finishMatch()
        await settle()

        let result = try deliver(
            commandPayload(matchID: matchID, revision: 9, kind: .recordPoint(.teamA)),
            to: fixture
        )

        #expect(rejection(result.response) == .matchFinished)
        #expect(fixture.matchStore.load() == nil)
    }
}
