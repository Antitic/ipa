import SwiftUI

struct DetectorHome: View {
    var body: some View {
        List {
            Section {
                row(.bluetooth, "Bluetooth", "Appareils proches, traceurs, connexion") { BLEView() }
                row(.lan, "Réseau local", "Appareils du Wi‑Fi, ports, outils") { LANView() }
                row(.infrared, "Infrarouge", "LED de vision nocturne, objectifs") { InfraredView() }
                row(.ultrasound, "Ultrasons", "Balises inaudibles 17–20 kHz") { UltrasoundView() }
            } header: {
                Text("Outils")
            } footer: {
                Text("Aucune méthode n'est infaillible seule. Combine-les, et inspecte aussi à l'œil : une caméra sur carte SD sans Wi‑Fi ni Bluetooth n'émet rien.")
            }

            Section("Méthode rapide") {
                Label("Scanne le réseau local pour repérer les caméras Wi‑Fi.", systemImage: "1.circle")
                Label("Lance le scan Bluetooth et filtre « Suspects ».", systemImage: "2.circle")
                Label("Lumière éteinte, balaye la pièce en infrarouge.", systemImage: "3.circle")
                Label("Lampe allumée, cherche les reflets d'objectif.", systemImage: "4.circle")
                Label("Laisse l'analyse des ultrasons tourner une minute.", systemImage: "5.circle")
            }
            .font(.callout)
        }
        .navigationTitle("Wave")
    }

    private func row<Dest: View>(_ feature: Feature, _ title: String, _ subtitle: String,
                                 @ViewBuilder destination: @escaping () -> Dest) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: feature.symbol).foregroundStyle(feature.tint)
            }
        }
    }
}
