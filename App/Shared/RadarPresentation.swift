import Foundation
import VarioRadarCore

/// The small, Codable view of a radar frame that every presentation
/// surface consumes: the main UI, the Live Activity `ContentState`, the
/// widgets, and the App Group snapshot. Deliberately tiny so it is cheap
/// to encode and to ship inside a Live Activity update.
struct RadarPresentation: Codable, Hashable, Sendable {
    var isClear: Bool
    var threatCount: Int
    var nearestDistanceMeters: Int?
    var nearestSpeedKmh: Int?
    var highestLevelRaw: Int
    var updatedAt: Date

    static let clear = RadarPresentation(
        isClear: true,
        threatCount: 0,
        nearestDistanceMeters: nil,
        nearestSpeedKmh: nil,
        highestLevelRaw: 0,
        updatedAt: .distantPast
    )
}

extension RadarPresentation {
    init(frame: RadarFrame, now: Date) {
        let nearest = frame.nearestThreat
        self.init(
            isClear: frame.isClear,
            threatCount: frame.threats.count,
            nearestDistanceMeters: nearest?.distanceMeters,
            nearestSpeedKmh: nearest?.speedKmh,
            highestLevelRaw: frame.highestLevel.rawValue,
            updatedAt: now
        )
    }

    var highestLevel: ThreatLevel {
        ThreatLevel(rawValue: highestLevelRaw) ?? .none
    }
}
