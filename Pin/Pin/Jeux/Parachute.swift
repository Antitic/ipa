import SwiftUI

/// Parachute : la molette oriente le canon, le centre tire. Abats les
/// hélicoptères et les parachutistes avant que 5 ne touchent le sol.
@MainActor
final class PartieParachute: ObservableObject {
    struct Helico: Identifiable { let id = UUID(); var x: CGFloat; let y: CGFloat; let vx: CGFloat; var largage: Double }
    struct Para: Identifiable { let id = UUID(); var x: CGFloat; var y: CGFloat; var ouvert: Bool }
    struct Obus: Identifiable { let id = UUID(); var x: CGFloat; var y: CGFloat; let vx: CGFloat; let vy: CGFloat }
    enum Etat { case pret, enJeu, perdu }

    @Published var angle: Double = 0          // -80…80 degrés
    @Published var helicos: [Helico] = []
    @Published var paras: [Para] = []
    @Published var obus: [Obus] = []
    @Published var poses: [CGFloat] = []      // x des parachutistes posés
    @Published var score = 0
    @Published var etat: Etat = .pret
    let maxPoses = 5
    private var boucle: Task<Void, Never>?
    private var prochainHelico: Double = 0
    private var temps: Double = 0
    private var dernierTir = Date.distantPast

    let canon = CGPoint(x: 0.5, y: 0.9)

    func tourner(_ s: Int) { angle = min(max(angle + Double(s) * 6, -80), 80) }

    func centre() {
        switch etat {
        case .pret: etat = .enJeu; demarrer()
        case .perdu:
            helicos = []; paras = []; obus = []; poses = []; score = 0; temps = 0; prochainHelico = 0
            etat = .enJeu; demarrer()
        case .enJeu: tirer()
        }
    }

    private func tirer() {
        guard Date().timeIntervalSince(dernierTir) > 0.18 else { return }
        dernierTir = Date()
        let a = angle * .pi / 180
        let v: CGFloat = 1.1
        obus.append(Obus(x: canon.x + CGFloat(sin(a)) * 0.06, y: canon.y - CGFloat(cos(a)) * 0.06,
                         vx: CGFloat(sin(a)) * v, vy: -CGFloat(cos(a)) * v))
        Son.tic()
        score = max(0, score - 1)
    }

    func arreter() { boucle?.cancel() }

    private func demarrer() {
        boucle?.cancel()
        boucle = Task { @MainActor [weak self] in
            var avant = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let maintenant = Date()
                let dt = min(maintenant.timeIntervalSince(avant), 0.05)
                avant = maintenant
                guard let self, self.etat == .enJeu else { return }
                self.pas(dt)
            }
        }
    }

    private func pas(_ dt: Double) {
        temps += dt
        let d = CGFloat(dt)
        // Nouveaux hélicoptères, de plus en plus souvent
        if temps >= prochainHelico {
            let gauche = Bool.random()
            helicos.append(Helico(x: gauche ? -0.1 : 1.1, y: CGFloat.random(in: 0.08...0.22),
                                  vx: (gauche ? 1 : -1) * CGFloat.random(in: 0.12...0.2),
                                  largage: Double.random(in: 0.6...2.2)))
            prochainHelico = temps + max(0.9, 2.6 - temps / 40)
        }
        for i in helicos.indices {
            helicos[i].x += helicos[i].vx * d
            helicos[i].largage -= dt
            if helicos[i].largage <= 0, helicos[i].x > 0.05, helicos[i].x < 0.95, abs(helicos[i].x - 0.5) > 0.08 {
                paras.append(Para(x: helicos[i].x, y: helicos[i].y + 0.04, ouvert: false))
                helicos[i].largage = Double.random(in: 1.5...3.5)
            }
        }
        helicos.removeAll { $0.x < -0.15 || $0.x > 1.15 }
        // Parachutistes : chute libre puis parachute ouvert
        for i in paras.indices {
            if !paras[i].ouvert && paras[i].y > 0.32 { paras[i].ouvert = true }
            paras[i].y += (paras[i].ouvert ? 0.09 : 0.3) * d
        }
        let poses = paras.filter { $0.y >= 0.92 }
        if !poses.isEmpty {
            self.poses.append(contentsOf: poses.map(\.x))
            paras.removeAll { $0.y >= 0.92 }
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            if self.poses.count >= maxPoses {
                etat = .perdu
                boucle?.cancel()
                return
            }
        }
        // Obus et collisions
        for i in obus.indices { obus[i].x += obus[i].vx * d; obus[i].y += obus[i].vy * d }
        var touches = Set<UUID>()
        for o in obus {
            if let h = helicos.first(where: { abs($0.x - o.x) < 0.06 && abs($0.y - o.y) < 0.03 }) {
                helicos.removeAll { $0.id == h.id }; touches.insert(o.id); score += 10
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else if let p = paras.first(where: { abs($0.x - o.x) < 0.03 && abs($0.y - o.y) < ($0.ouvert ? 0.045 : 0.025) }) {
                paras.removeAll { $0.id == p.id }; touches.insert(o.id); score += 5
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        obus.removeAll { touches.contains($0.id) || $0.y < -0.05 || $0.x < -0.05 || $0.x > 1.05 }
    }
}

struct EcranParachute: View {
    @StateObject private var partie = PartieParachute()
    @AppStorage("record.parachute") private var record = 0

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(red: 0.05, green: 0.08, blue: 0.2), Color(red: 0.15, green: 0.2, blue: 0.38)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(Color(red: 0.25, green: 0.4, blue: 0.2)).frame(height: h * 0.08).offset(y: h * 0.92)
                ForEach(partie.helicos) { hl in
                    Image(systemName: "airplane").rotationEffect(.degrees(hl.vx > 0 ? 0 : 180))
                        .font(.system(size: 20)).foregroundStyle(.white)
                        .position(x: hl.x * w, y: hl.y * h)
                }
                ForEach(partie.paras) { p in
                    VStack(spacing: 0) {
                        if p.ouvert { Image(systemName: "umbrella.fill").font(.system(size: 14)).foregroundStyle(.orange) }
                        Image(systemName: "figure.stand").font(.system(size: 11)).foregroundStyle(.white)
                    }
                    .position(x: p.x * w, y: p.y * h)
                }
                ForEach(Array(partie.poses.enumerated()), id: \.offset) { _, x in
                    Image(systemName: "figure.stand").font(.system(size: 11)).foregroundStyle(.yellow)
                        .position(x: x * w, y: h * 0.905)
                }
                ForEach(partie.obus) { o in
                    Circle().fill(.yellow).frame(width: 4, height: 4).position(x: o.x * w, y: o.y * h)
                }
                // Canon
                ZStack {
                    Capsule().fill(Color(white: 0.85)).frame(width: 6, height: h * 0.09).offset(y: -h * 0.045)
                        .rotationEffect(.degrees(partie.angle), anchor: .center)
                    Circle().fill(Color(white: 0.7)).frame(width: 22, height: 22)
                }
                .position(x: partie.canon.x * w, y: partie.canon.y * h)
                HStack {
                    Text("\(partie.score)").font(.system(size: 11, weight: .bold).monospacedDigit())
                    Spacer()
                    Text("Posés \(partie.poses.count)/\(partie.maxPoses)").font(.system(size: 10))
                }
                .foregroundStyle(.white).padding(.horizontal, 6).padding(.top, 3)
                if partie.etat != .enJeu {
                    VStack(spacing: 3) {
                        Text(partie.etat == .perdu ? "Envahi !" : "Parachute").font(.system(size: 18, weight: .heavy))
                        if partie.etat == .perdu { Text("Score \(partie.score) · Record \(record)").font(.system(size: 11)) }
                        Text("Molette : viser · Centre : tirer").font(.system(size: 10)).opacity(0.8)
                    }
                    .foregroundStyle(.white)
                    .position(x: w / 2, y: h * 0.5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { partie.centre() }
        }
        .onChange(of: partie.score) { _, s in if s > record { record = s } }
        .onDisappear { partie.arreter() }
        .roue { g in
            g.tour = { s in partie.tourner(s) }
            g.centre = { partie.centre() }
        }
    }
}
