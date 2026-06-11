import Foundation

/// A deterministic, clock-free generator of radar frames for testing and
/// previews. Drives the fake-radar peripheral, SwiftUI previews, and the
/// simulator `RadarSource`, so every layer can be exercised without a real
/// device or any real cars.
///
/// `tick(_:)` maps an integer step (call it once per second) to a frame, so
/// behaviour is fully reproducible and needs no timer of its own.
public struct RadarScript: Sendable {
    public enum Scenario: String, Sendable, CaseIterable {
        /// No vehicles, ever.
        case clear
        /// A single car closing from 140 m at a steady speed.
        case singleApproach
        /// A fast car overtaking while a second car lingers behind.
        case overtake
        /// Stop-and-go: cars appear and drop off repeatedly.
        case busyRoad
    }

    public let scenario: Scenario

    public init(_ scenario: Scenario) {
        self.scenario = scenario
    }

    /// The frame for step `t` (one step per second).
    public func tick(_ t: Int) -> RadarFrame {
        switch scenario {
        case .clear:
            return RadarFrame(packetCounter: counter(t), threats: [])

        case .singleApproach:
            // 140 m closing at ~50 km/h (~13.9 m/s) => ~10 m per step.
            let distance = 140 - (t * 14)
            guard distance > 0 else {
                return RadarFrame(packetCounter: counter(t), threats: [])
            }
            return RadarFrame(
                packetCounter: counter(t),
                threats: [Threat(id: 1, distanceMeters: distance, speedKmh: 50)]
            )

        case .overtake:
            let fast = max(0, 120 - t * 25)
            let slow = max(0, 90 - t * 4)
            var threats: [Threat] = []
            if fast > 0 { threats.append(Threat(id: 1, distanceMeters: fast, speedKmh: 90)) }
            if slow > 0 { threats.append(Threat(id: 2, distanceMeters: slow, speedKmh: 32)) }
            return RadarFrame(packetCounter: counter(t), threats: threats)

        case .busyRoad:
            // Up to three cars phasing in and out on different cycles.
            var threats: [Threat] = []
            if (t % 6) < 4 {
                threats.append(Threat(id: 1, distanceMeters: 140 - (t % 6) * 30, speedKmh: 45))
            }
            if (t % 9) < 3 {
                threats.append(Threat(id: 2, distanceMeters: 80 - (t % 9) * 20, speedKmh: 60))
            }
            if (t % 4) == 0 {
                threats.append(Threat(id: 3, distanceMeters: 30, speedKmh: 85))
            }
            return RadarFrame(packetCounter: counter(t), threats: threats)
        }
    }

    private func counter(_ t: Int) -> UInt8 {
        UInt8(t & 0x0F)
    }
}
