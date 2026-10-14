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
    private(set) var temps: Double = 0
    private var feu = false
    private var dernierTir = Date.distantPast

    let canon = CGPoint(x: 0.5, y: 0.9)

    func tourner(_ s: Int) { angle = min(max(angle + Double(s) * 6, -80), 80) }
    /// ⏮ ⏭ : grand coup de canon d'un côté ou de l'autre.
    func pivoter(_ s: Int) { angle = min(max(angle + Double(s) * 20, -80), 80) }
    /// Centre maintenu : tir continu.
    func tirContinu(_ on: Bool) { feu = on && etat == .enJeu }

    func centre() {
        switch etat {
        case .pret: etat = .enJeu; demarrer()
        case .perdu:
            helicos = []; paras = []; obus = []; poses = []; score = 0; temps = 0; prochainHelico = 0; feu = false
            etat = .enJeu; demarrer()
        case .enJeu: tirer()
        }
    }

    private func tirer() {
        guard Date().timeIntervalSince(dernierTir) > 0.16 else { return }
        dernierTir = Date()
        let a = angle * .pi / 180
        let v: CGFloat = 1.1
        obus.append(Obus(x: canon.x + CGFloat(sin(a)) * 0.06, y: canon.y - CGFloat(cos(a)) * 0.06,
                         vx: CGFloat(sin(a)) * v, vy: -CGFloat(cos(a)) * v))
        Son.tic()
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
        if feu { tirer() }
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
                feu = false
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

    private let etoiles: [(CGFloat, CGFloat, CGFloat)] = (0..<26).map { i in
        let f = CGFloat(i)
        return (fmod(f * 0.6180339, 1), fmod(f * 0.3819660 + 0.1, 1) * 0.55, 0.6 + fmod(f * 0.37, 1))
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Canvas { ctx, size in dessiner(&ctx, w: size.width, h: size.height) }
                HStack {
                    Text("\(partie.score)").font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                    Spacer()
                    HStack(spacing: 3) {
                        ForEach(0..<partie.maxPoses, id: \.self) { i in
                            Image(systemName: "figure.stand").font(.system(size: 9))
                                .foregroundStyle(i < partie.poses.count ? Color.red : Color.white.opacity(0.3))
                        }
                    }
                }
                .foregroundStyle(.white).padding(.horizontal, 8).padding(.top, 4)
                .frame(maxHeight: .infinity, alignment: .top)
                if partie.etat != .enJeu {
                    VStack(spacing: 4) {
                        Text(partie.etat == .perdu ? "Envahi !" : "Parachute").font(.system(size: 22, weight: .heavy, design: .rounded))
                        if partie.etat == .perdu { Text("Score \(partie.score) · Record \(record)").font(.system(size: 11, weight: .semibold)) }
                        Text("Molette ou ⏮ ⏭ : viser\nCentre : tirer (maintenu : tir continu)")
                            .font(.system(size: 10)).multilineTextAlignment(.center).opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.black.opacity(0.6)))
                }
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .onTapGesture { partie.centre() }
        }
        .onChange(of: partie.score) { _, s in if s > record { record = s } }
        .onDisappear { partie.arreter() }
        .roue { g in
            g.tour = { s in partie.tourner(s) }
            g.precedent = { partie.pivoter(-1) }
            g.suivant = { partie.pivoter(1) }
            g.centre = { partie.centre() }
            g.centreMaintenu = { partie.tirContinu(true) }
            g.centreRelache = { partie.tirContinu(false) }
        }
    }

    private func dessiner(_ ctx: inout GraphicsContext, w: CGFloat, h: CGFloat) {
        // Ciel de nuit et lune
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: .linearGradient(Gradient(colors: [Color(red: 0.03, green: 0.05, blue: 0.16), Color(red: 0.28, green: 0.25, blue: 0.5), Color(red: 0.85, green: 0.5, blue: 0.4)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h * 0.92)))
        for (x, y, r) in etoiles {
            ctx.fill(Path(ellipseIn: CGRect(x: x * w, y: y * h, width: r, height: r)), with: .color(.white.opacity(0.8)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: w * 0.8, y: h * 0.1, width: 18, height: 18)), with: .color(Color(red: 1, green: 0.96, blue: 0.8)))
        // Collines et sol
        var col = Path()
        col.move(to: CGPoint(x: 0, y: h))
        col.addLine(to: CGPoint(x: 0, y: h * 0.86))
        col.addQuadCurve(to: CGPoint(x: w * 0.5, y: h * 0.9), control: CGPoint(x: w * 0.22, y: h * 0.8))
        col.addQuadCurve(to: CGPoint(x: w, y: h * 0.85), control: CGPoint(x: w * 0.78, y: h * 0.82))
        col.addLine(to: CGPoint(x: w, y: h))
        ctx.fill(col, with: .color(Color(red: 0.08, green: 0.16, blue: 0.14)))
        ctx.fill(Path(CGRect(x: 0, y: h * 0.92, width: w, height: h * 0.08)), with: .color(Color(red: 0.14, green: 0.3, blue: 0.16)))
        ctx.fill(Path(CGRect(x: 0, y: h * 0.92, width: w, height: 2)), with: .color(Color(red: 0.4, green: 0.65, blue: 0.3)))
        // Hélicoptères
        for hl in partie.helicos {
            let dir: CGFloat = hl.vx > 0 ? 1 : -1
            let x = hl.x * w, y = hl.y * h
            let corps = CGRect(x: x - 11, y: y - 5, width: 22, height: 11)
            ctx.fill(Path(ellipseIn: corps), with: .color(Color(red: 0.25, green: 0.4, blue: 0.3)))
            ctx.fill(Path(ellipseIn: CGRect(x: x + dir * 3 - 4, y: y - 4, width: 9, height: 6)), with: .color(Color(red: 0.7, green: 0.9, blue: 1).opacity(0.9)))
            var queue = Path()
            queue.move(to: CGPoint(x: x - dir * 8, y: y))
            queue.addLine(to: CGPoint(x: x - dir * 20, y: y - 4))
            ctx.stroke(queue, with: .color(Color(red: 0.25, green: 0.4, blue: 0.3)), lineWidth: 3)
            let r = 15 * abs(cos(hl.x * 70))
            var rotor = Path()
            rotor.move(to: CGPoint(x: x - r - 4, y: y - 7)); rotor.addLine(to: CGPoint(x: x + r + 4, y: y - 7))
            ctx.stroke(rotor, with: .color(.white.opacity(0.8)), lineWidth: 1.5)
            var patin = Path()
            patin.move(to: CGPoint(x: x - 8, y: y + 8)); patin.addLine(to: CGPoint(x: x + 8, y: y + 8))
            ctx.stroke(patin, with: .color(.white.opacity(0.7)), lineWidth: 1)
        }
        // Parachutistes
        for p in partie.paras {
            let x = p.x * w, y = p.y * h
            if p.ouvert {
                var toile = Path()
                toile.addArc(center: CGPoint(x: x, y: y - 6), radius: 9, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                toile.closeSubpath()
                ctx.fill(toile, with: .color(Color(red: 1, green: 0.55, blue: 0.15)))
                for dx in [-9.0, 0.0, 9.0] {
                    var corde = Path(); corde.move(to: CGPoint(x: x + dx, y: y - 6)); corde.addLine(to: CGPoint(x: x, y: y + 1))
                    ctx.stroke(corde, with: .color(.white.opacity(0.6)), lineWidth: 0.5)
                }
            }
            ctx.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 1, width: 4, height: 4)), with: .color(.white))
            ctx.fill(Path(CGRect(x: x - 1.5, y: y + 3, width: 3, height: 5)), with: .color(.white))
        }
        for x in partie.poses {
            let px = x * w, py = h * 0.915
            ctx.fill(Path(ellipseIn: CGRect(x: px - 2, y: py - 8, width: 4, height: 4)), with: .color(.red))
            ctx.fill(Path(CGRect(x: px - 1.5, y: py - 4, width: 3, height: 5)), with: .color(.red))
        }
        // Obus avec traînée
        for o in partie.obus {
            let ox = o.x * w, oy = o.y * h
            var tr = Path(); tr.move(to: CGPoint(x: ox, y: oy)); tr.addLine(to: CGPoint(x: ox - o.vx * w * 0.04, y: oy - o.vy * h * 0.04))
            ctx.stroke(tr, with: .color(.yellow.opacity(0.4)), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: ox - 2, y: oy - 2, width: 4, height: 4)), with: .color(Color(red: 1, green: 0.95, blue: 0.5)))
        }
        // Canon : le fût pivote autour de sa base
        let bx = partie.canon.x * w, by = partie.canon.y * h
        var c2 = ctx
        c2.translateBy(x: bx, y: by)
        c2.rotate(by: .degrees(partie.angle))
        c2.fill(Path(roundedRect: CGRect(x: -3.5, y: -h * 0.1, width: 7, height: h * 0.1), cornerRadius: 2), with: .color(Color(white: 0.82)))
        c2.fill(Path(CGRect(x: -4.5, y: -h * 0.1, width: 9, height: 3)), with: .color(Color(white: 0.55)))
        ctx.fill(Path(ellipseIn: CGRect(x: bx - 12, y: by - 10, width: 24, height: 20)), with: .linearGradient(Gradient(colors: [Color(white: 0.8), Color(white: 0.45)]), startPoint: CGPoint(x: bx, y: by - 10), endPoint: CGPoint(x: bx, y: by + 10)))
    }
}
