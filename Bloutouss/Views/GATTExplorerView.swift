import CoreBluetooth
import SwiftUI

struct GATTExplorerView: View {
    @EnvironmentObject private var scanner: BluetoothScanner
    let deviceID: UUID
    @State private var connection: PeripheralConnection?

    var body: some View {
        Group {
            if let connection {
                GATTContent(connection: connection, deviceID: deviceID)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Appareil introuvable. Vérifiez que le Bluetooth est activé.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .navigationTitle("Exploration")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if connection == nil {
                connection = scanner.connection(for: deviceID)
            }
            if let connection, connection.state != .connected, connection.state != .connecting {
                scanner.connect(deviceID)
            }
        }
        .onDisappear {
            scanner.disconnect(deviceID)
        }
    }
}

private struct CharacteristicRef: Identifiable {
    let characteristic: CBCharacteristic
    var id: ObjectIdentifier { ObjectIdentifier(characteristic) }
}

private struct GATTContent: View {
    @EnvironmentObject private var scanner: BluetoothScanner
    @EnvironmentObject private var store: DeviceStore
    @ObservedObject var connection: PeripheralConnection
    let deviceID: UUID
    @State private var selected: CharacteristicRef?

    private var deviceName: String {
        if let device = scanner.devices[deviceID] {
            return store.displayName(for: device)
        }
        return connection.name ?? "Appareil"
    }

    private var statusText: String {
        switch connection.state {
        case .disconnected: return "Déconnecté"
        case .connecting: return "Connexion en cours…"
        case .connected: return "Connecté"
        case .failed(let message): return "Échec : \(message)"
        }
    }

    private var statusColor: Color {
        switch connection.state {
        case .disconnected: return .secondary
        case .connecting: return .orange
        case .connected: return .green
        case .failed: return .red
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(deviceName)
                            .font(.headline)
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if connection.state == .connecting {
                        ProgressView()
                    } else if let rssi = connection.rssi, connection.state == .connected {
                        Text("\(rssi) dBm")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                switch connection.state {
                case .connected, .connecting:
                    Button(role: .destructive) {
                        scanner.disconnect(deviceID)
                    } label: {
                        Label("Se déconnecter", systemImage: "xmark.circle")
                    }
                case .disconnected, .failed:
                    Button {
                        scanner.connect(deviceID)
                    } label: {
                        Label("Se connecter", systemImage: "link")
                    }
                }
            }

            if connection.batteryLevel != nil || !connection.deviceInfo.isEmpty {
                Section("Informations") {
                    if let battery = connection.batteryLevel {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Label("Batterie", systemImage: batterySymbol(battery))
                                Spacer()
                                Text("\(battery) %")
                                    .foregroundStyle(.secondary)
                            }
                            ProgressView(value: Double(min(battery, 100)), total: 100)
                                .tint(battery > 20 ? .green : .red)
                        }
                    }
                    ForEach(connection.deviceInfo.keys.sorted(), id: \.self) { key in
                        InfoRow(key, connection.deviceInfo[key] ?? "")
                    }
                }
            }

            if connection.state == .connected && connection.services.isEmpty {
                Section {
                    HStack {
                        ProgressView()
                        Text("Découverte des services…")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(connection.services, id: \.self) { service in
                Section {
                    let characteristics = service.characteristics ?? []
                    if characteristics.isEmpty {
                        Text("Aucune caractéristique (ou découverte en cours)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(characteristics, id: \.self) { characteristic in
                        Button {
                            selected = CharacteristicRef(characteristic: characteristic)
                        } label: {
                            CharacteristicRow(
                                characteristic: characteristic,
                                value: connection.value(for: characteristic)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GATTNames.service(service.uuid))
                        Text(service.uuid.uuidString)
                            .font(.caption2.monospaced())
                            .textCase(nil)
                    }
                }
            }

            if !connection.log.isEmpty {
                Section("Journal") {
                    ForEach(Array(connection.log.suffix(40).reversed())) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(entry.date.formatted(date: .omitted, time: .standard))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .sheet(item: $selected) { ref in
            CharacteristicDetailView(connection: connection, characteristic: ref.characteristic)
        }
    }

    private func batterySymbol(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }
}

private struct CharacteristicRow: View {
    let characteristic: CBCharacteristic
    let value: Data?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(GATTNames.characteristic(characteristic.uuid))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if characteristic.isNotifying {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Text(characteristic.uuid.uuidString)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            Text(PropertyFormatter.names(characteristic.properties).joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.blue)
            if let value {
                Text(ValueFormatter.describe(value, uuid: characteristic.uuid))
                    .font(.caption.monospaced())
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct CharacteristicDetailView: View {
    @ObservedObject var connection: PeripheralConnection
    let characteristic: CBCharacteristic
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var inputIsHex = true
    @State private var inputError: String?

    private var properties: CBCharacteristicProperties { characteristic.properties }

    var body: some View {
        NavigationStack {
            List {
                Section("Caractéristique") {
                    InfoRow("Nom", GATTNames.characteristic(characteristic.uuid))
                    InfoRow("UUID", characteristic.uuid.uuidString, monospaced: true)
                    InfoRow("Propriétés", PropertyFormatter.names(properties).joined(separator: ", "))
                }

                Section("Valeur") {
                    if let value = connection.value(for: characteristic) {
                        InfoRow("Interprétée", ValueFormatter.describe(value, uuid: characteristic.uuid))
                        InfoRow("Hexadécimal", value.hexString, monospaced: true)
                        if let text = ValueFormatter.text(value) {
                            InfoRow("Texte", text)
                        }
                        InfoRow("Taille", "\(value.count) octet\(value.count > 1 ? "s" : "")")
                        if let date = connection.valueDate(for: characteristic) {
                            InfoRow("Mise à jour", date.formatted(date: .omitted, time: .standard))
                        }
                    } else {
                        Text("Aucune valeur lue")
                            .foregroundStyle(.secondary)
                    }

                    if properties.contains(.read) {
                        Button {
                            connection.read(characteristic)
                        } label: {
                            Label("Lire", systemImage: "arrow.down.circle")
                        }
                    }
                    if properties.contains(.notify) || properties.contains(.indicate) {
                        Toggle(isOn: Binding(
                            get: { characteristic.isNotifying },
                            set: { connection.setNotify($0, for: characteristic) }
                        )) {
                            Label("Notifications en direct", systemImage: "bell")
                        }
                    }
                }

                if properties.contains(.write) || properties.contains(.writeWithoutResponse) {
                    Section {
                        Picker("Format", selection: $inputIsHex) {
                            Text("Hexadécimal").tag(true)
                            Text("Texte").tag(false)
                        }
                        .pickerStyle(.segmented)
                        TextField(inputIsHex ? "ex. 01 FF 3A" : "Texte à envoyer", text: $input)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                        if let inputError {
                            Text(inputError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Button {
                            send()
                        } label: {
                            Label("Envoyer", systemImage: "paperplane")
                        }
                        .disabled(input.isEmpty || connection.state != .connected)
                    } header: {
                        Text("Écrire")
                    } footer: {
                        Text("Attention : écrire une valeur peut modifier le comportement de l'appareil.")
                    }
                }
            }
            .navigationTitle(GATTNames.characteristic(characteristic.uuid))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    private func send() {
        let data = inputIsHex ? Data(hexString: input) : input.data(using: .utf8)
        guard let data, !data.isEmpty else {
            inputError = "Valeur hexadécimale invalide"
            return
        }
        inputError = nil
        connection.write(data, to: characteristic)
    }
}
