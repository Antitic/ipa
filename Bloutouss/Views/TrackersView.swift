import SwiftUI

/// Repère les traqueurs (AirTag, Tile, SmartTag…) qui pourraient vous suivre.
struct TrackersView: View {
    @EnvironmentObject private var scanner: BluetoothScanner
    @EnvironmentObject private var store: DeviceStore

    /// Au-delà de cette durée de présence, un traqueur devient suspect.
    private let suspiciousAfter: TimeInterval = 10 * 60

    private var trackers: [BluetoothDevice] {
        scanner.devices.values
            .filter { $0.info.isTracker }
            .sorted { $0.trackedDuration > $1.trackedDuration }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if trackers.isEmpty {
                        Label("Aucun traqueur détecté pour l'instant", systemImage: "checkmark.shield.fill")
                            .foregroundStyle(.green)
                    }
                    ForEach(trackers) { device in
                        NavigationLink(value: Route.device(device.id)) {
                            TrackerRow(
                                device: device,
                                name: store.displayName(for: device),
                                now: scanner.now,
                                isSuspicious: device.trackedDuration > suspiciousAfter && !device.isStale(now: scanner.now)
                            )
                        }
                    }
                } header: {
                    Text("\(trackers.count) traqueur\(trackers.count > 1 ? "s" : "") repéré\(trackers.count > 1 ? "s" : "")")
                } footer: {
                    if !scanner.isScanning {
                        Text("Le scan est en pause : lancez-le depuis l'onglet Appareils.")
                    }
                }

                Section("Comment ça marche") {
                    Text("Bloutouss signale les AirTag et accessoires Localiser **séparés de leur propriétaire**, ainsi que les traqueurs Tile et Samsung SmartTag.")
                    Text("Un traqueur qui reste près de vous pendant plus de 10 minutes, même quand vous vous déplacez, est signalé en rouge.")
                    Text("Utilisez « Localiser l'appareil » pour le retrouver grâce à la force du signal. En cas de doute, contactez les autorités.")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("Traqueurs")
            .bloutoussDestinations()
        }
    }
}

private struct TrackerRow: View {
    let device: BluetoothDevice
    let name: String
    let now: Date
    let isSuspicious: Bool

    var body: some View {
        let stale = device.isStale(now: now)
        HStack(spacing: 12) {
            DeviceIcon(kind: .tracker, color: isSuspicious ? .red : (stale ? .gray : .orange))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.headline)
                Text("Présent depuis \(device.trackedDuration.shortDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isSuspicious {
                    Text("Vous suit peut-être")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(device.rssi) dBm")
                    .font(.subheadline.monospacedDigit())
                Text(stale ? "absent" : device.estimatedDistance.formattedDistance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(stale ? 0.6 : 1)
    }
}
