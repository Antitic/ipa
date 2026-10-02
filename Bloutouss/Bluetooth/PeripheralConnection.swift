import CoreBluetooth
import Foundation

/// Connexion GATT à un appareil : services, caractéristiques, lecture, écriture et notifications.
final class PeripheralConnection: NSObject, ObservableObject {
    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let date = Date()
        let message: String
    }

    let peripheral: CBPeripheral

    @Published private(set) var state: State = .disconnected
    @Published private(set) var services: [CBService] = []
    @Published private(set) var rssi: Int?
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var deviceInfo: [String: String] = [:]
    @Published private(set) var log: [LogEntry] = []
    @Published private var values: [ObjectIdentifier: Data] = [:]
    @Published private var valueDates: [ObjectIdentifier: Date] = [:]

    private var rssiTimer: Timer?

    private static let deviceInfoNames: [String: String] = [
        "2A00": "Nom",
        "2A29": "Fabricant",
        "2A24": "Modèle",
        "2A25": "Numéro de série",
        "2A26": "Firmware",
        "2A27": "Matériel",
        "2A28": "Logiciel",
    ]

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
    }

    var name: String? { peripheral.name }

    func value(for characteristic: CBCharacteristic) -> Data? {
        values[ObjectIdentifier(characteristic)]
    }

    func valueDate(for characteristic: CBCharacteristic) -> Date? {
        valueDates[ObjectIdentifier(characteristic)]
    }

    // MARK: - Cycle de vie (appelé par le scanner)

    func willConnect() {
        state = .connecting
        addLog("Connexion…")
    }

    func didConnect() {
        state = .connected
        addLog("Connecté")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        startRSSITimer()
    }

    func didFailToConnect(message: String) {
        state = .failed(message)
        addLog("Échec : \(message)")
        stopRSSITimer()
    }

    func didDisconnect(error: Error?) {
        if let error {
            state = .failed(error.localizedDescription)
            addLog("Déconnecté : \(error.localizedDescription)")
        } else {
            state = .disconnected
            addLog("Déconnecté")
        }
        stopRSSITimer()
    }

    func markDisconnected() {
        guard state != .disconnected else { return }
        state = .disconnected
        stopRSSITimer()
    }

    // MARK: - Actions

    func read(_ characteristic: CBCharacteristic) {
        peripheral.readValue(for: characteristic)
    }

    func setNotify(_ enabled: Bool, for characteristic: CBCharacteristic) {
        peripheral.setNotifyValue(enabled, for: characteristic)
    }

    func write(_ data: Data, to characteristic: CBCharacteristic) {
        let withResponse = characteristic.properties.contains(.write)
        peripheral.writeValue(data, for: characteristic, type: withResponse ? .withResponse : .withoutResponse)
        addLog("Écriture \(data.hexString) → \(GATTNames.characteristic(characteristic.uuid))")
    }

    // MARK: - Interne

    private func addLog(_ message: String) {
        log.append(LogEntry(message: message))
        if log.count > 200 {
            log.removeFirst(log.count - 200)
        }
    }

    private func startRSSITimer() {
        stopRSSITimer()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.state == .connected else { return }
            self.peripheral.readRSSI()
        }
    }

    private func stopRSSITimer() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }

    private func handleKnownValue(_ data: Data, for uuid: CBUUID) {
        let key = uuid.uuidString
        if key == "2A19", let level = data.first {
            batteryLevel = Int(level)
        } else if let title = Self.deviceInfoNames[key], let text = ValueFormatter.text(data) {
            deviceInfo[title] = text
        }
    }
}

extension PeripheralConnection: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            addLog("Erreur de découverte : \(error.localizedDescription)")
            return
        }
        services = peripheral.services ?? []
        addLog("\(services.count) service(s) trouvé(s)")
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            addLog("Erreur (\(GATTNames.service(service.uuid))) : \(error.localizedDescription)")
            return
        }
        objectWillChange.send()
        for characteristic in service.characteristics ?? [] where characteristic.properties.contains(.read) {
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            addLog("Lecture impossible (\(GATTNames.characteristic(characteristic.uuid))) : \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        let key = ObjectIdentifier(characteristic)
        values[key] = data
        valueDates[key] = Date()
        handleKnownValue(data, for: characteristic.uuid)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            addLog("Écriture refusée : \(error.localizedDescription)")
        } else {
            addLog("Écriture confirmée")
            if characteristic.properties.contains(.read) {
                peripheral.readValue(for: characteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        objectWillChange.send()
        let name = GATTNames.characteristic(characteristic.uuid)
        if let error {
            addLog("Notifications impossibles (\(name)) : \(error.localizedDescription)")
        } else {
            addLog(characteristic.isNotifying ? "Notifications activées : \(name)" : "Notifications désactivées : \(name)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if error == nil {
            rssi = RSSI.intValue
        }
    }

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        objectWillChange.send()
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        addLog("Services modifiés, nouvelle découverte…")
        peripheral.discoverServices(nil)
    }
}
