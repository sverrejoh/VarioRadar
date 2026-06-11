import Foundation
import VarioRadarCore

/// The small, Codable view of a radar frame that every presentation
/// surface consumes: the main UI, the Live Activity `ContentState`, the
/// widgets, and the App Group snapshot. Deliberately tiny so it is cheap
/// to encode and to ship inside a Live Activity update (ActivityKit caps
/// the state payload at 4 KB; this stays well under at 8 cars).
struct RadarPresentation: Codable, Hashable, Sendable {
    /// One tracked vehicle, compacted for transport.
    struct Car: Codable, Hashable, Sendable, Identifiable {
        var id: UInt8
        var distanceMeters: Int
        var speedKmh: Int
        var levelRaw: Int

        var level: ThreatLevel { ThreatLevel(rawValue: levelRaw) ?? .none }
    }

    var isClear: Bool
    var cars: [Car]
    var highestLevelRaw: Int
    var updatedAt: Date

    static let clear = RadarPresentation(
        isClear: true,
        cars: [],
        highestLevelRaw: 0,
        updatedAt: .distantPast
    )
}

extension RadarPresentation {
    init(frame: RadarFrame, now: Date) {
        let cars = frame.threats
            .sorted { $0.distanceMeters < $1.distanceMeters }
            .prefix(8)
            .map { threat in
                Car(
                    id: threat.id,
                    distanceMeters: threat.distanceMeters,
                    speedKmh: threat.speedKmh,
                    levelRaw: threat.level.rawValue
                )
            }
        self.init(
            isClear: frame.isClear,
            cars: Array(cars),
            highestLevelRaw: frame.highestLevel.rawValue,
            updatedAt: now
        )
    }

    var highestLevel: ThreatLevel {
        ThreatLevel(rawValue: highestLevelRaw) ?? .none
    }

    var threatCount: Int { cars.count }

    /// The closest car (cars are kept sorted nearest-first).
    var nearest: Car? { cars.first }

    var nearestDistanceMeters: Int? { nearest?.distanceMeters }
    var nearestSpeedKmh: Int? { nearest?.speedKmh }
}
