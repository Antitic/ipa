import SwiftUI
import Charts

struct NetworkToolsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { WakeOnLANView() } label: {
                    Label("Wake-on-LAN", systemImage: "power")
                }
                NavigationLink { PingView() } label: {
                    Label("Ping", systemImage: "waveform.path.ecg")
                }
                NavigationLink { PortScanView() } label: {
                    Label("Test de ports", systemImage: "door.left.hand.open")
                }
                NavigationLink { DNSLookupView() } label: {
                    Label("Recherche DNS", systemImage: "magnifyingglass")
                }
                NavigationLink { HTTPHeadersView() } label: {
                    Label("En-têtes HTTP", systemImage: "doc.text.magnifyingglass")
                }
            } footer: {
                Text("À utiliser sur tes propres appareils et réseaux.")
            }
        }
        .navigationTitle("Outils réseau")
    }
}

// MARK: - Wake-on-LAN

struct WakeOnLANView: View {
    @StateObject private var store = WOLStore()
    @State private var editing: WOLDevice?
    @State private var results: [WakeOnLAN.Result] = []
    @State private var sendingID: UUID?

    var prefill: WOLDevice?

    var body: some View {
        List {
            Section {
                if store.devices.isEmpty {
                    Text("Ajoute un ordinateur ou une console avec son adresse MAC pour le réveiller à distance.")
                        .foregroundStyle(.secondary)
                }
                ForEach(store.devices) { device in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(device.name)
                            Text(device.mac + (device.ip.isEmpty ? "" : " · \(device.ip)"))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await wake(device) }
                        } label: {
                            if sendingID == device.id {
                                ProgressView()
                            } else {
                                Label("Réveiller", systemImage: "power")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.devices.removeAll { $0.id == device.id }
                        } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                        Button {
                            editing = device
                        } label: {
                            Label("Modifier", systemImage: "pencil")
                        }
                    }
                }
            } header: {
                Text("Appareils")
            } footer: {
                Text("L'appareil doit être branché, relié au même réseau (de préférence en Ethernet) et avoir Wake-on-LAN activé dans son BIOS ou ses réglages.")
            }

            if !results.isEmpty {
                Section("Dernier envoi") {
                    ForEach(results) { r in
                        Label {
                            VStack(alignment: .leading) {
                                Text(r.target).font(.callout.monospaced())
                                Text(r.message).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(r.ok ? .green : .red)
                        }
                    }
                }
            }
        }
        .navigationTitle("Wake-on-LAN")
        .toolbar {
            Button {
                editing = WOLDevice(name: "", mac: "")
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(item: $editing) { device in
            WOLEditor(device: device) { saved in
                if let i = store.devices.firstIndex(where: { $0.id == saved.id }) {
                    store.devices[i] = saved
                } else {
                    store.devices.append(saved)
                }
            }
        }
        .onAppear {
            if let prefill, !store.devices.contains(where: { $0.mac == prefill.mac && !prefill.mac.isEmpty }) {
                editing = prefill
            }
        }
    }

    private func wake(_ device: WOLDevice) async {
        guard let mac = WakeOnLAN.parseMAC(device.mac) else { return }
        sendingID = device.id
        results = await WakeOnLAN.send(mac: mac, ip: device.ip)
        sendingID = nil
    }
}

private struct WOLEditor: View {
    @State var device: WOLDevice
    let onSave: (WOLDevice) -> Void
    @Environment(\.dismiss) private var dismiss

    private var macValid: Bool { WakeOnLAN.parseMAC(device.mac) != nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (ex. PC du salon)", text: $device.name)
                TextField("Adresse MAC (AA:BB:CC:DD:EE:FF)", text: $device.mac)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                TextField("Adresse IP (facultatif)", text: $device.ip)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                if !device.mac.isEmpty && !macValid {
                    Text("Adresse MAC invalide : 12 chiffres hexadécimaux.").foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("Appareil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        if let mac = WakeOnLAN.parseMAC(device.mac) {
                            device.mac = WakeOnLAN.formatMAC(mac)
                        }
                        if device.name.trimmingCharacters(in: .whitespaces).isEmpty { device.name = device.mac }
                        onSave(device)
                        dismiss()
                    }
                    .disabled(!macValid)
                }
            }
        }
    }
}

// MARK: - Ping

struct PingView: View {
    @State var host: String = ""
    @State var port: String = "443"
    @StateObject private var session = PingSession()

    var body: some View {
        let received = session.received
        List {
            Section {
                TextField("Adresse IP ou nom", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Port TCP", text: $port)
                    .keyboardType(.numberPad)
                Button {
                    if session.running {
                        session.stop()
                    } else if let p = UInt16(port), !host.isEmpty {
                        session.start(host: host.trimmingCharacters(in: .whitespaces), port: p)
                    }
                } label: {
                    Label(session.running ? "Arrêter" : "Démarrer", systemImage: session.running ? "stop.fill" : "play.fill")
                }
                .disabled(host.isEmpty || UInt16(port) == nil)
            } footer: {
                Text("iOS n'autorise pas le ping ICMP classique : Wave mesure le temps de connexion TCP. Un port fermé répond quand même et compte comme une réponse.")
            }

            if !session.samples.isEmpty {
                Section("Résultats") {
                    Chart(session.samples) { s in
                        if let ms = s.ms {
                            BarMark(x: .value("Essai", s.id), y: .value("ms", ms))
                                .foregroundStyle(.green)
                        } else {
                            RuleMark(x: .value("Essai", s.id))
                                .foregroundStyle(.red.opacity(0.5))
                        }
                    }
                    .chartYAxisLabel("ms")
                    .frame(height: 160)

                    LabeledContent("Envoyés", value: "\(session.samples.count)")
                    LabeledContent("Perte", value: String(format: "%.0f %%", session.loss * 100))
                    if let min = received.min(), let max = received.max() {
                        LabeledContent("Min / moy. / max",
                                       value: String(format: "%.0f / %.0f / %.0f ms", min,
                                                     received.reduce(0, +) / Double(received.count), max))
                    }
                }
            }
        }
        .navigationTitle("Ping")
        .onDisappear { session.stop() }
    }
}

// MARK: - Ports

struct PortScanView: View {
    @State var host: String = ""
    @State private var portsText = ""
    @State private var showClosed = false
    @StateObject private var scan = PortScan()

    var body: some View {
        List {
            Section {
                TextField("Adresse IP ou nom", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Ports (vide = ports courants, ex. 22,80,8000-8100)", text: $portsText)
                    .keyboardType(.numbersAndPunctuation)
                    .autocorrectionDisabled()
                Button {
                    let ports = portsText.isEmpty ? PortScan.commonPorts : PortScan.parse(portsText)
                    guard let ports else {
                        scan.error = "Liste de ports invalide."
                        return
                    }
                    Task { await scan.run(host: host.trimmingCharacters(in: .whitespaces), ports: ports) }
                } label: {
                    Label("Analyser", systemImage: "play.fill")
                }
                .disabled(host.isEmpty || scan.running)
                if scan.running {
                    ProgressView(value: scan.progress)
                }
                if let error = scan.error {
                    Text(error).foregroundStyle(.red)
                }
            } footer: {
                Text("Uniquement sur des appareils qui t'appartiennent ou que tu es autorisé à tester.")
            }

            if !scan.results.isEmpty {
                let open = scan.results.filter { $0.state == .open }
                Section("\(open.count) ouvert\(open.count > 1 ? "s" : "") sur \(scan.results.count)") {
                    ForEach(open) { e in
                        LabeledContent {
                            Text(LANHost.portNames[e.port] ?? "—")
                        } label: {
                            Label("\(e.port)", systemImage: "circle.fill")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.green)
                                .monospacedDigit()
                        }
                    }
                    Toggle("Afficher les ports fermés", isOn: $showClosed)
                    if showClosed {
                        ForEach(scan.results.filter { $0.state != .open }) { e in
                            LabeledContent("\(e.port)", value: e.state == .closed ? "Fermé" : "Pas de réponse")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Test de ports")
    }
}

// MARK: - DNS

struct DNSLookupView: View {
    @State private var name = ""
    @State private var answers: [DNSLookup.Answer] = []
    @State private var reverse: String?
    @State private var searching = false
    @State private var searched = false

    var body: some View {
        List {
            Section {
                TextField("Nom de domaine ou adresse IP", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit { Task { await lookup() } }
                Button("Rechercher") { Task { await lookup() } }
                    .disabled(name.isEmpty || searching)
            }
            if searching {
                ProgressView()
            } else if searched {
                Section("Adresses") {
                    if answers.isEmpty { Text("Aucune réponse.").foregroundStyle(.secondary) }
                    ForEach(answers) { a in
                        LabeledContent(a.family) {
                            Text(a.address).font(.callout.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                if let reverse {
                    Section("Nom inverse") {
                        Text(reverse).textSelection(.enabled)
                    }
                }
            }
        }
        .navigationTitle("Recherche DNS")
    }

    private func lookup() async {
        let query = name.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return }
        searching = true
        answers = await DNSLookup.resolve(query)
        let first = answers.first { $0.family == "IPv4" }?.address
        let ip = first ?? query
        reverse = await Task.detached { NetUtil.reverseDNS(ip) }.value
        searching = false
        searched = true
    }
}

// MARK: - HTTP

struct HTTPHeadersView: View {
    @State var address = ""
    @State private var result: HTTPInspection?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            Section {
                TextField("Adresse (ex. 192.168.1.1 ou exemple.fr)", text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button("Charger") { Task { await load() } }
                    .disabled(address.isEmpty || loading)
                if loading { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
            }
            if let result {
                Section("Réponse") {
                    LabeledContent("Code", value: "\(result.status) \(HTTPURLResponse.localizedString(forStatusCode: result.status))")
                    LabeledContent("Temps", value: String(format: "%.0f ms", result.duration))
                    Text(result.finalURL).font(.caption.monospaced()).textSelection(.enabled)
                    if let url = URL(string: result.finalURL) {
                        Link("Ouvrir dans Safari", destination: url)
                    }
                }
                Section("En-têtes") {
                    ForEach(Array(result.headers.enumerated()), id: \.offset) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.element.0).font(.caption.weight(.semibold))
                            Text(item.element.1).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
            }
        }
        .navigationTitle("En-têtes HTTP")
    }

    private func load() async {
        loading = true
        error = nil
        do {
            result = try await HTTPInspection.fetch(address)
        } catch {
            self.error = error.localizedDescription
            result = nil
        }
        loading = false
    }
}
