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
            VStack(spacing: 16) {
                connectionCard
                speedCard
                publicCard
                localCard
                Text("Le nom du Wi‑Fi et sa puissance ne sont pas accessibles aux applis installées hors App Store sur iOS.")
                    .font(.caption2).foregroundStyle(Theme.dim).padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .waveScreen(.network)
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

    private var isOnline: Bool { model.path?.status == .satisfied }

    private var connectionCard: some View {
        Card {
            HStack(spacing: 14) {
                IconTile(symbol: connectionType.1,
                         colors: isOnline ? Feature.network.colors : [Theme.red, Theme.orange], size: 56)
                VStack(alignment: .leading, spacing: 6) {
                    Text(connectionType.0).font(.system(.title2, design: .rounded).weight(.bold))
                    if let p = model.path {
                        HStack(spacing: 6) {
                            if p.supportsIPv4 { Pill(text: "IPv4", color: Theme.green) }
                            if p.supportsIPv6 { Pill(text: "IPv6", color: Theme.blue) }
                            if p.isExpensive { Pill(text: "Coûteux", color: Theme.warn) }
                            if p.isConstrained { Pill(text: "Données réduites", color: Theme.warn) }
                        }
                    }
                }
            }
        }
    }

    private var speedCard: some View {
        Card {
            HStack {
                SectionTitle(text: "Test de débit", symbol: "speedometer", color: Theme.green)
                Spacer()
                Button {
                    Task { await model.runTest() }
                } label: {
                    if model.testing {
                        HStack(spacing: 6) { ProgressView().tint(.white); Text(model.testPhase) }
                    } else {
                        Label("Lancer", systemImage: "play.fill")
                    }
                }
                .buttonStyle(GradientButtonStyle(colors: Feature.network.colors))
                .disabled(model.testing)
            }
            HStack(spacing: 10) {
                metric("Réception", model.download.map { String(format: "%.0f", $0) }, "Mb/s",
                       "arrow.down.circle.fill", [Theme.green, Theme.mint])
                metric("Envoi", model.upload.map { String(format: "%.0f", $0) }, "Mb/s",
                       "arrow.up.circle.fill", [Theme.violet, Theme.pink])
            }
            HStack(spacing: 10) {
                metric("Latence", model.pingAvg.map { String(format: "%.0f", $0) }, "ms",
                       "timer", [Theme.orange, Theme.yellow])
                metric("Gigue", model.jitter.map { String(format: "%.0f", $0) }, "ms",
                       "waveform.path", [Theme.blue, Theme.cyan])
            }
            if model.pings.count > 1 {
                Sparkline(values: model.pings, color: Theme.orange).frame(height: 40)
            }
            Text("Mesure vers Cloudflare (1.1.1.1 et speed.cloudflare.com). Consomme environ 35 Mo.")
                .font(.caption2).foregroundStyle(Theme.dim)
        }
    }

    private func metric(_ label: String, _ value: String?, _ unit: String, _ symbol: String, _ colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(colors[0])
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "–")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .contentTransition(.numericText())
                Text(unit).font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(colors[0].opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var publicCard: some View {
        Card {
            SectionTitle(text: "Internet", symbol: "globe", color: Theme.blue)
            if let info = model.publicInfo {
                InfoRow(label: "IP publique", value: info.ip ?? "—", mono: true)
                if let isp = info.connection?.isp ?? info.connection?.org { InfoRow(label: "Opérateur", value: isp) }
                if let asn = info.connection?.asn { InfoRow(label: "ASN", value: "AS\(asn)", mono: true) }
                let place = [info.city, info.country].compactMap { $0 }.joined(separator: ", ")
                if !place.isEmpty { InfoRow(label: "Localisation de l'IP", value: place) }
            } else if model.publicError {
                HStack {
                    Label("Impossible de joindre ipwho.is.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(Theme.warn)
                    Spacer()
                    Button("Réessayer") { Task { await model.loadPublicIP() } }
                        .font(.callout.weight(.semibold))
                }
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
            SectionTitle(text: "Réseau local", symbol: "house.fill", color: Theme.indigo)
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
