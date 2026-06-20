import Foundation
import WatchConnectivity

/// Receives the latest radar snapshot the phone relays over
/// WatchConnectivity. The phone pushes the newest `RadarPresentation` via
/// `updateApplicationContext` (latest-wins, coalesced), which suits a
/// glanceable wrist display and is battery friendly.
@MainActor
final class WatchRadarModel: NSObject, ObservableObject {
    @Published var presentation: RadarPresentation = .clear
    @Published var hasData = false

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        apply(WCSession.default.receivedApplicationContext)
    }

    private func apply(_ context: [String: Any]) {
        guard let data = context["p"] as? Data,
              let p = try? JSONDecoder().decode(RadarPresentation.self, from: data) else { return }
        presentation = p
        hasData = true
    }
}

extension WatchRadarModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {}

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.apply(context) }
    }
}
