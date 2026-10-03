import Foundation
import Network

// MARK: - Wake-on-LAN

struct WOLDevice: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var mac: String
    var ip: String = ""
}

/// Appareils Wake-on-LAN enregistrés (UserDefaults).
final class WOLStore: ObservableObject {
    @Published var devices: [WOLDevice] = [] {
        didSet { save() }
    }

    private static let key = "wolDevices"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let list = try? JSONDecoder().decode([WOLDevice].self, from: data) {
            devices = list
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

enum WakeOnLAN {
    struct Result: Identifiable {
        let id = UUID()
        let target: String
        let ok: Bool
        let message: String
    }

    /// « AA:BB:CC:DD:EE:FF », « aa-bb-… » ou « aabbccddeeff ».
    static func parseMAC(_ text: String) -> [UInt8]? {
        let hex = text.filter { $0.isHexDigit }
        guard hex.count == 12 else { return nil }
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let b = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(b)
            index = next
        }
        return bytes
    }

    static func formatMAC(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    /// Paquet magique : 6 × FF puis 16 fois l'adresse MAC.
    static func magicPacket(_ mac: [UInt8]) -> [UInt8] {
        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 { packet += mac }
        return packet
    }

    /// Envoie le paquet en UDP (ports 9 et 7) vers l'adresse de diffusion du sous-réseau,
    /// la diffusion générale et, si connue, l'adresse IP de l'appareil.
    static func send(mac: [UInt8], ip: String?) async -> [Result] {
        await Task.detached { () -> [Result] in
            var targets: [String] = []
            if let wifi = NetUtil.wifi() {
                targets.append(NetUtil.ipString(wifi.network | ~wifi.mask))
            }
            targets.append("255.255.255.255")
            if let ip, !ip.isEmpty { targets.append(ip) }

            let packet = magicPacket(mac)
            let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
            guard fd >= 0 else {
                return [Result(target: "socket", ok: false, message: String(cString: strerror(errno)))]
            }
            defer { close(fd) }
            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

            var results: [Result] = []
            for target in targets {
                var ok = false
                var message = ""
                for port: UInt16 in [9, 7] {
                    var addr = sockaddr_in()
                    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                    addr.sin_family = sa_family_t(AF_INET)
                    addr.sin_port = port.bigEndian
                    guard inet_pton(AF_INET, target, &addr.sin_addr) == 1 else { continue }
                    let sent = withUnsafePointer(to: &addr) { ptr in
                        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                            packet.withUnsafeBytes { buf in
                                sendto(fd, buf.baseAddress, buf.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                            }
                        }
                    }
                    if sent == packet.count {
                        ok = true
                    } else {
                        message = String(cString: strerror(errno))
                    }
                }
                results.append(Result(target: target, ok: ok, message: ok ? "Envoyé (ports 9 et 7)" : message))
            }
            return results
        }.value
    }
}

// MARK: - Ping (TCP)

/// iOS n'autorise pas l'ICMP brut : on mesure le temps d'établissement d'une connexion TCP.
/// Un refus de connexion (RST) compte comme une réponse : l'hôte est joignable.
@MainActor
final class PingSession: ObservableObject {
    struct Sample: Identifiable {
        let id: Int
        let ms: Double?   // nil = pas de réponse
    }

    @Published private(set) var samples: [Sample] = []
    @Published private(set) var running = false
    private var task: Task<Void, Never>?
    private var counter = 0

    var received: [Double] { samples.compactMap(\.ms) }
    var loss: Double {
        samples.isEmpty ? 0 : Double(samples.filter { $0.ms == nil }.count) / Double(samples.count)
    }

    func start(host: String, port: UInt16) {
        stop()
        samples = []
        counter = 0
        running = true
        task = Task {
            while !Task.isCancelled {
                let start = Date()
                let state = await NetUtil.probe(host, port, timeout: 2)
                let ms = state == .silent ? nil : Date().timeIntervalSince(start) * 1000
                counter += 1
                samples.append(Sample(id: counter, ms: ms))
                if samples.count > 60 { samples.removeFirst(samples.count - 60) }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        running = false
    }
}

// MARK: - Test de ports

@MainActor
final class PortScan: ObservableObject {
    struct Entry: Identifiable {
        let port: UInt16
        let state: PortState
        var id: UInt16 { port }
    }

    @Published private(set) var results: [Entry] = []
    @Published private(set) var progress: Double = 0
    @Published private(set) var running = false
    @Published var error: String?

    static let maxPorts = 1024
    static let commonPorts: [UInt16] = LANScanner.fullPorts

    /// « 22, 80, 8000-8010 » → liste de ports.
    static func parse(_ text: String) -> [UInt16]? {
        var ports: [UInt16] = []
        for part in text.split(whereSeparator: { $0 == "," || $0 == " " }) {
            let bounds = part.split(separator: "-")
            if bounds.count == 2, let a = UInt16(bounds[0]), let b = UInt16(bounds[1]), a <= b, a > 0 {
                ports += Array(a...b)
            } else if bounds.count == 1, let p = UInt16(bounds[0]), p > 0 {
                ports.append(p)
            } else {
                return nil
            }
        }
        let unique = Array(Set(ports)).sorted()
        return unique.isEmpty ? nil : unique
    }

    func run(host: String, ports: [UInt16]) async {
        guard !running else { return }
        guard ports.count <= Self.maxPorts else {
            error = "\(Self.maxPorts) ports maximum par analyse."
            return
        }
        error = nil
        running = true
        results = []
        progress = 0
        let total = Double(ports.count)
        let states = await NetUtil.concurrentMap(ports, limit: 32, progress: { done in
            Task { @MainActor in self.progress = Double(done) / total }
        }) { port in
            (port, await NetUtil.probe(host, port, timeout: 1.5))
        }
        results = states.map { Entry(port: $0.0, state: $0.1) }
        running = false
        progress = 1
    }
}

// MARK: - DNS

enum DNSLookup {
    struct Answer: Identifiable {
        let id = UUID()
        let family: String
        let address: String
    }

    static func resolve(_ name: String) async -> [Answer] {
        await Task.detached { () -> [Answer] in
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(name, nil, &hints, &result) == 0, let first = result else { return [] }
            defer { freeaddrinfo(result) }
            var answers: [Answer] = []
            var seen = Set<String>()
            var ptr: UnsafeMutablePointer<addrinfo>? = first
            while let info = ptr {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let address = String(cString: host)
                    if seen.insert(address).inserted {
                        answers.append(Answer(family: info.pointee.ai_family == AF_INET6 ? "IPv6" : "IPv4",
                                              address: address))
                    }
                }
                ptr = info.pointee.ai_next
            }
            return answers
        }.value
    }
}

// MARK: - En-têtes HTTP

struct HTTPInspection {
    var status: Int
    var headers: [(String, String)]
    var finalURL: String
    var duration: Double

    static func fetch(_ text: String) async throws -> HTTPInspection {
        var string = text.trimmingCharacters(in: .whitespaces)
        if !string.contains("://") { string = "http://" + string }
        guard let url = URL(string: string) else { throw URLError(.badURL) }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "GET"
        req.setValue("Wave-iOS/1.0", forHTTPHeaderField: "User-Agent")
        let start = Date()
        let (_, response) = try await HTTPProbe.session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let headers = http.allHeaderFields
            .map { ("\($0.key)", "\($0.value)") }
            .sorted { $0.0.lowercased() < $1.0.lowercased() }
        return HTTPInspection(status: http.statusCode, headers: headers,
                              finalURL: http.url?.absoluteString ?? string,
                              duration: Date().timeIntervalSince(start) * 1000)
    }
}
