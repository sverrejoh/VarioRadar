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

    /// Severity, derived from distance with a closing-speed kicker. A
    /// `Threat` always represents a detected vehicle, so its level is at
    /// least `.tracking`; only an empty frame is `.none`. Thresholds match
    /// the "SCOPE" product design and are kept here so they are easy to
    /// tune against real captures.
    var level: ThreatLevel {
        if distanceMeters < 30 || (distanceMeters < 55 && speedKmh >= 40) { return .critical }
        if distanceMeters < 70 { return .warning }
        if distanceMeters < 110 { return .approaching }
        return .tracking
    }
}

/// Client-derived urgency for a threat. Not a value the radar sends; we
/// compute it so every presentation surface ranks targets the same way.
///
/// `none` means the road is clear (no targets). `tracking` is a detected
/// but distant vehicle (shown green, distinct from clear). The rest
/// escalate by proximity.
public enum ThreatLevel: Int, Sendable, Codable, Comparable, CaseIterable {
    case none = 0
    case tracking = 1
    case approaching = 2
    case warning = 3
    case critical = 4

    public static func < (lhs: ThreatLevel, rhs: ThreatLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
