import SwiftUI
import CoreBluetooth

extension DeviceCategory {
    var colors: [Color] {
        switch self {
        case .camera: return [Theme.red, Theme.pink]
        case .recorder: return [Theme.orange, Theme.red]
        case .tracker: return [Theme.yellow, Theme.orange]
        case .audio: return [Theme.pink, Theme.violet]
        case .phone: return [Theme.blue, Theme.cyan]
        case .computer: return [Theme.indigo, Theme.blue]
        case .wearable: return [Theme.green, Theme.mint]
        case .tv: return [Theme.violet, Theme.indigo]
        case .input: return [Color.gray, Theme.blue]
        case .beacon: return [Theme.teal, Theme.cyan]
        case .iot: return [Theme.yellow, Theme.green]
        case .unknown: return [Color.gray, Color.gray.opacity(0.7)]
        }
    }
}

struct BLEView: View {
    @StateObject private var scanner = BLEScanner()
    @State private var filter: Filter = .all
    @State private var search = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tous", suspects = "Suspects", trackers = "Traceurs", named = "Avec nom"
        var id: String { rawValue }
    }

    private func isSuspect(_ d: BLEDevice) -> Bool {
        d.info.category.isSuspicious || d.info.alert != nil
    }

    var body: some View {
        let devices = scanner.devices
        let filtered = devices.filter { d in
            switch filter {
            case .all: break
            case .suspects: if !isSuspect(d) { return false }
            case .trackers: if d.info.category != .tracker { return false }
            case .named: if d.name == nil { return false }
            }
            if search.isEmpty { return true }
            let hay = [d.displayName, d.info.brand ?? "", d.info.model ?? "", d.info.category.rawValue].joined(separator: " ")
            return hay.localizedCaseInsensitiveContains(search)
        }
        let suspects = devices.filter(isSuspect).count
        let trackers = devices.filter { $0.info.category == .tracker }.count

        List {
            Section {
                statusCard(total: devices.count, suspects: suspects, trackers: trackers)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                Picker("Filtre", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                if filtered.isEmpty {
                    Text(scanner.isScanning ? "Recherche en cours…" : "Aucun appareil.")
                        .foregroundStyle(Theme.dim)
                        .waveRow()
                }
                ForEach(filtered) { d in
                    NavigationLink {
                        BLEDetailView(scanner: scanner, id: d.id)
                    } label: {
                        BLERow(device: d)
                    }
                    .waveRow()
                }
            } footer: {
                Text("iOS masque l'adresse MAC réelle des appareils : chaque appareil reçoit un identifiant propre à ton iPhone. Beaucoup d'appareils changent aussi d'adresse toutes les 15 minutes environ.")
                    .font(.caption2)
            }
        }
        .searchable(text: $search, prompt: "Nom, marque, type…")
        .waveScreen(.bluetooth)
        .navigationTitle("Bluetooth")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        scanner.togglePause()
                    } label: {
                        Label(scanner.isScanning ? "Mettre en pause" : "Reprendre",
                              systemImage: scanner.isScanning ? "pause.fill" : "play.fill")
                    }
                    Button(role: .destructive) {
                        scanner.clear()
                    } label: {
                        Label("Effacer la liste", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear { scanner.acquire() }
        .onDisappear { scanner.release() }
    }

    private func statusCard(total: Int, suspects: Int, trackers: Int) -> some View {
        Card {
            HStack(spacing: 14) {
                IconTile(symbol: Feature.bluetooth.symbol, colors: Feature.bluetooth.colors, size: 52)
                    .symbolEffect(.variableColor.iterative, isActive: scanner.isScanning)
                VStack(alignment: .leading, spacing: 3) {
                    Text(stateText).font(.system(.headline, design: .rounded))
                    Text(scanner.isScanning ? "Les appareils proches apparaissent en direct" : "Touche ⋯ pour reprendre")
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }
            HStack(spacing: 10) {
                StatTile(value: "\(total)", label: "appareils", color: Theme.blue)
                StatTile(value: "\(suspects)", label: "à vérifier", color: suspects > 0 ? Theme.orange : Theme.green)
                StatTile(value: "\(trackers)", label: "traceurs", color: trackers > 0 ? Theme.red : Theme.green)
            }
        }
    }

    private var stateText: String {
        switch scanner.state {
        case .poweredOn: return scanner.isScanning ? "Scan en cours" : "En pause"
        case .poweredOff: return "Bluetooth désactivé"
        case .unauthorized: return "Accès Bluetooth refusé (Réglages)"
        case .unsupported: return "Bluetooth non pris en charge"
        default: return "Démarrage…"
        }
    }
}

struct BLERow: View {
    let device: BLEDevice

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: device.info.category.icon, colors: device.info.category.colors, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                if device.info.alert != nil {
                    Pill(text: "À vérifier", color: Theme.orange, symbol: "exclamationmark.triangle.fill")
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                SignalBars(rssi: device.rssi)
                Text("\(device.rssi) dBm").font(.caption2.monospacedDigit()).foregroundStyle(Theme.dim)
                Text(device.distanceText).font(.caption2).foregroundStyle(Theme.dim)
            }
        }
        .padding(.vertical, 3)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let b = device.info.brand { parts.append(b) }
        if let m = device.info.model, m != device.displayName { parts.append(m) }
        if parts.isEmpty { parts.append(device.info.category.rawValue) }
        return parts.joined(separator: " · ")
    }
}

struct BLEDetailView: View {
    @ObservedObject var scanner: BLEScanner
    let id: UUID
    @State private var beep = false
    @StateObject private var tone = ToneGenerator()

    private var device: BLEDevice? { scanner.devices.first { $0.id == id } ?? scanner.device(id) }

    var body: some View {
        ScrollView {
            if let d = device {
                VStack(spacing: 16) {
                    header(d)
                    if let alert = d.info.alert {
                        Card {
                            Label(alert, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.orange)
                                .font(.callout)
                        }
                    }
                    hotCold(d)
                    Card {
                        SectionTitle(text: "Identification", symbol: "info.circle")
                        InfoRow(label: "Nom diffusé", value: d.name ?? "—")
                        InfoRow(label: "Marque", value: d.info.brand ?? "Inconnue")
                        InfoRow(label: "Modèle / type", value: d.info.model ?? d.info.category.rawValue)
                        InfoRow(label: "Catégorie", value: d.info.category.rawValue)
                        InfoRow(label: "Connectable", value: d.connectable ? "Oui" : "Non")
                        if let tx = d.txPower { InfoRow(label: "Puissance émise", value: "\(tx) dBm") }
                        InfoRow(label: "Vu pour la 1re fois", value: d.firstSeen.formatted(date: .omitted, time: .standard))
                        InfoRow(label: "Présent depuis", value: durationText(d.lastSeen.timeIntervalSince(d.firstSeen)))
                    }
                    if !d.info.details.isEmpty {
                        Card {
                            SectionTitle(text: "Ce que l'appareil annonce", symbol: "antenna.radiowaves.left.and.right")
                            ForEach(Array(d.info.details.enumerated()), id: \.offset) { item in
                                Label(item.element, systemImage: "circle.fill")
                                    .labelStyle(BulletLabelStyle(color: d.info.category.colors[0]))
                                    .font(.callout)
                            }
                        }
                    }
                    if let m = d.manufacturerData {
                        Card {
                            SectionTitle(text: "Données brutes", symbol: "number")
                            Text(m.hex).font(.caption.monospaced()).textSelection(.enabled)
                            Text("ID iOS : \(d.id.uuidString)").font(.caption2.monospaced()).foregroundStyle(Theme.dim)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            } else {
                ContentUnavailableView("Appareil plus à portée",
                                       systemImage: "antenna.radiowaves.left.and.right.slash",
                                       description: Text("Il n'émet plus depuis 2 minutes."))
                    .padding(.top, 60)
            }
        }
        .waveScreen(.bluetooth)
        .navigationTitle(device?.displayName ?? "Appareil")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: device?.rssi ?? -120) { _, rssi in
            tone.frequency = 300 + Double(max(0, min(70, rssi + 100))) * 18
        }
        .onChange(of: beep) { _, on in
            if on { tone.start(amplitude: 0.12) } else { tone.stop() }
        }
        .onAppear { scanner.acquire() }
        .onDisappear {
            beep = false
            tone.stop()
            scanner.release()
        }
    }

    private func header(_ d: BLEDevice) -> some View {
        HStack(spacing: 14) {
            IconTile(symbol: d.info.category.icon, colors: d.info.category.colors, size: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text(d.displayName)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(2)
                Text([d.info.brand, d.info.category.rawValue].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
            }
            Spacer()
        }
        .padding(.top, 8)
    }

    private func hotCold(_ d: BLEDevice) -> some View {
        let level = max(0.03, min(1, Double(d.rssi + 100) / 65))
        let colors = [rssiColor(d.rssi), rssiColor(d.rssi).opacity(0.6)]
        return Card {
            HStack {
                SectionTitle(text: "Chaud / froid", symbol: "flame.fill", color: rssiColor(d.rssi))
                Spacer()
                Button {
                    beep.toggle()
                } label: {
                    Image(systemName: beep ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
                .buttonStyle(CircleIconButtonStyle(color: beep ? rssiColor(d.rssi) : .primary))
                .accessibilityLabel("Son")
            }
            HStack(spacing: 20) {
                ZStack {
                    GaugeRing(progress: level, colors: [Theme.red, Theme.orange, Theme.teal, Theme.green], lineWidth: 14)
                    VStack(spacing: 0) {
                        Text(proximity(d.rssi))
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(rssiColor(d.rssi))
                        Text(d.distanceText).font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                .frame(width: 130, height: 130)
                VStack(alignment: .leading, spacing: 4) {
                    BigNumber(value: "\(d.rssi)", unit: "dBm", colors: colors, size: 44)
                    Sparkline(values: d.history.map(Double.init), color: rssiColor(d.rssi), minValue: -100, maxValue: -30)
                        .frame(height: 54)
                }
            }
            Text("Déplace-toi lentement : plus le chiffre monte (vers −30), plus tu te rapproches. Active le son pour chercher sans regarder l'écran.")
                .font(.caption).foregroundStyle(Theme.dim)
        }
    }

    private func proximity(_ rssi: Int) -> String {
        switch rssi {
        case (-50)...: return "Brûlant 🔥"
        case (-62)...: return "Chaud"
        case (-74)...: return "Tiède"
        case (-86)...: return "Froid"
        default: return "Glacial"
        }
    }

    private func durationText(_ t: TimeInterval) -> String {
        let s = Int(t)
        if s < 60 { return "\(s) s" }
        if s < 3600 { return "\(s / 60) min \(s % 60) s" }
        return "\(s / 3600) h \((s % 3600) / 60) min"
    }
}

/// Puce colorée devant un texte.
struct BulletLabelStyle: LabelStyle {
    var color: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(color).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            configuration.title
        }
    }
}
