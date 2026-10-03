import CoreBluetooth
import Foundation

/// Connexion GATT à un appareil : services, caractéristiques, lecture, écriture, notifications.
final class GATTSession: NSObject, ObservableObject, CBPeripheralDelegate {
    enum State: Equatable {
        case idle, connecting, connected, disconnected
        case failed(String)
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let date = Date()
        let text: String
    }

    let peripheral: CBPeripheral
    @Published private(set) var state: State = .idle
    @Published private(set) var services: [CBService] = []
    @Published private(set) var rssi: Int?
    @Published private(set) var rssiHistory: [Int] = []
    @Published private(set) var battery: Int?
    @Published private(set) var info: [String: String] = [:]
    @Published private(set) var log: [LogEntry] = []
    @Published private var values: [ObjectIdentifier: Data] = [:]

    /// Appelé quand un nom est lu (caractéristique 2A00 ou nom GAP mis à jour par iOS).
    var onName: ((String) -> Void)?
    private var rssiTimer: Timer?

    static let infoNames: [String: String] = [
        "2A00": "Nom", "2A29": "Fabricant", "2A24": "Modèle", "2A25": "N° de série",
        "2A26": "Firmware", "2A27": "Matériel", "2A28": "Logiciel",
    ]

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
    }

    func value(for c: CBCharacteristic) -> Data? { values[ObjectIdentifier(c)] }

    /// Caractéristique « Niveau d'alerte » du service « Alerte immédiate » (0x1802), si présente.
    var alertCharacteristic: CBCharacteristic? {
        services.first { $0.uuid == CBUUID(string: "1802") }?
            .characteristics?.first { $0.uuid == CBUUID(string: "2A06") }
    }

    // MARK: Cycle de vie (appelé par le scanner)

    func willConnect() {
        state = .connecting
        add("Connexion…")
    }

    func didConnect() {
        peripheral.delegate = self
        state = .connected
        add("Connecté")
        peripheral.discoverServices(nil)
        rssiTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.state == .connected else { return }
            self.peripheral.readRSSI()
        }
        RunLoop.main.add(timer, forMode: .common)
        rssiTimer = timer
    }

    func didFail(_ message: String) {
        state = .failed(message)
        add("Échec : \(message)")
        rssiTimer?.invalidate()
    }

    func didDisconnect(_ error: Error?) {
        rssiTimer?.invalidate()
        if let error {
            state = .failed(error.localizedDescription)
            add("Déconnecté : \(error.localizedDescription)")
        } else {
            state = .disconnected
            add("Déconnecté")
        }
    }

    // MARK: Actions

    func read(_ c: CBCharacteristic) { peripheral.readValue(for: c) }

    func setNotify(_ on: Bool, _ c: CBCharacteristic) { peripheral.setNotifyValue(on, for: c) }

    func write(_ data: Data, to c: CBCharacteristic) {
        let withResponse = c.properties.contains(.write)
        peripheral.writeValue(data, for: c, type: withResponse ? .withResponse : .withoutResponse)
        add("Écriture \(data.hex) → \(GATTNames.characteristic(c.uuid))")
    }

    /// Fait sonner l'appareil (niveau 2 = alerte forte) ou arrête l'alerte (niveau 0).
    func alert(_ level: UInt8) {
        guard let c = alertCharacteristic else { return }
        peripheral.writeValue(Data([level]), for: c, type: .withoutResponse)
        add(level == 0 ? "Alerte arrêtée" : "Alerte envoyée")
    }

    private func add(_ text: String) {
        log.append(LogEntry(text: text))
        if log.count > 150 { log.removeFirst(log.count - 150) }
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { add("Services : \(error.localizedDescription)"); return }
        services = peripheral.services ?? []
        add("\(services.count) service(s)")
        for s in services { peripheral.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        objectWillChange.send()
        for c in service.characteristics ?? [] where c.properties.contains(.read) {
            peripheral.readValue(for: c)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if let error { add("Lecture \(GATTNames.characteristic(c.uuid)) : \(error.localizedDescription)"); return }
        guard let data = c.value else { return }
        values[ObjectIdentifier(c)] = data
        let key = c.uuid.uuidString
        if key == "2A19", let level = data.first {
            battery = Int(level)
        } else if let title = Self.infoNames[key], let text = GATTFormat.text(data) {
            info[title] = text
            if key == "2A00" { onName?(text) }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        add(error.map { "Écriture refusée : \($0.localizedDescription)" } ?? "Écriture confirmée")
        if error == nil, c.properties.contains(.read) { peripheral.readValue(for: c) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        objectWillChange.send()
        if let error {
            add("Notifications impossibles : \(error.localizedDescription)")
        } else {
            add(c.isNotifying ? "Notifications activées" : "Notifications désactivées")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard error == nil else { return }
        rssi = RSSI.intValue
        rssiHistory.append(RSSI.intValue)
        if rssiHistory.count > 60 { rssiHistory.removeFirst(rssiHistory.count - 60) }
    }

    func peripheralDidUpdateName(_ peripheral: CBPeripheral) {
        objectWillChange.send()
        if let name = peripheral.name, !name.isEmpty { onName?(name) }
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        peripheral.discoverServices(nil)
    }
}

enum GATTNames {
    static let services: [String: String] = [
        "1800": "Accès générique", "1801": "Attributs génériques", "1802": "Alerte immédiate",
        "1803": "Perte de lien", "1804": "Puissance d'émission", "1805": "Heure actuelle",
        "1808": "Glucose", "1809": "Thermomètre", "180A": "Informations sur l'appareil",
        "180D": "Fréquence cardiaque", "180F": "Batterie", "1810": "Tension artérielle",
        "1812": "Interface humaine (HID)", "1814": "Course", "1816": "Vélo (vitesse/cadence)",
        "1818": "Vélo (puissance)", "181A": "Capteur environnemental", "181D": "Balance",
        "1822": "Oxymètre", "1826": "Appareil de fitness", "FE2C": "Google Fast Pair",
    ]

    static let characteristics: [String: String] = [
        "2A00": "Nom de l'appareil", "2A01": "Apparence", "2A04": "Paramètres de connexion",
        "2A05": "Service modifié", "2A06": "Niveau d'alerte", "2A07": "Puissance d'émission",
        "2A19": "Niveau de batterie", "2A23": "ID système", "2A24": "Modèle", "2A25": "N° de série",
        "2A26": "Firmware", "2A27": "Matériel", "2A28": "Logiciel", "2A29": "Fabricant",
        "2A2B": "Heure actuelle", "2A37": "Fréquence cardiaque", "2A38": "Position du capteur",
        "2A4D": "Rapport HID", "2A50": "ID PnP", "2A6D": "Pression", "2A6E": "Température",
        "2A6F": "Humidité",
    ]

    static func service(_ uuid: CBUUID) -> String {
        services[uuid.uuidString] ?? (uuid.uuidString.count > 4 ? "Service propriétaire" : uuid.description)
    }

    static func characteristic(_ uuid: CBUUID) -> String {
        characteristics[uuid.uuidString] ?? (uuid.uuidString.count > 4 ? "Caractéristique propriétaire" : uuid.description)
    }

    static func properties(_ p: CBCharacteristicProperties) -> String {
        var names: [String] = []
        if p.contains(.read) { names.append("Lecture") }
        if p.contains(.write) { names.append("Écriture") }
        if p.contains(.writeWithoutResponse) { names.append("Écriture sans réponse") }
        if p.contains(.notify) { names.append("Notification") }
        if p.contains(.indicate) { names.append("Indication") }
        return names.joined(separator: " · ")
    }
}

enum GATTFormat {
    static func describe(_ data: Data, uuid: CBUUID) -> String {
        let b = [UInt8](data)
        guard !b.isEmpty else { return "(vide)" }
        switch uuid.uuidString {
        case "2A19":
            return "\(b[0]) %"
        case "2A37" where b.count >= 2:
            if b[0] & 0x01 == 0 { return "\(b[1]) bpm" }
            if b.count >= 3 { return "\(Int(b[1]) | Int(b[2]) << 8) bpm" }
        case "2A6E" where b.count >= 2:
            return String(format: "%.2f °C", Double(Int16(bitPattern: UInt16(b[0]) | UInt16(b[1]) << 8)) / 100)
        case "2A6F" where b.count >= 2:
            return String(format: "%.1f %%", Double(Int(b[0]) | Int(b[1]) << 8) / 100)
        default:
            break
        }
        if let t = text(data) { return "« \(t) »" }
        return data.hex
    }

    static func text(_ data: Data) -> String? {
        guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
        guard !t.isEmpty, t.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return t
    }

    static func parseHex(_ text: String) -> Data? {
        let hex = text.lowercased().replacingOccurrences(of: "0x", with: "").filter { $0.isHexDigit }
        guard !hex.isEmpty, hex.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let n = hex.index(i, offsetBy: 2)
            guard let v = UInt8(hex[i..<n], radix: 16) else { return nil }
            bytes.append(v)
            i = n
        }
        return Data(bytes)
    }
}
