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

    // Rising-edge contact alerting: fire once on clear -> car, re-arm only
    // after the road has been clear for ~1 s so flickering contacts do not
    // re-trigger the cue.
    private var contactArmed = true
    private var clearStreak = 0

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
        contactArmed = true
        clearStreak = 0
    }

    private func makeSource() -> RadarSource {
        switch sourceKind {
        case .real: return BLERadarSource()
        case .demo: return ScriptedRadarSource(scenario: .busyRoad)
        }
    }

    private func handle(_ frame: RadarFrame) {
        self.frame = frame
        let presentation = RadarPresentation(frame: frame, now: frame.receivedAt ?? Date())
        AppGroup.writeSnapshot(presentation)
        WatchLink.shared.send(presentation)

        if frame.isClear {
            clearStreak += 1
            if clearStreak >= 8 { contactArmed = true } // ~1 s clear re-arms
            activity.update(presentation)
            return
        }

        clearStreak = 0
        let rising = contactArmed
        if rising { contactArmed = false }
        let appActive = UIApplication.shared.applicationState == .active
        // Foreground: play our cue directly. Background: let the Live
        // Activity alert play the system cue (so it sounds with the app
        // suspended, and we never double up).
        activity.update(presentation, alerting: rising && !appActive)
        if rising && appActive { alertPlayer.playContactAlert() }
    }
}
