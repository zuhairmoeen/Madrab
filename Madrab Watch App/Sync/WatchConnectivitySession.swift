import Foundation
import WatchConnectivity

/// The slice of `WCSession` the Watch client actually uses. Extracting it as
/// a protocol lets every command, retry, and snapshot rule be tested against
/// a fake, with no paired device and no real radio involved.
protocol WatchConnectivitySession: AnyObject {
    var isReachable: Bool { get }
    var isActivated: Bool { get }

    /// Set by `WatchSyncClient` before activation so transport events can be
    /// delivered back to it.
    var events: WatchConnectivitySessionEvents? { get set }

    func activate()
    func sendMessage(
        _ payload: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void,
        errorHandler: @escaping (Error) -> Void
    )
}

/// Transport callbacks, delivered on the main actor. The real `WCSession`
/// delivers its delegate callbacks on an arbitrary queue; the concrete
/// session below is responsible for hopping before calling any of these.
@MainActor
protocol WatchConnectivitySessionEvents: AnyObject {
    func sessionActivationDidChange(isActivated: Bool)
    func sessionReachabilityDidChange(isReachable: Bool)
    func sessionDidReceiveSnapshotPayload(_ payload: [String: Any])
}

/// Concrete `WCSession` wrapper.
///
/// `WCSessionDelegate` callbacks arrive on a background queue, so the
/// delegate conformance is `nonisolated` and every callback hops to the main
/// actor before touching client state. Only `Sendable` values cross that
/// boundary: the payload dictionaries carry `Data` produced by
/// `JSONEncoder`, never live objects.
final class LiveWatchConnectivitySession: NSObject, WatchConnectivitySession {
    weak var events: WatchConnectivitySessionEvents?

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

    func sendMessage(
        _ payload: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void,
        errorHandler: @escaping (Error) -> Void
    ) {
        session.sendMessage(payload, replyHandler: replyHandler, errorHandler: errorHandler)
    }
}

extension LiveWatchConnectivitySession: WCSessionDelegate {
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
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        Task { @MainActor [weak self] in
            self?.events?.sessionDidReceiveSnapshotPayload(applicationContext)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor [weak self] in
            self?.events?.sessionDidReceiveSnapshotPayload(message)
        }
    }
}
