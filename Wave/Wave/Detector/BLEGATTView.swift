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

    var body: some View {
        List {
            Section {
                LabeledContent("État") {
                    HStack(spacing: 6) {
                        if session.state == .connecting { ProgressView() }
                        Text(stateText)
                    }
                }
                if let rssi = session.rssi, session.state == .connected {
                    LabeledContent("Signal", value: "\(rssi) dBm")
                }
                switch session.state {
                case .connected, .connecting:
                    Button("Se déconnecter", role: .destructive) { scanner.disconnect(id) }
                default:
                    Button("Se connecter") { scanner.connect(id) }
                }
            }

            if session.alertCharacteristic != nil {
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
                    Text("Utilise le service standard « Alerte immédiate » (porte-clés, traceurs, certains bracelets).")
                }
            }

            if session.battery != nil || !session.info.isEmpty {
                Section("Informations") {
                    if let b = session.battery {
                        LabeledContent("Batterie") {
                            HStack {
                                Gauge(value: Double(min(b, 100)), in: 0...100) { EmptyView() }
                                    .gaugeStyle(.accessoryLinearCapacity)
                                    .tint(b > 20 ? .green : .red)
                                    .frame(width: 80)
                                Text("\(b) %").monospacedDigit()
                            }
                        }
                    }
                    ForEach(session.info.keys.sorted(), id: \.self) { key in
                        InfoRow(label: key, value: session.info[key] ?? "")
                    }
                }
            }

            if session.state == .connected && session.services.isEmpty {
                Section { ProgressView("Découverte des services…") }
            }

            ForEach(session.services, id: \.self) { service in
                Section {
                    ForEach(service.characteristics ?? [], id: \.self) { c in
                        Button {
                            selected = CharacteristicRef(c: c)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(GATTNames.characteristic(c.uuid))
                                    Spacer()
                                    if c.isNotifying {
                                        Image(systemName: "bell.fill").foregroundStyle(.green).font(.caption)
                                    }
                                }
                                Text(GATTNames.properties(c.properties))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let v = session.value(for: c) {
                                    Text(GATTFormat.describe(v, uuid: c.uuid))
                                        .font(.caption.monospaced())
                                        .lineLimit(2)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("\(GATTNames.service(service.uuid)) · \(service.uuid.uuidString)")
                }
            }

            if !session.log.isEmpty {
                Section("Journal") {
                    ForEach(Array(session.log.suffix(30).reversed())) { e in
                        HStack(alignment: .firstTextBaseline) {
                            Text(e.date.formatted(date: .omitted, time: .standard))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(e.text).font(.caption)
                        }
                    }
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
