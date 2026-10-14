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
    private var prochaine = (1, 0)
    private var boucle: Task<Void, Never>?

    init() { reinitialiser() }

    func reinitialiser() {
        serpent = [Case(x: 6, y: 7), Case(x: 5, y: 7), Case(x: 4, y: 7)]
        direction = (1, 0)
        prochaine = (1, 0)
        score = 0
        placerFruit()
    }

    private func placerFruit() {
        var c: Case
        repeat { c = Case(x: Int.random(in: 0..<colonnes), y: Int.random(in: 0..<lignes)) } while serpent.contains(c)
        fruit = c
    }

    /// +1 = tourner à droite, -1 = à gauche (par rapport au sens du serpent).
    func tourner(_ sens: Int) {
        guard etat == .enJeu else { return }
        let (dx, dy) = direction
        prochaine = sens > 0 ? (-dy, dx) : (dy, -dx)
    }

    /// Glisser sur l'écran : direction absolue.
    func diriger(_ dx: Int, _ dy: Int) {
        guard etat == .enJeu, (dx, dy) != (-direction.0, -direction.1) else { return }
        prochaine = (dx, dy)
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
                let attente = max(70, 170 - (self?.score ?? 0) * 3)
                try? await Task.sleep(for: .milliseconds(attente))
                guard let self, self.etat == .enJeu, !Task.isCancelled else { return }
                self.pas()
            }
        }
    }

    private func pas() {
        direction = prochaine
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

    var body: some View {
        GeometryReader { g in
            let c = min(g.size.width / CGFloat(partie.colonnes), (g.size.height - 16) / CGFloat(partie.lignes))
            let w = c * CGFloat(partie.colonnes), h = c * CGFloat(partie.lignes)
            VStack(spacing: 0) {
                HStack {
                    Text("Score \(partie.score)").font(.system(size: 11, weight: .bold).monospacedDigit())
                    Spacer()
                    Text("Record \(record)").font(.system(size: 10))
                }
                .padding(.horizontal, 6).frame(height: 16)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color(red: 0.78, green: 0.84, blue: 0.62))
                    ForEach(Array(partie.serpent.enumerated()), id: \.offset) { i, s in
                        RoundedRectangle(cornerRadius: i == 0 ? c * 0.35 : c * 0.2)
                            .fill(Color(red: 0.12, green: 0.2, blue: 0.1).opacity(i == 0 ? 1 : 0.85))
                            .frame(width: c - 1, height: c - 1)
                            .offset(x: CGFloat(s.x) * c, y: CGFloat(s.y) * c)
                    }
                    Circle().fill(Color(red: 0.75, green: 0.12, blue: 0.1))
                        .frame(width: c * 0.8, height: c * 0.8)
                        .offset(x: CGFloat(partie.fruit.x) * c + c * 0.1, y: CGFloat(partie.fruit.y) * c + c * 0.1)
                    if partie.etat != .enJeu {
                        VStack(spacing: 3) {
                            Text(partie.etat == .perdu ? "Perdu !" : (partie.etat == .pause ? "Pause" : "Snake"))
                                .font(.system(size: 18, weight: .heavy))
                            Text("Molette : tourner · Centre : \(partie.etat == .pause ? "reprendre" : "jouer")")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(Color(red: 0.12, green: 0.2, blue: 0.1))
                        .frame(width: w, height: h)
                    }
                }
                .frame(width: w, height: h)
                .clipped()
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 12).onEnded { v in
                    let dx = v.translation.width, dy = v.translation.height
                    if abs(dx) > abs(dy) { partie.diriger(dx > 0 ? 1 : -1, 0) } else { partie.diriger(0, dy > 0 ? 1 : -1) }
                })
                .onTapGesture { partie.centre() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(red: 0.7, green: 0.76, blue: 0.55))
        .onChange(of: partie.score) { _, s in if s > record { record = s } }
        .onDisappear { partie.arreter() }
        .roue { g in
            g.tour = { s in partie.tourner(s) }
            g.centre = { partie.centre() }
        }
    }
}
