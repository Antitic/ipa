import Foundation
import CoreBluetooth
import Combine

final class BLEScanner: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published private(set) var devices: [BLEDevice] = []
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isScanning = false

    private var central: CBCentralManager?
    private var store: [UUID: BLEDevice] = [:]
    private var wantsScan = false
    private var publishTimer: Timer?

    func start() {
        wantsScan = true
        if central == nil {
            central = CBCentralManager(delegate: self, queue: .main)
        } else if central?.state == .poweredOn {
            beginScan()
        }
        if publishTimer == nil {
            publishTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
                self?.publish()
            }
        }
    }

    func stop() {
        wantsScan = false
        central?.stopScan()
        isScanning = false
        publishTimer?.invalidate()
        publishTimer = nil
    }

    func clear() {
        store.removeAll()
        devices = []
    }

    func device(_ id: UUID) -> BLEDevice? { store[id] }

    private func beginScan() {
        central?.scanForPeripherals(withServices: nil,
                                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        isScanning = true
    }

    private func publish() {
        // On oublie les appareils silencieux depuis 2 minutes.
        let cutoff = Date().addingTimeInterval(-120)
        store = store.filter { $0.value.lastSeen > cutoff }
        devices = store.values.sorted { $0.rssi > $1.rssi }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        if central.state == .poweredOn && wantsScan {
            beginScan()
        } else if central.state != .poweredOn {
            isScanning = false
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let r = RSSI.intValue
        guard r < 0, r > -120 else { return }
        let now = Date()
        var d = store[peripheral.identifier] ?? BLEDevice(id: peripheral.identifier, firstSeen: now, lastSeen: now)

        if let n = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !n.isEmpty {
            d.name = n
        } else if d.name == nil, let n = peripheral.name, !n.isEmpty {
            d.name = n
        }
        d.rssi = d.history.isEmpty ? r : Int((Double(d.rssi) * 0.6 + Double(r) * 0.4).rounded())
        d.history.append(r)
        if d.history.count > 90 { d.history.removeFirst(d.history.count - 90) }
        d.lastSeen = now

        if let m = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data { d.manufacturerData = m }
        if let s = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] { d.serviceUUIDs.formUnion(s) }
        if let s = advertisementData[CBAdvertisementDataOverflowServiceUUIDsKey] as? [CBUUID] { d.serviceUUIDs.formUnion(s) }
        if let sd = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (k, v) in sd { d.serviceData[k] = v }
        }
        if let tx = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber { d.txPower = tx.intValue }
        if let c = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber { d.connectable = c.boolValue }

        d.info = BLEDecoder.decode(d)
        store[peripheral.identifier] = d
    }
}
