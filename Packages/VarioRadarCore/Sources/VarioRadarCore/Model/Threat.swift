import Foundation

/// A single vehicle the radar is tracking behind the rider.
///
/// Field layout comes from community reverse engineering of the Garmin
/// Varia radar characteristic and is documented in `docs/protocols`. The
/// raw wire values are unsigned bytes; we widen them to `Int` so callers
/// never have to think about overflow when doing arithmetic.
public struct Threat: Equatable, Sendable, Codable, Identifiable {
    /// Per-target identifier assigned by the radar. Stable while a given
    /// vehicle stays in view, reused once it drops off.
    public let id: UInt8

    /// Distance from the rider, in metres. The RCT7xx reports up to 140 m.
    public let distanceMeters: Int

    /// Closing speed of the vehicle, in km/h.
    public let speedKmh: Int

    public init(id: UInt8, distanceMeters: Int, speedKmh: Int) {
        self.id = id
        self.distanceMeters = distanceMeters
        self.speedKmh = speedKmh
    }
}

public extension Threat {
    /// Seconds until the vehicle reaches the rider at the current closing
    /// speed, or `nil` when the radar reports zero closing speed (not
    /// meaningfully approaching).
    var closingTimeSeconds: Double? {
        guard speedKmh > 0 else { return nil }
        let metresPerSecond = Double(speedKmh) / 3.6
        return Double(distanceMeters) / metresPerSecond
    }

    /// A coarse severity derived from closing time. The thresholds are a
    /// starting point tuned for road cycling and are expected to be
    /// adjusted once we have real-world captures; they are intentionally
    /// kept in one place so they are easy to change.
    var level: ThreatLevel {
        guard let closingTime = closingTimeSeconds else { return .approaching }
        switch closingTime {
        case ..<4: return .critical
        case ..<8: return .warning
        default: return .approaching
        }
    }
}

/// Client-derived urgency for a threat. Not a value the radar sends; we
/// compute it so every presentation surface ranks targets the same way.
public enum ThreatLevel: Int, Sendable, Codable, Comparable, CaseIterable {
    case none = 0
    case approaching = 1
    case warning = 2
    case critical = 3

    public static func < (lhs: ThreatLevel, rhs: ThreatLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
