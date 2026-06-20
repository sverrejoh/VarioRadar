import Foundation
import VarioRadarCore

/// A radar source that replays a `RadarScript` at 1 Hz. Used in the
/// simulator (which has no Bluetooth) and in previews so the whole UI and
/// Live Activity pipeline can run without hardware.
final class ScriptedRadarSource: RadarSource {
    var onFrame: ((RadarFrame) -> Void)?
    var onStatus: ((RadarConnectionStatus) -> Void)?
    var onDeviceName: ((String?) -> Void)?

    private let script: RadarScript
    private var timer: Timer?
    private var tick = 0

    init(scenario: RadarScript.Scenario = .busyRoad) {
        self.script = RadarScript(scenario)
    }

    func start() {
        onDeviceName?("Demo")
        onStatus?(.connected)
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.emit()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        emit()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        tick = 0
        onStatus?(.idle)
    }

    private func emit() {
        let frame = script.tick(tick)
        tick += 1
        onFrame?(frame.stamped(at: Date()))
    }
}
