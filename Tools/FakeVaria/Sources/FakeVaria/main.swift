import CoreBluetooth
import Foundation
import VarioRadarCore

// FakeVaria: a macOS BLE peripheral that impersonates a Garmin Varia
// radar. It advertises the real radar service and streams scripted target
// frames on the measurement characteristic at 1 Hz, so the VarioRadar
// iPhone app can be developed and tested end to end without the real
// device (which refuses live BLE sessions from macOS anyway).
//
// Usage:
//   swift run FakeVaria [scenario]
// where scenario is one of: clear, singleApproach, overtake, busyRoad
// (default: busyRoad). The scripted approach loops forever.

setbuf(stdout, nil) // live output even when piped

let scenarioName = CommandLine.arguments.dropFirst().first ?? "busyRoad"
guard let scenario = RadarScript.Scenario(rawValue: scenarioName) else {
    let valid = RadarScript.Scenario.allCases.map(\.rawValue).joined(separator: ", ")
    FileHandle.standardError.write(Data("Unknown scenario '\(scenarioName)'. Valid: \(valid)\n".utf8))
    exit(2)
}

final class FakeVaria: NSObject, CBPeripheralManagerDelegate {
    private var manager: CBPeripheralManager!
    // Rebuilt on every power-on: CoreBluetooth forbids adding the same
    // characteristic instance twice, and Bluetooth can cycle (e.g. Mac
    // sleep) while the tool runs.
    private var measurement: CBMutableCharacteristic?
    private let script: RadarScript
    private var tick = 0
    private var timer: DispatchSourceTimer?

    init(scenario: RadarScript.Scenario) {
        self.script = RadarScript(scenario)
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            print("Bluetooth on, (re)publishing service")
            stopStreaming()
            manager.removeAllServices()
            manager.stopAdvertising()
            let characteristic = CBMutableCharacteristic(
                type: CBUUID(string: VariaIdentifiers.radarMeasurement),
                properties: [.notify],
                value: nil,
                permissions: [.readable]
            )
            measurement = characteristic
            let service = CBMutableService(
                type: CBUUID(string: VariaIdentifiers.service),
                primary: true
            )
            service.characteristics = [characteristic]
            manager.add(service)
        case .poweredOff:
            print("Bluetooth is off, pausing")
            stopStreaming()
        case .unauthorized:
            print("Bluetooth permission denied for this process")
            exit(1)
        default:
            break
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didAdd service: CBService, error: Error?) {
        if let error {
            print("Failed to add service: \(error)")
            exit(1)
        }
        manager.startAdvertising([
            CBAdvertisementDataLocalNameKey: "FakeVaria",
            CBAdvertisementDataServiceUUIDsKey: [CBUUID(string: VariaIdentifiers.service)],
        ])
        print("Advertising as 'FakeVaria' with service \(VariaIdentifiers.service)")
        print("Scenario: \(script.scenario.rawValue). Waiting for a subscriber...")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        print("Subscriber connected (MTU \(central.maximumUpdateValueLength)). Streaming at 1 Hz.")
        startStreaming()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        print("Subscriber disconnected. Pausing stream.")
        stopStreaming()
    }

    private func startStreaming() {
        stopStreaming()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 1.0)
        t.setEventHandler { [weak self] in self?.emit() }
        t.resume()
        timer = t
    }

    private func stopStreaming() {
        timer?.cancel()
        timer = nil
    }

    private func emit() {
        guard let measurement else { return }
        let frame = script.tick(tick)
        tick += 1
        guard let data = try? VariaRadarEncoder.encode(frame) else { return }
        let sent = manager.updateValue(
            data, for: measurement, onSubscribedCentrals: nil
        )
        let summary = frame.isClear
            ? "clear"
            : frame.threats
                .map { "#\($0.id) \($0.distanceMeters)m/\($0.speedKmh)kmh" }
                .joined(separator: ", ")
        print(String(format: "t=%-4d %@%@", tick, summary, sent ? "" : "  [queued]"))
    }
}

let fake = FakeVaria(scenario: scenario)
RunLoop.main.run()
