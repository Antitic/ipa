import SwiftUI

extension LANKind {
    var colors: [Color] {
        switch self {
        case .me: return [Theme.teal, Theme.mint]
        case .router: return [Theme.indigo, Theme.violet]
        case .camera: return [Theme.red, Theme.pink]
        case .phone: return [Theme.blue, Theme.cyan]
        case .computer: return [Theme.indigo, Theme.blue]
        case .printer: return [Color.gray, Theme.blue]
        case .nas: return [Theme.orange, Theme.yellow]
        case .tv: return [Theme.violet, Theme.pink]
        case .speaker: return [Theme.pink, Theme.orange]
        case .iot: return [Theme.yellow, Theme.green]
        case .unknown: return [Color.gray, Color.gray.opacity(0.7)]
        }
    }
}

struct LANView: View {
    @StateObject private var scanner = LANScanner()
    @State private var showServices = false

    var body: some View {
        let cameras = scanner.hosts.filter { $0.kind == .camera }.count

        List {
            Section {
                header(cameras: cameras)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            if !scanner.hosts.isEmpty {
                Section("Appareils (\(scanner.hosts.count))") {
                    ForEach(scanner.hosts) { h in
                        NavigationLink { LANHostDetail(host: h) } label: { LANRow(host: h) }
                            .waveRow()
                    }
                }
            }
            if !scanner.bonjour.isEmpty {
                Section {
                    DisclosureGroup("Services Bonjour annoncés (\(scanner.bonjour.count))", isExpanded: $showServices) {
                        ForEach(scanner.bonjour) { s in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.callout.weight(.medium))
                                Text("\(s.typeLabel)\(s.ip.map { " · \($0)" } ?? "")")
                                    .font(.caption).foregroundStyle(Theme.dim)
                            }
                        }
                    }
                    .waveRow()
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Scanne uniquement des réseaux qui t'appartiennent ou où tu y es autorisé. iOS ne donne pas l'adresse MAC des appareils : la marque vient de ce qu'ils annoncent eux-mêmes (Bonjour, pages web, nom réseau).")
                    .font(.caption2)
            }
        }
        .waveScreen(.lan)
        .navigationTitle("Réseau local")
        .task { if scanner.hosts.isEmpty && !scanner.scanning { await scanner.scan() } }
        .refreshable { await scanner.scan() }
    }

    private func header(cameras: Int) -> some View {
        Card {
            HStack(spacing: 14) {
                IconTile(symbol: Feature.lan.symbol, colors: Feature.lan.colors, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    if let i = scanner.iface {
                        Text("\(NetUtil.ipString(i.network))/\(i.prefix)")
                            .font(.system(.headline, design: .rounded).monospacedDigit())
                        Text("Ton IP : \(i.ipString)\(scanner.gateway.map { " · box : \($0)" } ?? "")")
                            .font(.caption).foregroundStyle(Theme.dim)
                    } else {
                        Text("Réseau local").font(.system(.headline, design: .rounded))
                        Text("Appareils connectés à ton Wi‑Fi").font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                Spacer()
                Button {
                    Task { await scanner.scan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(CircleIconButtonStyle(color: Theme.indigo))
                .disabled(scanner.scanning)
                .accessibilityLabel("Relancer le scan")
            }
            if scanner.scanning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: scanner.progress)
                        .tint(Theme.violet)
                    Text(scanner.phase).font(.caption).foregroundStyle(Theme.dim)
                }
            } else if let err = scanner.error {
                Label(err, systemImage: "wifi.exclamationmark").foregroundStyle(Theme.warn).font(.callout)
            } else if scanner.finishedAt != nil {
                HStack(spacing: 10) {
                    StatTile(value: "\(scanner.hosts.count)", label: "appareils", color: Theme.indigo)
                    StatTile(value: "\(cameras)", label: cameras > 1 ? "caméras probables" : "caméra probable",
                             color: cameras > 0 ? Theme.red : Theme.green)
                }
                if scanner.hosts.count <= 2 {
                    Label("Peu d'appareils trouvés ? Vérifie que l'accès au réseau local est autorisé (Réglages › Wave › Réseau local), puis relance.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }
}

struct LANRow: View {
    let host: LANHost

    var body: some View {
        let kind = host.kind
        HStack(spacing: 12) {
            IconTile(symbol: kind.icon, colors: kind.colors, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                Text(host.brandModel ?? kind.rawValue).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                Text(host.ip).font(.caption2.monospaced()).foregroundStyle(Theme.dim)
            }
            Spacer()
            if kind == .camera {
                Pill(text: "Caméra", color: Theme.red, symbol: "video.fill")
            } else if !host.openPorts.isEmpty {
                Text("\(host.openPorts.count) port\(host.openPorts.count > 1 ? "s" : "")")
                    .font(.caption2).foregroundStyle(Theme.dim)
            }
        }
        .padding(.vertical, 3)
    }
}

struct LANHostDetail: View {
    let host: LANHost

    var body: some View {
        let kind = host.kind
        List {
            Section {
                HStack(spacing: 14) {
                    IconTile(symbol: kind.icon, colors: kind.colors, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(host.displayName).font(.system(.title3, design: .rounded).weight(.bold))
                        Text(kind.rawValue).font(.subheadline).foregroundStyle(Theme.dim)
                    }
                }
                .padding(.vertical, 4)
                if let a = host.alert {
                    Label(a, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warn)
                        .font(.callout)
                }
            }
            .waveRow()

            Section("Identité") {
                InfoRow(label: "Adresse IP", value: host.ip, mono: true)
                if let h = host.hostname { InfoRow(label: "Nom réseau", value: h) }
                if let b = host.brandModel { InfoRow(label: "Marque / modèle", value: b) }
                if let mac = host.macAddress { InfoRow(label: "Adresse MAC", value: mac, mono: true) }
                if host.isGateway { InfoRow(label: "Rôle", value: "Passerelle (box)") }
            }
            .waveRow()

            Section("Actions") {
                NavigationLink {
                    PingView(host: host.ip, port: "\(host.openPorts.first ?? 80)")
                } label: {
                    Label("Ping", systemImage: "waveform.path.ecg")
                }
                NavigationLink {
                    PortScanView(host: host.ip)
                } label: {
                    Label("Analyser les ports", systemImage: "door.left.hand.open")
                }
                if let web = host.openPorts.first(where: { LANScanner.webPorts.contains($0) }) {
                    NavigationLink {
                        HTTPHeadersView(address: "\([443, 8443, 5001].contains(Int(web)) ? "https" : "http")://\(host.ip):\(web)")
                    } label: {
                        Label("En-têtes HTTP", systemImage: "doc.text.magnifyingglass")
                    }
                }
                NavigationLink {
                    WakeOnLANView(prefill: WOLDevice(name: host.displayName, mac: host.macAddress ?? "", ip: host.ip))
                } label: {
                    Label("Wake-on-LAN", systemImage: "power")
                }
                Button {
                    UIPasteboard.general.string = host.ip
                } label: {
                    Label("Copier l'adresse IP", systemImage: "doc.on.doc")
                }
            }
            .waveRow()

            let apps = openWith
            if !apps.isEmpty {
                Section {
                    ForEach(Array(apps.enumerated()), id: \.offset) { item in
                        if let url = URL(string: item.element.1) {
                            Link(destination: url) {
                                Label(item.element.0, systemImage: item.element.2)
                            }
                        }
                    }
                } header: {
                    Text("Ouvrir avec")
                } footer: {
                    Text("Ouvre l'app installée qui gère ce protocole (Safari, Fichiers, client SSH, VNC, Bureau à distance, VLC…).")
                }
                .waveRow()
            }

            if !host.openPorts.isEmpty {
                Section("Ports ouverts") {
                    ForEach(host.openPorts, id: \.self) { p in
                        HStack {
                            Text("\(p)").font(.callout.monospaced())
                            Spacer()
                            Text(LANHost.portNames[p] ?? "—").foregroundStyle(Theme.dim).font(.callout)
                        }
                    }
                }
                .waveRow()
            }

            let webPorts = host.http.keys.sorted()
            if !webPorts.isEmpty {
                Section("Interface web") {
                    ForEach(webPorts, id: \.self) { p in
                        if let fp = host.http[p] {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Port \(p)").font(.caption).foregroundStyle(Theme.dim)
                                if let t = fp.title { Text(t).font(.callout.weight(.semibold)) }
                                if let s = fp.server { Text("Serveur : \(s)").font(.caption) }
                                if let r = fp.realm { Text("Zone d'authentification : \(r)").font(.caption) }
                                if let pb = fp.poweredBy { Text("Technologie : \(pb)").font(.caption) }
                                let scheme = [443, 8443, 5001].contains(Int(p)) ? "https" : "http"
                                if let url = URL(string: "\(scheme)://\(host.ip):\(p)") {
                                    Link(destination: url) {
                                        Label("Ouvrir dans Safari", systemImage: "safari")
                                    }
                                    .font(.caption.weight(.semibold))
                                }
                            }
                        }
                    }
                }
                .waveRow()
            }

            if !host.services.isEmpty {
                Section("Annonces Bonjour") {
                    ForEach(host.services) { s in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(s.name).font(.callout.weight(.semibold))
                            Text(s.typeLabel + (s.port.map { " · port \($0)" } ?? "")).font(.caption).foregroundStyle(Theme.dim)
                            ForEach(s.txt.keys.sorted(), id: \.self) { k in
                                if let v = s.txt[k], !v.isEmpty, v.count < 120 {
                                    Text("\(k) = \(v)").font(.caption2.monospaced()).foregroundStyle(Theme.dim)
                                }
                            }
                        }
                    }
                }
                .waveRow()
            }
        }
        .waveScreen(.lan)
        .navigationTitle(host.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// (titre, URL, symbole) pour chaque service ouvert qu'une app iOS sait ouvrir.
    private var openWith: [(String, String, String)] {
        let ip = host.ip
        var items: [(String, String, String)] = []
        for p in host.openPorts {
            switch p {
            case 80, 81, 8000, 8080, 8888, 9000, 5000:
                items.append(("Page web (port \(p))", p == 80 ? "http://\(ip)" : "http://\(ip):\(p)", "safari"))
            case 443, 8443, 5001:
                items.append(("Page web sécurisée (port \(p))", p == 443 ? "https://\(ip)" : "https://\(ip):\(p)", "lock"))
            case 22:
                items.append(("Terminal SSH", "ssh://\(ip)", "terminal"))
            case 21:
                items.append(("FTP", "ftp://\(ip)", "folder"))
            case 445:
                items.append(("Partage de fichiers (SMB)", "smb://\(ip)", "externaldrive.connected.to.line.below"))
            case 548:
                items.append(("Partage de fichiers (AFP)", "afp://\(ip)", "externaldrive"))
            case 5900:
                items.append(("Partage d'écran (VNC)", "vnc://\(ip)", "display"))
            case 3389:
                items.append(("Bureau à distance (RDP)", "rdp://full%20address=s:\(ip)", "desktopcomputer"))
            case 554, 8554:
                items.append(("Flux vidéo RTSP (port \(p))", "rtsp://\(ip):\(p)", "play.rectangle"))
            default:
                break
            }
        }
        return items
    }
}
