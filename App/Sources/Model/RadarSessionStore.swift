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

        // Throttle Live Activity updates. Flooding ActivityKit at the
        // radar's ~8 Hz makes the system coalesce and lag everything.
        // Important signals (a car appears/drops, severity changes) must
        // always pass immediately; only pure movement is rate-limited, and
        // the view interpolates motion between snapshots on-device.
        // Demo (a steady 1 Hz) renders smoothly in the background, so 1 Hz
        // sits within the system budget. Match it: pure movement rides a
        // 1 Hz cadence (motion is interpolated on-device between snapshots),
        // important changes (car appears/drops, severity) get a faster 0.5 s
        // floor, and an alert always passes immediately. Sending more than
        // this overruns the background budget and makes live LAG behind demo.
        let importantSig = presentation.isClear
            ? "clear" : "\(presentation.threatCount)|\(presentation.highestLevelRaw)"
        let elapsed = now.timeIntervalSince(lastIslandUpdate)
        let importantChanged = importantSig != lastImportantSignature
        if rising || elapsed >= 1.0 || (importantChanged && elapsed >= 0.5) {
            lastIslandUpdate = now
            lastImportantSignature = importantSig
            let appActive = UIApplication.shared.applicationState == .active
            activity.update(presentation, alerting: rising && !appActive)
            if rising && appActive { alertPlayer.playContactAlert() }
        }

        // App Group snapshot (widgets) at ~1 Hz; watch link self-throttles.
        if now.timeIntervalSince(lastSnapshot) >= 1.0 {
            lastSnapshot = now
            AppGroup.writeSnapshot(presentation)
        }
        WatchLink.shared.send(presentation)
    }
}
