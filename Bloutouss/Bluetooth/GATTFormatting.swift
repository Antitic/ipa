import CoreBluetooth
import Foundation

enum GATTNames {
    private static let services: [String: String] = [
        "1800": "Accès générique",
        "1801": "Attributs génériques",
        "1802": "Alerte immédiate",
        "1803": "Perte de lien",
        "1804": "Puissance d'émission",
        "1805": "Heure actuelle",
        "1808": "Glucose",
        "1809": "Thermomètre médical",
        "180A": "Informations sur l'appareil",
        "180D": "Fréquence cardiaque",
        "180F": "Batterie",
        "1810": "Tension artérielle",
        "1812": "Interface humaine (HID)",
        "1814": "Vitesse et cadence (course)",
        "1816": "Vitesse et cadence (vélo)",
        "1818": "Puissance (vélo)",
        "181A": "Détection environnementale",
        "181D": "Balance",
        "1822": "Oxymètre de pouls",
        "1826": "Appareil de fitness",
        "FE2C": "Google Fast Pair",
        "FEAA": "Eddystone",
        "FD6F": "Notification d'exposition",
    ]

    private static let characteristics: [String: String] = [
        "2A00": "Nom de l'appareil",
        "2A01": "Apparence",
        "2A04": "Paramètres de connexion",
        "2A05": "Service modifié",
        "2A06": "Niveau d'alerte",
        "2A07": "Puissance d'émission",
        "2A19": "Niveau de batterie",
        "2A23": "ID système",
        "2A24": "Modèle",
        "2A25": "Numéro de série",
        "2A26": "Version du firmware",
        "2A27": "Version matérielle",
        "2A28": "Version logicielle",
        "2A29": "Fabricant",
        "2A2B": "Heure actuelle",
        "2A37": "Fréquence cardiaque",
        "2A38": "Position du capteur",
        "2A4A": "Informations HID",
        "2A4B": "Carte de rapport HID",
        "2A4D": "Rapport HID",
        "2A50": "ID PnP",
        "2A5B": "Vitesse et cadence",
        "2A63": "Puissance (vélo)",
        "2A6D": "Pression",
        "2A6E": "Température",
        "2A6F": "Humidité",
        "2AA6": "Résolution d'adresse centrale",
    ]

    static func service(_ uuid: CBUUID) -> String {
        if let name = services[uuid.uuidString] { return name }
        return uuid.uuidString.count > 4 ? "Service propriétaire" : uuid.description
    }

    static func characteristic(_ uuid: CBUUID) -> String {
        if let name = characteristics[uuid.uuidString] { return name }
        return uuid.uuidString.count > 4 ? "Caractéristique propriétaire" : uuid.description
    }
}

enum PropertyFormatter {
    static func names(_ properties: CBCharacteristicProperties) -> [String] {
        var names: [String] = []
        if properties.contains(.read) { names.append("Lecture") }
        if properties.contains(.write) { names.append("Écriture") }
        if properties.contains(.writeWithoutResponse) { names.append("Écriture sans réponse") }
        if properties.contains(.notify) { names.append("Notification") }
        if properties.contains(.indicate) { names.append("Indication") }
        if properties.contains(.broadcast) { names.append("Diffusion") }
        if properties.contains(.authenticatedSignedWrites) { names.append("Écriture signée") }
        return names
    }
}

enum ValueFormatter {
    /// Valeur lisible quand le format est connu, sinon texte ou hexadécimal.
    static func describe(_ data: Data, uuid: CBUUID) -> String {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return "(vide)" }

        switch uuid.uuidString {
        case "2A19":
            return "\(bytes[0]) %"
        case "2A37" where bytes.count >= 2:
            if bytes[0] & 0x01 == 0 {
                return "\(bytes[1]) bpm"
            }
            if bytes.count >= 3 {
                return "\(Int(bytes[1]) | Int(bytes[2]) << 8) bpm"
            }
        case "2A6E" where bytes.count >= 2:
            let raw = Int16(bitPattern: UInt16(bytes[0]) | UInt16(bytes[1]) << 8)
            return String(format: "%.2f °C", Double(raw) / 100)
        case "2A6F" where bytes.count >= 2:
            let raw = Int(bytes[0]) | Int(bytes[1]) << 8
            return String(format: "%.2f %%", Double(raw) / 100)
        case "2A6D" where bytes.count >= 4:
            let raw = Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
            return String(format: "%.1f hPa", Double(raw) / 1000)
        case "2A07":
            return "\(Int8(bitPattern: bytes[0])) dBm"
        default:
            break
        }

        if let text = text(data) {
            return "« \(text) »"
        }
        return data.hexString
    }

    /// Le contenu en texte s'il s'agit d'UTF-8 imprimable.
    static func text(_ data: Data) -> String? {
        guard !data.isEmpty, let string = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = string.trimmingCharacters(in: CharacterSet(charactersIn: "\0").union(.whitespacesAndNewlines))
        guard !trimmed.isEmpty,
              trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return trimmed
    }
}
