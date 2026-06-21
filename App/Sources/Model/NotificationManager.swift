import UIKit
import UserNotifications

/// Posts a Time Sensitive banner when traffic first appears, so the rider
/// gets a reliable nudge that does not depend on the throttled Live
/// Activity. Kept unobtrusive: background only, silent (the radar's own cue
/// already chimes), and rate-limited so it never nags per car.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private var authorized = false
    private var lastNotified = Date.distantPast
    private let cooldown: TimeInterval = 90

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
    }

    /// Call on a clear -> car rising edge. Only fires when backgrounded
    /// (foreground, the rider sees the app) and at most once per cooldown.
    func notifyContact(distanceMeters: Int?) {
        guard authorized else { return }
        guard UIApplication.shared.applicationState != .active else { return }
        let now = Date()
        guard now.timeIntervalSince(lastNotified) > cooldown else { return }
        lastNotified = now

        let content = UNMutableNotificationContent()
        content.title = "Traffic behind you"
        content.body = distanceMeters.map { "A vehicle is approaching (\($0) m)." }
            ?? "A vehicle is approaching."
        content.interruptionLevel = .timeSensitive
        content.sound = nil // the radar cue already plays; keep the banner silent

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
