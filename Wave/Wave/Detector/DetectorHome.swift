import SwiftUI

struct DetectorHome: View {
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero

                SectionTitle(text: "Outils de détection")
                    .padding(.horizontal, 4)

                LazyVGrid(columns: columns, spacing: 12) {
                    tile(.bluetooth, title: "Bluetooth", subtitle: "Caméras, micros, traceurs") { BLEView() }
                    tile(.lan, title: "Réseau local", subtitle: "Caméras IP, ports, Bonjour") { LANView() }
                    tile(.infrared, title: "Infrarouge", subtitle: "LED de vision nocturne, objectifs") { InfraredView() }
                    tile(.ultrasound, title: "Ultrasons", subtitle: "Balises de pistage inaudibles") { UltrasoundView() }
                }

                SectionTitle(text: "Méthode rapide")
                    .padding(.horizontal, 4)

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        step(1, .lan, "Scanne le réseau local pour repérer les caméras Wi‑Fi.")
                        step(2, .bluetooth, "Lance le scan Bluetooth et filtre « Suspects ».")
                        step(3, .infrared, "Lumière éteinte, balaye les coins, détecteurs, prises et réveils en infrarouge.")
                        step(4, .infrared, "Lampe allumée, cherche les reflets d'objectif.")
                        step(5, .ultrasound, "Laisse l'analyse des ultrasons tourner une minute.")
                    }
                    Divider().overlay(Theme.faint)
                    Label("Un micro filaire ou une caméra autonome (carte SD, sans Wi‑Fi ni Bluetooth) ne se trouve qu'à l'œil : inspecte aussi physiquement.",
                          systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .waveScreen(.lan)
        .navigationTitle("Wave")
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [Theme.indigo, Theme.violet, Theme.pink],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // Ondes décoratives
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .stroke(Color.white.opacity(0.12 - Double(i) * 0.02), lineWidth: 1.5)
                    .frame(width: 120 + CGFloat(i) * 70, height: 120 + CGFloat(i) * 70)
                    .offset(x: 140, y: -60)
            }
            Image(systemName: "viewfinder")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .offset(x: 250, y: -110)

            VStack(alignment: .leading, spacing: 6) {
                Text("Caméras & micros cachés")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Text("Combine les quatre méthodes : aucune n'est infaillible seule, mais ensemble elles couvrent la plupart des appareils grand public.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.violet.opacity(0.35), radius: 20, y: 10)
    }

    private func tile<Dest: View>(_ feature: Feature, title: String, subtitle: String,
                                  @ViewBuilder destination: @escaping () -> Dest) -> some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    IconTile(symbol: feature.symbol, colors: feature.colors, size: 46)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.dim)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2, reservesSpace: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    Theme.card
                    LinearGradient(colors: [feature.colors[0].opacity(0.12), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                },
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func step(_ n: Int, _ feature: Feature, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)")
                .font(.system(.footnote, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(feature.gradient, in: Circle())
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
