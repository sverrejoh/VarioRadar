import Foundation
import VarioRadarCore

/// Connection state of a radar source, surfaced to the UI.
enum RadarConnectionStatus: Equatable {
    case idle
    case scanning
    case connecting
    case connected
    case disconnected(reason: String?)

    var label: String {
        switch self {
        case .idle: return "Idle"
        case .scanning: return "Searching..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .disconnected(let reason): return reason.map { "Disconnected: \($0)" } ?? "Disconnected"
        }
    }
}

/// Abstraction over "something that produces radar frames". The real
/// implementation talks to the Varia over BLE; the scripted one replays a
/// `RadarScript` for the simulator and previews. Callbacks are delivered
/// on the main thread.
protocol RadarSource: AnyObject {
    var onFrame: ((RadarFrame) -> Void)? { get set }
    var onStatus: ((RadarConnectionStatus) -> Void)? { get set }
    func start()
    func stop()
}
