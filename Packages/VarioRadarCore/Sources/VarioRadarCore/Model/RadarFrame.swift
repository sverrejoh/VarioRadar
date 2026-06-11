import Foundation

/// One decoded radar notification: the set of vehicles currently tracked.
///
/// The parser produces frames without a wall-clock timestamp so it stays
/// pure and deterministic for testing. The BLE layer stamps `receivedAt`
/// when it hands a frame onward, using ``stamped(at:)``.
public struct RadarFrame: Equatable, Sendable, Codable {
    /// Raw value of byte 0 of the packet. The high nibble identifies a
    /// fragment when the radar splits a large target list across packets;
    /// the low nibble is a rolling counter. Retained mostly for
    /// fragment reassembly and duplicate suppression.
    public let packetCounter: UInt8

    /// Tracked vehicles, in the order the radar reported them.
    public let threats: [Threat]

    /// When the frame was received. `nil` straight out of the parser.
    public let receivedAt: Date?

    public init(packetCounter: UInt8, threats: [Threat], receivedAt: Date? = nil) {
        self.packetCounter = packetCounter
        self.threats = threats
        self.receivedAt = receivedAt
    }
}

public extension RadarFrame {
    /// True when the radar currently sees no vehicles.
    var isClear: Bool { threats.isEmpty }

    /// The closest tracked vehicle, or `nil` when clear.
    var nearestThreat: Threat? {
        threats.min { $0.distanceMeters < $1.distanceMeters }
    }

    /// The most urgent severity across all tracked vehicles.
    var highestLevel: ThreatLevel {
        threats.map(\.level).max() ?? .none
    }

    /// A copy stamped with a receive time, for handing to the UI and the
    /// Live Activity.
    func stamped(at date: Date) -> RadarFrame {
        RadarFrame(packetCounter: packetCounter, threats: threats, receivedAt: date)
    }
}
