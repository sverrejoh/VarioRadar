import CoreBluetooth
import Foundation
import VarioRadarCore

/// The real radar source: a CoreBluetooth central that connects to a
/// Garmin Varia, subscribes to the measurement characteristic, and decodes
/// frames with `VariaRadarParser`.
///
/// Designed for background operation: it opts into state preservation and
/// restoration with a fixed restore identifier, so iOS can relaunch the
/// app on a Bluetooth event after terminating it for memory. The central
/// uses the main queue, so all callbacks (and the `onFrame`/`onStatus`
/// hooks) arrive on the main thread.
final class BLERadarSource: NSObject, RadarSource {
    var onFrame: ((RadarFrame) -> Void)?
    var onStatus: ((RadarConnectionStatus) -> Void)?

    private var central: CBCentralManager?
    private var radar: CBPeripheral?

    private let serviceUUID = CBUUID(string: VariaIdentifiers.service)
    private let measurementUUID = CBUUID(string: VariaIdentifiers.radarMeasurement)
    static let restoreIdentifier = "com.varioradar.central"

    func start() {
        if let central {
            beginScan(with: central)
        } else {
            central = CBCentralManager(
                delegate: self,
                queue: .main,
                options: [CBCentralManagerOptionRestoreIdentifierKey: BLERadarSource.restoreIdentifier]
            )
        }
    }

    func stop() {
        if let radar { central?.cancelPeripheralConnection(radar) }
        central?.stopScan()
        radar = nil
        onStatus?(.idle)
    }

    private func beginScan(with central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        // If we already know a connected radar (e.g. after restoration),
        // reuse it instead of scanning again.
        let known = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
        if let peripheral = known.first {
            connect(peripheral, with: central)
            return
        }
        onStatus?(.scanning)
        central.scanForPeripherals(withServices: [serviceUUID])
    }

    private func connect(_ peripheral: CBPeripheral, with central: CBCentralManager) {
        radar = peripheral
        peripheral.delegate = self
        onStatus?(.connecting)
        central.connect(peripheral)
    }
}

extension BLERadarSource: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            beginScan(with: central)
        case .poweredOff:
            onStatus?(.disconnected(reason: "Bluetooth is off"))
        case .unauthorized:
            onStatus?(.disconnected(reason: "Bluetooth permission denied"))
        case .unsupported:
            onStatus?(.disconnected(reason: "Bluetooth unavailable"))
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let peripheral = peripherals.first {
            radar = peripheral
            peripheral.delegate = self
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        central.stopScan()
        connect(peripheral, with: central)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        onStatus?(.connected)
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        onStatus?(.disconnected(reason: error?.localizedDescription))
        // Keep trying: iOS reconnects when the radar comes back in range.
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        beginScan(with: central)
    }
}

extension BLERadarSource: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else { return }
        peripheral.discoverCharacteristics([measurementUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == measurementUUID }) else { return }
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value,
              let frame = try? VariaRadarParser.parse(data) else { return }
        onFrame?(frame.stamped(at: Date()))
    }
}
