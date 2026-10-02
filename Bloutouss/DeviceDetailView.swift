import Charts
import CoreBluetooth
import SwiftUI

struct DeviceDetailView: View {
    @EnvironmentObject private var scanner: BluetoothScanner
    let deviceID: UUID

    var body: some View {
        Group {
            if let device = scanner.devices[deviceID] {
                details(for: device)
            } else {
                Text("Cet appareil n'est plus dans la liste.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(scanner.devices[deviceID]?.displayName ?? "Appareil")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func details(for device: BluetoothDevice) -> some View {
        List {
            Section("Signal") {
                Chart(device.rssiHistory) { sample in
                    LineMark(
                        x: .value("Heure", sample.date),
                        y: .value("RSSI", sample.rssi)
                    )
                    .interpolationMethod(.monotone)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxisLabel("dBm")
                .frame(height: 160)
                .padding(.vertical, 4)

                InfoRow("RSSI", "\(device.rssi) dBm")
                InfoRow("Distance estimée", device.estimatedDistance.formattedDistance)
                InfoRow("Dernière détection", device.lastSeen.formatted(date: .omitted, time: .standard))
            }

            Section("Général") {
                InfoRow("Nom", device.name ?? "—")
                InfoRow("Identifiant", device.id.uuidString, monospaced: true)
                InfoRow("Connectable", device.isConnectable.map { $0 ? "Oui" : "Non" } ?? "—")
                InfoRow("Puissance d'émission", device.txPower.map { "\($0) dBm" } ?? "—")
                InfoRow("Annonces reçues", "\(device.advertisementCount)")
                InfoRow("Première détection", device.firstSeen.formatted(date: .omitted, time: .standard))
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
                        InfoRow(uuid.description, uuid.uuidString, monospaced: true)
                    }
                }
            }

            if !device.serviceData.isEmpty {
                Section("Données de service") {
                    ForEach(device.serviceData.keys.sorted { $0.uuidString < $1.uuidString }, id: \.uuidString) { uuid in
                        InfoRow(uuid.description, device.serviceData[uuid]?.hexString ?? "", monospaced: true)
                    }
                }
            }

            Section {
                Text("L'identifiant est attribué par iOS à cet iPhone ; ce n'est pas l'adresse MAC de l'appareil. La distance est une estimation basée sur la force du signal.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    let monospaced: Bool

    init(_ title: String, _ value: String, monospaced: Bool = false) {
        self.title = title
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        Group {
            if monospaced {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                    Text(value)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Text(title)
                    Spacer()
                    Text(value)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .contextMenu {
            Button {
                UIPasteboard.general.string = value
            } label: {
                Label("Copier", systemImage: "doc.on.doc")
            }
        }
    }
}
