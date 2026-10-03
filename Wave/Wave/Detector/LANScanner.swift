import Foundation
import Network
import SwiftUI

enum LANKind: String {
    case me = "Cet iPhone"
    case router = "Box / routeur"
    case camera = "Caméra probable"
    case phone = "Téléphone / tablette"
    case computer = "Ordinateur"
    case printer = "Imprimante"
    case nas = "Stockage réseau (NAS)"
    case tv = "TV / multimédia"
    case speaker = "Enceinte connectée"
    case iot = "Objet connecté"
    case unknown = "Appareil"

    var icon: String {
        switch self {
        case .me: return "iphone.gen3"
        case .router: return "wifi.router"
        case .camera: return "video.fill"
        case .phone: return "iphone"
        case .computer: return "desktopcomputer"
        case .printer: return "printer"
        case .nas: return "externaldrive.connected.to.line.below"
        case .tv: return "tv"
        case .speaker: return "hifispeaker"
        case .iot: return "lightbulb"
        case .unknown: return "questionmark.square.dashed"
        }
    }
}

struct LANHost: Identifiable {
    let ip: String
    let ipNum: UInt32
    var openPorts: [UInt16] = []
    var isSelf = false
    var isGateway = false
    var hostname: String?
    var services: [BonjourService] = []
    var http: [UInt16: HTTPFingerprint] = [:]

    var id: String { ip }

    static let portNames: [UInt16: String] = [
        21: "FTP", 22: "SSH", 23: "Telnet", 53: "DNS", 80: "HTTP", 81: "HTTP alt", 443: "HTTPS",
        445: "SMB", 548: "AFP", 554: "RTSP (vidéo)", 631: "Impression IPP", 1883: "MQTT (domotique)",
        1935: "RTMP (vidéo)", 3389: "Bureau à distance", 5000: "UPnP / NAS", 5001: "NAS HTTPS",
        5353: "mDNS", 5900: "VNC", 6668: "Tuya (domotique)", 7000: "AirPlay", 8000: "HTTP / SDK caméra",
        8008: "Google Cast", 8009: "Google Cast", 8080: "HTTP alt", 8443: "HTTPS alt",
        8554: "RTSP alt (vidéo)", 8888: "HTTP alt", 9000: "HTTP alt", 9100: "Impression brute",
        34567: "DVR/caméra (XMeye)", 37777: "Caméra Dahua", 49152: "UPnP", 62078: "Synchro iPhone/iPad",
    ]

    /// Tout le texte connu sur l'appareil, en minuscules, pour les heuristiques.
    var haystack: String {
        var parts: [String] = []
        if let h = hostname { parts.append(h) }
        for s in services {
            parts.append(s.name)
            parts.append(contentsOf: s.txt.values)
        }
        for fp in http.values {
            parts.append(contentsOf: [fp.title, fp.server, fp.realm, fp.poweredBy].compactMap { $0 })
        }
        return " " + parts.joined(separator: " ").lowercased() + " "
    }

    private func has(_ words: [String]) -> Bool {
        let h = haystack
        return words.contains { h.contains($0) }
    }

    private func hasPort(_ ports: [UInt16]) -> Bool { ports.contains { openPorts.contains($0) } }
    private func hasService(_ types: [String]) -> Bool { services.contains { types.contains($0.type) } }

    var kind: LANKind {
        if isSelf { return .me }
        if hasPort([554, 8554, 37777, 34567]) || hasService(["_rtsp._tcp", "_axis-video._tcp"])
            || has(["camera", "caméra", "ipcam", "ip cam", "webcam", "netcam", "hikvision", "dahua", "dvr", "nvr",
                    "onvif", "reolink", "ezviz", "foscam", "amcrest", "imou", "tapo c", "xmeye", "yoosee",
                    "wyze", "arlo", "blink", "eufy", "annke", "uniview", "vstarcam", " ipc"]) {
            return .camera
        }
        if isGateway || has(["freebox server", "livebox", "bbox", "sfr box", "router", "routeur", "gateway",
                             "openwrt", "fritz!box", "fritzbox", "netgear", "asuswrt", "tp-link archer", "orbi", " deco "]) {
            return .router
        }
        if hasPort([631, 9100]) || hasService(["_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp"])
            || has(["printer", "imprimante", "laserjet", "deskjet", "officejet", "epson", "canon", "brother"]) {
            return .printer
        }
        if has(["synology", "diskstation", "qnap", " nas", "truenas", "unraid"]) { return .nas }
        if hasPort([8008, 8009]) || hasService(["_googlecast._tcp", "_amzn-wplay._tcp", "_nvstream._tcp"])
            || has(["appletv", "apple tv", "chromecast", "bravia", "android tv", "google tv", "fire tv", "roku",
                    "freebox player", "freebox mini", "tv ", "[tv]", "shield", "playstation", "xbox"]) {
            return .tv
        }
        if hasService(["_sonos._tcp", "_spotify-connect._tcp", "_raop._tcp"])
            || has(["homepod", "sonos", "echo", "nest audio", "nest mini", "google home", "bose", "marshall"]) {
            return .speaker
        }
        if hasPort([62078]) || has(["iphone", "ipad", "android", "galaxy", "pixel", "redmi", "oneplus", "nothing-phone", "huawei"]) {
            return .phone
        }
        if hasPort([22, 445, 548, 3389, 5900]) || hasService(["_smb._tcp", "_afpovertcp._tcp", "_ssh._tcp", "_workstation._tcp", "_device-info._tcp"])
            || has(["macbook", "imac", "mac-mini", "desktop-", "laptop", "thinkpad", "-pc", "ubuntu", "debian", "archlinux"]) {
            return .computer
        }
        if hasPort([1883, 6668]) || hasService(["_hap._tcp", "_homekit._tcp", "_matter._tcp", "_meshcop._udp"])
            || has([" esp", "esp32", "esp8266", "tasmota", "shelly", "philips hue", "hue bridge", "tuya", "govee", "google nest", "nest-", "netatmo", "tado", "meross", "sonoff", "yeelight"]) {
            return .iot
        }
        return .unknown
    }

    var displayName: String {
        if isSelf { return "Cet iPhone" }
        if let fn = services.compactMap({ $0.txt["fn"] }).first { return fn }
        if let s = services.first(where: { !["_http._tcp", "_https._tcp", "_device-info._tcp"].contains($0.type) }) {
            return s.name
        }
        if let s = services.first { return s.name }
        if let h = hostname {
            return h.replacingOccurrences(of: ".home", with: "")
                .replacingOccurrences(of: ".lan", with: "")
                .replacingOccurrences(of: ".local", with: "")
        }
        if let t = http.values.compactMap({ $0.title }).first { return t }
        return kind.rawValue
    }

    /// Marque / modèle déduits des annonces.
    var brandModel: String? {
        let txtKeys = ["md", "model", "am", "ty", "usb_MDL", "product", "manufacturer", "mfg", "usb_MFG"]
        var found: [String] = []
        for s in services {
            for k in txtKeys {
                if let v = s.txt[k], !v.isEmpty, !found.contains(v) { found.append(v) }
            }
        }
        if found.isEmpty, let srv = http.values.compactMap({ $0.server }).first { found.append(srv) }
        if found.isEmpty, let realm = http.values.compactMap({ $0.realm }).first { found.append(realm) }
        return found.isEmpty ? nil : found.prefix(2).joined(separator: " · ")
    }

    var macAddress: String? {
        for s in services {
            if let id = s.txt["deviceid"], id.count == 17, id.contains(":") { return id.uppercased() }
        }
        return nil
    }

    var alert: String? {
        switch kind {
        case .camera:
            return "Caméra probable : flux vidéo (RTSP) ou nom de caméra détecté. Vérifie qu'elle t'appartient ou qu'elle est signalée."
        case .speaker:
            return "Les enceintes connectées intègrent souvent des micros (assistant vocal)."
        default:
            if hasPort([23]) { return "Telnet ouvert : service ancien et non chiffré, souvent présent sur les caméras bas de gamme." }
            return nil
        }
    }
}

@MainActor
final class LANScanner: ObservableObject {
    @Published var hosts: [LANHost] = []
    @Published var bonjour: [BonjourService] = []
    @Published var scanning = false
    @Published var progress: Double = 0
    @Published var phase = ""
    @Published var error: String?
    @Published var iface: NetInterface?
    @Published var gateway: String?
    @Published var finishedAt: Date?

    nonisolated static let discoveryPorts: [UInt16] = [80, 443, 62078, 554, 445, 8080]
    nonisolated static let fullPorts: [UInt16] = [21, 22, 23, 53, 80, 81, 443, 445, 548, 554, 631, 1883, 1935, 3389, 5000,
                                       5001, 5900, 6668, 7000, 8000, 8008, 8009, 8080, 8443, 8554, 8888, 9000,
                                       9100, 34567, 37777, 49152, 62078]
    nonisolated static let webPorts: [UInt16] = [80, 81, 443, 5000, 5001, 8000, 8080, 8443, 8888, 9000]

    func scan() async {
        guard !scanning else { return }
        error = nil
        guard let wifi = NetUtil.wifi() else {
            error = "Pas connecté à un réseau Wi‑Fi."
            return
        }
        scanning = true
        iface = wifi
        hosts = []
        bonjour = []
        progress = 0

        if let path = await NetUtil.currentPath(), let gw = path.gateways.first,
           case let .hostPort(host, _) = gw {
            gateway = NetUtil.hostString(host)
        }

        // Plage d'adresses (limitée à un /24 autour de l'iPhone si le réseau est plus grand).
        var first = wifi.network &+ 1
        var last = (wifi.network | ~wifi.mask) &- 1
        if wifi.prefix < 24 || last < first {
            first = (wifi.ip & 0xFFFF_FF00) + 1
            last = (wifi.ip & 0xFFFF_FF00) + 254
        }
        let ips = Array(first...last)

        // Bonjour en parallèle
        let bonjourTask = Task { await BonjourBrowser.browse(seconds: 6) }

        // Phase 1 : quels hôtes répondent ?
        phase = "Recherche des appareils…"
        let total = Double(ips.count)
        let alive: [UInt32] = await NetUtil.concurrentMap(ips, limit: 12, progress: { done in
            Task { @MainActor in self.progress = 0.6 * Double(done) / total }
        }) { ip -> UInt32? in
            if ip == wifi.ip { return ip }
            let s = NetUtil.ipString(ip)
            let states = await NetUtil.concurrentMap(LANScanner.discoveryPorts, limit: 6) { port in
                await NetUtil.probe(s, port, timeout: 1.0)
            }
            return states.contains { $0 != .silent } ? ip : nil
        }.compactMap { $0 }

        var found: [String: LANHost] = [:]
        for ip in alive {
            let s = NetUtil.ipString(ip)
            found[s] = LANHost(ip: s, ipNum: ip, isSelf: ip == wifi.ip, isGateway: s == gateway)
        }

        // Bonjour : ajoute aussi les appareils silencieux en TCP.
        phase = "Lecture des annonces Bonjour…"
        let services = await bonjourTask.value
        bonjour = services.sorted { $0.name < $1.name }
        for svc in services {
            guard let ip = svc.ip, ip.contains("."), !ip.contains(":") else { continue }
            if found[ip] == nil {
                let num = ip.split(separator: ".").compactMap { UInt32($0) }.reduce(0) { ($0 << 8) | $1 }
                found[ip] = LANHost(ip: ip, ipNum: num, isSelf: num == wifi.ip, isGateway: ip == gateway)
            }
            found[ip]?.services.append(svc)
        }
        if let gw = gateway, found[gw] == nil {
            let num = gw.split(separator: ".").compactMap { UInt32($0) }.reduce(0) { ($0 << 8) | $1 }
            found[gw] = LANHost(ip: gw, ipNum: num, isGateway: true)
        }
        hosts = found.values.sorted { $0.ipNum < $1.ipNum }

        // Phase 2 : ports
        phase = "Analyse des ports…"
        let targets = hosts.filter { !$0.isSelf }.map { $0.ip }
        let pairs = targets.flatMap { ip in LANScanner.fullPorts.map { (ip, $0) } }
        let pairTotal = Double(max(pairs.count, 1))
        let portResults = await NetUtil.concurrentMap(pairs, limit: 48, progress: { done in
            Task { @MainActor in self.progress = 0.6 + 0.25 * Double(done) / pairTotal }
        }) { pair -> (String, UInt16, PortState) in
            (pair.0, pair.1, await NetUtil.probe(pair.0, pair.1, timeout: 1.2))
        }
        for r in portResults where r.2 == .open {
            found[r.0]?.openPorts.append(r.1)
        }
        for k in found.keys { found[k]?.openPorts.sort() }
        hosts = found.values.sorted { $0.ipNum < $1.ipNum }

        // Phase 3 : noms et pages web
        phase = "Identification…"
        let webJobs = found.values.flatMap { h in h.openPorts.filter { LANScanner.webPorts.contains($0) }.map { (h.ip, $0) } }
        let fps = await NetUtil.concurrentMap(webJobs, limit: 12) { job -> (String, UInt16, HTTPFingerprint?) in
            (job.0, job.1, await HTTPProbe.fingerprint(ip: job.0, port: job.1))
        }
        for f in fps { if let fp = f.2 { found[f.0]?.http[f.1] = fp } }
        progress = 0.92

        let names = await NetUtil.concurrentMap(Array(found.keys), limit: 12) { ip -> (String, String?) in
            await Task.detached { (ip, NetUtil.reverseDNS(ip)) }.value
        }
        for n in names { found[n.0]?.hostname = n.1 }

        hosts = found.values.sorted { $0.ipNum < $1.ipNum }
        progress = 1
        phase = ""
        scanning = false
        finishedAt = Date()
    }
}
