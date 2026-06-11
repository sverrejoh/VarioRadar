import Foundation
import Testing
@testable import VarioRadarCore

/// Helper: build `Data` from a hex string like "10 01 8c 28".
private func hex(_ string: String) -> Data {
    let cleaned = string.filter { !$0.isWhitespace }
    var bytes = [UInt8]()
    var i = cleaned.startIndex
    while i < cleaned.endIndex {
        let next = cleaned.index(i, offsetBy: 2)
        bytes.append(UInt8(cleaned[i..<next], radix: 16)!)
        i = next
    }
    return Data(bytes)
}

// NOTE: these fixtures are synthetic, hand-built from the documented wire
// format. They are NOT real device captures (the RCT716 refuses live BLE
// sessions from macOS). Replace or augment with real iPhone captures once
// available, but the byte math they assert is protocol-accurate.

@Suite("Varia radar parser")
struct VariaRadarParserTests {
    @Test("empty data is rejected")
    func emptyData() {
        #expect(throws: VariaRadarParser.ParseError.empty) {
            try VariaRadarParser.parse(Data())
        }
    }

    @Test("a single counter byte means the road is clear")
    func clearRoad() throws {
        let frame = try VariaRadarParser.parse(hex("00"))
        #expect(frame.packetCounter == 0x00)
        #expect(frame.threats.isEmpty)
        #expect(frame.isClear)
        #expect(frame.nearestThreat == nil)
        #expect(frame.highestLevel == .none)
    }

    @Test("one vehicle decodes its id, distance and speed")
    func singleVehicle() throws {
        // counter 0x10, id 1, distance 0x8c = 140 m, speed 0x28 = 40 km/h
        let frame = try VariaRadarParser.parse(hex("10 01 8c 28"))
        #expect(frame.packetCounter == 0x10)
        #expect(frame.threats == [Threat(id: 1, distanceMeters: 140, speedKmh: 40)])
        #expect(frame.nearestThreat == frame.threats.first)
    }

    @Test("multiple vehicles decode in order")
    func multipleVehicles() throws {
        // three targets: far/slow, mid, near/fast
        let frame = try VariaRadarParser.parse(hex("21 01 78 1e 02 3c 32 03 0f 50"))
        #expect(frame.threats.count == 3)
        #expect(frame.threats[0] == Threat(id: 1, distanceMeters: 120, speedKmh: 30))
        #expect(frame.threats[1] == Threat(id: 2, distanceMeters: 60, speedKmh: 50))
        #expect(frame.threats[2] == Threat(id: 3, distanceMeters: 15, speedKmh: 80))
    }

    @Test("nearest threat is by distance, not packet order")
    func nearestByDistance() throws {
        let frame = try VariaRadarParser.parse(hex("00 01 78 1e 02 0f 50 03 3c 32"))
        #expect(frame.nearestThreat?.id == 2)
        #expect(frame.nearestThreat?.distanceMeters == 15)
    }

    @Test("a length that is not 1 + 3n is rejected")
    func malformedLength() {
        // 3 bytes total: counter + 2 leftover bytes, not a whole target
        #expect(throws: VariaRadarParser.ParseError.malformedLength(3)) {
            try VariaRadarParser.parse(hex("10 01 8c"))
        }
    }

    @Test("full byte range round-trips without overflow")
    func byteRange() throws {
        // distance 0xff = 255 m, speed 0xff = 255 km/h
        let frame = try VariaRadarParser.parse(hex("ff 09 ff ff"))
        #expect(frame.threats[0].distanceMeters == 255)
        #expect(frame.threats[0].speedKmh == 255)
    }
}

@Suite("Threat severity")
struct ThreatSeverityTests {
    @Test("closing time is distance over speed")
    func closingTime() {
        // 100 m at 36 km/h = 10 m/s => 10 s
        let threat = Threat(id: 1, distanceMeters: 100, speedKmh: 36)
        #expect(threat.closingTimeSeconds == 10)
    }

    @Test("zero speed has no closing time and reads as approaching")
    func zeroSpeed() {
        let threat = Threat(id: 1, distanceMeters: 50, speedKmh: 0)
        #expect(threat.closingTimeSeconds == nil)
        #expect(threat.level == .approaching)
    }

    @Test("severity escalates as closing time shrinks")
    func levels() {
        // 30 m @ 90 km/h (25 m/s) = 1.2 s -> critical
        #expect(Threat(id: 1, distanceMeters: 30, speedKmh: 90).level == .critical)
        // 100 m @ 60 km/h (16.7 m/s) = 6 s -> warning
        #expect(Threat(id: 2, distanceMeters: 100, speedKmh: 60).level == .warning)
        // 140 m @ 30 km/h (8.3 m/s) = 16.8 s -> approaching
        #expect(Threat(id: 3, distanceMeters: 140, speedKmh: 30).level == .approaching)
    }

    @Test("frame reports the highest severity present")
    func frameHighestLevel() throws {
        let frame = try VariaRadarParser.parse(hex("00 01 8c 1e 02 1e 5a"))
        // target 2 is 30 m @ 90 km/h -> critical
        #expect(frame.highestLevel == .critical)
    }
}

@Suite("Frame stamping")
struct FrameStampingTests {
    @Test("stamping attaches a receive time without altering data")
    func stamp() throws {
        let frame = try VariaRadarParser.parse(hex("10 01 8c 28"))
        #expect(frame.receivedAt == nil)
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let stamped = frame.stamped(at: when)
        #expect(stamped.receivedAt == when)
        #expect(stamped.threats == frame.threats)
        #expect(stamped.packetCounter == frame.packetCounter)
    }
}
