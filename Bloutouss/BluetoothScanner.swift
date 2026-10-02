import Combine
import CoreBluetooth
import Foundation

final class BluetoothScanner: NSObject, ObservableObject {
    @Published private(set) var devices: [UUID: BluetoothDevice] = [:]
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    @Published private(set) var now = Date()

    private var central: CBCentralManager!
    /// Les annonces arrivent très vite : on les accumule ici et on publie
    /// vers l'interface à intervalle régulier.
    private var buffer: [UUID: BluetoothDevice] = [:]
    private var wantsToScan = true
    private var refreshTimer: AnyCancellable?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        refreshTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                guard let self else { return }
                self.now = date
                self.devices = self.buffer
            }
    }

    func startScan() {
        wantsToScan = true
        guard central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        isScanning = true
    }

    func stopScan() {
        wantsToScan = false
        central.stopScan()
        isScanning = false
    }

    func toggleScan() {
        isScanning ? stopScan() : startScan()
    }

    func clear() {
        buffer.removeAll()
        devices.removeAll()
    }
}

extension BluetoothScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        if central.state == .poweredOn {
            if wantsToScan { startScan() }
        } else {
            isScanning = false
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let rssi = RSSI.intValue
        // 127 = valeur RSSI indisponible
        guard rssi != 127 else { return }

        let date = Date()
        let id = peripheral.identifier
        var device = buffer[id] ?? BluetoothDevice(id: id, rssi: rssi, firstSeen: date, lastSeen: date)

        device.rssi = rssi
        device.lastSeen = date
        device.advertisementCount += 1

        if let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String, !name.isEmpty {
            device.name = name
        } else if let name = peripheral.name, !name.isEmpty {
            device.name = name
        }
        if let connectable = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber {
            device.isConnectable = connectable.boolValue
        }
        if let tx = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
            device.txPower = tx.intValue
        }
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data {
            device.manufacturerData = data
        }
        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            for uuid in uuids where !device.serviceUUIDs.contains(uuid) {
                device.serviceUUIDs.append(uuid)
            }
        }
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            device.serviceData.merge(serviceData) { _, new in new }
        }

        device.rssiHistory.append(RSSISample(date: date, rssi: rssi))
        if device.rssiHistory.count > BluetoothDevice.maxHistory {
            device.rssiHistory.removeFirst(device.rssiHistory.count - BluetoothDevice.maxHistory)
        }

        buffer[id] = device
    }
}
