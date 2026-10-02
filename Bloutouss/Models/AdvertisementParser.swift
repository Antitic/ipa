import CoreBluetooth
import Foundation

enum DeviceKind: String, CaseIterable, Identifiable {
    case unknown, phone, computer, watch, headphones, tracker, beacon, input, health, sensor, media

    var id: Self { self }

    var label: String {
        switch self {
        case .unknown: return "Inconnu"
        case .phone: return "Téléphone / tablette"
        case .computer: return "Ordinateur"
        case .watch: return "Montre / bracelet"
        case .headphones: return "Audio"
        case .tracker: return "Traqueur"
        case .beacon: return "Balise"
        case .input: return "Clavier / souris / manette"
        case .health: return "Santé / sport"
        case .sensor: return "Capteur / maison"
        case .media: return "TV / multimédia"
        }
    }

    var symbol: String {
        switch self {
        case .unknown: return "antenna.radiowaves.left.and.right"
        case .phone: return "iphone"
        case .computer: return "laptopcomputer"
        case .watch: return "applewatch"
        case .headphones: return "headphones"
        case .tracker: return "location.viewfinder"
        case .beacon: return "dot.radiowaves.left.and.right"
        case .input: return "keyboard"
        case .health: return "heart.fill"
        case .sensor: return "thermometer"
        case .media: return "tv"
        }
    }
}

struct InfoItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    var monospaced = false
}

/// Ce que l'on peut déduire des données d'annonce d'un appareil.
struct AdvertisementInfo {
    var kind: DeviceKind = .unknown
    var productName: String?
    var protocols: [String] = []
    var details: [InfoItem] = []
    var isTracker = false

    mutating func setKind(_ newKind: DeviceKind, force: Bool = false) {
        if force || kind == .unknown { kind = newKind }
    }

    mutating func addProtocol(_ name: String) {
        if !protocols.contains(name) { protocols.append(name) }
    }

    mutating func add(_ title: String, _ value: String, monospaced: Bool = false) {
        details.append(InfoItem(title: title, value: value, monospaced: monospaced))
    }
}

enum AdvertisementParser {
    static func parse(
        name: String?,
        manufacturerData: Data?,
        serviceUUIDs: [CBUUID],
        serviceData: [CBUUID: Data]
    ) -> AdvertisementInfo {
        var info = AdvertisementInfo()

        if let data = manufacturerData, data.count >= 2 {
            let bytes = [UInt8](data)
            let company = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
            let payload = Array(bytes.dropFirst(2))
            switch company {
            case 0x004C: parseApple(payload, into: &info)
            case 0x0006: parseMicrosoft(payload, into: &info)
            case 0x0075: info.addProtocol("Samsung")
            case 0x0499: parseRuuvi(payload, into: &info)
            default: break
            }
        }

        for (uuid, data) in serviceData {
            parseServiceData(uuid.uuidString, [UInt8](data), into: &info)
        }
        for uuid in serviceUUIDs {
            parseServiceUUID(uuid.uuidString, into: &info)
        }

        if let name, let guessed = guessKind(fromName: name) {
            info.setKind(guessed)
            if guessed == .tracker { info.isTracker = true }
        }
        return info
    }

    // MARK: - Apple (Continuity)

    private static let appleAudioModels: [UInt16: String] = [
        0x0220: "AirPods",
        0x0F20: "AirPods (2e gén.)",
        0x1320: "AirPods (3e gén.)",
        0x0E20: "AirPods Pro",
        0x1420: "AirPods Pro (2e gén.)",
        0x2420: "AirPods Pro (2e gén., USB-C)",
        0x0A20: "AirPods Max",
        0x0320: "Powerbeats3",
        0x0B20: "Powerbeats Pro",
        0x0C20: "Beats Solo Pro",
        0x1120: "Beats Studio Buds",
        0x1020: "Beats Flex",
        0x0520: "BeatsX",
        0x0620: "Beats Solo3",
        0x0920: "Beats Studio3",
        0x1720: "Beats Studio Pro",
        0x1220: "Beats Fit Pro",
        0x1620: "Beats Studio Buds+",
    ]

    private static let appleMessageTypes: [UInt8: String] = [
        0x03: "AirPrint",
        0x05: "AirDrop",
        0x06: "HomeKit",
        0x07: "Appairage de proximité",
        0x08: "Dis Siri",
        0x09: "AirPlay (cible)",
        0x0A: "AirPlay (source)",
        0x0B: "Magic Switch",
        0x0C: "Handoff",
        0x0D: "Partage de connexion (cible)",
        0x0E: "Partage de connexion (source)",
        0x0F: "Nearby Action",
        0x10: "Nearby Info",
        0x12: "Localiser (Find My)",
    ]

    private static func parseApple(_ payload: [UInt8], into info: inout AdvertisementInfo) {
        var index = 0
        while index + 1 < payload.count {
            let type = payload[index]
            let length = Int(payload[index + 1])
            let start = index + 2
            let end = min(start + length, payload.count)
            let body = Array(payload[start..<end])
            if let name = appleMessageTypes[type] {
                info.addProtocol("Apple \(name)")
            }

            switch type {
            case 0x02 where body.count >= 21:
                info.setKind(.beacon, force: true)
                info.productName = "iBeacon"
                info.add("UUID iBeacon", uuidString(Array(body[0..<16])), monospaced: true)
                info.add("Major", "\(be16(body, 16))")
                info.add("Minor", "\(be16(body, 18))")
                info.add("Puissance à 1 m", "\(Int8(bitPattern: body[20])) dBm")

            case 0x07 where body.count >= 6:
                let model = UInt16(be16(body, 1))
                info.setKind(.headphones, force: true)
                info.productName = appleAudioModels[model] ?? "Écouteurs Apple / Beats"
                info.add("Modèle", String(format: "0x%04X", model), monospaced: true)
                info.add("Batterie écouteur 1", batteryText(Int(body[4] >> 4)))
                info.add("Batterie écouteur 2", batteryText(Int(body[4] & 0x0F)))
                info.add("Batterie boîtier", batteryText(Int(body[5] & 0x0F)))
                let charging = body[5] >> 4
                if charging != 0 {
                    info.add("En charge", charging & 0x04 != 0 ? "Boîtier" : "Écouteurs")
                }

            case 0x12:
                if length >= 0x19 {
                    // Un accessoire Find My éloigné de son propriétaire émet une annonce longue.
                    info.setKind(.tracker, force: true)
                    info.isTracker = true
                    info.productName = "Traqueur Find My (AirTag…)"
                    info.add("Séparé de son propriétaire", "Oui")
                    if let status = body.first {
                        let levels = ["Pleine", "Moyenne", "Faible", "Critique"]
                        info.add("Batterie", levels[Int(status >> 6)])
                    }
                } else {
                    info.add("Find My", "Proche de son propriétaire")
                    info.setKind(.phone)
                }

            case 0x10:
                info.setKind(.phone)
            case 0x09:
                info.setKind(.media)
            case 0x0B:
                info.setKind(.watch)
            case 0x06:
                info.setKind(.sensor)
            default:
                break
            }
            index = start + length
        }
        if info.productName == nil {
            info.productName = "Appareil Apple"
        }
    }

    private static func batteryText(_ value: Int) -> String {
        value <= 10 ? "\(value * 10) %" : "—"
    }

    // MARK: - Autres fabricants

    private static func parseMicrosoft(_ payload: [UInt8], into info: inout AdvertisementInfo) {
        guard let first = payload.first else { return }
        switch first {
        case 0x01:
            info.addProtocol("Microsoft Cross Device")
            info.setKind(.computer)
            info.productName = info.productName ?? "Appareil Windows"
        case 0x03:
            info.addProtocol("Microsoft Swift Pair")
        default:
            info.addProtocol("Microsoft")
        }
    }

    private static func parseRuuvi(_ payload: [UInt8], into info: inout AdvertisementInfo) {
        info.setKind(.sensor, force: true)
        info.productName = "RuuviTag"
        guard payload.count >= 7, payload[0] == 0x05 else { return }
        let temperature = Double(Int16(bitPattern: UInt16(be16(payload, 1)))) * 0.005
        let humidity = Double(be16(payload, 3)) * 0.0025
        let pressure = (Double(be16(payload, 5)) + 50_000) / 100
        info.add("Température", String(format: "%.2f °C", temperature))
        info.add("Humidité", String(format: "%.1f %%", humidity))
        info.add("Pression", String(format: "%.1f hPa", pressure))
    }

    // MARK: - Données de service

    private static func parseServiceData(_ uuid: String, _ bytes: [UInt8], into info: inout AdvertisementInfo) {
        switch uuid {
        case "FEAA":
            parseEddystone(bytes, into: &info)
        case "FE2C":
            info.addProtocol("Google Fast Pair")
            info.setKind(.headphones)
            if bytes.count == 3 {
                info.add("Modèle Fast Pair", bytes.map { String(format: "%02X", $0) }.joined(), monospaced: true)
            }
        case "FD6F":
            info.addProtocol("Notification d'exposition (COVID)")
            info.setKind(.phone)
        case "FD5A":
            markTracker(&info, name: "Samsung SmartTag")
        case "FEED", "FEEC":
            markTracker(&info, name: "Tile")
        case "FE95":
            info.addProtocol("Xiaomi MiBeacon")
            info.setKind(.sensor)
        case "FCD2":
            info.addProtocol("BTHome")
            info.setKind(.sensor)
        default:
            break
        }
    }

    private static func parseServiceUUID(_ uuid: String, into info: inout AdvertisementInfo) {
        switch uuid {
        case "180D":
            info.setKind(.health)
            info.addProtocol("Fréquence cardiaque")
        case "1816", "1818", "1826", "1814":
            info.setKind(.health)
            info.addProtocol("Sport / fitness")
        case "1810", "1808", "1809", "181D", "1822":
            info.setKind(.health)
            info.addProtocol("Santé")
        case "1812":
            info.setKind(.input)
            info.addProtocol("HID (clavier, souris…)")
        case "181A":
            info.setKind(.sensor)
            info.addProtocol("Capteur environnemental")
        case "FEED", "FEEC":
            markTracker(&info, name: "Tile")
        case "FD5A":
            markTracker(&info, name: "Samsung SmartTag")
        case "FEAA":
            info.setKind(.beacon)
        case "FE2C":
            info.addProtocol("Google Fast Pair")
        default:
            break
        }
    }

    private static func markTracker(_ info: inout AdvertisementInfo, name: String) {
        info.setKind(.tracker, force: true)
        info.isTracker = true
        info.productName = info.productName ?? name
        info.addProtocol(name)
    }

    private static func parseEddystone(_ bytes: [UInt8], into info: inout AdvertisementInfo) {
        info.setKind(.beacon, force: true)
        info.productName = info.productName ?? "Eddystone"
        guard let frame = bytes.first else { return }
        switch frame {
        case 0x00 where bytes.count >= 18:
            info.addProtocol("Eddystone-UID")
            info.add("Espace de noms", hex(Array(bytes[2..<12])), monospaced: true)
            info.add("Instance", hex(Array(bytes[12..<18])), monospaced: true)
            info.add("Puissance à 0 m", "\(Int8(bitPattern: bytes[1])) dBm")
        case 0x10 where bytes.count >= 3:
            info.addProtocol("Eddystone-URL")
            info.add("URL", eddystoneURL(bytes))
            info.add("Puissance à 0 m", "\(Int8(bitPattern: bytes[1])) dBm")
        case 0x20 where bytes.count >= 14:
            info.addProtocol("Eddystone-TLM")
            let millivolts = be16(bytes, 2)
            if millivolts > 0 { info.add("Tension batterie", "\(millivolts) mV") }
            if !(bytes[4] == 0x80 && bytes[5] == 0x00) {
                let temperature = Double(Int8(bitPattern: bytes[4])) + Double(bytes[5]) / 256
                info.add("Température", String(format: "%.1f °C", temperature))
            }
            info.add("Annonces émises", "\(be32(bytes, 6))")
            info.add("Allumée depuis", (Double(be32(bytes, 10)) / 10).shortDuration)
        case 0x30:
            info.addProtocol("Eddystone-EID")
        default:
            break
        }
    }

    private static func eddystoneURL(_ bytes: [UInt8]) -> String {
        let schemes = ["http://www.", "https://www.", "http://", "https://"]
        let expansions = [".com/", ".org/", ".edu/", ".net/", ".info/", ".biz/", ".gov/",
                          ".com", ".org", ".edu", ".net", ".info", ".biz", ".gov"]
        var url = Int(bytes[2]) < schemes.count ? schemes[Int(bytes[2])] : ""
        for byte in bytes.dropFirst(3) {
            if Int(byte) < expansions.count {
                url += expansions[Int(byte)]
            } else if byte > 0x20 && byte < 0x7F {
                url += String(Character(UnicodeScalar(byte)))
            }
        }
        return url
    }

    // MARK: - Déduction depuis le nom

    private static let nameHints: [(DeviceKind, [String])] = [
        (.tracker, ["airtag", "smarttag", "chipolo", "tile"]),
        (.headphones, ["airpods", "buds", "beats", "headphone", "headset", "earbud", "jbl", "bose",
                       "wh-1000", "wf-1000", "soundcore", "speaker", "enceinte", "marshall", "sonos", "boom"]),
        (.watch, ["watch", "band", "fitbit", "garmin", "amazfit", "forerunner", "fenix", "whoop"]),
        (.phone, ["iphone", "ipad", "galaxy", "pixel", "phone", "redmi", "oneplus"]),
        (.computer, ["macbook", "imac", "mac mini", "laptop", "desktop", "thinkpad", "surface"]),
        (.media, ["[tv]", " tv", "bravia", "roku", "chromecast", "projector", "vidéoprojecteur"]),
        (.input, ["keyboard", "clavier", "mouse", "souris", "trackpad", "controller", "manette",
                  "xbox", "dualsense", "dualshock", "pencil", "joy-con"]),
        (.health, ["polar", "hrm", "heart", "wahoo", "scale", "balance", "oxim"]),
        (.sensor, ["sensor", "capteur", "ruuvi", "thermo", "hygro", "switchbot", "govee", "inkbird", "hue"]),
    ]

    private static func guessKind(fromName name: String) -> DeviceKind? {
        let lowered = name.lowercased()
        for (kind, hints) in nameHints where hints.contains(where: { lowered.contains($0) }) {
            return kind
        }
        return nil
    }

    // MARK: - Utilitaires

    private static func be16(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
    }

    private static func be32(_ bytes: [UInt8], _ offset: Int) -> Int {
        (be16(bytes, offset) << 16) | be16(bytes, offset + 2)
    }

    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined()
    }

    private static func uuidString(_ bytes: [UInt8]) -> String {
        let digits = hex(bytes)
        let parts = [
            digits.prefix(8),
            digits.dropFirst(8).prefix(4),
            digits.dropFirst(12).prefix(4),
            digits.dropFirst(16).prefix(4),
            digits.dropFirst(20),
        ]
        return parts.joined(separator: "-")
    }
}
