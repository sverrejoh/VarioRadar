import Foundation
import WatchConnectivity

/// Relays the latest radar snapshot to the Apple Watch over
/// WatchConnectivity. Uses `updateApplicationContext` (latest-wins,
/// coalesced by the system) rather than a queue, which is the right
/// primitive for streaming "current state" to a glanceable wrist display.
@MainActor
final class WatchLink: NSObject {
    static let shared = WatchLink()
    private var lastSent = Date.distantPast

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ presentation: RadarPresentation) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        // Throttle to ~2 Hz; the wrist cannot use more and it saves power.
        let now = Date()
        guard now.timeIntervalSince(lastSent) > 0.45 else { return }
        lastSent = now
        guard let data = try? JSONEncoder().encode(presentation) else { return }
        try? session.updateApplicationContext(["p": data])
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
