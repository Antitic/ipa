import Foundation
import CoreBluetooth

enum DeviceCategory: String {
    case camera = "Caméra"
    case recorder = "Enregistreur / micro"
    case tracker = "Traceur"
    case audio = "Audio"
    case phone = "Téléphone / tablette"
    case computer = "Ordinateur"
    case wearable = "Montre / bracelet"
    case tv = "TV / multimédia"
    case input = "Clavier / souris"
    case beacon = "Balise"
    case iot = "Objet connecté"
    case unknown = "Inconnu"

    var icon: String {
        switch self {
        case .camera: return "video.fill"
        case .recorder: return "mic.fill"
        case .tracker: return "location.viewfinder"
        case .audio: return "headphones"
        case .phone: return "iphone"
        case .computer: return "laptopcomputer"
        case .wearable: return "applewatch"
        case .tv: return "tv"
        case .input: return "keyboard"
        case .beacon: return "dot.radiowaves.up.forward"
        case .iot: return "lightbulb"
        case .unknown: return "questionmark.circle"
        }
    }

    var isSuspicious: Bool { self == .camera || self == .recorder || self == .tracker }
}

struct BLEInfo {
    var brand: String?
    var model: String?
    var category: DeviceCategory = .unknown
    var details: [String] = []
    var alert: String?
}

struct BLEDevice: Identifiable {
    let id: UUID
    var name: String?
    var rssi: Int = 0
    var history: [Int] = []
    let firstSeen: Date
    var lastSeen: Date
    var manufacturerData: Data?
    var serviceUUIDs: Set<CBUUID> = []
    var serviceData: [CBUUID: Data] = [:]
    var txPower: Int?
    var connectable: Bool = false
    var info = BLEInfo()

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        if let m = info.model { return m }
        if let b = info.brand { return "Appareil \(b)" }
        return "Sans nom"
    }

    var companyID: UInt16? {
        guard let d = manufacturerData, d.count >= 2 else { return nil }
        return UInt16(d[d.startIndex]) | (UInt16(d[d.startIndex + 1]) << 8)
    }

    /// Distance estimée (modèle log-distance, très approximatif).
    var distance: Double {
        let ref = Double(txPower.map { $0 - 41 } ?? -59) // puissance attendue à 1 m
        return pow(10, (ref - Double(rssi)) / (10 * 2.4))
    }

    var distanceText: String {
        let d = distance
        if d < 1 { return "< 1 m" }
        if d < 10 { return String(format: "~%.1f m", d) }
        return "~\(Int(d)) m"
    }
}

enum BLEDecoder {

    // Identifiants constructeur officiels (Bluetooth SIG, « Company Identifiers »)
    static let companies: [UInt16: String] = [
        0x0002: "Intel", 0x0006: "Microsoft", 0x000A: "Qualcomm (CSR)", 0x000D: "Texas Instruments",
        0x000F: "Broadcom", 0x001D: "Qualcomm", 0x004C: "Apple", 0x0057: "Harman (JBL)",
        0x0059: "Nordic Semiconductor", 0x005D: "Realtek", 0x006B: "Polar", 0x0075: "Samsung",
        0x0078: "Nike", 0x0087: "Garmin", 0x008A: "Jawbone", 0x009E: "Bose", 0x00C4: "LG",
        0x00D2: "Dialog Semiconductor", 0x00E0: "Google", 0x0118: "Radius Networks", 0x012D: "Sony",
        0x0131: "Cypress", 0x0157: "Huami (Amazfit / Mi Band)", 0x0171: "Amazon", 0x01DA: "Logitech",
        0x027D: "Huawei", 0x02E5: "Espressif (ESP32)", 0x038F: "Xiaomi", 0x0499: "Ruuvi",
    ]

    // Modèles Apple (« Proximity Pairing », type 0x07)
    static let appleAudioModels: [UInt16: String] = [
        0x0220: "AirPods", 0x0F20: "AirPods (2e gén.)", 0x1320: "AirPods (3e gén.)",
        0x1920: "AirPods (4e gén.)", 0x1B20: "AirPods 4 (réduction de bruit)",
        0x0E20: "AirPods Pro", 0x1420: "AirPods Pro (2e gén.)", 0x2420: "AirPods Pro (2e gén., USB‑C)",
        0x0A20: "AirPods Max", 0x1F20: "AirPods Max (USB‑C)",
        0x0320: "Powerbeats3", 0x0B20: "Powerbeats Pro", 0x0C20: "Beats Solo Pro",
        0x0520: "BeatsX", 0x0620: "Beats Solo3", 0x0920: "Beats Studio3",
        0x1020: "Beats Flex", 0x1120: "Beats Studio Buds", 0x1220: "Beats Fit Pro",
        0x1620: "Beats Studio Buds+", 0x1720: "Beats Studio Pro", 0x1D20: "Powerbeats Pro 2",
    ]

    // Services GATT 16 bits connus (assigned numbers + membres du SIG)
    static let services: [String: (String, DeviceCategory?)] = [
        "FEED": ("Traceur Tile", .tracker), "FEEC": ("Traceur Tile", .tracker),
        "FD5A": ("Samsung SmartTag", .tracker), "FE33": ("Traceur Chipolo", .tracker),
        "FE2C": ("Google Fast Pair", nil), "FEAA": ("Balise Eddystone", .beacon),
        "FD6F": ("Notifications d'exposition", .phone), "FE9F": ("Service Google", nil),
        "FE03": ("Amazon (Alexa)", .iot), "FE95": ("Xiaomi Mi", .iot),
        "FE59": ("Mise à jour Nordic (DFU)", nil), "FE0F": ("Philips Hue", .iot),
        "180D": ("Fréquence cardiaque", .wearable), "1812": ("Périphérique HID", .input),
        "180F": ("Batterie", nil), "1816": ("Vitesse / cadence vélo", .wearable),
        "1826": ("Machine de fitness", .wearable), "181A": ("Capteur environnemental", .iot),
        "1809": ("Thermomètre", .iot), "1810": ("Tensiomètre", .wearable),
        "183B": ("Audio (LE Audio)", .audio), "184E": ("Audio (LE Audio)", .audio),
    ]

    // Marques reconnaissables dans le nom diffusé
    static let nameBrands: [(String, String)] = [
        ("airpods", "Apple"), ("beats", "Apple (Beats)"), ("iphone", "Apple"), ("ipad", "Apple"),
        ("macbook", "Apple"), ("apple watch", "Apple"), ("galaxy", "Samsung"), ("samsung", "Samsung"),
        ("[tv]", "Samsung"), ("jbl", "JBL"), ("bose", "Bose"), ("sony", "Sony"), ("wh-1000", "Sony"),
        ("wf-1000", "Sony"), ("xiaomi", "Xiaomi"), ("redmi", "Xiaomi"), ("mi band", "Xiaomi"),
        ("mi smart band", "Xiaomi"), ("huawei", "Huawei"), ("honor", "Honor"), ("nothing", "Nothing"),
        ("cmf", "Nothing (CMF)"), ("oneplus", "OnePlus"), ("pixel", "Google"), ("garmin", "Garmin"),
        ("fitbit", "Fitbit"), ("polar", "Polar"), ("amazfit", "Amazfit"), ("soundcore", "Anker"),
        ("anker", "Anker"), ("marshall", "Marshall"), ("philips", "Philips"), ("hue", "Philips Hue"),
        ("govee", "Govee"), ("ihoment", "Govee"), ("lg", "LG"), ("logitech", "Logitech"), ("mx ", "Logitech"),
        ("tesla", "Tesla"), ("echo", "Amazon"), ("withings", "Withings"), ("oura", "Oura"),
        ("jabra", "Jabra"), ("sennheiser", "Sennheiser"), ("bang & olufsen", "Bang & Olufsen"),
        ("beoplay", "Bang & Olufsen"), ("ue boom", "Ultimate Ears"), ("tile", "Tile"),
        ("chipolo", "Chipolo"), ("tapo", "TP-Link"), ("ezviz", "EZVIZ"), ("xbox", "Microsoft"),
        ("dualsense", "Sony"), ("wireless controller", "Sony"), ("switch", "Nintendo"),
        ("joy-con", "Nintendo"), ("oppo", "Oppo"), ("realme", "Realme"), ("vivo", "Vivo"),
        ("hp ", "HP"), ("canon", "Canon"), ("epson", "Epson"), ("gopro", "GoPro"),
        ("dji", "DJI"), ("insta360", "Insta360"), ("tado", "tado°"), ("netatmo", "Netatmo"),
        ("sonos", "Sonos"), ("skullcandy", "Skullcandy"), ("audio-technica", "Audio-Technica"),
        ("ruuvi", "Ruuvi"), ("esp32", "Espressif"),
    ]

    // Mots repérés au début ou à la fin d'un mot (« cam » ne doit pas déclencher pour « Camille »).
    static let cameraWords = ["cam ", " cam-", "-cam", "_cam", "webcam", "camera", "caméra", " ipc", "dvr", "nvr", "spy", "hidden", "v380", "a9 ", "eken", "yoosee",
                              "icsee", "xmeye", "camhi", "lookcam", "hdwificam", "wificam", "minicam",
                              "bodycam", "dashcam", "gopro", "insta360", "osmo"]
    static let recorderWords = ["recorder", "voice rec", "rec-", "dictaphone", "audio rec", "spy mic",
                                "wireless mic", "lavalier", "rode", "hollyland", "dji mic", "mic "]
    static let audioWords = ["buds", "pods", "headphone", "headset", "earbud", "speaker", "soundbar",
                             "sound", "audio", "wh-", "wf-", "boom", "flip", "qc", "jbl", "bose"]
    static let wearableWords = ["watch", " band", "fitbit", " fit ", " ring ", "oura", "hrm", "polar h", "versa", "charge "]
    static let tvWords = ["[tv]", " tv", "bravia", "chromecast", "fire tv", "roku", "projector", "projecteur"]
    static let phoneWords = ["iphone", "ipad", "galaxy", "pixel", "phone", "redmi", "oneplus"]
    static let computerWords = ["macbook", "imac", "laptop", "desktop-", " pc ", "-pc ", "thinkpad", "surface"]
    static let inputWords = ["keyboard", "clavier", "mouse", "souris", "trackpad", "mx ", "remote", "controller"]

    static func decode(_ d: BLEDevice) -> BLEInfo {
        var info = BLEInfo()
        let lname = " " + (d.name ?? "").lowercased() + " "

        // 1. Identifiant constructeur
        if let cid = d.companyID {
            if let brand = companies[cid], !brand.isEmpty { info.brand = brand }
            info.details.append(String(format: "Identifiant constructeur 0x%04X", cid))
            if cid == 0x004C, let data = d.manufacturerData {
                decodeApple(data, into: &info)
            } else if cid == 0x0006, let data = d.manufacturerData, data.count >= 3 {
                let scenario = data[data.startIndex + 2]
                if scenario == 0x03 {
                    info.details.append("Microsoft Swift Pair (appareil en mode appairage)")
                    if info.category == .unknown { info.category = .audio }
                } else {
                    info.details.append("Windows Cross-Device (PC Windows à proximité)")
                    info.category = .computer
                }
            } else if cid == 0x0075 {
                info.details.append("Protocole Samsung (Galaxy, Buds, montre, SmartThings…)")
            } else if cid == 0x00E0 {
                info.details.append("Protocole Google (Android, Nearby, Fast Pair…)")
            }
        }

        // 2. Services diffusés
        for uuid in d.serviceUUIDs.union(d.serviceData.keys) {
            let key = uuid.uuidString.uppercased()
            if let entry = services[key] {
                let label = entry.0
                let cat = entry.1
                info.details.append("Service \(key) : \(label)")
                if let cat, info.category == .unknown || cat == .tracker { info.category = cat }
                if cat == .tracker {
                    info.brand = info.brand ?? label.replacingOccurrences(of: "Traceur ", with: "")
                    info.model = info.model ?? label
                }
                if key == "FE2C", let sd = d.serviceData[uuid], sd.count == 3 {
                    let modelID = sd.map { String(format: "%02X", $0) }.joined()
                    info.details.append("Modèle Fast Pair 0x\(modelID)")
                    if info.category == .unknown { info.category = .audio }
                }
            } else {
                info.details.append("Service \(key)")
            }
        }

        // 3. Marque déduite du nom
        if info.brand == nil {
            for (word, brand) in nameBrands where lname.contains(word) {
                info.brand = brand
                break
            }
        }

        // 4. Catégorie déduite du nom
        func has(_ words: [String]) -> Bool { words.contains { lname.contains($0) } }
        if has(cameraWords) {
            info.category = .camera
            info.alert = info.alert ?? "Le nom ressemble à celui d'une caméra."
        } else if has(recorderWords) {
            info.category = .recorder
            info.alert = info.alert ?? "Le nom ressemble à celui d'un micro ou d'un enregistreur."
        } else if info.category == .unknown {
            if has(tvWords) { info.category = .tv }
            else if has(audioWords) { info.category = .audio }
            else if has(wearableWords) { info.category = .wearable }
            else if has(inputWords) { info.category = .input }
            else if has(computerWords) { info.category = .computer }
            else if has(phoneWords) { info.category = .phone }
            else if info.brand == "Espressif (ESP32)" || info.brand == "Nordic Semiconductor" { info.category = .iot }
        }

        if info.category == .tracker && info.alert == nil {
            info.alert = "Traceur détecté. S'il ne t'appartient pas et reste près de toi, vérifie tes affaires."
        }
        if info.category == .iot && d.name == nil && d.rssi > -50 {
            info.alert = "Module générique très proche, sans nom (ESP32, Nordic…). Ces puces équipent aussi des caméras et micros espions."
        }
        return info
    }

    /// Décodage des messages Apple « Continuity ».
    static func decodeApple(_ data: Data, into info: inout BLEInfo) {
        let bytes = [UInt8](data)
        var i = 2
        while i + 1 < bytes.count {
            let type = bytes[i]
            let len = Int(bytes[i + 1])
            let start = i + 2
            let end = min(start + len, bytes.count)
            let payload = start < end ? Array(bytes[start..<end]) : []
            switch type {
            case 0x02:
                info.category = .beacon
                info.model = "iBeacon"
                if payload.count >= 20 {
                    let uuid = payload[0..<16].map { String(format: "%02X", $0) }.joined()
                    let major = (UInt16(payload[16]) << 8) | UInt16(payload[17])
                    let minor = (UInt16(payload[18]) << 8) | UInt16(payload[19])
                    info.details.append("iBeacon \(uuid.prefix(8))… major \(major) minor \(minor)")
                }
            case 0x05:
                info.details.append("AirDrop actif")
                if info.category == .unknown { info.category = .phone }
            case 0x07:
                info.category = .audio
                if payload.count >= 3 {
                    let model = (UInt16(payload[1]) << 8) | UInt16(payload[2])
                    info.model = appleAudioModels[model] ?? String(format: "Écouteurs Apple/Beats (0x%04X)", model)
                    if payload.count >= 5 {
                        let left = Int(payload[4] >> 4), right = Int(payload[4] & 0x0F)
                        var parts: [String] = []
                        if left <= 10 { parts.append("G \(left * 10) %") }
                        if right <= 10 { parts.append("D \(right * 10) %") }
                        if !parts.isEmpty { info.details.append("Batterie " + parts.joined(separator: " · ")) }
                    }
                } else {
                    info.model = "Écouteurs Apple/Beats"
                }
                info.details.append("Proximity Pairing (boîtier ouvert ou appairage)")
            case 0x09:
                info.category = .tv
                info.model = info.model ?? "Cible AirPlay"
                info.details.append("AirPlay : Apple TV, HomePod, Mac ou enceinte compatible")
            case 0x0A:
                info.details.append("AirPlay source")
            case 0x0B:
                info.category = .wearable
                info.model = "Apple Watch"
            case 0x0C:
                info.details.append("Handoff (appareil Apple déverrouillé et actif)")
                if info.category == .unknown { info.category = .phone }
            case 0x0D, 0x0E:
                info.details.append("Partage de connexion (Instant Hotspot)")
                if info.category == .unknown { info.category = .phone }
            case 0x0F:
                info.details.append("Nearby Action (configuration, partage Wi‑Fi…)")
                if info.category == .unknown { info.category = .phone }
            case 0x10:
                info.details.append("Nearby Info (iPhone, iPad, Mac ou Watch à proximité)")
                if info.category == .unknown { info.category = .phone }
                if info.model == nil { info.model = "iPhone / iPad / Mac" }
            case 0x12:
                if len >= 0x19 {
                    info.category = .tracker
                    info.model = "AirTag ou objet Localiser"
                    info.alert = "Objet du réseau Localiser séparé de son propriétaire (AirTag, AirPods, accessoire…). S'il te suit, vérifie tes affaires."
                } else {
                    // Annonce courte : appareil Apple proche de son propriétaire (iPhone, AirTag, AirPods…).
                    // Ce n'est pas un signe de pistage : on ne le classe plus comme traceur.
                    info.details.append("Réseau Localiser (appareil proche de son propriétaire)")
                    if info.model == nil { info.model = "Appareil Apple (Localiser)" }
                }
            case 0x13, 0x16:
                info.details.append("Apple (message 0x\(String(format: "%02X", type)))")
            default:
                info.details.append(String(format: "Apple Continuity 0x%02X", type))
            }
            i = start + len
        }
        if info.brand == nil { info.brand = "Apple" }
    }
}
