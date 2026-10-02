import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var scanner: BluetoothScanner
    @EnvironmentObject private var store: DeviceStore

    @AppStorage(SettingsKey.staleAfter) private var staleAfter = 10.0
    @AppStorage(SettingsKey.removeAfter) private var removeAfter = 0.0
    @AppStorage(SettingsKey.smoothing) private var smoothing = 0.3
    @AppStorage(SettingsKey.pathLoss) private var pathLoss = 2.0
    @AppStorage(SettingsKey.measuredPower) private var measuredPower = -59.0
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.finderSound) private var finderSound = false
    @AppStorage(SettingsKey.keepScreenOn) private var keepScreenOn = false
    @AppStorage(SettingsKey.favoriteAlerts) private var favoriteAlerts = true

    @State private var confirmReset = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private struct KindCount: Identifiable {
        let kind: DeviceKind
        let count: Int
        var id: DeviceKind { kind }
    }

    private var kindCounts: [KindCount] {
        let devices = Array(scanner.devices.values)
        return DeviceKind.allCases
            .map { kind in KindCount(kind: kind, count: devices.filter { $0.kind == kind }.count) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Grisé après", selection: $staleAfter) {
                        Text("5 s").tag(5.0)
                        Text("10 s").tag(10.0)
                        Text("30 s").tag(30.0)
                        Text("1 min").tag(60.0)
                    }
                    Picker("Retirer de la liste après", selection: $removeAfter) {
                        Text("Jamais").tag(0.0)
                        Text("30 s").tag(30.0)
                        Text("1 min").tag(60.0)
                        Text("5 min").tag(300.0)
                        Text("15 min").tag(900.0)
                    }
                    VStack(alignment: .leading) {
                        Text("Réactivité du signal : \(Int(smoothing * 100)) %")
                        Slider(value: $smoothing, in: 0.05...1)
                    }
                } header: {
                    Text("Scan")
                } footer: {
                    Text("Une faible réactivité lisse les variations du signal ; une forte réactivité suit chaque annonce. Les favoris ne sont jamais retirés.")
                }

                Section {
                    VStack(alignment: .leading) {
                        Text("Atténuation de l'environnement : \(pathLoss, specifier: "%.1f")")
                        Slider(value: $pathLoss, in: 1.5...4, step: 0.1)
                    }
                    VStack(alignment: .leading) {
                        Text("Signal de référence à 1 m : \(Int(measuredPower)) dBm")
                        Slider(value: $measuredPower, in: -90 ... -40, step: 1)
                    }
                    Button("Valeurs par défaut") {
                        pathLoss = 2.0
                        measuredPower = -59
                    }
                } header: {
                    Text("Estimation de la distance")
                } footer: {
                    Text("Atténuation : 2 en extérieur dégagé, 2,5 à 3 en intérieur, jusqu'à 4 avec beaucoup d'obstacles. Pour calibrer, placez un appareil à 1 m et reportez son RSSI lissé.")
                }

                Section("Retours") {
                    Toggle("Vibrations", isOn: $haptics)
                    Toggle("Son en mode Localiser", isOn: $finderSound)
                    Toggle("Alerte quand un favori apparaît", isOn: $favoriteAlerts)
                    Toggle("Garder l'écran allumé", isOn: $keepScreenOn)
                }

                Section("Statistiques de la session") {
                    InfoRow("Appareils détectés", "\(scanner.devices.count)")
                    InfoRow("Annonces reçues", "\(scanner.totalAdvertisements)")
                    InfoRow("Traqueurs", "\(scanner.devices.values.filter { $0.info.isTracker }.count)")
                    ForEach(kindCounts) { item in
                        HStack {
                            Label(item.kind.label, systemImage: item.kind.symbol)
                            Spacer()
                            Text("\(item.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Données") {
                    InfoRow("Favoris", "\(store.favorites.count)")
                    InfoRow("Noms personnalisés", "\(store.customNames.count)")
                    Button("Effacer favoris et noms", role: .destructive) {
                        confirmReset = true
                    }
                    .confirmationDialog("Effacer tous les favoris et noms personnalisés ?", isPresented: $confirmReset, titleVisibility: .visible) {
                        Button("Effacer", role: .destructive) { store.reset() }
                    }
                }

                Section {
                    InfoRow("Version", version)
                    Text("iOS ne permet de voir que les appareils Bluetooth Low Energy qui émettent des annonces, et ne fournit pas leur adresse MAC. Certains appareils changent régulièrement d'identifiant pour protéger la vie privée.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("À propos")
                }
            }
            .navigationTitle("Réglages")
        }
    }
}
