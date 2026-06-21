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
    var onDeviceName: ((String?) -> Void)?

    private var central: CBCentralManager?
    private var radar: CBPeripheral?
    private var isSubscribed = false
    private var discoveredName: String?
    private var rateCount = 0
    private var rateWindowStart = Date()
    private let recorder = RawFrameRecorder()

    private let serviceUUID = CBUUID(string: VariaIdentifiers.service)
    private let measurementUUID = CBUUID(string: VariaIdentifiers.radarMeasurement)
    static let restoreIdentifier = "com.varioradar.central"
    private let log = Logger(subsystem: "com.varioradar", category: "ble")

    /// Mirror lifecycle events to both the unified log and stdout. stdout
    /// is what `devicectl ... --console` captures, so this makes a live
    /// console session show the full connection trace.
    private func trace(_ message: String) {
        log.info("\(message, privacy: .public)")
        print("[ble] \(message)")
    }

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
            trace("Reusing already-connected radar \(peripheral.identifier.uuidString)")
            connect(peripheral, with: central)
            return
        }
        trace("Scanning for radar service")
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
        trace("Central state: \(central.state.rawValue)")
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
            trace("Restoring radar \(peripheral.identifier.uuidString)")
            radar = peripheral
            peripheral.delegate = self
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        discoveredName = advName ?? peripheral.name
        trace("Discovered \(discoveredName ?? "?") rssi \(RSSI.intValue)")
        central.stopScan()
        connect(peripheral, with: central)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // Link is up, but not yet streaming. Stay in `.connecting` until
        // the notify subscription succeeds.
        onDeviceName?(discoveredName ?? peripheral.name)
        trace("Link connected, discovering services")
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        let reason = error?.localizedDescription ?? "clean"
        trace("Disconnected (was subscribed: \(self.isSubscribed)): \(reason)")
        isSubscribed = false
        onStatus?(.disconnected(reason: error?.localizedDescription))
        // iOS holds this pending and reconnects when the radar is available
        // again; it dedups repeat calls, so no manual backoff is needed.
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        trace("Failed to connect: \(error?.localizedDescription ?? "?")")
        beginScan(with: central)
    }
}

extension BLERadarSource: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { trace("Service discovery error: \(error.localizedDescription)") }
        guard let service = peripheral.services?.first(where: { $0.uuid == serviceUUID }) else {
            trace("Radar service not found on peripheral")
            return
        }
        peripheral.discoverCharacteristics([measurementUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let error { trace("Characteristic discovery error: \(error.localizedDescription)") }
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == measurementUUID }) else {
            trace("Measurement characteristic not found")
            return
        }
        trace("Subscribing to measurement characteristic")
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error {
            // A failure here usually means the characteristic demands
            // pairing/encryption, the key clue distinguishing "needs
            // bonding" from "competing connection".
            trace("Subscribe FAILED: \(error.localizedDescription)")
            onStatus?(.disconnected(reason: "Subscribe failed: \(error.localizedDescription)"))
            return
        }
        isSubscribed = characteristic.isNotifying
        if characteristic.isNotifying {
            trace("Subscribed; streaming")
            onStatus?(.connected)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }
        do {
            let frame = try VariaRadarParser.parse(data)
            recorder.record(data)
            measureRate()
            onFrame?(frame.stamped(at: Date()))
        } catch {
            recorder.record(data, parseFailed: true)
            let hex = data.map { String(format: "%02x", $0) }.joined()
            trace("Parse FAILED (\(error)): \(hex)")
        }
    }

    /// Logs the measured notification rate every ~2 s, to see how fast the
    /// radar actually delivers frames (and whether it drops in background).
    private func measureRate() {
        rateCount += 1
        let dt = Date().timeIntervalSince(rateWindowStart)
        if dt >= 2 {
            let hz = Double(rateCount) / dt
            trace(String(format: "rate %.1f Hz (%d frames / %.1fs)", hz, rateCount, dt))
            rateCount = 0
            rateWindowStart = Date()
        }
    }
}
