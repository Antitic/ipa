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
    var firstSeen: Date
    var lastSeen: Date
    var isConnectable: Bool?
    var txPower: Int?
    var manufacturerData: Data?
    var serviceUUIDs: [CBUUID] = []
    var serviceData: [CBUUID: Data] = [:]
    var advertisementCount = 0
    var rssiHistory: [RSSISample] = []

    static let maxHistory = 120

    var displayName: String { name ?? "Appareil inconnu" }

    var shortID: String { String(id.uuidString.prefix(8)) }

    /// Identifiant Bluetooth SIG du fabricant (2 premiers octets, little-endian).
    var companyID: UInt16? {
        guard let data = manufacturerData, data.count >= 2 else { return nil }
        return UInt16(data[data.startIndex]) | (UInt16(data[data.startIndex + 1]) << 8)
    }

    var manufacturerName: String? {
        guard let companyID else { return nil }
        return CompanyIdentifiers.name(for: companyID)
    }

    /// Distance approximative (modèle log-distance). Très indicative.
    var estimatedDistance: Double {
        let measuredPower = Double(txPower.map { $0 - 41 } ?? -59) // puissance attendue à 1 m
        let pathLoss = 2.0
        return pow(10, (measuredPower - Double(rssi)) / (10 * pathLoss))
    }

    /// Niveau de signal entre 0 et 1 pour l'affichage.
    var signalLevel: Double {
        let clamped = min(max(Double(rssi), -100), -40)
        return (clamped + 100) / 60
    }

    func isStale(now: Date) -> Bool {
        now.timeIntervalSince(lastSeen) > 10
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}

extension Double {
    var formattedDistance: String {
        if self < 1 {
            return String(format: "~%.0f cm", self * 100)
        }
        return String(format: "~%.1f m", self)
    }
}
