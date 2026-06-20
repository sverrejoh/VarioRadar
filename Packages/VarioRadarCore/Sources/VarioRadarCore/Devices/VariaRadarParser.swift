import Foundation

/// Decodes the raw bytes of the Garmin Varia radar measurement
/// characteristic into a ``RadarFrame``.
///
/// Wire format (community reverse engineering, see `docs/protocols`):
/// ```
/// byte 0        packet counter / fragment id
/// byte 1 + 3i   target id (RearVue 820 reuses this for lateral position)
/// byte 2 + 3i   distance from rider, metres (uint8); 0 == empty slot
/// byte 3 + 3i   closing speed, km/h (uint8); 0 on the RearVue 820
/// ```
/// so a packet is `1 + 3 * targetCount` bytes. A packet of just one byte
/// means the radar sees no vehicles.
///
/// The parser is pure (bytes in, frame out, no clock, no shared state) and
/// deliberately tolerant, because "Varia-compatible" radars from other
/// brands and newer Garmin firmware vary at the edges:
///
/// - **Trailing bytes** that do not complete a 3-byte target are ignored
///   rather than rejected, so one stray byte never drops a whole frame.
/// - **Empty slots** (distance 0) are skipped. Fixed-size frames from some
///   units pad unused target slots with zeroes; surfacing them would show
///   phantom cars sitting on top of the rider.
/// - **Speed 0 is kept** (the RearVue 820 always reports 0); only distance
///   0 marks a slot as empty.
///
/// Only genuinely unusable input (zero bytes) throws.
public enum VariaRadarParser {
    public enum ParseError: Error, Equatable {
        /// The characteristic delivered zero bytes.
        case empty
    }

    public static func parse(_ data: Data) throws -> RadarFrame {
        let bytes = [UInt8](data)
        guard let counter = bytes.first else {
            throw ParseError.empty
        }

        let body = Array(bytes.dropFirst())
        var threats: [Threat] = []
        if body.count >= 3 {
            threats.reserveCapacity(body.count / 3)
            // Parse as many complete triplets as the body holds; any 1-2
            // byte remainder is intentionally ignored.
            for start in stride(from: 0, through: body.count - 3, by: 3) {
                let distance = Int(body[start + 1])
                guard distance > 0 else { continue } // empty slot padding
                threats.append(
                    Threat(
                        id: body[start],
                        distanceMeters: distance,
                        speedKmh: Int(body[start + 2])
                    )
                )
            }
        }

        return RadarFrame(packetCounter: counter, threats: threats)
    }
}
