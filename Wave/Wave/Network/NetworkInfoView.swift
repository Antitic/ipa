import SwiftUI
import Network
import Charts

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

}

struct NetworkInfoView: View {
    @StateObject private var model = NetworkInfoModel()
    @StateObject private var speed = SpeedTest()

    var body: some View {
        List {
            connectionSection
            speedSection
            Section {
                NavigationLink {
                    NetworkToolsView()
                } label: {
                    Label("Outils réseau", systemImage: "wrench.and.screwdriver")
                }
            } footer: {
                Text("Wake-on-LAN, ping, test de ports, recherche DNS, en-têtes HTTP.")
            }
            publicSection
            localSection
        }
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

    private var connectionSection: some View {
        Section {
            Label(connectionType.0, systemImage: connectionType.1)
                .font(.headline)
            if let p = model.path {
                LabeledContent("Protocoles") {
                    Text([p.supportsIPv4 ? "IPv4" : nil, p.supportsIPv6 ? "IPv6" : nil].compactMap { $0 }.joined(separator: ", "))
                }
                if p.isExpensive { LabeledContent("Réseau coûteux", value: "Oui") }
                if p.isConstrained { LabeledContent("Mode données réduites", value: "Activé") }
            }
        }
    }

    // MARK: Test de débit

    private var speedSection: some View {
        Section {
            SpeedGauge(value: speed.running ? speed.live : (speed.download ?? 0),
                       phase: speed.phase,
                       progress: speed.phaseProgress,
                       running: speed.running)
                .frame(height: 190)
                .padding(.top, 8)

            HStack {
                result("Réception", speed.download, "Mb/s", .blue, active: speed.phase == .download)
                Divider()
                result("Envoi", speed.upload, "Mb/s", .purple, active: speed.phase == .upload)
            }
            HStack {
                result("Latence", speed.latency, "ms", .orange, active: speed.phase == .latency)
                Divider()
                result("Gigue", speed.jitter, "ms", .teal, active: speed.phase == .latency)
            }

            if !speed.downloadSamples.isEmpty || !speed.uploadSamples.isEmpty {
                Chart {
                    ForEach(speed.downloadSamples) { s in
                        LineMark(x: .value("Temps", s.time), y: .value("Mb/s", s.mbps), series: .value("Sens", "Réception"))
                            .foregroundStyle(.blue)
                        AreaMark(x: .value("Temps", s.time), y: .value("Mb/s", s.mbps), series: .value("Sens", "Réception"))
                            .foregroundStyle(.blue.opacity(0.15))
                    }
                    ForEach(speed.uploadSamples) { s in
                        LineMark(x: .value("Temps", s.time), y: .value("Mb/s", s.mbps), series: .value("Sens", "Envoi"))
                            .foregroundStyle(.purple)
                        AreaMark(x: .value("Temps", s.time), y: .value("Mb/s", s.mbps), series: .value("Sens", "Envoi"))
                            .foregroundStyle(.purple.opacity(0.15))
                    }
                }
                .chartXScale(domain: 0...10)
                .chartXAxisLabel("secondes")
                .chartYAxisLabel("Mb/s")
                .frame(height: 140)
                .animation(.linear(duration: 0.2), value: speed.downloadSamples.count + speed.uploadSamples.count)
            }

            if !speed.pings.isEmpty {
                Chart(Array(speed.pings.enumerated()), id: \.offset) { item in
                    BarMark(x: .value("Essai", item.offset + 1), y: .value("ms", item.element))
                        .foregroundStyle(.orange)
                }
                .chartXAxis(.hidden)
                .chartYAxisLabel("ms")
                .frame(height: 70)
            }

            if let error = speed.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            }

            Button {
                if speed.running { speed.cancel() } else { speed.start() }
            } label: {
                Label(speed.running ? "Arrêter" : (speed.phase == .done ? "Relancer le test" : "Lancer le test"),
                      systemImage: speed.running ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(speed.running ? .red : .accentColor)
            .controlSize(.large)
        } header: {
            Text("Test de débit")
        } footer: {
            Text("Mesure vers Cloudflare, 4 connexions en parallèle, 10 s par sens. Peut consommer jusqu'à 500 Mo sur une connexion rapide\(speed.dataUsed > 0 ? " (\(ByteCountFormatter.string(fromByteCount: speed.dataUsed, countStyle: .file)) utilisés)" : "").")
        }
    }

    private func result(_ label: String, _ value: Double?, _ unit: String, _ color: Color, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(active ? color : .secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value.map { $0 >= 100 ? String(format: "%.0f", $0) : String(format: "%.1f", $0) } ?? "–")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Infos

    private var publicSection: some View {
        Section("Internet") {
            if let info = model.publicInfo {
                InfoRow(label: "IP publique", value: info.ip ?? "—", mono: true)
                if let isp = info.connection?.isp ?? info.connection?.org { InfoRow(label: "Opérateur", value: isp) }
                if let asn = info.connection?.asn { InfoRow(label: "ASN", value: "AS\(asn)", mono: true) }
                let place = [info.city, info.country].compactMap { $0 }.joined(separator: ", ")
                if !place.isEmpty { InfoRow(label: "Localisation de l'IP", value: place) }
            } else if model.publicError {
                Button("Impossible de joindre ipwho.is — réessayer") { Task { await model.loadPublicIP() } }
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

    private var localSection: some View {
        Section {
            if let w = model.wifi {
                InfoRow(label: "IP Wi‑Fi", value: w.ipString, mono: true)
                InfoRow(label: "Masque", value: "\(w.maskString) (/\(w.prefix))", mono: true)
                InfoRow(label: "Sous-réseau", value: "\(NetUtil.ipString(w.network))/\(w.prefix)", mono: true)
            } else {
                Text("Pas d'adresse Wi‑Fi.").foregroundStyle(.secondary)
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
        } header: {
            Text("Réseau local")
        } footer: {
            Text("Le nom du Wi‑Fi et sa puissance ne sont pas accessibles aux applis installées hors App Store.")
        }
    }
}

/// Compteur semi-circulaire à échelle logarithmique (1 à 1000 Mb/s).
struct SpeedGauge: View {
    let value: Double
    let phase: SpeedTest.Phase
    let progress: Double
    let running: Bool

    private let ticks: [Double] = [1, 5, 10, 50, 100, 250, 500, 1000]

    private var color: Color {
        switch phase {
        case .upload: return .purple
        case .latency: return .orange
        default: return .blue
        }
    }

    private func fraction(_ v: Double) -> Double {
        guard v > 1 else { return max(0, v) * 0.02 }
        return min(1, log10(v) / 3)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let radius = min(w / 2, geo.size.height) - 18
            let center = CGPoint(x: w / 2, y: radius + 14)
            ZStack {
                Arc(fraction: 1)
                    .stroke(Color(uiColor: .systemFill), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                Arc(fraction: fraction(value))
                    .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .frame(width: radius * 2, height: radius * 2)
                    .position(center)
                    .animation(.easeOut(duration: 0.25), value: value)

                ForEach(ticks, id: \.self) { t in
                    let angle = Double.pi * (1 - fraction(t))
                    Text(t >= 1000 ? "1G" : "\(Int(t))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .position(x: center.x + CGFloat(cos(angle)) * (radius - 28),
                                  y: center.y - CGFloat(sin(angle)) * (radius - 28))
                }

                VStack(spacing: 0) {
                    Text(running || value > 0 ? (value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)) : "–")
                        .font(.system(size: 44, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(running ? "\(phase.rawValue) · Mb/s" : (phase == .done ? "Réception · Mb/s" : "Mb/s"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if running {
                        ProgressView(value: progress)
                            .tint(color)
                            .frame(width: 90)
                            .padding(.top, 6)
                    }
                }
                .position(x: center.x, y: center.y - radius * 0.25)
            }
        }
    }
}

/// Demi-cercle supérieur, rempli de gauche à droite selon `fraction`.
struct Arc: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                 radius: rect.width / 2,
                 startAngle: .degrees(180),
                 endAngle: .degrees(180 + 180 * max(0.001, min(1, fraction))),
                 clockwise: false)
        return p
    }
}
