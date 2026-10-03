import SwiftUI

struct DetectorHome: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Card {
                    Text("Caméras & micros cachés").font(.title3.weight(.bold))
                    Text("Combine les quatre méthodes : aucune n'est infaillible seule, mais ensemble elles couvrent la plupart des appareils grand public.")
                        .font(.callout).foregroundStyle(Theme.dim)
                }
                tile(title: "Bluetooth", subtitle: "Appareils à proximité, marque, modèle, traceurs (AirTag, Tile, SmartTag) et force du signal",
                     icon: "dot.radiowaves.left.and.right", color: Theme.blue) { BLEView() }
                tile(title: "Réseau local", subtitle: "Appareils connectés à ton Wi‑Fi, caméras IP (flux RTSP), ports et interfaces web",
                     icon: "wifi", color: Theme.violet) { LANView() }
                tile(title: "Infrarouge & objectifs", subtitle: "LED de vision nocturne avec la caméra frontale, reflets d'objectif avec la lampe",
                     icon: "camera.aperture", color: Theme.danger) { InfraredView() }
                tile(title: "Ultrasons", subtitle: "Spectre du micro jusqu'à ~20 kHz pour les balises de pistage et sifflements suspects",
                     icon: "waveform", color: Theme.warn) { UltrasoundView() }

                Card {
                    Text("Méthode rapide").font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        step(1, "Scan réseau local pour repérer les caméras Wi‑Fi.")
                        step(2, "Scan Bluetooth, filtre « Suspects ».")
                        step(3, "Lumière éteinte, balayage infrarouge des coins, détecteurs, prises, réveils.")
                        step(4, "Lampe allumée, recherche de reflets d'objectif.")
                        step(5, "Laisse l'analyse ultrasons tourner une minute.")
                    }
                    Text("Un micro filaire ou une caméra autonome sans Wi‑Fi ni Bluetooth (carte SD) ne peut être trouvé qu'à l'œil : regarde aussi physiquement.")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
            }
            .padding(16)
        }
        .waveScreen()
        .navigationTitle("Wave")
    }

    private func tile<Dest: View>(title: String, subtitle: String, icon: String, color: Color,
                                  @ViewBuilder destination: @escaping () -> Dest) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(color.opacity(0.16)).frame(width: 52, height: 52)
                    Image(systemName: icon).font(.title2).foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").foregroundStyle(Theme.dim)
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n)").font(.caption.weight(.bold)).foregroundStyle(Theme.bg)
                .frame(width: 18, height: 18).background(Theme.accent, in: Circle())
            Text(text).font(.callout)
        }
    }
}
