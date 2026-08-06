import Foundation
import Observation
import MadrabSyncKit

/// The iPhone's Watch-facing transport layer.
///
/// It owns the `WCSession`, decodes Watch commands, and hands every one of
/// them to `MatchSessionViewModel.applyRemoteCommand(_:)` — the single
/// authority path. It never touches the engine, the event log, or any store
/// itself, so nothing here can give the Watch scoring authority: the phone
/// validates, applies, persists, and only then answers.
@MainActor
@Observable
final class PhoneSyncService {
    private(set) var isActivated = false
    private(set) var isReachable = false
    /// Last transport-level failure, for diagnostics only. Never affects the
    /// authoritative match state.
    private(set) var lastTransportError: String?

    /// Stands in for the `commandID` of a payload that could not be decoded at
    /// all. `SyncCommandResponse.commandID` is not optional and there is no ID
    /// to echo — this is a value, not a new wire field. A Watch must not read
    /// it as an acknowledgement of its own pending command.
    static let unidentifiedCommandID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    private let session: PhoneConnectivitySession
    private let matchSession: MatchSessionViewModel
    /// `activate()` is driven from a SwiftUI `.task`, which can run again
    /// after a view identity change. Activating a `WCSession` twice is
    /// pointless work with a delegate reassignment in the middle, so the
    /// second and later calls are dropped.
    private var hasActivated = false

    /// `AppEnvironment` owns both objects and `matchSession` holds no
    /// reference back, so this strong reference forms no cycle. The session
    /// holds `events` weakly, exactly as on the Watch.
    init(session: PhoneConnectivitySession, matchSession: MatchSessionViewModel) {
        self.session = session
        self.matchSession = matchSession
        session.events = self
        observeMatchSession()
    }

    // MARK: - Lifecycle

    /// Idempotent: only the first call reaches the transport.
    func activate() {
        guard !hasActivated else { return }
        hasActivated = true
        session.activate()
    }

    // MARK: - Snapshot broadcast

    /// Publishes the phone's authoritative snapshot on both outbound channels:
    /// `updateApplicationContext` for durable latest-state delivery (survives
    /// an unreachable or backgrounded Watch), and `sendMessage` for an
    /// immediate update while the Watch is actually reachable. Direct reply
    /// handlers carry the third delivery path.
    ///
    /// `lastAcknowledgedCommandID` stays `nil`: a broadcast acknowledges no
    /// command, so the Watch can never read an acknowledgement into one.
    func broadcastCurrentSnapshot() {
        guard let payload = try? SyncPayload.encodeSnapshot(matchSession.currentSnapshot()) else { return }

        do {
            try session.updateApplicationContext(payload)
        } catch {
            lastTransportError = error.localizedDescription
        }

        if session.isReachable {
            session.sendMessage(payload)
        }
    }

    /// Re-broadcasts whenever the phone's own match state changes. Match
    /// start, score, undo, finish, restore, and the discard/setup transition
    /// all reassign `MatchSessionViewModel.phase`, so tracking that one
    /// property covers every case without adding a hook to the view model.
    ///
    /// `onChange` fires *before* the mutation lands, so the broadcast is
    /// deferred by one main-actor turn and tracking is re-registered from that
    /// same hop. Mutations that land within a single turn therefore coalesce
    /// into one broadcast — which is correct, because the broadcast always
    /// reads current truth rather than a captured intermediate value.
    private func observeMatchSession() {
        withObservationTracking {
            _ = matchSession.phase
        } onChange: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.broadcastCurrentSnapshot()
                self.observeMatchSession()
            }
        }
    }

    // MARK: - Command handling

    /// Decodes, applies, and answers exactly one Watch command. There is a
    /// single `reply.reply(…)` site, reached on every path;
    /// `SyncReplyHandler` additionally drops a second call, so a coding
    /// mistake can never trap `WCSession`.
    private func handleCommandPayload(_ payload: [String: Any], reply: SyncReplyHandler) {
        let response: SyncCommandResponse

        if let command = SyncPayload.decodeCommand(from: payload) {
            // The only scoring/undo path. All validation, mutation,
            // persistence, and outcome selection happen inside this call.
            response = matchSession.applyRemoteCommand(command)
        } else {
            // Malformed or foreign payload: nothing is mutated, and the Watch
            // still gets the best available authoritative snapshot so it can
            // resynchronise rather than sit on stale state.
            response = SyncCommandResponse(
                commandID: Self.unidentifiedCommandID,
                outcome: .rejected(.malformedCommand),
                snapshot: matchSession.currentSnapshot()
            )
        }

        // Encoding a fixed Codable struct of UUIDs, enums, ints, and strings
        // has no realistic failure mode; an empty reply is sent rather than
        // none at all, because the reply contract is unconditional.
        reply.reply((try? SyncPayload.encodeResponse(response)) ?? [:])
    }
}

// MARK: - Transport events

extension PhoneSyncService: PhoneConnectivitySessionEvents {
    func sessionActivationDidChange(isActivated: Bool) {
        self.isActivated = isActivated
        if isActivated {
            // Seed the durable context immediately, so a Watch that launches
            // later has current truth to show before it asks for any.
            broadcastCurrentSnapshot()
        }
    }

    func sessionReachabilityDidChange(isReachable: Bool) {
        let regainedReachability = !self.isReachable && isReachable
        self.isReachable = isReachable
        if regainedReachability {
            broadcastCurrentSnapshot()
        }
    }

    func sessionDidReceiveCommandPayload(_ payload: [String: Any], reply: SyncReplyHandler) {
        handleCommandPayload(payload, reply: reply)
    }
}
