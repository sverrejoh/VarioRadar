import Combine
import Foundation
import UIKit
import VarioRadarCore

/// The single source of truth for the UI. Owns a `RadarSource`, pumps its
/// frames into published state, mirrors each frame to the App Group
/// snapshot, and drives the Live Activity.
///
/// The source is chosen at runtime from ``SourceKind`` (live BLE radar or
/// scripted demo traffic) so the user can switch on the phone without a
/// rebuild. The choice is persisted.
@MainActor
final class RadarSessionStore: ObservableObject {
    enum SourceKind: String {
        case real   // CoreBluetooth, a real Varia (or FakeVaria peripheral)
        case demo   // scripted traffic, no hardware needed
    }

    @Published private(set) var frame: RadarFrame?
    @Published private(set) var status: RadarConnectionStatus = .idle
    @Published private(set) var isRunning = false
    @Published private(set) var sourceKind: SourceKind
    /// Name of the connected device (e.g. "RCT716-78425", "FakeVaria",
    /// "Demo"), or nil before connection.
    @Published private(set) var deviceName: String?

    private var source: RadarSource?
    private let activity = RadarActivityManager()
    private let alertPlayer = AlertPlayer()
    private let kindDefaultsKey = "radarSourceKind"

    // Contact alerting: fire on clear -> car. Re-arms on any clear frame
    // (so every genuine "car appears" chimes), but a cooldown prevents the
    // cue from machine-gunning when traffic is continuous. Starts disarmed
    // so a session that opens with a car already present does not ding.
    private var contactArmed = false
    private var lastContactAlert = Date.distantPast
    private let alertCooldown: TimeInterval = 2.5

    // Live Activity update throttling (see handle).
    private var lastIslandUpdate = Date.distantPast
    private var lastImportantSignature = ""
    private var lastSnapshot = Date.distantPast

    init(defaultKind: SourceKind) {
        let stored = UserDefaults.standard.string(forKey: "radarSourceKind")
        self.sourceKind = stored.flatMap(SourceKind.init(rawValue:)) ?? defaultKind
        WatchLink.shared.activate()
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in SessionLogger.shared.log("app -> background") }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { _ in SessionLogger.shared.log("app -> foreground") }
    }

    var presentation: RadarPresentation {
        guard let frame else { return .clear }
        return RadarPresentation(frame: frame, now: frame.receivedAt ?? Date())
    }

    /// Switch between live radar and demo data. Safe to call mid-session:
    /// it restarts cleanly on the new source.
    func setSourceKind(_ kind: SourceKind) {
        guard kind != sourceKind else { return }
        let wasRunning = isRunning
        if wasRunning { stop() }
        sourceKind = kind
        UserDefaults.standard.set(kind.rawValue, forKey: kindDefaultsKey)
        if wasRunning { start() }
    }

    func start() {
        guard !isRunning else { return }
        SessionLogger.shared.start()
        SessionLogger.shared.log("source=\(sourceKind.rawValue)")
        NotificationManager.shared.requestAuthorization()
        let source = makeSource()
        source.onFrame = { [weak self] frame in self?.handle(frame) }
        source.onStatus = { [weak self] status in self?.status = status }
        source.onDeviceName = { [weak self] name in self?.deviceName = name }
        self.source = source
        isRunning = true
        activity.start()
        source.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        SessionLogger.shared.stop()
        source?.stop()
        source = nil
        activity.end()
        frame = nil
        deviceName = nil
        status = .idle
        contactArmed = false
        lastContactAlert = .distantPast
        lastIslandUpdate = .distantPast
        lastImportantSignature = ""
        lastSnapshot = .distantPast
    }

    private func makeSource() -> RadarSource {
        switch sourceKind {
        case .real: return BLERadarSource()
        case .demo: return ScriptedRadarSource(scenario: .busyRoad)
        }
    }

    private func handle(_ frame: RadarFrame) {
        let now = Date()
        self.frame = frame  // in-app UI updates every frame (no throttle)
        let presentation = RadarPresentation(frame: frame, now: frame.receivedAt ?? Date())

        // Determine the contact-alert rising edge first; an alert always
        // forces an immediate Live Activity update regardless of throttle.
        var rising = false
        if frame.isClear {
            contactArmed = true
        } else if contactArmed, now.timeIntervalSince(lastContactAlert) > alertCooldown {
            rising = true
            contactArmed = false
            lastContactAlert = now
        } else {
            contactArmed = false
        }

        // Live Activity update budget management. Ride logs show that
        // sending a steady ~1 Hz for many minutes exhausts the background
        // update budget, after which iOS drops most island renders
        // ("random / nothing happens"). So spend the budget on the events
        // the rider watches for: a car appearing/dropping or a severity
        // change updates immediately (>= 0.3 s apart to absorb flicker);
        // pure movement only refreshes every ~4 s (still under the 5 s
        // stale window), with on-device interpolation carrying the motion
        // in between. This keeps our footprint low so arrivals/departures
        // actually render in the background.
        let importantSig = presentation.isClear
            ? "clear" : "\(presentation.threatCount)|\(presentation.highestLevelRaw)"
        let elapsed = now.timeIntervalSince(lastIslandUpdate)
        let importantChanged = importantSig != lastImportantSignature
        if rising || (importantChanged && elapsed >= 0.3) || elapsed >= 4.0 {
            lastIslandUpdate = now
            lastImportantSignature = importantSig
            let appActive = UIApplication.shared.applicationState == .active
            activity.update(presentation, alerting: rising && !appActive)
            if rising && appActive { alertPlayer.playContactAlert() }
            if rising {
                NotificationManager.shared.notifyContact(distanceMeters: presentation.nearestDistanceMeters)
                SessionLogger.shared.log("ALERT contact nearest=\(presentation.nearestDistanceMeters ?? -1)m sev=\(presentation.highestLevelRaw)")
            }
            SessionLogger.shared.log("island \(presentation.isClear ? "clear" : "n=\(presentation.threatCount) nearest=\(presentation.nearestDistanceMeters ?? -1)m sev=\(presentation.highestLevelRaw)")")
        }

        // App Group snapshot (widgets) at ~1 Hz; watch link self-throttles.
        if now.timeIntervalSince(lastSnapshot) >= 1.0 {
            lastSnapshot = now
            AppGroup.writeSnapshot(presentation)
        }
        WatchLink.shared.send(presentation)
    }
}
