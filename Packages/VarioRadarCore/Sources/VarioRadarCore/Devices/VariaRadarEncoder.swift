import Foundation

/// Encodes a ``RadarFrame`` back into the Varia measurement characteristic
/// byte layout. The inverse of ``VariaRadarParser``.
///
/// This exists so the fake-radar test peripheral (and unit tests) can
/// produce byte-accurate packets without duplicating the wire format. It
/// emits single, unfragmented packets, which is what the RCT7xx does on
/// modern (185-byte MTU) connections.
public enum VariaRadarEncoder {
    public enum EncodeError: Error, Equatable {
        /// More targets than fit in a single unfragmented packet. With a
        /// 1-byte header and 3 bytes per target, the practical ceiling for
        /// a classic 20-byte ATT payload is 6 targets; we allow up to the
        /// negotiated-MTU ceiling and surface anything larger as an error
        /// rather than silently truncating.
        case tooManyTargets(Int)
    }

    /// Maximum targets we will pack into one packet. The radar itself
    /// tracks at most 8 vehicles, which fits a 185-byte MTU comfortably.
    public static let maxTargets = 8

    public static func encode(_ frame: RadarFrame) throws -> Data {
        guard frame.threats.count <= maxTargets else {
            throw EncodeError.tooManyTargets(frame.threats.count)
        }
        var bytes: [UInt8] = [frame.packetCounter]
        for threat in frame.threats {
            bytes.append(threat.id)
            bytes.append(UInt8(clamping: threat.distanceMeters))
            bytes.append(UInt8(clamping: threat.speedKmh))
        }
        return Data(bytes)
    }
}
