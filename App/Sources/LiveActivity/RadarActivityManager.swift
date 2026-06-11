import ActivityKit
import Foundation

/// Owns the lifecycle of the radar Live Activity: start on session begin,
/// update on every frame, end on session stop.
///
/// Updates are local (driven from the in-app BLE callback), which is the
/// path that works while another app is foreground as long as the BLE
/// connection is alive. A push token path can be layered on later for the
/// case where the app is fully suspended; the staleness date tells the
/// system when to dim the activity if updates stop.
@MainActor
final class RadarActivityManager {
    private var activity: Activity<RadarActivityAttributes>?

    var isActive: Bool { activity != nil }

    func start(sessionName: String = "Ride") {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        let attributes = RadarActivityAttributes(sessionName: sessionName)
        let state = RadarActivityAttributes.ContentState(presentation: .clear)
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            activity = try Activity.request(attributes: attributes, content: content)
        } catch {
            print("Live Activity start failed: \(error)")
        }
    }

    func update(_ presentation: RadarPresentation) {
        guard let activity else { return }
        // A frame should arrive every second; if it stops for 5, let the
        // system mark the activity stale so the rider does not trust an
        // old reading.
        let state = RadarActivityAttributes.ContentState(presentation: presentation)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(5))
        Task { await activity.update(content) }
    }

    func end() {
        guard let activity else { return }
        let current = activity.content
        Task { await activity.end(current, dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
