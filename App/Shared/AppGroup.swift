import Foundation

/// Shared container used by the widget extension to read the latest radar
/// snapshot the app wrote. The Live Activity gets its state through
/// ActivityKit directly; this path is for the timeline-driven widgets and
/// for recovering the last frame after a relaunch.
enum AppGroup {
    static let identifier = "group.com.varioradar.shared"
    private static let snapshotKey = "latestPresentation"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    static func writeSnapshot(_ presentation: RadarPresentation) {
        guard let data = try? JSONEncoder().encode(presentation) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    static func readSnapshot() -> RadarPresentation? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(RadarPresentation.self, from: data)
    }
}
