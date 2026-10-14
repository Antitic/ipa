import SwiftUI

/// Snake : la molette fait tourner le serpent (un cran = un quart de tour),
/// le centre lance ou met en pause.
@MainActor
final class PartieSnake: ObservableObject {
    struct Case: Hashable { var x: Int; var y: Int }
    enum Etat { case pret, enJeu, pause, perdu }

    let colonnes = 18
    let lignes = 15
    @Published var serpent: [Case] = []
    @Published var fruit = Case(x: 0, y: 0)
    @Published var etat: Etat = .pret
    @Published var score = 0
    private var direction = (1, 0)
    /// Virages en attente (2 au plus) : plusieurs crans de molette entre deux
    /// pas du serpent comptent tous, au lieu de s'écraser.
    private var file: [(Int, Int)] = []
    private var boucle: Task<Void, Never>?

    init() { reinitialiser() }

    func reinitialiser() {
        serpent = [Case(x: 6, y: 7), Case(x: 5, y: 7), Case(x: 4, y: 7)]
        direction = (1, 0)
        file = []
        score = 0
        placerFruit()
    }

    private func placerFruit() {
        var c: Case
        repeat { c = Case(x: Int.random(in: 0..<colonnes), y: Int.random(in: 0..<lignes)) } while serpent.contains(c)
        fruit = c
    }

    private var derniere: (Int, Int) { file.last ?? direction }

    /// +1 = tourner à droite, -1 = à gauche (par rapport au dernier virage).
    func tourner(_ sens: Int) {
        guard etat == .enJeu, file.count < 2 else { return }
        let (dx, dy) = derniere
        file.append(sens > 0 ? (-dy, dx) : (dy, -dx))
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Glisser sur l'écran : direction absolue.
    func diriger(_ dx: Int, _ dy: Int) {
        guard etat == .enJeu, file.count < 2 else { return }
        let d = derniere
        guard (dx, dy) != d, (dx, dy) != (-d.0, -d.1) else { return }
        file.append((dx, dy))
    }

    func centre() {
        switch etat {
        case .pret: etat = .enJeu; demarrer()
        case .enJeu: etat = .pause; boucle?.cancel()
        case .pause: etat = .enJeu; demarrer()
        case .perdu: reinitialiser(); etat = .enJeu; demarrer()
        }
    }

    func arreter() { boucle?.cancel() }

    private func demarrer() {
        boucle?.cancel()
        boucle = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let attente = max(75, 190 - (self?.score ?? 0) * 4)
                try? await Task.sleep(for: .milliseconds(attente))
                guard let self, self.etat == .enJeu, !Task.isCancelled else { return }
                self.pas()
            }
        }
    }

    private func pas() {
        if !file.isEmpty { direction = file.removeFirst() }
        let tete = serpent[0]
        let nouvelle = Case(x: tete.x + direction.0, y: tete.y + direction.1)
        if nouvelle.x < 0 || nouvelle.y < 0 || nouvelle.x >= colonnes || nouvelle.y >= lignes || serpent.dropLast().contains(nouvelle) {
            etat = .perdu
            boucle?.cancel()
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        serpent.insert(nouvelle, at: 0)
        if nouvelle == fruit {
            score += 1
            UISelectionFeedbackGenerator().selectionChanged()
            Son.tic()
            placerFruit()
        } else {
            serpent.removeLast()
        }
    }
}

struct EcranSnake: View {
    @StateObject private var partie = PartieSnake()
    @AppStorage("record.snake") private var record = 0

    private let vertClair = Color(red: 0.55, green: 0.9, blue: 0.4)
    private let vertFonce = Color(red: 0.12, green: 0.55, blue: 0.3)

    var body: some View {
        GeometryReader { g in
            let c = min(g.size.width / CGFloat(partie.colonnes), (g.size.height - 18) / CGFloat(partie.lignes))
            let w = c * CGFloat(partie.colonnes), h = c * CGFloat(partie.lignes)
            VStack(spacing: 0) {
                HStack {
                    Label("\(partie.score)", systemImage: "applelogo").font(.system(size: 11, weight: .bold).monospacedDigit())
                    Spacer()
                    Label("\(record)", systemImage: "crown.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(.yellow)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).frame(height: 18)
                plateau(c, w, h)
                    .frame(width: w, height: h)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 12).onEnded { v in
                        let dx = v.translation.width, dy = v.translation.height
                        if abs(dx) > abs(dy) { partie.diriger(dx > 0 ? 1 : -1, 0) } else { partie.diriger(0, dy > 0 ? 1 : -1) }
                    })
                    .onTapGesture { partie.centre() }
                    .overlay { messages }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(LinearGradient(colors: [Color(red: 0.05, green: 0.1, blue: 0.14), Color(red: 0.02, green: 0.04, blue: 0.07)], startPoint: .top, endPoint: .bottom))
        .onChange(of: partie.score) { _, s in if s > record { record = s } }
        .onDisappear { partie.arreter() }
        .roue { g in
            g.tour = { s in partie.tourner(s) }
            g.precedent = { partie.tourner(-1) }
            g.suivant = { partie.tourner(1) }
            g.lecture = { partie.centre() }
            g.centre = { partie.centre() }
        }
    }

    private func plateau(_ c: CGFloat, _ w: CGFloat, _ h: CGFloat) -> some View {
        Canvas { ctx, _ in
            // Damier
            for x in 0..<partie.colonnes {
                for y in 0..<partie.lignes {
                    let r = CGRect(x: CGFloat(x) * c, y: CGFloat(y) * c, width: c, height: c)
                    ctx.fill(Path(r), with: .color((x + y) % 2 == 0 ? Color(red: 0.1, green: 0.2, blue: 0.16) : Color(red: 0.08, green: 0.17, blue: 0.13)))
                }
            }
            // Pomme
            let f = partie.fruit
            let pr = CGRect(x: CGFloat(f.x) * c + c * 0.12, y: CGFloat(f.y) * c + c * 0.18, width: c * 0.76, height: c * 0.76)
            ctx.fill(Path(ellipseIn: pr.insetBy(dx: -c * 0.2, dy: -c * 0.2)), with: .color(Color.red.opacity(0.18)))
            ctx.fill(Path(ellipseIn: pr), with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.45, blue: 0.4), Color(red: 0.8, green: 0.08, blue: 0.1)]),
                                                                 center: CGPoint(x: pr.minX + pr.width * 0.35, y: pr.minY + pr.height * 0.3), startRadius: 0, endRadius: pr.width * 0.8))
            var feuille = Path()
            feuille.addEllipse(in: CGRect(x: pr.midX, y: pr.minY - c * 0.2, width: c * 0.3, height: c * 0.18))
            ctx.fill(feuille, with: .color(vertClair))
            // Serpent, de la queue vers la tête
            let n = partie.serpent.count
            for (i, s) in partie.serpent.enumerated().reversed() {
                let t = n > 1 ? CGFloat(i) / CGFloat(n - 1) : 0
                let r = CGRect(x: CGFloat(s.x) * c, y: CGFloat(s.y) * c, width: c, height: c).insetBy(dx: c * 0.06, dy: c * 0.06)
                let col = Color(red: 0.55 - 0.43 * t, green: 0.9 - 0.35 * t, blue: 0.4 - 0.1 * t)
                if i > 0 {
                    // Relie au segment suivant pour un corps continu
                    let p = partie.serpent[i - 1]
                    let a = CGRect(x: CGFloat(p.x) * c, y: CGFloat(p.y) * c, width: c, height: c).insetBy(dx: c * 0.06, dy: c * 0.06)
                    ctx.fill(Path(roundedRect: r.union(a).insetBy(dx: abs(p.x - s.x) == 1 ? 0 : c * 0.04, dy: abs(p.y - s.y) == 1 ? 0 : c * 0.04), cornerRadius: c * 0.3), with: .color(col))
                }
                ctx.fill(Path(roundedRect: r, cornerRadius: c * (i == 0 ? 0.42 : 0.3)), with: .color(col))
            }
            // Yeux
            if let t = partie.serpent.first {
                let d = partie.serpent.count > 1 ? (t.x - partie.serpent[1].x, t.y - partie.serpent[1].y) : (1, 0)
                let cx = CGFloat(t.x) * c + c / 2, cy = CGFloat(t.y) * c + c / 2
                let (px, py) = (CGFloat(-d.1), CGFloat(d.0))
                for k in [-1.0, 1.0] {
                    let ex = cx + CGFloat(d.0) * c * 0.15 + px * CGFloat(k) * c * 0.2
                    let ey = cy + CGFloat(d.1) * c * 0.15 + py * CGFloat(k) * c * 0.2
                    ctx.fill(Path(ellipseIn: CGRect(x: ex - c * 0.12, y: ey - c * 0.12, width: c * 0.24, height: c * 0.24)), with: .color(.white))
                    ctx.fill(Path(ellipseIn: CGRect(x: ex + CGFloat(d.0) * c * 0.04 - c * 0.06, y: ey + CGFloat(d.1) * c * 0.04 - c * 0.06, width: c * 0.12, height: c * 0.12)), with: .color(.black))
                }
            }
        }
    }

    @ViewBuilder private var messages: some View {
        if partie.etat != .enJeu {
            VStack(spacing: 4) {
                Text(partie.etat == .perdu ? "Perdu !" : (partie.etat == .pause ? "Pause" : "Snake"))
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                if partie.etat == .perdu { Text("Score \(partie.score)").font(.system(size: 12, weight: .semibold)) }
                Text("Molette ou ⏮ ⏭ : tourner\nCentre : \(partie.etat == .pause ? "reprendre" : "jouer")")
                    .font(.system(size: 10)).multilineTextAlignment(.center).opacity(0.85)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.62)))
        }
    }
}
