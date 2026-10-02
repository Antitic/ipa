import CoreBluetooth
import Foundation

struct RSSISample: Identifiable {
    let id = UUID()
    let date: Date
    let rssi: Int
}

struct BluetoothDevice: Identifiable {
    let id: UUID
    var name: String?
    var rssi: Int
    /// Moyenne glissante exponentielle du RSSI, plus stable pour la distance et le tri.
    var smoothedRSSI: Double
    var minRSSI: Int
    var maxRSSI: Int
    var firstSeen: Date
    var lastSeen: Date
    var isConnectable: Bool?
    var txPower: Int?
    var manufacturerData: Data?
    var serviceUUIDs: [CBUUID] = []
    var serviceData: [CBUUID: Data] = [:]
    var advertisementCount = 0
    var rssiHistory: [RSSISample] = []
    var info = AdvertisementInfo()

    static let maxHistory = 180

    init(id: UUID, rssi: Int, date: Date) {
        self.id = id
        self.rssi = rssi
        smoothedRSSI = Double(rssi)
        minRSSI = rssi
        maxRSSI = rssi
        firstSeen = date
        lastSeen = date
    }

    var kind: DeviceKind { info.kind }

    /// Nom annoncé, sinon produit identifié, sinon « Appareil inconnu ».
    var baseName: String { name ?? info.productName ?? "Appareil inconnu" }

    var hasName: Bool { name != nil || info.productName != nil }

    var shortID: String { String(id.uuidString.prefix(8)) }

    /// Identifiant Bluetooth SIG du fabricant (2 premiers octets, little-endian).
    var companyID: UInt16? {
        guard let data = manufacturerData, data.count >= 2 else { return nil }
        let bytes = [UInt8](data)
        return UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
    }

    var manufacturerName: String? {
        guard let companyID else { return nil }
        return CompanyIdentifiers.name(for: companyID)
    }

    var subtitle: String {
        var parts: [String] = []
        if name != nil, let product = info.productName {
            parts.append(product)
        } else if info.productName == nil, kind != .unknown {
            parts.append(kind.label)
        }
        if let manufacturer = manufacturerName, !parts.contains(where: { $0.contains(manufacturer) }) {
            parts.append(manufacturer)
        }
        parts.append(shortID)
        return parts.joined(separator: " · ")
    }

    /// Distance approximative (modèle log-distance). Très indicative.
    var estimatedDistance: Double {
        let measuredPower = txPower.map { Double($0) - 41 } ?? AppSettings.measuredPower
        let pathLoss = max(AppSettings.pathLoss, 1)
        return pow(10, (measuredPower - smoothedRSSI) / (10 * pathLoss))
    }

    /// Niveau de signal entre 0 et 1 pour l'affichage.
    var signalLevel: Double {
        let clamped = min(max(smoothedRSSI, -100), -40)
        return (clamped + 100) / 60
    }

    var averageRSSI: Double {
        guard !rssiHistory.isEmpty else { return Double(rssi) }
        return Double(rssiHistory.reduce(0) { $0 + $1.rssi }) / Double(rssiHistory.count)
    }

    var trackedDuration: TimeInterval { lastSeen.timeIntervalSince(firstSeen) }

    func isStale(now: Date) -> Bool {
        now.timeIntervalSince(lastSeen) > AppSettings.staleAfter
    }

    /// Tendance du signal sur les dernières secondes : > 0 se rapproche, < 0 s'éloigne.
    var trend: Double {
        let recent = rssiHistory.suffix(6)
        let previous = rssiHistory.dropLast(6).suffix(6)
        guard recent.count >= 3, previous.count >= 3 else { return 0 }
        let recentAverage = Double(recent.reduce(0) { $0 + $1.rssi }) / Double(recent.count)
        let previousAverage = Double(previous.reduce(0) { $0 + $1.rssi }) / Double(previous.count)
        return recentAverage - previousAverage
    }
}
