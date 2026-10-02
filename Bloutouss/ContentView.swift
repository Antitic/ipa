import CoreBluetooth
import SwiftUI

enum DeviceSortOrder: String, CaseIterable, Identifiable {
    case signal = "Signal"
    case name = "Nom"
    case recent = "Plus récents"

    var id: Self { self }
}

struct ContentView: View {
    @EnvironmentObject private var scanner: BluetoothScanner
    @State private var searchText = ""
    @State private var sortOrder: DeviceSortOrder = .signal
    @State private var hideUnnamed = false

    private var visibleDevices: [BluetoothDevice] {
        var list = Array(scanner.devices.values)
        if hideUnnamed {
            list = list.filter { $0.name != nil }
        }
        if !searchText.isEmpty {
            list = list.filter { device in
                device.displayName.localizedCaseInsensitiveContains(searchText)
                    || device.id.uuidString.localizedCaseInsensitiveContains(searchText)
                    || (device.manufacturerName?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        switch sortOrder {
        case .signal:
            list.sort { $0.rssi > $1.rssi }
        case .name:
            list.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .recent:
            list.sort { $0.firstSeen > $1.firstSeen }
        }
        return list
    }

    private var stateMessage: String? {
        switch scanner.state {
        case .poweredOff:
            return "Le Bluetooth est désactivé. Activez-le dans le Centre de contrôle."
        case .unauthorized:
            return "Bloutouss n'a pas accès au Bluetooth. Autorisez-le dans Réglages."
        case .unsupported:
            return "Cet appareil ne prend pas en charge le Bluetooth Low Energy."
        case .resetting:
            return "Le Bluetooth redémarre…"
        default:
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let stateMessage {
                    Section {
                        Label(stateMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        if scanner.state == .unauthorized,
                           let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Ouvrir les Réglages", destination: url)
                        }
                    }
                }

                Section {
                    ForEach(visibleDevices) { device in
                        NavigationLink(value: device.id) {
                            DeviceRow(device: device, now: scanner.now)
                        }
                    }
                } header: {
                    Text(visibleDevices.count == 1 ? "1 appareil" : "\(visibleDevices.count) appareils")
                }
            }
            .overlay {
                if visibleDevices.isEmpty && stateMessage == nil {
                    EmptyStateView(isScanning: scanner.isScanning)
                }
            }
            .navigationTitle("Bloutouss")
            .navigationDestination(for: UUID.self) { id in
                DeviceDetailView(deviceID: id)
            }
            .searchable(text: $searchText, prompt: "Nom, identifiant, fabricant")
            .refreshable {
                scanner.clear()
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Trier par", selection: $sortOrder) {
                            ForEach(DeviceSortOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        Toggle("Masquer les inconnus", isOn: $hideUnnamed)
                        Button(role: .destructive) {
                            scanner.clear()
                        } label: {
                            Label("Vider la liste", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        scanner.toggleScan()
                    } label: {
                        Label(
                            scanner.isScanning ? "Pause" : "Scanner",
                            systemImage: scanner.isScanning ? "pause.circle.fill" : "play.circle.fill"
                        )
                        .labelStyle(.titleAndIcon)
                    }
                    .disabled(scanner.state != .poweredOn)
                }
            }
        }
    }
}

struct DeviceRow: View {
    let device: BluetoothDevice
    let now: Date

    private var signalColor: Color {
        if device.rssi >= -60 { return .green }
        if device.rssi >= -75 { return .yellow }
        if device.rssi >= -90 { return .orange }
        return .red
    }

    var body: some View {
        let stale = device.isStale(now: now)
        HStack(spacing: 12) {
            Image(systemName: "cellularbars", variableValue: stale ? 0 : device.signalLevel)
                .font(.title2)
                .foregroundStyle(stale ? Color.secondary : signalColor)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.headline)
                    .foregroundStyle(device.name == nil ? Color.secondary : Color.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let manufacturer = device.manufacturerName {
                        Text(manufacturer)
                            .font(.caption)
                    }
                    Text(device.shortID)
                        .font(.caption.monospaced())
                }
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(device.rssi) dBm")
                    .font(.subheadline.monospacedDigit())
                Text(stale
                     ? "il y a \(Int(now.timeIntervalSince(device.lastSeen))) s"
                     : device.estimatedDistance.formattedDistance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(stale ? 0.5 : 1)
    }
}

struct EmptyStateView: View {
    let isScanning: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(isScanning ? "Recherche d'appareils…" : "Scan en pause")
                .font(.headline)
            if isScanning {
                ProgressView()
            } else {
                Text("Appuyez sur « Scanner » pour détecter les appareils Bluetooth à proximité.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}
