import SwiftUI
import CoreBluetooth

/// Connexion à un appareil Bluetooth : infos, batterie, alerte, services et caractéristiques.
struct GATTView: View {
    @ObservedObject var scanner: BLEScanner
    let id: UUID
    @State private var session: GATTSession?

    var body: some View {
        Group {
            if let session {
                GATTContent(scanner: scanner, session: session, id: id)
            } else {
                ContentUnavailableView("Appareil introuvable", systemImage: "antenna.radiowaves.left.and.right.slash")
            }
        }
        .navigationTitle("Connexion")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            scanner.acquire()
            if session == nil { session = scanner.session(for: id) }
            if let session, session.state != .connected, session.state != .connecting {
                scanner.connect(id)
            }
        }
        .onDisappear {
            scanner.disconnect(id)
            scanner.release()
        }
    }
}

private struct CharacteristicRef: Identifiable {
    let c: CBCharacteristic
    var id: ObjectIdentifier { ObjectIdentifier(c) }
}

private struct GATTContent: View {
    @ObservedObject var scanner: BLEScanner
    @ObservedObject var session: GATTSession
    let id: UUID
    @State private var selected: CharacteristicRef?

    private var stateText: String {
        switch session.state {
        case .idle: return "En attente"
        case .connecting: return "Connexion…"
        case .connected: return "Connecté"
        case .disconnected: return "Déconnecté"
        case .failed(let m): return "Échec : \(m)"
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

    private var deviceName: String {
        scanner.device(id)?.displayName ?? session.peripheral.name ?? "Appareil"
    }

    private var statusColor: Color {
        switch session.state {
        case .connected: return .green
        case .connecting: return .orange
        case .failed: return .red
        default: return .secondary
        }
    }

    private var isConnected: Bool { session.state == .connected }

    var body: some View {
        List {
            // 1. En-tête : nom, état, bouton connexion.
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title2)
                        .foregroundStyle(statusColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deviceName).font(.headline)
                        HStack(spacing: 5) {
                            Circle().fill(statusColor).frame(width: 7, height: 7)
                            Text(stateText).font(.caption).foregroundStyle(.secondary)
                            if session.state == .connecting { ProgressView().controlSize(.mini) }
                        }
                    }
                    Spacer()
                }
                switch session.state {
                case .connected, .connecting:
                    Button("Se déconnecter", role: .destructive) { scanner.disconnect(id) }
                default:
                    Button {
                        scanner.connect(id)
                    } label: {
                        Label("Se connecter", systemImage: "link")
                    }
                }
            }

            // 2. Batterie + signal, toujours visibles quand connecté.
            if isConnected {
                Section("État de l'appareil") {
                    LabeledContent("Batterie") {
                        if let b = session.battery {
                            HStack(spacing: 8) {
                                Gauge(value: Double(min(b, 100)), in: 0...100) { EmptyView() }
                                    .gaugeStyle(.accessoryLinearCapacity)
                                    .tint(b > 20 ? .green : .red)
                                    .frame(width: 70)
                                Text("\(b) %").monospacedDigit().foregroundStyle(b > 20 ? .primary : .red)
                            }
                        } else {
                            Text("non communiquée").foregroundStyle(.secondary)
                        }
                    }
                    if let rssi = session.rssi {
                        LabeledContent("Signal") {
                            HStack(spacing: 8) {
                                if session.rssiHistory.count > 1 {
                                    Sparkline(values: session.rssiHistory.map(Double.init),
                                              color: rssiColor(rssi), minValue: -100, maxValue: -30)
                                        .frame(width: 60, height: 24)
                                }
                                Text("\(rssi) dBm · \(proximity(rssi))")
                                    .monospacedDigit()
                                    .foregroundStyle(rssiColor(rssi))
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                }
            }

            // 3. Actions.
            if isConnected && session.alertCharacteristic != nil {
                Section {
                    Button {
                        session.alert(2)
                    } label: {
                        Label("Faire sonner", systemImage: "speaker.wave.3")
                    }
                    Button {
                        session.alert(0)
                    } label: {
                        Label("Arrêter la sonnerie", systemImage: "speaker.slash")
                    }
                } header: {
                    Text("Retrouver l'appareil")
                } footer: {
                    Text("Fait sonner les porte-clés, traceurs et bracelets qui gèrent le service standard « Alerte immédiate ».")
                }
            }

            // 4. Infos appareil (fabricant, modèle…).
            if !session.info.isEmpty {
                Section("Fiche de l'appareil") {
                    ForEach(session.info.keys.sorted(), id: \.self) { key in
                        InfoRow(label: key, value: session.info[key] ?? "")
                    }
                }
            }

            // 5. État de la découverte.
            if isConnected && session.services.isEmpty {
                Section {
                    HStack(spacing: 8) { ProgressView(); Text("Lecture de l'appareil…").foregroundStyle(.secondary) }
                } footer: {
                    Text("Certains appareils (écouteurs, enceintes, téléphones) ne partagent aucune information sans appairage. Dans ce cas, seuls le signal et la batterie (si disponible) s'affichent.")
                }
            }

            // 6. Détails techniques, repliés.
            if isConnected && !session.services.isEmpty {
                Section {
                    DisclosureGroup("Services et caractéristiques (avancé)") {
                        ForEach(session.services, id: \.self) { service in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(GATTNames.service(service.uuid))
                                    .font(.subheadline.weight(.semibold))
                                ForEach(service.characteristics ?? [], id: \.self) { c in
                                    Button {
                                        selected = CharacteristicRef(c: c)
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(GATTNames.characteristic(c.uuid)).font(.callout)
                                                if let v = session.value(for: c) {
                                                    Text(GATTFormat.describe(v, uuid: c.uuid))
                                                        .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                                                } else {
                                                    Text(GATTNames.properties(c.properties))
                                                        .font(.caption).foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                            if c.isNotifying { Image(systemName: "bell.fill").foregroundStyle(.green).font(.caption) }
                                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .foregroundStyle(.primary)
                                    .padding(.leading, 8)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } footer: {
                    Text("Pour explorer, lire et écrire les données brutes de l'appareil.")
                }
            }
        }
        .sheet(item: $selected) { ref in
            CharacteristicSheet(session: session, c: ref.c)
        }
    }
}

private struct CharacteristicSheet: View {
    @ObservedObject var session: GATTSession
    let c: CBCharacteristic
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var hex = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    InfoRow(label: "UUID", value: c.uuid.uuidString, mono: true)
                    InfoRow(label: "Propriétés", value: GATTNames.properties(c.properties))
                }
                Section("Valeur") {
                    if let v = session.value(for: c) {
                        InfoRow(label: "Lisible", value: GATTFormat.describe(v, uuid: c.uuid))
                        InfoRow(label: "Hexadécimal", value: v.hex, mono: true)
                        InfoRow(label: "Taille", value: "\(v.count) octet\(v.count > 1 ? "s" : "")")
                    } else {
                        Text("Aucune valeur lue").foregroundStyle(.secondary)
                    }
                    if c.properties.contains(.read) {
                        Button("Lire") { session.read(c) }
                    }
                    if c.properties.contains(.notify) || c.properties.contains(.indicate) {
                        Toggle("Notifications en direct", isOn: Binding(
                            get: { c.isNotifying },
                            set: { session.setNotify($0, c) }
                        ))
                    }
                }
                if c.properties.contains(.write) || c.properties.contains(.writeWithoutResponse) {
                    Section {
                        Picker("Format", selection: $hex) {
                            Text("Hex").tag(true)
                            Text("Texte").tag(false)
                        }
                        .pickerStyle(.segmented)
                        TextField(hex ? "ex. 01 FF" : "Texte", text: $input)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                        if let error { Text(error).foregroundStyle(.red).font(.caption) }
                        Button("Envoyer") {
                            let data = hex ? GATTFormat.parseHex(input) : input.data(using: .utf8)
                            guard let data, !data.isEmpty else {
                                error = "Valeur invalide"
                                return
                            }
                            error = nil
                            session.write(data, to: c)
                        }
                        .disabled(input.isEmpty || session.state != .connected)
                    } header: {
                        Text("Écrire")
                    } footer: {
                        Text("Écrire une valeur peut modifier le comportement de l'appareil.")
                    }
                }
            }
            .navigationTitle(GATTNames.characteristic(c.uuid))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
