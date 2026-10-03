import SwiftUI
import CoreBluetooth

struct BLEView: View {
    @StateObject private var scanner = BLEScanner()
    @State private var filter: Filter = .all
    @State private var search = ""

    enum Filter: String, CaseIterable, Identifiable {
        case all = "Tous", suspects = "Suspects", trackers = "Traceurs", named = "Avec nom"
        var id: String { rawValue }
    }

    private var filtered: [BLEDevice] {
        scanner.devices.filter { d in
            switch filter {
            case .all: break
            case .suspects: if !(d.info.category.isSuspicious || d.info.alert != nil) { return false }
            case .trackers: if d.info.category != .tracker { return false }
            case .named: if d.name == nil { return false }
            }
            if search.isEmpty { return true }
            let hay = [d.displayName, d.info.brand ?? "", d.info.model ?? "", d.info.category.rawValue].joined(separator: " ")
            return hay.localizedCaseInsensitiveContains(search)
        }
    }

    private var suspectCount: Int {
        scanner.devices.filter { $0.info.category.isSuspicious || $0.info.alert != nil }.count
    }

    var body: some View {
        List {
            Section {
                statusCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                Picker("Filtre", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(filtered) { d in
                    NavigationLink {
                        BLEDetailView(scanner: scanner, id: d.id)
                    } label: {
                        BLERow(device: d)
                    }
                    .listRowBackground(Theme.card)
                }
            } footer: {
                Text("iOS masque l'adresse MAC réelle des appareils : chaque appareil reçoit un identifiant propre à ton iPhone. Beaucoup d'appareils changent aussi d'adresse toutes les 15 minutes environ.")
                    .font(.caption2)
            }
        }
        .searchable(text: $search, prompt: "Nom, marque, type…")
        .waveScreen()
        .navigationTitle("Bluetooth")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(scanner.isScanning ? "Mettre en pause" : "Reprendre") {
                        if scanner.isScanning { scanner.stop() } else { scanner.start() }
                    }
                    Button("Effacer la liste", role: .destructive) { scanner.clear() }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear { scanner.start() }
        .onDisappear { scanner.stop() }
    }

    @ViewBuilder private var statusCard: some View {
        Card {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.blue.opacity(0.15)).frame(width: 52, height: 52)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(Theme.blue)
                        .symbolEffect(.variableColor.iterative, isActive: scanner.isScanning)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(stateText).font(.headline)
                    Text("\(scanner.devices.count) appareils · \(suspectCount) à vérifier")
                        .font(.subheadline)
                        .foregroundStyle(suspectCount > 0 ? Theme.warn : Theme.dim)
                }
            }
        }
    }

    private var stateText: String {
        switch scanner.state {
        case .poweredOn: return scanner.isScanning ? "Scan en cours…" : "En pause"
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
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: device.info.category.icon)
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName).font(.callout.weight(.semibold)).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                if device.info.alert != nil {
                    Text("⚠︎ À vérifier").font(.caption2.weight(.semibold)).foregroundStyle(Theme.warn)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 3) {
                SignalBars(rssi: device.rssi)
                Text("\(device.rssi) dBm").font(.caption2.monospacedDigit()).foregroundStyle(Theme.dim)
                Text(device.distanceText).font(.caption2).foregroundStyle(Theme.dim)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let b = device.info.brand { parts.append(b) }
        if let m = device.info.model, m != device.displayName { parts.append(m) }
        if parts.isEmpty { parts.append(device.info.category.rawValue) }
        return parts.joined(separator: " · ")
    }

    private var iconColor: Color {
        if device.info.category.isSuspicious || device.info.alert != nil { return Theme.warn }
        return Theme.blue
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
                VStack(spacing: 14) {
                    if let alert = d.info.alert {
                        Card {
                            Label(alert, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.warn)
                                .font(.callout)
                        }
                    }
                    hotCold(d)
                    Card {
                        Text("Identification").font(.headline)
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
                            Text("Ce que l'appareil annonce").font(.headline)
                            ForEach(Array(d.info.details.enumerated()), id: \.offset) { item in
                                Text("• " + item.element).font(.callout)
                            }
                        }
                    }
                    if let m = d.manufacturerData {
                        Card {
                            Text("Données brutes").font(.headline)
                            Text(m.hex).font(.caption.monospaced()).textSelection(.enabled)
                            Text("ID iOS : \(d.id.uuidString)").font(.caption2.monospaced()).foregroundStyle(Theme.dim)
                        }
                    }
                }
                .padding(16)
            } else {
                Text("Appareil plus à portée.").foregroundStyle(Theme.dim).padding(40)
            }
        }
        .waveScreen()
        .navigationTitle(device?.displayName ?? "Appareil")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: device?.rssi ?? -120) { _, rssi in
            tone.frequency = 300 + Double(max(0, min(70, rssi + 100))) * 18
        }
        .onChange(of: beep) { _, on in
            if on { tone.start(amplitude: 0.12) } else { tone.stop() }
        }
        .onDisappear { tone.stop() }
    }

    private func hotCold(_ d: BLEDevice) -> some View {
        Card {
            HStack {
                Text("Chaud / froid").font(.headline)
                Spacer()
                Toggle(isOn: $beep) { Image(systemName: beep ? "speaker.wave.2.fill" : "speaker.slash") }
                    .toggleStyle(.button)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(d.rssi)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(rssiColor(d.rssi))
                    .contentTransition(.numericText())
                Text("dBm").foregroundStyle(Theme.dim)
                Spacer()
                VStack(alignment: .trailing) {
                    Text(proximity(d.rssi)).font(.headline).foregroundStyle(rssiColor(d.rssi))
                    Text(d.distanceText).font(.caption).foregroundStyle(Theme.dim)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.faint)
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.danger, Theme.warn, Theme.blue, Theme.accent],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * CGFloat(max(0.03, min(1, Double(d.rssi + 100) / 65))))
                        .animation(.easeOut(duration: 0.3), value: d.rssi)
                }
            }
            .frame(height: 10)
            Sparkline(values: d.history.map(Double.init), color: rssiColor(d.rssi), minValue: -100, maxValue: -30)
                .frame(height: 60)
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
        return "\(s / 60) min \(s % 60) s"
    }
}
