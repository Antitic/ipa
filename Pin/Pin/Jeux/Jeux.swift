import SwiftUI
import AVFoundation

/// Le menu Jeux, comme sur l'iPod classic.
struct MenuJeux: View {
    @EnvironmentObject var nav: Navigateur
    @AppStorage("record.brick") private var recordBrick = 0
    @AppStorage("record.quiz") private var recordQuiz = 0

    var body: some View {
        EcranListe(cle: .jeux, elements: [
            ElementListe(id: "brick", titre: "Brick", detail: recordBrick > 0 ? "Record : \(recordBrick)" : nil),
            ElementListe(id: "quiz", titre: "Music Quiz", detail: recordQuiz > 0 ? "Record : \(recordQuiz)/10" : "Devine le morceau"),
        ]) { e in
            nav.ouvrir(e.id == "brick" ? .brick : .musicQuiz)
        }
    }
}

// MARK: - Brick

@MainActor
final class PartieBrick: ObservableObject {
    struct Brique: Identifiable { let id: Int; let x: CGFloat; let y: CGFloat; let ligne: Int; var vivante = true }

    // Coordonnées : 0…1 en largeur et en hauteur.
    @Published var raquette: CGFloat = 0.5
    @Published var balle = CGPoint(x: 0.5, y: 0.86)
    @Published var briques: [Brique] = []
    @Published var score = 0
    @Published var vies = 3
    @Published var niveau = 1
    @Published var etat: Etat = .pret

    enum Etat { case pret, enJeu, perdu }

    let largeurRaquette: CGFloat = 0.22
    let yRaquette: CGFloat = 0.9
    let rayon: CGFloat = 0.018
    let colonnes = 8
    let lignes = 5
    let hauteurBrique: CGFloat = 0.045
    private var vitesse = CGVector(dx: 0.45, dy: -0.6)
    private var boucle: Task<Void, Never>?

    init() { nouvelleGrille() }

    func nouvelleGrille() {
        var b: [Brique] = []
        for l in 0..<lignes {
            for c in 0..<colonnes {
                b.append(Brique(id: l * colonnes + c, x: (CGFloat(c) + 0.5) / CGFloat(colonnes), y: 0.1 + CGFloat(l) * (hauteurBrique + 0.012), ligne: l))
            }
        }
        briques = b
    }

    func deplacer(_ crans: Int) {
        raquette = min(max(raquette + CGFloat(crans) * 0.055, largeurRaquette / 2), 1 - largeurRaquette / 2)
        if etat != .enJeu { balle.x = raquette }
    }

    func placer(_ x: CGFloat) {
        raquette = min(max(x, largeurRaquette / 2), 1 - largeurRaquette / 2)
        if etat != .enJeu { balle.x = raquette }
    }

    func lancer() {
        switch etat {
        case .perdu:
            score = 0; vies = 3; niveau = 1
            nouvelleGrille()
            remettre()
        case .pret:
            let v = 0.55 + 0.07 * CGFloat(niveau - 1)
            vitesse = CGVector(dx: (Bool.random() ? 1 : -1) * v * 0.6, dy: -v)
            etat = .enJeu
            demarrerBoucle()
        case .enJeu:
            break
        }
    }

    private func remettre() {
        etat = .pret
        balle = CGPoint(x: raquette, y: yRaquette - rayon - 0.01)
    }

    func arreter() { boucle?.cancel(); boucle = nil }

    private func demarrerBoucle() {
        boucle?.cancel()
        boucle = Task { @MainActor [weak self] in
            var avant = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let maintenant = Date()
                let dt = min(maintenant.timeIntervalSince(avant), 0.05)
                avant = maintenant
                guard let self, self.etat == .enJeu else { return }
                self.pas(CGFloat(dt))
            }
        }
    }

    private func pas(_ dt: CGFloat) {
        var p = CGPoint(x: balle.x + vitesse.dx * dt, y: balle.y + vitesse.dy * dt)
        // Murs
        if p.x < rayon { p.x = rayon; vitesse.dx = abs(vitesse.dx) }
        if p.x > 1 - rayon { p.x = 1 - rayon; vitesse.dx = -abs(vitesse.dx) }
        if p.y < rayon { p.y = rayon; vitesse.dy = abs(vitesse.dy) }
        // Raquette : l'angle dépend de l'endroit touché
        if vitesse.dy > 0, p.y + rayon >= yRaquette, p.y < yRaquette + 0.03, abs(p.x - raquette) <= largeurRaquette / 2 + rayon {
            let decalage = (p.x - raquette) / (largeurRaquette / 2)
            let v = hypot(vitesse.dx, vitesse.dy)
            let angle = decalage * .pi / 3
            vitesse = CGVector(dx: v * sin(angle), dy: -v * cos(angle))
            p.y = yRaquette - rayon
            Son.tic()
        }
        // Briques
        let demiL = 0.5 / CGFloat(colonnes) - 0.006
        for i in briques.indices where briques[i].vivante {
            let b = briques[i]
            if abs(p.x - b.x) <= demiL + rayon, abs(p.y - b.y) <= hauteurBrique / 2 + rayon {
                briques[i].vivante = false
                score += (lignes - b.ligne) * 10
                if abs(p.x - b.x) - demiL > abs(p.y - b.y) - hauteurBrique / 2 { vitesse.dx = -vitesse.dx } else { vitesse.dy = -vitesse.dy }
                UISelectionFeedbackGenerator().selectionChanged()
                break
            }
        }
        balle = p
        if !briques.contains(where: \.vivante) {
            niveau += 1
            nouvelleGrille()
            remettre()
            arreter()
            return
        }
        // Raté
        if p.y > 1.02 {
            vies -= 1
            arreter()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            if vies <= 0 { etat = .perdu } else { remettre() }
        }
    }
}

struct EcranBrick: View {
    @StateObject private var partie = PartieBrick()
    @AppStorage("record.brick") private var record = 0

    private let couleurs: [Color] = [.red, .orange, .yellow, .green, Color(red: 0.2, green: 0.5, blue: 0.95)]

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                Color.black
                ForEach(partie.briques.filter(\.vivante)) { b in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(couleurs[b.ligne % couleurs.count])
                        .frame(width: w / CGFloat(partie.colonnes) - 4, height: h * partie.hauteurBrique)
                        .position(x: b.x * w, y: b.y * h)
                }
                Capsule()
                    .fill(LinearGradient(colors: [.white, Color(white: 0.7)], startPoint: .top, endPoint: .bottom))
                    .frame(width: partie.largeurRaquette * w, height: 7)
                    .position(x: partie.raquette * w, y: partie.yRaquette * h + 3)
                Circle().fill(.white)
                    .frame(width: partie.rayon * 2 * w, height: partie.rayon * 2 * w)
                    .position(x: partie.balle.x * w, y: partie.balle.y * h)
                HStack {
                    Text("\(partie.score)").font(.system(size: 11, weight: .bold).monospacedDigit())
                    Spacer()
                    Text("Niv. \(partie.niveau)").font(.system(size: 10))
                    Spacer()
                    Text(String(repeating: "●", count: max(partie.vies, 0))).font(.system(size: 9))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.top, 3)
                if partie.etat != .enJeu {
                    VStack(spacing: 3) {
                        Text(partie.etat == .perdu ? "Partie terminée" : (partie.score == 0 ? "Brick" : "Prêt ?"))
                            .font(.system(size: 16, weight: .bold))
                        if partie.etat == .perdu { Text("Score \(partie.score) · Record \(record)").font(.system(size: 11)) }
                        Text("Molette : raquette · Centre : jouer").font(.system(size: 10)).opacity(0.7)
                    }
                    .foregroundStyle(.white)
                    .frame(width: w, height: h * 0.25)
                    .position(x: w / 2, y: h * 0.6)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { v in partie.placer(v.location.x / w) })
            .onTapGesture { partie.lancer() }
        }
        .onChange(of: partie.score) { _, s in if s > record { record = s } }
        .onDisappear { partie.arreter() }
        .roue { g in
            g.tour = { s in partie.deplacer(s) }
            g.centre = { partie.lancer() }
        }
    }
}

// MARK: - Music Quiz

@MainActor
final class PartieQuiz: NSObject, ObservableObject {
    @Published var question = 0
    @Published var score = 0
    @Published var choix: [Morceau] = []
    @Published var bonne: Morceau?
    @Published var selection = 0
    @Published var reponse: Int?
    @Published var chargement = true
    @Published var fini = false
    @Published var erreur: String?
    @Published var restant: Double = 10

    let total = 10
    private var morceaux: [Morceau] = []
    private var lecteur: AVAudioPlayer?
    private var minuteur: Task<Void, Never>?

    func demarrer() async {
        do {
            morceaux = try await API.get("/api/musique", [Morceau].self)
            guard morceaux.count >= 4 else { erreur = "Il faut au moins 4 morceaux sur ton profil."; return }
            question = 0
            score = 0
            fini = false
            await suivante()
        } catch {
            erreur = error.localizedDescription
        }
    }

    func suivante() async {
        minuteur?.cancel()
        lecteur?.stop()
        reponse = nil
        selection = 0
        guard question < total else { fini = true; return }
        question += 1
        chargement = true
        let options = Array(morceaux.shuffled().prefix(4))
        let b = options.randomElement()!
        choix = options
        bonne = b
        do {
            let url = try await Lecteur.telecharger(b.id)
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            let p = try AVAudioPlayer(contentsOf: url)
            p.currentTime = max(0, Double.random(in: 0.15...0.6) * max(p.duration - 12, 0))
            p.play()
            lecteur = p
        } catch {
            erreur = "Morceau illisible."
        }
        chargement = false
        restant = 10
        minuteur = Task { @MainActor [weak self] in
            while let self, self.restant > 0, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                if self.reponse != nil { return }
                self.restant -= 0.1
            }
            if let self, !Task.isCancelled, self.reponse == nil { self.repondre(-1) }
        }
    }

    func repondre(_ i: Int) {
        guard reponse == nil, !chargement else { return }
        reponse = i
        minuteur?.cancel()
        if i >= 0, choix.indices.contains(i), choix[i].id == bonne?.id {
            score += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            await suivante()
        }
    }

    func arreter() {
        minuteur?.cancel()
        lecteur?.stop()
    }
}

struct EcranMusicQuiz: View {
    @EnvironmentObject var lecteurPrincipal: Lecteur
    @StateObject private var partie = PartieQuiz()
    @AppStorage("record.quiz") private var record = 0

    var body: some View {
        Group {
            if let e = partie.erreur {
                MessageEcran(icone: "music.note", texte: "Music Quiz", detail: e)
            } else if partie.fini {
                MessageEcran(icone: "trophy.fill", texte: "\(partie.score) / \(partie.total)",
                             detail: (partie.score > record ? "Nouveau record ! " : "Record : \(max(record, partie.score)). ") + "Centre pour rejouer.")
            } else if partie.chargement && partie.choix.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Question \(partie.question)/\(partie.total)").font(.system(size: 11, weight: .semibold))
                        Spacer()
                        Text("Score \(partie.score)").font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    ProgressView(value: max(partie.restant, 0), total: 10).tint(partie.restant < 3 ? .red : .blue).padding(.horizontal, 8)
                    ForEach(Array(partie.choix.enumerated()), id: \.offset) { i, m in
                        ligne(i, m)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .background(Color.white)
        .task {
            lecteurPrincipal.pause()
            await partie.demarrer()
        }
        .onChange(of: partie.fini) { _, f in if f && partie.score > record { record = partie.score } }
        .onDisappear { partie.arreter() }
        .roue { g in
            g.tour = { s in
                guard partie.reponse == nil else { return }
                partie.selection = min(max(partie.selection + s, 0), max(partie.choix.count - 1, 0))
            }
            g.centre = {
                if partie.fini { Task { await partie.demarrer() } } else { partie.repondre(partie.selection) }
            }
        }
    }

    private func ligne(_ i: Int, _ m: Morceau) -> some View {
        let sel = i == partie.selection
        var fond: Color = sel ? Color(red: 0.16, green: 0.44, blue: 0.86) : .clear
        if let r = partie.reponse {
            if m.id == partie.bonne?.id { fond = .green } else if r == i { fond = .red } else { fond = .clear }
        }
        let clair = fond != .clear
        return VStack(alignment: .leading, spacing: 1) {
            Text(m.titre).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            if let a = m.artiste { Text(a).font(.system(size: 10)).opacity(0.75).lineLimit(1) }
        }
        .foregroundStyle(clair ? Color.white : Color.black)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(fond)
        .contentShape(Rectangle())
        .onTapGesture { partie.selection = i; partie.repondre(i) }
    }
}
