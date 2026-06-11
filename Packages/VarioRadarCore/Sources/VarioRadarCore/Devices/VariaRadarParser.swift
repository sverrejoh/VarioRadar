import Foundation

/// Decodes the raw bytes of the Garmin Varia radar measurement
/// characteristic into a ``RadarFrame``.
///
/// Wire format (community reverse engineering, see `docs/protocols`):
/// ```
/// byte 0        packet counter / fragment id
/// byte 1 + 3i   target id
/// byte 2 + 3i   distance from rider, metres (uint8)
/// byte 3 + 3i   closing speed, km/h (uint8)
/// ```
/// so a packet is `1 + 3 * targetCount` bytes. A packet of just one byte
/// means the radar sees no vehicles.
///
/// The parser is pure: bytes in, frame out, no clock and no shared state.
/// Fragment reassembly (when the radar splits a long target list across
/// packets on older, small-MTU firmware) is handled one layer up by
/// ``RadarFrameAssembler`` so this stays trivial to test.
public enum VariaRadarParser {
    public enum ParseError: Error, Equatable {
        /// The characteristic delivered zero bytes.
        case empty
        /// The payload length is not `1 + 3 * n`, so target boundaries
        /// cannot be trusted. Carries the offending byte count.
        case malformedLength(Int)
    }

    public static func parse(_ data: Data) throws -> RadarFrame {
        let bytes = [UInt8](data)
        guard let counter = bytes.first else {
            throw ParseError.empty
        }

        let payload = bytes.dropFirst()
        guard payload.count % 3 == 0 else {
            throw ParseError.malformedLength(bytes.count)
        }

        var threats: [Threat] = []
        threats.reserveCapacity(payload.count / 3)
        var index = payload.startIndex
        while index < payload.endIndex {
            threats.append(
                Threat(
                    id: payload[index],
                    distanceMeters: Int(payload[index + 1]),
                    speedKmh: Int(payload[index + 2])
                )
            )
            index += 3
        }

        return RadarFrame(packetCounter: counter, threats: threats)
    }
}
