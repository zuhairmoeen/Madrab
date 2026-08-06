import Foundation
import WatchConnectivity

/// The slice of `WCSession` the phone service actually uses. Mirrors the
/// Watch's `WatchConnectivitySession` so both halves of the sprint are tested
/// the same way: against a fake, with no paired device and no radio involved.
protocol PhoneConnectivitySession: AnyObject {
    var isReachable: Bool { get }
    var isActivated: Bool { get }

    /// Set by `PhoneSyncService` before activation so transport events can be
    /// delivered back to it.
    var events: PhoneConnectivitySessionEvents? { get set }

    func activate()

    /// Durable latest-state delivery: the Watch reads this whenever it next
    /// launches or foregrounds, reachable or not. Throws when no counterpart
    /// is available; the caller records that and carries on.
    func updateApplicationContext(_ payload: [String: Any]) throws

    /// Immediate best-effort push, meaningful only while reachable.
    func sendMessage(_ payload: [String: Any])
}

/// Transport callbacks, delivered on the main actor. The real `WCSession`
/// delivers its delegate callbacks on an arbitrary queue; the concrete session
/// below is responsible for hopping before calling any of these.
@MainActor
protocol PhoneConnectivitySessionEvents: AnyObject {
    func sessionActivationDidChange(isActivated: Bool)
    func sessionReachabilityDidChange(isReachable: Bool)
    func sessionDidReceiveCommandPayload(_ payload: [String: Any], reply: SyncReplyHandler)
}

/// Wraps `WCSession`'s reply closure.
///
/// Two jobs: carry a non-`Sendable` closure across the hop to the main actor,
/// and guarantee the phone answers a command **at most once** — `WCSession`
/// traps on a second reply. Answering *at least* once is guaranteed separately,
/// by `PhoneSyncService` replying on every path through command handling.
nonisolated final class SyncReplyHandler: @unchecked Sendable {
    private let handler: ([String: Any]) -> Void
    private let lock = NSLock()
    private var hasReplied = false

    init(_ handler: @escaping ([String: Any]) -> Void) {
        self.handler = handler
    }

    func reply(_ payload: [String: Any]) {
        lock.lock()
        let alreadyReplied = hasReplied
        hasReplied = true
        lock.unlock()

        guard !alreadyReplied else { return }
        handler(payload)
    }
}

/// Concrete `WCSession` wrapper for the iPhone.
///
/// `WCSessionDelegate` callbacks arrive on a background queue, so the delegate
/// conformance is `nonisolated` and every callback hops to the main actor
/// before touching service state. Only `Sendable` values cross that boundary:
/// the payload dictionaries carry `Data` produced by `JSONEncoder`, never live
/// objects.
final class LivePhoneConnectivitySession: NSObject, PhoneConnectivitySession {
    weak var events: PhoneConnectivitySessionEvents?

    private let session: WCSession

    var isReachable: Bool { session.isReachable }
    var isActivated: Bool { session.activationState == .activated }

    init(session: WCSession = .default) {
        self.session = session
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func updateApplicationContext(_ payload: [String: Any]) throws {
        try session.updateApplicationContext(payload)
    }

    func sendMessage(_ payload: [String: Any]) {
        guard session.isReachable else { return }
        // Snapshot pushes need no reply: the Watch adopts or ignores them by
        // revision, and `updateApplicationContext` is the durable channel.
        session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
    }
}

extension LivePhoneConnectivitySession: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let activated = activationState == .activated
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.events?.sessionActivationDidChange(isActivated: activated)
            self?.events?.sessionReachabilityDidChange(isReachable: reachable)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.events?.sessionReachabilityDidChange(isReachable: reachable)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        let reply = SyncReplyHandler(replyHandler)
        Task { @MainActor [weak self] in
            guard let events = self?.events else {
                // Nothing is left to answer the command, but the reply
                // contract is unconditional — an empty reply beats leaving the
                // Watch waiting forever. This is the transport's
                // service-is-gone path, not a second reply site inside
                // command handling.
                reply.reply([:])
                return
            }
            events.sessionDidReceiveCommandPayload(message, reply: reply)
        }
    }

    // iOS-only `WCSessionDelegate` requirements. Reactivating on deactivation
    // is the standard handling for a switch to a different paired Watch; it
    // carries no authority implication — the phone stays the sole authority.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
