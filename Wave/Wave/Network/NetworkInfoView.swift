import SwiftUI
import Network

struct PublicIPInfo: Decodable {
    struct Connection: Decodable {
        let asn: Int?
        let org: String?
        let isp: String?
        let domain: String?
    }
    let ip: String?
    let type: String?
    let country: String?
    let city: String?
    let region: String?
    let connection: Connection?
}

@MainActor
final class NetworkInfoModel: ObservableObject {
    @Published var path: NWPath?
    @Published var wifi: NetInterface?
    @Published var cellular: NetInterface?
    @Published var publicInfo: PublicIPInfo?
    @Published var publicError = false
    @Published var pings: [Double] = []
    @Published var download: Double?
    @Published var upload: Double?
    @Published var testing = false
    @Published var testPhase = ""

    private var monitor: NWPathMonitor?

    func start() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] p in
            Task { @MainActor in
                self?.path = p
                self?.wifi = NetUtil.wifi()
                self?.cellular = NetUtil.cellular()
            }
        }
        m.start(queue: NetUtil.queue)
        monitor = m
        wifi = NetUtil.wifi()
        cellular = NetUtil.cellular()
        Task { await loadPublicIP() }
    }

    func loadPublicIP() async {
        publicError = false
        do {
            var req = URLRequest(url: URL(string: "https://ipwho.is/")!, timeoutInterval: 8)
            req.setValue("Wave-iOS/1.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: req)
            publicInfo = try JSONDecoder().decode(PublicIPInfo.self, from: data)
        } catch {
            publicError = true
        }
    }

    func runTest() async {
        guard !testing else { return }
        testing = true
        pings = []
        download = nil
        upload = nil

        testPhase = "Latence…"
        for _ in 0..<8 {
            let start = Date()
            let st = await NetUtil.probe("1.1.1.1", 443, timeout: 2)
            if st == .open { pings.append(Date().timeIntervalSince(start) * 1000) }
        }

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        let session = URLSession(configuration: cfg)

        testPhase = "Téléchargement…"
        if let url = URL(string: "https://speed.cloudflare.com/__down?bytes=25000000") {
            let start = Date()
            if let result = try? await session.data(from: url) {
                let data = result.0
                let secs = Date().timeIntervalSince(start)
                if secs > 0 { download = Double(data.count) * 8 / secs / 1_000_000 }
            }
        }

        testPhase = "Envoi…"
        if let url = URL(string: "https://speed.cloudflare.com/__up") {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            let payload = Data(count: 8_000_000)
            let start = Date()
            if (try? await session.upload(for: req, from: payload)) != nil {
                let secs = Date().timeIntervalSince(start)
                if secs > 0 { upload = Double(payload.count) * 8 / secs / 1_000_000 }
            }
        }
        testPhase = ""
        testing = false
    }

    var pingAvg: Double? { pings.isEmpty ? nil : pings.reduce(0, +) / Double(pings.count) }
    var jitter: Double? {
        guard pings.count > 1 else { return nil }
        var sum = 0.0
        for i in 1..<pings.count { sum += abs(pings[i] - pings[i - 1]) }
        return sum / Double(pings.count - 1)
    }
}

struct NetworkInfoView: View {
    @StateObject private var model = NetworkInfoModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                connectionCard
                speedCard
                publicCard
                localCard
                Text("Le nom du Wi‑Fi et sa puissance ne sont pas accessibles aux applis installées hors App Store sur iOS.")
                    .font(.caption2).foregroundStyle(Theme.dim).padding(.horizontal, 4)
            }
            .padding(16)
        }
        .waveScreen()
        .navigationTitle("Réseau")
        .refreshable { await model.loadPublicIP() }
        .onAppear { model.start() }
    }

    private var connectionType: (String, String) {
        guard let p = model.path, p.status == .satisfied else { return ("Hors ligne", "wifi.slash") }
        if p.usesInterfaceType(.wifi) { return ("Wi‑Fi", "wifi") }
        if p.usesInterfaceType(.cellular) { return ("Données mobiles", "antenna.radiowaves.left.and.right") }
        if p.usesInterfaceType(.wiredEthernet) { return ("Ethernet", "cable.connector") }
        return ("Connecté", "network")
    }

    private var connectionCard: some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.15)).frame(width: 52, height: 52)
                    Image(systemName: connectionType.1).font(.title2).foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(connectionType.0).font(.title3.weight(.bold))
                    if let p = model.path {
                        HStack(spacing: 6) {
                            if p.supportsIPv4 { Pill(text: "IPv4") }
                            if p.supportsIPv6 { Pill(text: "IPv6", color: Theme.blue) }
                            if p.isExpensive { Pill(text: "Coûteux", color: Theme.warn) }
                            if p.isConstrained { Pill(text: "Mode données réduites", color: Theme.warn) }
                        }
                    }
                }
            }
        }
    }

    private var speedCard: some View {
        Card {
            HStack {
                Text("Test de débit").font(.headline)
                Spacer()
                Button {
                    Task { await model.runTest() }
                } label: {
                    if model.testing {
                        HStack(spacing: 6) { ProgressView(); Text(model.testPhase) }
                    } else {
                        Text("Lancer")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .foregroundStyle(Theme.bg)
                .disabled(model.testing)
            }
            HStack(spacing: 10) {
                metric("Latence", model.pingAvg.map { String(format: "%.0f", $0) }, "ms")
                metric("Gigue", model.jitter.map { String(format: "%.0f", $0) }, "ms")
                metric("Réception", model.download.map { String(format: "%.0f", $0) }, "Mb/s")
                metric("Envoi", model.upload.map { String(format: "%.0f", $0) }, "Mb/s")
            }
            if model.pings.count > 1 {
                Sparkline(values: model.pings, color: Theme.blue).frame(height: 36)
            }
            Text("Mesure vers Cloudflare (1.1.1.1 et speed.cloudflare.com). Consomme environ 35 Mo.")
                .font(.caption2).foregroundStyle(Theme.dim)
        }
    }

    private func metric(_ label: String, _ value: String?, _ unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value ?? "–").font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
            Text(unit).font(.caption2).foregroundStyle(Theme.dim)
            Text(label).font(.caption2).foregroundStyle(Theme.dim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var publicCard: some View {
        Card {
            Text("Internet").font(.headline)
            if let info = model.publicInfo {
                InfoRow(label: "IP publique", value: info.ip ?? "—", mono: true)
                if let isp = info.connection?.isp ?? info.connection?.org { InfoRow(label: "Opérateur", value: isp) }
                if let asn = info.connection?.asn { InfoRow(label: "ASN", value: "AS\(asn)", mono: true) }
                let place = [info.city, info.country].compactMap { $0 }.joined(separator: ", ")
                if !place.isEmpty { InfoRow(label: "Localisation de l'IP", value: place) }
            } else if model.publicError {
                Text("Impossible de joindre ipwho.is.").font(.callout).foregroundStyle(Theme.warn)
            } else {
                ProgressView()
            }
        }
    }

    private var gatewayIP: String? {
        guard let gws = model.path?.gateways else { return nil }
        for ep in gws {
            if case let .hostPort(host, _) = ep, let s = NetUtil.hostString(host) { return s }
        }
        return nil
    }

    private var localCard: some View {
        Card {
            Text("Réseau local").font(.headline)
            if let w = model.wifi {
                InfoRow(label: "IP Wi‑Fi", value: w.ipString, mono: true)
                InfoRow(label: "Masque", value: "\(w.maskString) (/\(w.prefix))", mono: true)
                InfoRow(label: "Sous-réseau", value: "\(NetUtil.ipString(w.network))/\(w.prefix)", mono: true)
            } else {
                Text("Pas d'adresse Wi‑Fi.").font(.callout).foregroundStyle(Theme.dim)
            }
            if let gw = gatewayIP {
                InfoRow(label: "Passerelle", value: gw, mono: true)
            }
            if let c = model.cellular {
                InfoRow(label: "IP mobile", value: c.ipString, mono: true)
            }
            if let p = model.path {
                InfoRow(label: "Interfaces", value: p.availableInterfaces.map { $0.name }.joined(separator: ", "))
            }
        }
    }
}
