import Combine
import CoreBluetooth
import Foundation

struct FavoriteAlert: Identifiable, Equatable {
    let id = UUID()
    let deviceID: UUID
    let name: String
}

/// Appareil déjà connecté à l'iPhone : il n'émet plus d'annonces mais reste explorable.
struct SystemPeripheral: Identifiable, Equatable {
    let id: UUID
    let name: String
}

final class BluetoothScanner: NSObject, ObservableObject {
    @Published private(set) var devices: [UUID: BluetoothDevice] = [:]
    @Published private(set) var state: CBManagerState = .unknown
    @Published private(set) var isScanning = false
    @Published private(set) var now = Date()
    @Published private(set) var systemPeripherals: [SystemPeripheral] = []
    @Published private(set) var totalAdvertisements = 0
    @Published var favoriteAlert: FavoriteAlert?

    let store: DeviceStore

    private var central: CBCentralManager!
    /// Les annonces arrivent très vite : on les accumule ici et on publie
    /// vers l'interface à intervalle régulier.
    private var buffer: [UUID: BluetoothDevice] = [:]
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var connections: [UUID: PeripheralConnection] = [:]
    private var advertisementCounter = 0
    private var wantsToScan = true
    private var refreshTimer: AnyCancellable?
    private var tick = 0

    /// Services courants utilisés pour retrouver les appareils déjà connectés au système.
    private static let systemServiceUUIDs = ["1800", "180A", "180F", "1812", "180D", "FE2C"].map(CBUUID.init(string:))

    init(store: DeviceStore) {
        self.store = store
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
        refreshTimer = Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                self?.refresh(date)
            }
    }

    // MARK: - Scan

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
        peripherals = peripherals.filter { connections[$0.key] != nil }
    }

    private func refresh(_ date: Date) {
        now = date
        let removeAfter = AppSettings.removeAfter
        if removeAfter > 0 {
            buffer = buffer.filter { id, device in
                date.timeIntervalSince(device.lastSeen) < removeAfter
                    || store.isFavorite(id)
                    || connections[id] != nil
            }
            peripherals = peripherals.filter { buffer[$0.key] != nil || connections[$0.key] != nil }
        }
        devices = buffer
        totalAdvertisements = advertisementCounter
        tick += 1
        if tick % 10 == 0 {
            refreshSystemPeripherals()
        }
    }

    func refreshSystemPeripherals() {
        guard central.state == .poweredOn else {
            if !systemPeripherals.isEmpty { systemPeripherals = [] }
            return
        }
        let connected = central.retrieveConnectedPeripherals(withServices: Self.systemServiceUUIDs)
        for peripheral in connected {
            peripherals[peripheral.identifier] = peripheral
        }
        let list = connected
            .map { SystemPeripheral(id: $0.identifier, name: $0.name ?? "Appareil sans nom") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if list != systemPeripherals {
            systemPeripherals = list
        }
    }

    // MARK: - Connexion GATT

    func connection(for id: UUID) -> PeripheralConnection? {
        if let existing = connections[id] { return existing }
        let peripheral = peripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first
        guard let peripheral else { return nil }
        peripherals[id] = peripheral
        let connection = PeripheralConnection(peripheral: peripheral)
        connections[id] = connection
        return connection
    }

    func connect(_ id: UUID) {
        guard central.state == .poweredOn, let connection = connection(for: id) else { return }
        connection.willConnect()
        central.connect(connection.peripheral, options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak connection] in
            guard let self, let connection, connection.state == .connecting else { return }
            self.central.cancelPeripheralConnection(connection.peripheral)
            connection.didFailToConnect(message: "Délai de connexion dépassé")
        }
    }

    func disconnect(_ id: UUID) {
        guard let connection = connections[id] else { return }
        central.cancelPeripheralConnection(connection.peripheral)
        connection.markDisconnected()
    }
}

extension BluetoothScanner: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        state = central.state
        if central.state == .poweredOn {
            if wantsToScan { startScan() }
            refreshSystemPeripherals()
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
        peripherals[id] = peripheral
        advertisementCounter += 1

        let existing = buffer[id]
        var device = existing ?? BluetoothDevice(id: id, rssi: rssi, date: date)
        let wasAbsent = existing.map { date.timeIntervalSince($0.lastSeen) > max(AppSettings.staleAfter, 30) } ?? true
        var changed = existing == nil

        let alpha = min(max(AppSettings.smoothing, 0.05), 1)
        device.smoothedRSSI = existing == nil ? Double(rssi) : alpha * Double(rssi) + (1 - alpha) * device.smoothedRSSI
        device.rssi = rssi
        device.minRSSI = min(device.minRSSI, rssi)
        device.maxRSSI = max(device.maxRSSI, rssi)
        device.lastSeen = date
        device.advertisementCount += 1

        let advertisedName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        if let advertisedName, !advertisedName.isEmpty, advertisedName != device.name {
            device.name = advertisedName
            changed = true
        }
        if let connectable = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber {
            device.isConnectable = connectable.boolValue
        }
        if let tx = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
            device.txPower = tx.intValue
        }
        if let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, data != device.manufacturerData {
            device.manufacturerData = data
            changed = true
        }
        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            for uuid in uuids where !device.serviceUUIDs.contains(uuid) {
                device.serviceUUIDs.append(uuid)
                changed = true
            }
        }
        if let serviceData = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            for (uuid, data) in serviceData where device.serviceData[uuid] != data {
                device.serviceData[uuid] = data
                changed = true
            }
        }

        if changed {
            device.info = AdvertisementParser.parse(
                name: device.name,
                manufacturerData: device.manufacturerData,
                serviceUUIDs: device.serviceUUIDs,
                serviceData: device.serviceData
            )
        }

        device.rssiHistory.append(RSSISample(date: date, rssi: rssi))
        if device.rssiHistory.count > BluetoothDevice.maxHistory {
            device.rssiHistory.removeFirst(device.rssiHistory.count - BluetoothDevice.maxHistory)
        }

        buffer[id] = device

        if wasAbsent, AppSettings.favoriteAlerts, store.isFavorite(id) {
            favoriteAlert = FavoriteAlert(deviceID: id, name: store.displayName(for: device))
            Haptics.success()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connections[peripheral.identifier]?.didConnect()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connections[peripheral.identifier]?.didFailToConnect(message: error?.localizedDescription ?? "Échec de la connexion")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connections[peripheral.identifier]?.didDisconnect(error: error)
    }
}
