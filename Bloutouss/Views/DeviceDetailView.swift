import Charts
import CoreBluetooth
import SwiftUI

struct DeviceDetailView: View {
    @EnvironmentObject private var scanner: BluetoothScanner
    @EnvironmentObject private var store: DeviceStore
    let deviceID: UUID

    @State private var showRename = false
    @State private var draftName = ""

    var body: some View {
        Group {
            if let device = scanner.devices[deviceID] {
                details(for: device)
            } else {
                Text("Cet appareil n'est plus dans la liste.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(scanner.devices[deviceID].map { store.displayName(for: $0) } ?? "Appareil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    store.toggleFavorite(deviceID)
                } label: {
                    Image(systemName: store.isFavorite(deviceID) ? "star.fill" : "star")
                }
                .tint(.yellow)
            }
        }
        .alert("Renommer l'appareil", isPresented: $showRename) {
            TextField("Nom personnalisé", text: $draftName)
            Button("Enregistrer") {
                store.setCustomName(draftName, for: deviceID)
            }
            if store.customNames[deviceID] != nil {
                Button("Revenir au nom d'origine", role: .destructive) {
                    store.setCustomName(nil, for: deviceID)
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ce nom n'est utilisé que dans Bloutouss.")
        }
    }

    private func details(for device: BluetoothDevice) -> some View {
        let stale = device.isStale(now: scanner.now)
        return List {
            Section {
                HStack(spacing: 16) {
                    DeviceIcon(kind: device.kind, color: stale ? .gray : device.signalColor, size: 60)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.displayName(for: device))
                            .font(.title3.bold())
                        Text(device.info.productName ?? device.kind.label)
                            .foregroundStyle(.secondary)
                        if let manufacturer = device.manufacturerName {
                            Text(manufacturer)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                if device.info.isTracker {
                    Label("Traqueur de localisation détecté", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Section {
                NavigationLink(value: Route.finder(device.id)) {
                    Label("Localiser l'appareil", systemImage: "location.magnifyingglass")
                }
                NavigationLink(value: Route.gatt(device.id)) {
                    Label("Se connecter et explorer", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .disabled(device.isConnectable == false)
                Button {
                    draftName = store.customNames[device.id] ?? device.baseName
                    showRename = true
                } label: {
                    Label("Renommer", systemImage: "pencil")
                }
            } footer: {
                if device.isConnectable == false {
                    Text("Cet appareil n'accepte pas les connexions.")
                }
            }

            Section("Signal") {
                Chart(device.rssiHistory) { sample in
                    LineMark(
                        x: .value("Heure", sample.date),
                        y: .value("RSSI", sample.rssi)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(device.signalColor)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel("dBm")
                .frame(height: 160)
                .padding(.vertical, 4)

                InfoRow("RSSI", "\(device.rssi) dBm")
                InfoRow("RSSI lissé", String(format: "%.0f dBm", device.smoothedRSSI))
                InfoRow("Min / moy. / max", String(format: "%d / %.0f / %d dBm", device.minRSSI, device.averageRSSI, device.maxRSSI))
                InfoRow("Distance estimée", device.estimatedDistance.formattedDistance)
                InfoRow("Dernière détection", stale
                        ? "il y a \(scanner.now.timeIntervalSince(device.lastSeen).shortDuration)"
                        : "à l'instant")
            }

            if device.info.productName != nil || !device.info.protocols.isEmpty || !device.info.details.isEmpty {
                Section("Analyse des annonces") {
                    InfoRow("Catégorie", device.kind.label)
                    if let product = device.info.productName {
                        InfoRow("Identifié comme", product)
                    }
                    ForEach(device.info.protocols, id: \.self) { name in
                        InfoRow("Protocole", name)
                    }
                    ForEach(device.info.details) { item in
                        InfoRow(item.title, item.value, monospaced: item.monospaced)
                    }
                }
            }

            Section("Général") {
                InfoRow("Nom annoncé", device.name ?? "—")
                InfoRow("Identifiant", device.id.uuidString, monospaced: true)
                InfoRow("Connectable", device.isConnectable.map { $0 ? "Oui" : "Non" } ?? "—")
                InfoRow("Puissance d'émission", device.txPower.map { "\($0) dBm" } ?? "—")
                InfoRow("Annonces reçues", "\(device.advertisementCount)")
                InfoRow("Première détection", device.firstSeen.formatted(date: .omitted, time: .standard))
                InfoRow("Présent depuis", device.trackedDuration.shortDuration)
            }

            if let data = device.manufacturerData {
                Section("Fabricant") {
                    InfoRow("Fabricant", device.manufacturerName ?? "Inconnu")
                    if let companyID = device.companyID {
                        InfoRow("Company ID", String(format: "0x%04X", companyID), monospaced: true)
                    }
                    InfoRow("Données", data.hexString, monospaced: true)
                }
            }

            if !device.serviceUUIDs.isEmpty {
                Section("Services annoncés") {
                    ForEach(device.serviceUUIDs, id: \.uuidString) { uuid in
                        InfoRow(GATTNames.service(uuid), uuid.uuidString, monospaced: true)
                    }
                }
            }

            if !device.serviceData.isEmpty {
                Section("Données de service") {
                    ForEach(device.serviceData.keys.sorted { $0.uuidString < $1.uuidString }, id: \.uuidString) { uuid in
                        InfoRow(GATTNames.service(uuid), device.serviceData[uuid]?.hexString ?? "", monospaced: true)
                    }
                }
            }

            Section {
                Text("L'identifiant est attribué par iOS à cet iPhone ; ce n'est pas l'adresse MAC de l'appareil. La distance est une estimation basée sur la force du signal (réglable dans Réglages).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
