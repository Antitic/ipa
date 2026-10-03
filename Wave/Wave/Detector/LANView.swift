import SwiftUI

struct LANView: View {
    @StateObject private var scanner = LANScanner()
    @State private var showServices = false

    private var cameras: Int { scanner.hosts.filter { $0.kind == .camera }.count }

    var body: some View {
        List {
            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            if !scanner.hosts.isEmpty {
                Section("Appareils (\(scanner.hosts.count))") {
                    ForEach(scanner.hosts) { h in
                        NavigationLink { LANHostDetail(host: h) } label: { LANRow(host: h) }
                            .listRowBackground(Theme.card)
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
                    .listRowBackground(Theme.card)
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Scanne uniquement des réseaux qui t'appartiennent ou où tu y es autorisé. iOS ne donne pas l'adresse MAC des appareils : la marque vient de ce qu'ils annoncent eux-mêmes (Bonjour, pages web, nom réseau).")
                    .font(.caption2)
            }
        }
        .waveScreen()
        .navigationTitle("Réseau local")
        .task { if scanner.hosts.isEmpty { await scanner.scan() } }
        .refreshable { await scanner.scan() }
    }

    private var header: some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.violet.opacity(0.15)).frame(width: 52, height: 52)
                    Image(systemName: "wifi").font(.title2).foregroundStyle(Theme.violet)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let i = scanner.iface {
                        Text("\(NetUtil.ipString(i.network))/\(i.prefix)").font(.headline.monospaced())
                        Text("Ton IP : \(i.ipString)\(scanner.gateway.map { " · box : \($0)" } ?? "")")
                            .font(.caption).foregroundStyle(Theme.dim)
                    } else {
                        Text("Réseau local").font(.headline)
                    }
                }
                Spacer()
                Button {
                    Task { await scanner.scan() }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.headline)
                }
                .buttonStyle(.bordered)
                .disabled(scanner.scanning)
            }
            if scanner.scanning {
                ProgressView(value: scanner.progress) {
                    Text(scanner.phase).font(.caption).foregroundStyle(Theme.dim)
                }
                .tint(Theme.violet)
            } else if let err = scanner.error {
                Label(err, systemImage: "wifi.exclamationmark").foregroundStyle(Theme.warn).font(.callout)
            } else if scanner.finishedAt != nil {
                HStack {
                    Pill(text: "\(scanner.hosts.count) appareils", color: Theme.violet)
                    Pill(text: "\(cameras) caméra\(cameras > 1 ? "s" : "") probable\(cameras > 1 ? "s" : "")",
                         color: cameras > 0 ? Theme.danger : Theme.accent)
                }
            }
        }
    }
}

struct LANRow: View {
    let host: LANHost

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.16)).frame(width: 40, height: 40)
                Image(systemName: host.kind.icon).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(host.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                Text(host.brandModel ?? host.kind.rawValue).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                Text(host.ip).font(.caption2.monospaced()).foregroundStyle(Theme.dim)
            }
            Spacer()
            if !host.openPorts.isEmpty {
                Text("\(host.openPorts.count) port\(host.openPorts.count > 1 ? "s" : "")")
                    .font(.caption2).foregroundStyle(Theme.dim)
            }
        }
    }

    private var color: Color {
        switch host.kind {
        case .camera: return Theme.danger
        case .me: return Theme.accent
        case .router: return Theme.violet
        case .speaker: return Theme.warn
        default: return Theme.blue
        }
    }
}

struct LANHostDetail: View {
    let host: LANHost

    var body: some View {
        List {
            if let a = host.alert {
                Section {
                    Label(a, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
                }
                .listRowBackground(Theme.card)
            }
            Section("Identité") {
                InfoRow(label: "Type", value: host.kind.rawValue)
                InfoRow(label: "Adresse IP", value: host.ip, mono: true)
                if let h = host.hostname { InfoRow(label: "Nom réseau", value: h) }
                if let b = host.brandModel { InfoRow(label: "Marque / modèle", value: b) }
                if let mac = host.macAddress { InfoRow(label: "Adresse MAC", value: mac, mono: true) }
                if host.isGateway { InfoRow(label: "Rôle", value: "Passerelle (box)") }
            }
            .listRowBackground(Theme.card)

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
                .listRowBackground(Theme.card)
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
                                    Link("Ouvrir dans Safari", destination: url).font(.caption)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Theme.card)
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
                .listRowBackground(Theme.card)
            }
        }
        .waveScreen()
        .navigationTitle(host.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
