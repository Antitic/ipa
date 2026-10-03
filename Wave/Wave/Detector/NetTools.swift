import Foundation
import Network

// MARK: - Outils réseau bas niveau

struct NetInterface {
    let name: String
    let ip: UInt32     // ordre hôte
    let mask: UInt32

    var ipString: String { NetUtil.ipString(ip) }
    var maskString: String { NetUtil.ipString(mask) }
    var prefix: Int { mask.nonzeroBitCount }
    var network: UInt32 { ip & mask }
}

final class Once {
    private var done = false
    private let lock = NSLock()
    func run(_ f: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        if done { return }
        done = true
        f()
    }
}

enum PortState { case open, closed, silent }

enum NetUtil {
    static let queue = DispatchQueue(label: "wave.net", qos: .userInitiated, attributes: .concurrent)

    static func ipString(_ v: UInt32) -> String {
        "\((v >> 24) & 255).\((v >> 16) & 255).\((v >> 8) & 255).\(v & 255)"
    }

    static func interfaces() -> [NetInterface] {
        var result: [NetInterface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let ifa = p.pointee
            ptr = ifa.ifa_next
            guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
                  let nm = ifa.ifa_netmask else { continue }
            let name = String(cString: ifa.ifa_name)
            let addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            let mask = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
            result.append(NetInterface(name: name, ip: UInt32(bigEndian: addr), mask: UInt32(bigEndian: mask)))
        }
        return result
    }

    static func wifi() -> NetInterface? {
        interfaces().first { $0.name == "en0" }
    }

    static func cellular() -> NetInterface? {
        interfaces().first { $0.name.hasPrefix("pdp_ip") }
    }

    /// Tentative de connexion TCP : ouvert, refusé (l'hôte existe) ou silence.
    static func probe(_ host: String, _ port: UInt16, timeout: Double = 0.9) async -> PortState {
        await withCheckedContinuation { (cont: CheckedContinuation<PortState, Never>) in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                cont.resume(returning: .silent)
                return
            }
            let tcp = NWProtocolTCP.Options()
            tcp.connectionTimeout = max(1, Int(timeout.rounded(.up)))
            let params = NWParameters(tls: nil, tcp: tcp)
            let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
            let once = Once()
            let finish: (PortState) -> Void = { state in
                once.run {
                    conn.stateUpdateHandler = nil
                    conn.cancel()
                    cont.resume(returning: state)
                }
            }
            conn.stateUpdateHandler = { st in
                switch st {
                case .ready:
                    finish(.open)
                case .waiting(let err), .failed(let err):
                    if case .posix(let code) = err, code == .ECONNREFUSED {
                        finish(.closed)
                    } else {
                        finish(.silent)
                    }
                default:
                    break
                }
            }
            conn.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(.silent) }
        }
    }

    /// Nom de l'hôte via DNS inverse (souvent fourni par la box).
    static func reverseDNS(_ ip: String) -> String? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        guard inet_pton(AF_INET, ip, &addr.sin_addr) == 1 else { return nil }
        let capacity = Int(NI_MAXHOST)
        var host = [CChar](repeating: 0, count: capacity)
        let r = withUnsafePointer(to: addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getnameinfo(sa, socklen_t(MemoryLayout<sockaddr_in>.size),
                            &host, socklen_t(capacity), nil, 0, NI_NAMEREQD)
            }
        }
        guard r == 0 else { return nil }
        let name = String(cString: host)
        return name == ip ? nil : name
    }

    /// Exécute `f` sur chaque élément avec un nombre limité de tâches simultanées.
    static func concurrentMap<T, R: Sendable>(_ items: [T], limit: Int,
                                    progress: ((Int) -> Void)? = nil,
                                    _ f: @escaping (T) async -> R) async -> [R] {
        if items.isEmpty { return [] }
        var results = [R?](repeating: nil, count: items.count)
        var done = 0
        await withTaskGroup(of: (Int, R).self) { group in
            var next = 0
            for _ in 0..<min(limit, items.count) {
                let i = next
                group.addTask { (i, await f(items[i])) }
                next += 1
            }
            while let res = await group.next() {
                results[res.0] = res.1
                done += 1
                progress?(done)
                if next < items.count {
                    let j = next
                    group.addTask { (j, await f(items[j])) }
                    next += 1
                }
            }
        }
        return results.compactMap { $0 }
    }

    static func currentPath(timeout: Double = 2) async -> NWPath? {
        await withCheckedContinuation { (cont: CheckedContinuation<NWPath?, Never>) in
            let monitor = NWPathMonitor()
            let once = Once()
            monitor.pathUpdateHandler = { path in
                once.run {
                    monitor.cancel()
                    cont.resume(returning: path)
                }
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                once.run {
                    monitor.cancel()
                    cont.resume(returning: nil)
                }
            }
        }
    }

    static func hostString(_ host: NWEndpoint.Host) -> String? {
        switch host {
        case .ipv4(let a): return a.rawValue.map { String($0) }.joined(separator: ".")
        case .ipv6(let a): return "\(a)"
        case .name(let n, _): return n
        @unknown default: return nil
        }
    }
}

// MARK: - Bonjour (mDNS)

struct BonjourService: Identifiable {
    let name: String
    let type: String
    var txt: [String: String] = [:]
    var ip: String?
    var port: UInt16?
    var id: String { name + "|" + type }

    var typeLabel: String { BonjourBrowser.labels[type] ?? type }
}

enum BonjourBrowser {
    static let types = [
        "_http._tcp", "_https._tcp", "_rtsp._tcp", "_airplay._tcp", "_raop._tcp", "_googlecast._tcp",
        "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp", "_hap._tcp", "_homekit._tcp",
        "_smb._tcp", "_afpovertcp._tcp", "_ssh._tcp", "_sftp-ssh._tcp", "_companion-link._tcp",
        "_spotify-connect._tcp", "_sonos._tcp", "_amzn-wplay._tcp", "_device-info._tcp",
        "_workstation._tcp", "_matter._tcp", "_meshcop._udp", "_axis-video._tcp", "_nvstream._tcp",
        "_webdav._tcp",
    ]

    static let labels: [String: String] = [
        "_http._tcp": "Interface web", "_https._tcp": "Interface web sécurisée",
        "_rtsp._tcp": "Flux vidéo RTSP", "_airplay._tcp": "AirPlay", "_raop._tcp": "AirPlay audio",
        "_googlecast._tcp": "Chromecast / Google Cast", "_ipp._tcp": "Imprimante (IPP)",
        "_ipps._tcp": "Imprimante (IPPS)", "_printer._tcp": "Imprimante (LPD)",
        "_pdl-datastream._tcp": "Imprimante (port 9100)", "_hap._tcp": "Accessoire HomeKit",
        "_homekit._tcp": "HomeKit", "_smb._tcp": "Partage de fichiers (SMB)",
        "_afpovertcp._tcp": "Partage de fichiers (AFP)", "_ssh._tcp": "SSH", "_sftp-ssh._tcp": "SFTP",
        "_companion-link._tcp": "Appareil Apple", "_spotify-connect._tcp": "Spotify Connect",
        "_sonos._tcp": "Sonos", "_amzn-wplay._tcp": "Amazon Fire TV / Echo",
        "_device-info._tcp": "Infos appareil", "_workstation._tcp": "Ordinateur",
        "_matter._tcp": "Objet Matter", "_meshcop._udp": "Thread (domotique)",
        "_axis-video._tcp": "Caméra Axis", "_nvstream._tcp": "NVIDIA GameStream",
        "_webdav._tcp": "WebDAV",
    ]

    private final class Collector {
        private var results: [String: Set<NWBrowser.Result>] = [:]
        private let lock = NSLock()
        func set(_ type: String, _ r: Set<NWBrowser.Result>) {
            lock.lock(); results[type] = r; lock.unlock()
        }
        func all() -> [(String, NWBrowser.Result)] {
            lock.lock(); defer { lock.unlock() }
            return results.flatMap { type, set in set.map { (type, $0) } }
        }
    }

    static func browse(seconds: Double) async -> [BonjourService] {
        let collector = Collector()
        var browsers: [NWBrowser] = []
        for t in types {
            let udp = t.hasSuffix("._udp")
            let b = NWBrowser(for: .bonjourWithTXTRecord(type: t, domain: "local."), using: udp ? .udp : .tcp)
            b.browseResultsChangedHandler = { results, _ in collector.set(t, results) }
            b.start(queue: NetUtil.queue)
            browsers.append(b)
        }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        browsers.forEach { $0.cancel() }

        let found = collector.all()
        return await NetUtil.concurrentMap(found, limit: 10) { item -> BonjourService in
            let (type, result) = item
            var name = "?"
            if case let .service(n, _, _, _) = result.endpoint { name = n }
            var svc = BonjourService(name: name, type: type)
            if case let .bonjour(txt) = result.metadata { svc.txt = txt.dictionary }
            if !type.hasSuffix("._udp"), let res = await resolve(result.endpoint) {
                svc.ip = res.0
                svc.port = res.1
            }
            return svc
        }
    }

    /// Ouvre une connexion vers le service pour obtenir son adresse IPv4.
    static func resolve(_ endpoint: NWEndpoint) async -> (String, UInt16)? {
        await withCheckedContinuation { (cont: CheckedContinuation<(String, UInt16)?, Never>) in
            let params = NWParameters.tcp
            if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ip.version = .v4
            }
            let conn = NWConnection(to: endpoint, using: params)
            let once = Once()
            let finish: ((String, UInt16)?) -> Void = { value in
                once.run {
                    conn.stateUpdateHandler = nil
                    conn.cancel()
                    cont.resume(returning: value)
                }
            }
            conn.stateUpdateHandler = { st in
                switch st {
                case .ready:
                    var out: (String, UInt16)?
                    if let ep = conn.currentPath?.remoteEndpoint, case let .hostPort(host, port) = ep,
                       let s = NetUtil.hostString(host) {
                        out = (s, port.rawValue)
                    }
                    finish(out)
                case .failed, .waiting:
                    finish(nil)
                default:
                    break
                }
            }
            conn.start(queue: NetUtil.queue)
            NetUtil.queue.asyncAfter(deadline: .now() + 3) { finish(nil) }
        }
    }
}

// MARK: - Empreinte HTTP

struct HTTPFingerprint {
    var title: String?
    var server: String?
    var realm: String?
    var poweredBy: String?
}

final class TrustAllDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

enum HTTPProbe {
    static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 3
        cfg.timeoutIntervalForResource = 4
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg, delegate: TrustAllDelegate(), delegateQueue: nil)
    }()

    static func fingerprint(ip: String, port: UInt16) async -> HTTPFingerprint? {
        let https = [443, 8443, 5001].contains(Int(port))
        let defaultPort = https ? 443 : 80
        let portPart = Int(port) == defaultPort ? "" : ":\(port)"
        guard let url = URL(string: "\(https ? "https" : "http")://\(ip)\(portPart)/") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (iPhone) Wave", forHTTPHeaderField: "User-Agent")
        guard let result = try? await session.data(for: req),
              let http = result.1 as? HTTPURLResponse else {
            return nil
        }
        let data = result.0
        var fp = HTTPFingerprint()
        fp.server = http.value(forHTTPHeaderField: "Server")
        fp.poweredBy = http.value(forHTTPHeaderField: "X-Powered-By")
        if let auth = http.value(forHTTPHeaderField: "WWW-Authenticate"),
           let r = auth.range(of: "realm=\"") {
            let rest = auth[r.upperBound...]
            fp.realm = rest.split(separator: "\"").first.map(String.init)
        }
        let html = String(decoding: data.prefix(80_000), as: UTF8.self)
        fp.title = extractTitle(html)
        return fp
    }

    static func extractTitle(_ html: String) -> String? {
        let lower = html.lowercased()
        guard let open = lower.range(of: "<title") else { return nil }
        guard let gt = lower.range(of: ">", range: open.upperBound..<lower.endIndex) else { return nil }
        guard let close = lower.range(of: "</title>", range: gt.upperBound..<lower.endIndex) else { return nil }
        // Les indices de `lower` correspondent à `html` uniquement si les longueurs sont identiques.
        let source = lower.count == html.count ? html : lower
        let startOffset = lower.distance(from: lower.startIndex, to: gt.upperBound)
        let endOffset = lower.distance(from: lower.startIndex, to: close.lowerBound)
        let s = source.index(source.startIndex, offsetBy: startOffset)
        let e = source.index(source.startIndex, offsetBy: endOffset)
        let t = source[s..<e]
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : String(t.prefix(80))
    }
}
