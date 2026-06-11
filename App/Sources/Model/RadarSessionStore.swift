import Combine
import Foundation
import VarioRadarCore

/// The single source of truth for the UI. Owns a `RadarSource`, pumps its
/// frames into published state, mirrors each frame to the App Group
/// snapshot, and drives the Live Activity.
@MainActor
final class RadarSessionStore: ObservableObject {
    @Published private(set) var frame: RadarFrame?
    @Published private(set) var status: RadarConnectionStatus = .idle
    @Published private(set) var isRunning = false

    private let source: RadarSource
    private let activity = RadarActivityManager()

    init(source: RadarSource) {
        self.source = source
        source.onFrame = { [weak self] frame in self?.handle(frame) }
        source.onStatus = { [weak self] status in self?.status = status }
    }

    var presentation: RadarPresentation {
        guard let frame else { return .clear }
        return RadarPresentation(frame: frame, now: frame.receivedAt ?? Date())
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        activity.start()
        source.start()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        source.stop()
        activity.end()
        frame = nil
    }

    private func handle(_ frame: RadarFrame) {
        self.frame = frame
        let presentation = RadarPresentation(frame: frame, now: frame.receivedAt ?? Date())
        AppGroup.writeSnapshot(presentation)
        activity.update(presentation)
    }
}
