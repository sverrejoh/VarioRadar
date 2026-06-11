import ActivityKit
import Foundation
import OSLog

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
    private var updateCount = 0
    private let log = Logger(subsystem: "com.varioradar", category: "activity")

    private func trace(_ message: String) {
        log.info("\(message, privacy: .public)")
        print("[activity] \(message)")
    }

    var isActive: Bool { activity != nil }

    func start(sessionName: String = "Ride") {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            trace("Live Activities are disabled for this app")
            return
        }
        guard activity == nil else { return }

        // Live Activities outlive the app process. End any orphans from a
        // previous run first, otherwise the system keeps showing a stale
        // activity that no one is updating.
        let orphans = Activity<RadarActivityAttributes>.activities
        if !orphans.isEmpty {
            trace("Ending \(orphans.count) orphaned activit\(orphans.count == 1 ? "y" : "ies")")
            for orphan in orphans {
                Task { await orphan.end(nil, dismissalPolicy: .immediate) }
            }
        }

        let attributes = RadarActivityAttributes(sessionName: sessionName)
        let state = RadarActivityAttributes.ContentState(presentation: .clear)
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            let started = try Activity.request(attributes: attributes, content: content)
            activity = started
            updateCount = 0
            trace("Started activity \(started.id)")
        } catch {
            trace("Activity request FAILED: \(error.localizedDescription)")
        }
    }

    func update(_ presentation: RadarPresentation) {
        guard let activity else { return }
        // A frame should arrive every second; if it stops for 5, let the
        // system mark the activity stale so the rider does not trust an
        // old reading.
        let state = RadarActivityAttributes.ContentState(presentation: presentation)
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(5))
        updateCount += 1
        if updateCount == 1 || updateCount % 30 == 0 {
            trace("Update #\(self.updateCount): \(presentation.isClear ? "clear" : "\(presentation.threatCount) car(s), nearest \(presentation.nearestDistanceMeters ?? -1) m") -> \(activity.id)")
        }
        Task { await activity.update(content) }
    }

    func end() {
        guard let activity else { return }
        trace("Ending activity \(activity.id) after \(updateCount) updates")
        let current = activity.content
        Task { await activity.end(current, dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
