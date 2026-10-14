import SwiftUI

/// Solitaire (Klondike, une carte à la fois). La molette promène le curseur
/// sur la pioche, la défausse, les 4 fondations et les 7 colonnes ; le centre
/// prend une carte (ou une suite) puis la pose. Appui long sur le centre :
/// envoie la carte vers les fondations.
@MainActor
final class PartieSolitaire: ObservableObject {
    struct Carte: Identifiable, Equatable {
        let id: Int
        let valeur: Int      // 1…13
        let couleur: Int     // 0 ♠, 1 ♥, 2 ♣, 3 ♦
        var visible = false
        var rouge: Bool { couleur % 2 == 1 }
        var symbole: String { ["♠", "♥", "♣", "♦"][couleur] }
        var nom: String { ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "V", "D", "R"][valeur] }
    }

    // Emplacements : 0 pioche, 1 défausse, 2…5 fondations, 6…12 colonnes
    @Published var pioche: [Carte] = []
    @Published var defausse: [Carte] = []
    @Published var fondations: [[Carte]] = Array(repeating: [], count: 4)
    @Published var colonnes: [[Carte]] = Array(repeating: [], count: 7)
    @Published var curseur = 1
    @Published var prise: (emplacement: Int, nombre: Int)?
    @Published var coups = 0
    @Published var gagne = false

    init() { distribuer() }

    func distribuer() {
        var paquet = (0..<52).map { Carte(id: $0, valeur: $0 % 13 + 1, couleur: $0 / 13) }.shuffled()
        colonnes = Array(repeating: [], count: 7)
        for c in 0..<7 {
            for r in 0...c {
                var carte = paquet.removeLast()
                carte.visible = r == c
                colonnes[c].append(carte)
            }
        }
        pioche = paquet
        defausse = []
        fondations = Array(repeating: [], count: 4)
        prise = nil
        curseur = 0
        coups = 0
        gagne = false
    }

    /// ⏮ ⏭ : saute entre le haut (pioche, défausse, fondations) et les colonnes.
    func sauter(_ s: Int) {
        if curseur < 6 { curseur = s > 0 ? 6 : 0 } else { curseur = s > 0 ? 2 : 0 }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func deplacer(_ s: Int) { curseur = (curseur + s + 13) % 13 }

    func toucher(_ emplacement: Int) {
        curseur = emplacement
        centre()
    }

    func centre() {
        if gagne { distribuer(); return }
        if let p = prise {
            if p.emplacement == curseur { prise = nil; return }
            poser(depuis: p.emplacement, nombre: p.nombre, vers: curseur)
            prise = nil
            return
        }
        switch curseur {
        case 0: piocher()
        case 1: if !defausse.isEmpty { prise = (1, 1) }
        case 2...5: if !fondations[curseur - 2].isEmpty { prise = (curseur, 1) }
        default:
            let col = colonnes[curseur - 6]
            guard let last = col.last else { return }
            if !last.visible {
                colonnes[curseur - 6][col.count - 1].visible = true
                return
            }
            prise = (curseur, col.filter(\.visible).count)
        }
        if prise != nil { UISelectionFeedbackGenerator().selectionChanged() }
    }

    /// Appui long : la carte du dessus file vers sa fondation.
    func versFondation() {
        prise = nil
        guard let carte = dessus(curseur), curseur != 0 else { return }
        for f in 0..<4 where accepteFondation(f, carte) {
            poser(depuis: curseur, nombre: 1, vers: f + 2)
            return
        }
    }

    private func dessus(_ e: Int) -> Carte? {
        switch e {
        case 0: return nil
        case 1: return defausse.last
        case 2...5: return fondations[e - 2].last
        default: return colonnes[e - 6].last.flatMap { $0.visible ? $0 : nil }
        }
    }

    private func piocher() {
        if pioche.isEmpty {
            pioche = defausse.reversed().map { var c = $0; c.visible = false; return c }
            defausse = []
        } else {
            var c = pioche.removeLast()
            c.visible = true
            defausse.append(c)
        }
        coups += 1
        Son.tic()
    }

    private func accepteFondation(_ f: Int, _ c: Carte) -> Bool {
        guard let haut = fondations[f].last else { return c.valeur == 1 }
        return haut.couleur == c.couleur && c.valeur == haut.valeur + 1
    }

    private func accepteColonne(_ col: Int, _ c: Carte) -> Bool {
        guard let haut = colonnes[col].last else { return c.valeur == 13 }
        return haut.visible && haut.rouge != c.rouge && c.valeur == haut.valeur - 1
    }

    private func cartes(_ e: Int, _ n: Int) -> [Carte] {
        switch e {
        case 1: return Array(defausse.suffix(1))
        case 2...5: return Array(fondations[e - 2].suffix(1))
        default: return Array(colonnes[e - 6].suffix(n))
        }
    }

    private func retirer(_ e: Int, _ n: Int) {
        switch e {
        case 1: defausse.removeLast()
        case 2...5: fondations[e - 2].removeLast()
        default:
            colonnes[e - 6].removeLast(n)
            if let last = colonnes[e - 6].indices.last, !colonnes[e - 6][last].visible {
                colonnes[e - 6][last].visible = true
            }
        }
    }

    /// Pose la plus longue suite possible (parmi les n cartes prises) sur la cible.
    private func poser(depuis e: Int, nombre n: Int, vers cible: Int) {
        switch cible {
        case 2...5:
            guard let c = cartes(e, 1).first, accepteFondation(cible - 2, c) else { return refus() }
            retirer(e, 1)
            fondations[cible - 2].append(c)
        case 6...12:
            for k in stride(from: n, through: 1, by: -1) {
                let suite = cartes(e, k)
                guard let premiere = suite.first, premiere.visible else { continue }
                if accepteColonne(cible - 6, premiere) {
                    retirer(e, k)
                    colonnes[cible - 6].append(contentsOf: suite)
                    coups += 1
                    Son.tic()
                    verifierVictoire()
                    return
                }
            }
            return refus()
        default:
            return refus()
        }
        coups += 1
        Son.tic()
        verifierVictoire()
    }

    private func refus() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }

    private func verifierVictoire() {
        if fondations.allSatisfy({ $0.count == 13 }) {
            gagne = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

struct EcranSolitaire: View {
    @StateObject private var partie = PartieSolitaire()
    @AppStorage("record.solitaire") private var victoires = 0

    var body: some View {
        GeometryReader { g in
            let lc = (g.size.width - 8 * 4) / 7
            let hc = lc * 1.38
            ZStack {
                RadialGradient(colors: [Color(red: 0.12, green: 0.5, blue: 0.3), Color(red: 0.03, green: 0.25, blue: 0.13)],
                               center: .center, startRadius: 10, endRadius: max(g.size.width, g.size.height) * 0.8)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        emplacement(0, lc, hc) { carte(partie.pioche.last, lc, hc, vide: "↻") }
                        emplacement(1, lc, hc) { carte(partie.defausse.last, lc, hc) }
                        Spacer().frame(width: lc)
                        ForEach(0..<4, id: \.self) { f in
                            emplacement(f + 2, lc, hc) { carte(partie.fondations[f].last, lc, hc, vide: ["♠", "♥", "♣", "♦"][f]) }
                        }
                    }
                    HStack(alignment: .top, spacing: 4) {
                        ForEach(0..<7, id: \.self) { c in
                            colonne(c, lc, hc, hauteurDispo: g.size.height - hc - 22)
                        }
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if partie.gagne {
                    VStack(spacing: 4) {
                        Text("Gagné !").font(.system(size: 22, weight: .heavy))
                        Text("\(partie.coups) coups · Centre pour rejouer").font(.system(size: 11))
                    }
                    .foregroundStyle(.white).padding(12)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.6)))
                }
            }
        }
        .onChange(of: partie.gagne) { _, g in if g { victoires += 1 } }
        .roue { g in
            g.tour = { s in partie.deplacer(s) }
            g.centre = { partie.centre() }
            g.centreMaintenu = { partie.versFondation() }
            g.centreRelache = { }
            g.lecture = { partie.versFondation() }
            g.precedent = { partie.sauter(-1) }
            g.suivant = { partie.sauter(1) }
        }
    }

    private func emplacement<C: View>(_ e: Int, _ lc: CGFloat, _ hc: CGFloat, @ViewBuilder _ contenu: () -> C) -> some View {
        contenu()
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(partie.curseur == e ? Color.yellow : .clear, lineWidth: 2.5).shadow(color: .yellow.opacity(partie.curseur == e ? 0.9 : 0), radius: 4))
            .offset(y: partie.prise?.emplacement == e ? -4 : 0)
            .onTapGesture { partie.toucher(e) }
    }

    private func colonne(_ c: Int, _ lc: CGFloat, _ hc: CGFloat, hauteurDispo: CGFloat) -> some View {
        let cartes = partie.colonnes[c]
        let cachees = cartes.filter { !$0.visible }.count
        let visibles = cartes.count - cachees
        let pasCache: CGFloat = 5
        let pasVisible = max(8, min(hc * 0.3, (hauteurDispo - hc - CGFloat(cachees) * pasCache) / CGFloat(max(visibles - 1, 1))))
        let prises = partie.prise?.emplacement == c + 6 ? partie.prise!.nombre : 0
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.25), lineWidth: 1).frame(width: lc, height: hc)
            ForEach(Array(cartes.enumerated()), id: \.element.id) { i, carteC in
                let y = CGFloat(min(i, cachees)) * pasCache + CGFloat(max(0, i - cachees)) * pasVisible
                carte(carteC, lc, hc)
                    .offset(y: y - (i >= cartes.count - prises ? 4 : 0))
                    .overlay(alignment: .top) {
                        if i >= cartes.count - prises {
                            RoundedRectangle(cornerRadius: 4).stroke(Color.cyan, lineWidth: 2).frame(width: lc, height: hc).offset(y: y - 4)
                        }
                    }
            }
        }
        .frame(width: lc, alignment: .top)
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 5).stroke(partie.curseur == c + 6 ? Color.yellow : .clear, lineWidth: 2.5)
                .shadow(color: .yellow.opacity(partie.curseur == c + 6 ? 0.9 : 0), radius: 4)
                .frame(width: lc + 2, height: hc + CGFloat(cachees) * pasCache + CGFloat(max(visibles - 1, 0)) * pasVisible + 2)
                .offset(y: -1)
        }
        .contentShape(Rectangle())
        .onTapGesture { partie.toucher(c + 6) }
    }

    @ViewBuilder
    private func carte(_ c: PartieSolitaire.Carte?, _ lc: CGFloat, _ hc: CGFloat, vide: String = "") -> some View {
        if let c, c.visible {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [.white, Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
                RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.35), lineWidth: 0.5)
                VStack(alignment: .leading, spacing: -2) {
                    Text(c.nom).font(.system(size: lc * 0.36, weight: .heavy, design: .rounded))
                    Text(c.symbole).font(.system(size: lc * 0.32))
                }
                .padding(.leading, 2).padding(.top, 1)
                Text(c.symbole).font(.system(size: lc * 0.62)).opacity(0.9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(2)
            }
            .foregroundStyle(c.rouge ? Color(red: 0.85, green: 0.1, blue: 0.12) : Color(white: 0.1))
            .frame(width: lc, height: hc)
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        } else if c != nil {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(red: 0.2, green: 0.35, blue: 0.75), Color(red: 0.1, green: 0.2, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.85), lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(Color.white.opacity(0.25), lineWidth: 0.5).padding(3))
                .frame(width: lc, height: hc)
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
        } else {
            RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.3), lineWidth: 1)
                .overlay(Text(vide).font(.system(size: lc * 0.4)).foregroundStyle(.white.opacity(0.35)))
                .frame(width: lc, height: hc)
        }
    }
}
