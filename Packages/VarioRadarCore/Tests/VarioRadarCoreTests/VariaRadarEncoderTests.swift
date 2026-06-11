import Foundation
import Testing
@testable import VarioRadarCore

@Suite("Varia radar encoder")
struct VariaRadarEncoderTests {
    @Test("encode then parse is the identity for valid frames")
    func roundTrip() throws {
        let frames = [
            RadarFrame(packetCounter: 0x00, threats: []),
            RadarFrame(packetCounter: 0x10, threats: [
                Threat(id: 1, distanceMeters: 140, speedKmh: 50),
            ]),
            RadarFrame(packetCounter: 0x2F, threats: [
                Threat(id: 1, distanceMeters: 120, speedKmh: 30),
                Threat(id: 2, distanceMeters: 60, speedKmh: 50),
                Threat(id: 3, distanceMeters: 15, speedKmh: 80),
            ]),
        ]
        for frame in frames {
            let data = try VariaRadarEncoder.encode(frame)
            let parsed = try VariaRadarParser.parse(data)
            #expect(parsed == frame)
        }
    }

    @Test("a clear frame encodes to a single counter byte")
    func clearIsOneByte() throws {
        let data = try VariaRadarEncoder.encode(RadarFrame(packetCounter: 7, threats: []))
        #expect(data == Data([0x07]))
    }

    @Test("out-of-range distance and speed clamp to a byte")
    func clamping() throws {
        let frame = RadarFrame(packetCounter: 0, threats: [
            Threat(id: 1, distanceMeters: 999, speedKmh: 300),
        ])
        let data = try VariaRadarEncoder.encode(frame)
        #expect([UInt8](data) == [0x00, 0x01, 0xFF, 0xFF])
    }

    @Test("too many targets is rejected")
    func tooMany() {
        let threats = (0..<9).map { Threat(id: UInt8($0), distanceMeters: 100, speedKmh: 40) }
        let frame = RadarFrame(packetCounter: 0, threats: threats)
        #expect(throws: VariaRadarEncoder.EncodeError.tooManyTargets(9)) {
            try VariaRadarEncoder.encode(frame)
        }
    }
}

@Suite("Radar script")
struct RadarScriptTests {
    @Test("clear scenario never produces threats")
    func clear() {
        let script = RadarScript(.clear)
        for t in 0..<20 {
            #expect(script.tick(t).isClear)
        }
    }

    @Test("single approach gets closer each step then clears")
    func singleApproach() {
        let script = RadarScript(.singleApproach)
        let first = script.tick(0).nearestThreat!.distanceMeters
        let later = script.tick(3).nearestThreat!.distanceMeters
        #expect(later < first)
        // Eventually the car passes and the road is clear.
        #expect(script.tick(20).isClear)
    }

    @Test("scripts are deterministic")
    func deterministic() {
        let a = RadarScript(.busyRoad)
        let b = RadarScript(.busyRoad)
        for t in 0..<30 {
            #expect(a.tick(t) == b.tick(t))
        }
    }

    @Test("every scripted frame survives an encode/parse round trip")
    func scriptEncodes() throws {
        for scenario in RadarScript.Scenario.allCases {
            let script = RadarScript(scenario)
            for t in 0..<30 {
                let frame = script.tick(t)
                let data = try VariaRadarEncoder.encode(frame)
                #expect(try VariaRadarParser.parse(data) == frame)
            }
        }
    }
}
