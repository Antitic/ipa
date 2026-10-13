import SwiftUI

/// Cover Flow, comme sur l'iPod classic : les pochettes défilent en 3D à la
/// molette, celle du centre est de face, les autres pivotent sur les côtés.
/// Centre = lire depuis ce morceau.
struct EcranCoverFlow: View {
    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var lecteur: Lecteur
    @State private var morceaux: [Morceau] = []
    @State private var index = 0
    @State private var charge = false

    var body: some View {
        GeometryReader { g in
            let cote = min(g.size.width * 0.46, g.size.height * 0.62)
            ZStack {
                LinearGradient(colors: [Color(white: 0.16), .black], startPoint: .top, endPoint: .bottom)
                if morceaux.isEmpty {
                    Text(charge ? "Aucun morceau" : "Chargement…")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
                } else {
                    // Seules les pochettes proches sont dessinées.
                    ForEach(max(0, index - 5)...min(morceaux.count - 1, index + 5), id: \.self) { i in
                        let d = CGFloat(i - index)
                        PochetteFlow(morceau: morceaux[i], cote: cote)
                            .rotation3DEffect(.degrees(d == 0 ? 0 : (d < 0 ? 62 : -62)),
                                              axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                            .scaleEffect(d == 0 ? 1 : 0.82)
                            .offset(x: d == 0 ? 0 : (d < 0 ? -1 : 1) * (cote * 0.52 + (abs(d) - 1) * cote * 0.2),
                                    y: -g.size.height * 0.08)
                            .zIndex(-Double(abs(d)))
                            .onTapGesture { if i == index { jouer() } else { index = i } }
                    }
                    VStack(spacing: 2) {
                        Spacer()
                        Text(morceaux[index].titre).font(.system(size: 13, weight: .bold)).lineLimit(1)
                        Text(morceaux[index].artiste ?? " ").font(.system(size: 11)).opacity(0.7).lineLimit(1)
                        Text("\(index + 1) sur \(morceaux.count)").font(.system(size: 9)).opacity(0.5)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: index)
        }
        .task {
            if let m = try? await API.get("/api/musique", [Morceau].self) { morceaux = m }
            if let c = lecteur.courant, let i = morceaux.firstIndex(where: { $0.id == c.id }) { index = i }
            charge = true
        }
        .roue { g in
            g.tour = { s in
                guard !morceaux.isEmpty else { return }
                index = min(max(index + s, 0), morceaux.count - 1)
            }
            g.centre = { jouer() }
        }
    }

    private func jouer() {
        guard morceaux.indices.contains(index) else { return }
        lecteur.jouer(morceaux, depuis: index)
        nav.ouvrir(.enLecture)
    }
}

/// Une pochette avec son reflet sur le « sol ».
private struct PochetteFlow: View {
    let morceau: Morceau
    let cote: CGFloat
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 1) {
            carre
            carre
                .scaleEffect(x: 1, y: -1)
                .frame(height: cote * 0.35, alignment: .top)
                .clipped()
                .mask(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
        }
        .task(id: morceau.id) {
            guard morceau.pochette else { return }
            image = await API.image("/api/musique/\(API.segment(morceau.id))/pochette")
        }
    }

    private var carre: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.35), Color(white: 0.2)], startPoint: .top, endPoint: .bottom)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: cote * 0.3)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: cote, height: cote)
        .clipped()
    }
}
