import ActivityKit
import Foundation

/// The Live Activity contract shared between the app (which starts and
/// updates the activity) and the widget extension (which renders it). The
/// dynamic `ContentState` is just the current ``RadarPresentation``.
struct RadarActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var presentation: RadarPresentation
    }

    /// A label for the session, shown in the expanded Live Activity.
    var sessionName: String
}
