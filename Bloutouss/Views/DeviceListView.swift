import CoreBluetooth
import SwiftUI

enum DeviceSortOrder: String, CaseIterable, Identifiable {
    case signal = "Signal"
    case name = "Nom"
    case recent = "Plus récents"
    case duration = "Présents depuis longtemps"

    var id: Self { self }
}

struct DeviceFilter: Equatable {
    var minRSSI: Double = -100
    var onlyConnectable = false
    var onlyFavorites = false
    var onlyNamed = false
    var hideStale = false
    var kind: DeviceKind?

    var isActive: Bool { self != DeviceFilter() }
}

private struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct DeviceListView: View {
    @EnvironmentObject private var scanner: BluetoothScanner
    @EnvironmentObject private var store: DeviceStore
    @AppStorage(SettingsKey.sortOrder) private var sortOrder: DeviceSortOrder = .signal
    @State private var searchText = ""
    @State private var filter = DeviceFilter()
    @State private var showFilters = false
    @State private var exportFile: ExportFile?

    private var filteredDevices: [BluetoothDevice] {
        let now = scanner.now
        var list = scanner.devices.values.filter { device in
            if device.smoothedRSSI < filter.minRSSI { return false }
            if filter.onlyConnectable && device.isConnectable != true { return false }
            if filter.onlyFavorites && !store.isFavorite(device.id) { return false }
            if filter.onlyNamed && !device.hasName && store.customNames[device.id] == nil { return false }
            if filter.hideStale && device.isStale(now: now) { return false }
            if let kind = filter.kind, device.kind != kind { return false }
            if !searchText.isEmpty {
                let haystack = [
                    store.displayName(for: device),
                    device.id.uuidString,
                    device.manufacturerName ?? "",
                    device.info.productName ?? "",
                    device.kind.label,
                ].joined(separator: " ")
                if !haystack.localizedCaseInsensitiveContains(searchText) { return false }
            }
            return true
        }
        switch sortOrder {
        case .signal:
            list.sort { $0.smoothedRSSI > $1.smoothedRSSI }
        case .name:
            list.sort { store.displayName(for: $0).localizedCaseInsensitiveCompare(store.displayName(for: $1)) == .orderedAscending }
        case .recent:
            list.sort { $0.firstSeen > $1.firstSeen }
        case .duration:
            list.sort { $0.trackedDuration > $1.trackedDuration }
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
            content
                .navigationTitle("Bloutouss")
                .bloutoussDestinations()
                .searchable(text: $searchText, prompt: "Nom, identifiant, fabricant, type")
                .refreshable { scanner.clear() }
                .toolbar { toolbar }
                .sheet(isPresented: $showFilters) {
                    FilterSheet(filter: $filter)
                }
                .sheet(item: $exportFile) { file in
                    ActivityView(items: [file.url])
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        let devices = filteredDevices
        let favorites = devices.filter { store.isFavorite($0.id) }
        let others = devices.filter { !store.isFavorite($0.id) }
        let activeCount = devices.filter { !$0.isStale(now: scanner.now) }.count

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

            if filter.isActive {
                Section {
                    Button {
                        filter = DeviceFilter()
                    } label: {
                        Label("Filtres actifs — toucher pour réinitialiser", systemImage: "line.3.horizontal.decrease.circle.fill")
                            .font(.subheadline)
                    }
                }
            }

            if !favorites.isEmpty {
                Section("Favoris") {
                    rows(favorites)
                }
            }

            if !scanner.systemPeripherals.isEmpty && searchText.isEmpty && !filter.isActive {
                Section {
                    ForEach(scanner.systemPeripherals) { peripheral in
                        NavigationLink(value: Route.gatt(peripheral.id)) {
                            Label(peripheral.name, systemImage: "link.circle.fill")
                        }
                    }
                } header: {
                    Text("Connectés à l'iPhone")
                } footer: {
                    Text("Ces appareils sont déjà connectés au système et n'émettent plus d'annonces, mais on peut explorer leurs services.")
                }
            }

            Section {
                rows(others)
            } header: {
                Text("\(devices.count) détecté\(devices.count > 1 ? "s" : "") · \(activeCount) actif\(activeCount > 1 ? "s" : "")")
            }
        }
        .overlay {
            if devices.isEmpty && stateMessage == nil {
                EmptyStateView(isScanning: scanner.isScanning, isFiltered: filter.isActive || !searchText.isEmpty)
            }
        }
    }

    private func rows(_ list: [BluetoothDevice]) -> some View {
        ForEach(list) { device in
            let isFavorite = store.isFavorite(device.id)
            NavigationLink(value: Route.device(device.id)) {
                DeviceRow(
                    device: device,
                    name: store.displayName(for: device),
                    isFavorite: isFavorite,
                    now: scanner.now
                )
            }
            .swipeActions(edge: .leading) {
                Button {
                    store.toggleFavorite(device.id)
                } label: {
                    Label(isFavorite ? "Retirer" : "Favori", systemImage: isFavorite ? "star.slash" : "star")
                }
                .tint(.yellow)
            }
            .contextMenu {
                Button {
                    store.toggleFavorite(device.id)
                } label: {
                    Label(isFavorite ? "Retirer des favoris" : "Ajouter aux favoris", systemImage: isFavorite ? "star.slash" : "star")
                }
                Button {
                    UIPasteboard.general.string = device.id.uuidString
                } label: {
                    Label("Copier l'identifiant", systemImage: "doc.on.doc")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Menu {
                Picker("Trier par", selection: $sortOrder) {
                    ForEach(DeviceSortOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                Button {
                    showFilters = true
                } label: {
                    Label("Filtres…", systemImage: "line.3.horizontal.decrease")
                }
                Button {
                    export()
                } label: {
                    Label("Exporter en CSV", systemImage: "square.and.arrow.up")
                }
                Button(role: .destructive) {
                    scanner.clear()
                } label: {
                    Label("Vider la liste", systemImage: "trash")
                }
            } label: {
                Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
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

    private func export() {
        let csv = CSVExporter.csv(for: Array(scanner.devices.values), store: store)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bloutouss-\(formatter.string(from: Date())).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            exportFile = ExportFile(url: url)
        } catch {
            exportFile = nil
        }
    }
}

struct DeviceRow: View {
    let device: BluetoothDevice
    let name: String
    let isFavorite: Bool
    let now: Date

    var body: some View {
        let stale = device.isStale(now: now)
        HStack(spacing: 12) {
            DeviceIcon(kind: device.kind, color: stale ? .gray : device.signalColor)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(name)
                        .font(.headline)
                        .foregroundStyle(device.hasName || name != device.baseName ? Color.primary : Color.secondary)
                        .lineLimit(1)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                    if device.info.isTracker {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Text(device.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "cellularbars", variableValue: stale ? 0 : device.signalLevel)
                        .font(.caption)
                        .foregroundStyle(stale ? Color.secondary : device.signalColor)
                    Text("\(device.rssi) dBm")
                        .font(.subheadline.monospacedDigit())
                }
                Text(stale
                     ? "il y a \(now.timeIntervalSince(device.lastSeen).shortDuration)"
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
    var isFiltered = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            if isFiltered {
                Text("Aucun appareil ne correspond")
                    .font(.headline)
            } else {
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
        }
        .padding()
    }
}

struct FilterSheet: View {
    @Binding var filter: DeviceFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Signal") {
                    VStack(alignment: .leading) {
                        Text("Signal minimum : \(Int(filter.minRSSI)) dBm")
                        Slider(value: $filter.minRSSI, in: -100 ... -30, step: 1)
                    }
                }
                Section("Type") {
                    Picker("Type d'appareil", selection: $filter.kind) {
                        Text("Tous").tag(DeviceKind?.none)
                        ForEach(DeviceKind.allCases) { kind in
                            Label(kind.label, systemImage: kind.symbol).tag(DeviceKind?.some(kind))
                        }
                    }
                }
                Section("Afficher uniquement") {
                    Toggle("Les favoris", isOn: $filter.onlyFavorites)
                    Toggle("Les appareils nommés", isOn: $filter.onlyNamed)
                    Toggle("Les appareils connectables", isOn: $filter.onlyConnectable)
                    Toggle("Les appareils actifs", isOn: $filter.hideStale)
                }
            }
            .navigationTitle("Filtres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Réinitialiser") { filter = DeviceFilter() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

enum CSVExporter {
    static func csv(for devices: [BluetoothDevice], store: DeviceStore) -> String {
        let dateFormatter = ISO8601DateFormatter()
        var lines = [
            "nom,identifiant,type,produit,fabricant,rssi,rssi_lisse,distance_m,connectable,traqueur,favori,premiere_detection,derniere_detection,annonces",
        ]
        for device in devices.sorted(by: { $0.firstSeen < $1.firstSeen }) {
            let fields: [String] = [
                store.displayName(for: device),
                device.id.uuidString,
                device.kind.label,
                device.info.productName ?? "",
                device.manufacturerName ?? "",
                "\(device.rssi)",
                String(format: "%.1f", device.smoothedRSSI),
                String(format: "%.2f", device.estimatedDistance),
                device.isConnectable.map { $0 ? "oui" : "non" } ?? "",
                device.info.isTracker ? "oui" : "non",
                store.isFavorite(device.id) ? "oui" : "non",
                dateFormatter.string(from: device.firstSeen),
                dateFormatter.string(from: device.lastSeen),
                "\(device.advertisementCount)",
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static func escape(_ field: String) -> String {
        "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
