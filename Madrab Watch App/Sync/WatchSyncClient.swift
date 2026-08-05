import Foundation
import Observation
import MadrabScoringEngine
import MadrabSyncKit

/// The Watch's view of a phone-authoritative match.
///
/// This type never mutates score state. It sends commands, displays whatever
/// snapshot the iPhone returns, and nothing else — there is no local scoring,
/// no optimistic increment, and no offline queue. When the phone is
/// unreachable the last known snapshot stays on screen and the client reports
/// itself read-only.
@MainActor
@Observable
final class WatchSyncClient {
    /// The phone's most recent authoritative view, or `nil` before the first
    /// snapshot arrives.
    private(set) var latestSnapshot: SyncSnapshot?
    private(set) var isActivated = false
    private(set) var isReachable = false
    /// The command awaiting a reply. Non-nil blocks further scoring commands
    /// so two mutations can never be in flight at once.
    private(set) var pendingCommand: SyncCommand?
    /// Why the phone refused the most recent command, if it did.
    private(set) var lastRejection: SyncRejectionReason?
    /// Transport-level failure text, for the diagnostic screen.
    private(set) var lastTransportError: String?

    /// Scoring and undo are unavailable unless the phone can actually be
    /// reached — the Watch is strictly read-only otherwise.
    var isReadOnly: Bool { !isActivated || !isReachable }

    /// True while a command is in flight; the UI disables further input.
    var hasPendingCommand: Bool { pendingCommand != nil }

    private let session: WatchConnectivitySession
    private let makeCommandID: () -> UUID
    private let now: () -> Date

    init(
        session: WatchConnectivitySession,
        makeCommandID: @escaping () -> UUID = { UUID() },
        now: @escaping () -> Date = { Date() }
    ) {
        self.session = session
        self.makeCommandID = makeCommandID
        self.now = now
        session.events = self
    }

    // MARK: - Lifecycle

    func activate() {
        session.activate()
    }

    // MARK: - Sending

    /// Asks the phone for its current truth. Never occupies the pending slot:
    /// it is a pure read, safe to repeat, and valid even before the Watch
    /// knows which match is active.
    func requestLatestState() {
        guard isActivated, isReachable else { return }
        send(
            SyncCommand(
                matchID: latestSnapshot?.matchID,
                commandID: makeCommandID(),
                expectedStateRevision: latestSnapshot?.stateRevision ?? 0,
                kind: .requestLatestState,
                sentAt: now()
            ),
            isPending: false
        )
    }

    func recordPoint(for team: Team) {
        sendScoringCommand(kind: .recordPoint(team))
    }

    func undo() {
        sendScoringCommand(kind: .undo)
    }

    /// Resends the in-flight command **with its original `commandID`**, so the
    /// phone recognises a retry after a lost reply as a duplicate rather than
    /// scoring it a second time.
    func retryPendingCommand() {
        guard let pendingCommand, isActivated, isReachable else { return }
        send(pendingCommand, isPending: true)
    }

    /// Abandons the in-flight command locally. The phone may still have
    /// applied it, so the next snapshot remains authoritative.
    func cancelPendingCommand() {
        pendingCommand = nil
    }

    private func sendScoringCommand(kind: SyncCommandKind) {
        guard !isReadOnly, pendingCommand == nil else { return }
        // A scoring command must address a known, specific match.
        guard let snapshot = latestSnapshot, let matchID = snapshot.matchID else { return }

        let command = SyncCommand(
            matchID: matchID,
            commandID: makeCommandID(),
            expectedStateRevision: snapshot.stateRevision,
            kind: kind,
            sentAt: now()
        )
        send(command, isPending: true)
    }

    private func send(_ command: SyncCommand, isPending: Bool) {
        guard let payload = try? SyncPayload.encodeCommand(command) else { return }

        if isPending {
            pendingCommand = command
            lastRejection = nil
        }
        lastTransportError = nil

        session.sendMessage(
            payload,
            replyHandler: { [weak self] reply in
                Task { @MainActor in
                    self?.handleReply(reply, for: command)
                }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    self?.handleTransportFailure(error, for: command)
                }
            }
        )
    }

    // MARK: - Receiving

    private func handleReply(_ reply: [String: Any], for command: SyncCommand) {
        // A reply may carry a full response, or just a snapshot for reads.
        if let response = SyncPayload.decodeResponse(from: reply) {
            adopt(response.snapshot)

            switch response.outcome {
            case .accepted, .alreadyApplied:
                lastRejection = nil
            case .rejected(let reason):
                lastRejection = reason
            }

            // Only the command actually answered leaves the pending slot.
            if pendingCommand?.commandID == response.commandID {
                pendingCommand = nil
            }
            return
        }

        if let snapshot = SyncPayload.decodeSnapshot(from: reply) {
            adopt(snapshot)
            if pendingCommand?.commandID == command.commandID {
                pendingCommand = nil
            }
        }
    }

    /// A transport failure leaves the command pending: the phone may or may
    /// not have applied it, and only a retry of the same `commandID` can
    /// resolve that safely.
    private func handleTransportFailure(_ error: Error, for command: SyncCommand) {
        lastTransportError = error.localizedDescription
    }

    /// Adopts a snapshot only when it is genuinely newer.
    ///
    /// Revisions are comparable only within one match: a different `matchID`
    /// means a different event log, so its revision is adopted outright
    /// rather than compared against the previous match's.
    private func adopt(_ incoming: SyncSnapshot) {
        guard let current = latestSnapshot else {
            latestSnapshot = incoming
            return
        }

        if current.matchID != incoming.matchID {
            latestSnapshot = incoming
        } else if incoming.stateRevision >= current.stateRevision {
            latestSnapshot = incoming
        }
        // Otherwise the incoming snapshot is stale and is ignored.
    }
}

// MARK: - Transport events

extension WatchSyncClient: WatchConnectivitySessionEvents {
    func sessionActivationDidChange(isActivated: Bool) {
        self.isActivated = isActivated
        if isActivated {
            requestLatestState()
        }
    }

    func sessionReachabilityDidChange(isReachable: Bool) {
        let regainedReachability = !self.isReachable && isReachable
        self.isReachable = isReachable
        if regainedReachability {
            requestLatestState()
        }
    }

    func sessionDidReceiveSnapshotPayload(_ payload: [String: Any]) {
        guard let snapshot = SyncPayload.decodeSnapshot(from: payload) else { return }
        adopt(snapshot)
    }
}
