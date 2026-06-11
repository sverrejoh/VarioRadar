import CoreBluetooth
import Foundation
import OSLog
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
///
/// Connection lifecycle is logged to the "ble" category; filter Console
/// (or the Xcode debug console) by subsystem `com.varioradar` to see why a
/// link drops. We only report `.connected` once notifications are actually
/// flowing, so a flip in the UI means the radar is really dropping us (most
/// often because another device, e.g. the Garmin Varia app or an Edge, is
/// holding one of the radar's limited connection slots).
final class BLERadarSource: NSObject, RadarSource {
    var onFrame: ((RadarFrame) -> Void)?
    var onStatus: ((RadarConnectionStatus) -> Void)?

    private var central: CBCentralManager?
    private var radar: CBPeripheral?
    private var isSubscribed = false

    private let serviceUUID = CBUUID(string: VariaIdentifiers.service)
    private let measurementUUID = CBUUID(string: VariaIdentifiers.radarMeasurement)
    static let restoreIdentifier = "com.varioradar.central"
    private let log = Logger(subsystem: "com.varioradar", category: "ble")

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
        isSubscribed = false
        onStatus?(.idle)
    }

    private func beginScan(with central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        let known = central.retrieveConnectedPeripherals(withServices: [serviceUUID])
        if let peripheral = known.first {
            log.info("Reusing already-connected radar \(peripheral.identifier.uuidString, privacy: .public)")
            connect(peripheral, with: central)
            return
        }
        log.info("Scanning for radar service")
        onStatus?(.scanning)
        central.scanForPeripherals(withServices: [serviceUUID])
    }

    private func connect(_ peripheral: CBPeripheral, with central: CBCentralManager) {
        radar = peripheral
        isSubscribed = false
        peripheral.delegate = self
        onStatus?(.connecting)
        central.connect(peripheral)
    }
}

extension BLERadarSource: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.info("Central state: \(central.state.rawValue)")
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
            log.info("Restoring radar \(peripheral.identifier.uuidString, privacy: .public)")
            radar = peripheral
            peripheral.delegate = self
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        log.info("Discovered \(peripheral.name ?? "?", privacy: .public) rssi \(RSSI.intValue)")
        central.stopScan()
        connect(peripheral, with: central)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Link is up, but not yet streaming. Stay in `.connecting` until
        // the notify subscription succeeds.
        log.info("Link connected, discovering services")
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        let reason = error?.localizedDescription ?? "clean"
        log.error("Disconnected (was subscribed: \(self.isSubscribed)): \(reason, privacy: .public)")
        isSubscribed = false
        onStatus?(.disconnected(reason: error?.localizedDescription))
        // iOS holds this pending and reconnects when the radar is available
        // again; it dedups repeat calls, so no manual backoff is needed.
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        log.error("Failed to connect: \(error?.localizedDescription ?? "?", privacy: .public)")
        beginScan(with: central)
    }
}

extension BLERadarSource: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { log.error("Service discovery error: \(error.localizedDescription, privacy: .public)") }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            log.error("Radar service not found on peripheral")
            return
        }
        peripheral.discoverCharacteristics([measurementUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error { log.error("Characteristic discovery error: \(error.localizedDescription, privacy: .public)") }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == measurementUUID }) else {
            log.error("Measurement characteristic not found")
            return
        }
        log.info("Subscribing to measurement characteristic")
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            // A failure here usually means the characteristic demands
            // pairing/encryption, the key clue distinguishing "needs
            // bonding" from "competing connection".
            log.error("Subscribe FAILED: \(error.localizedDescription, privacy: .public)")
            onStatus?(.disconnected(reason: "Subscribe failed: \(error.localizedDescription)"))
            return
        }
        isSubscribed = characteristic.isNotifying
        if characteristic.isNotifying {
            log.info("Subscribed; streaming")
            onStatus?(.connected)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value,
              let frame = try? VariaRadarParser.parse(data) else { return }
        onFrame?(frame.stamped(at: Date()))
    }
}
