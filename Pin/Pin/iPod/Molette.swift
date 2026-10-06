import SwiftUI
import UIKit

/// La molette cliquable. Tourner le doigt = défiler (un cran tous les 18°,
/// avec un retour haptique), toucher le haut = MENU, la droite = ⏭, la gauche
/// = ⏮, le bas = ⏯. Le bouton central valide ; maintenu, il déclenche
/// l'action longue de l'écran (vocal WhatsApp). MENU maintenu = accueil.
struct Molette: View {
    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var lecteur: Lecteur
    @AppStorage("haptique") private var haptique = true

    @State private var dernierAngle: Double?
    @State private var cumul: Double = 0
    @State private var parcours: Double = 0
    @State private var debutTouche: Date?
    @State private var pointDepart: CGPoint = .zero

    @State private var appuiCentre: Date?
    @State private var maintenu = false
    @State private var minuteurMaintien: Task<Void, Never>?
    @State private var centreEnfonce = false

    private let cran = Double.pi / 10
    private let tic = UISelectionFeedbackGenerator()
    private let clic = UIImpactFeedbackGenerator(style: .light)
    private let lourd = UIImpactFeedbackGenerator(style: .heavy)

    var body: some View {
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            ZStack {
                anneau(d)
                    .contentShape(Circle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in tourne(v, rayon: d / 2) }
                            .onEnded { v in fini(v, rayon: d / 2) }
                    )
                boutonCentre(d * 0.38)
            }
            .frame(width: d, height: d)
            .position(x: g.size.width / 2, y: g.size.height / 2)
        }
    }

    // MARK: - Dessin

    private func anneau(_ d: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().stroke(Color(white: 0.78), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
            Group {
                Text("MENU")
                    .font(.system(size: d * 0.055, weight: .bold))
                    .offset(y: -d * 0.39)
                Image(systemName: "forward.end.alt.fill")
                    .font(.system(size: d * 0.05))
                    .offset(x: d * 0.39)
                Image(systemName: "backward.end.alt.fill")
                    .font(.system(size: d * 0.05))
                    .offset(x: -d * 0.39)
                Image(systemName: "playpause.fill")
                    .font(.system(size: d * 0.05))
                    .offset(y: d * 0.39)
            }
            .foregroundStyle(Color(white: 0.62))
        }
        .frame(width: d, height: d)
    }

    private func boutonCentre(_ d: CGFloat) -> some View {
        Circle()
            .fill(LinearGradient(colors: centreEnfonce ? [Color(white: 0.86), Color(white: 0.93)] : [Color(white: 0.99), Color(white: 0.9)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Circle().stroke(Color(white: 0.76), lineWidth: 1))
            .shadow(color: .black.opacity(centreEnfonce ? 0.02 : 0.1), radius: 2, y: 1)
            .frame(width: d, height: d)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in appuieCentre() }
                    .onEnded { _ in relacheCentre() }
            )
    }

    // MARK: - Anneau

    private func angle(_ p: CGPoint, rayon: CGFloat) -> Double {
        atan2(Double(p.y - rayon), Double(p.x - rayon))
    }

    private func tourne(_ v: DragGesture.Value, rayon: CGFloat) {
        if debutTouche == nil {
            debutTouche = Date()
            pointDepart = v.startLocation
            parcours = 0
            cumul = 0
            dernierAngle = nil
        }
        let distanceCentre = hypot(v.location.x - rayon, v.location.y - rayon)
        guard distanceCentre > rayon * 0.2 else { return }
        let a = angle(v.location, rayon: rayon)
        if let precedent = dernierAngle {
            var delta = a - precedent
            if delta > .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            cumul += delta
            parcours += abs(delta)
            while cumul >= cran { cumul -= cran; cranFranchi(1) }
            while cumul <= -cran { cumul += cran; cranFranchi(-1) }
        }
        dernierAngle = a
    }

    private func cranFranchi(_ sens: Int) {
        if haptique { tic.selectionChanged() }
        nav.gestionnaire.tour?(sens)
    }

    private func fini(_ v: DragGesture.Value, rayon: CGFloat) {
        let duree = Date().timeIntervalSince(debutTouche ?? Date())
        defer { debutTouche = nil; dernierAngle = nil }
        let deplacement = hypot(v.translation.width, v.translation.height)
        guard parcours < 0.2, deplacement < 14 else { return }

        // Un toucher : quelle zone ?
        let a = angle(pointDepart, rayon: rayon) * 180 / .pi   // 0 = droite, 90 = bas
        if haptique { clic.impactOccurred() }
        switch a {
        case -135 ..< -45:
            if duree > 0.6 { nav.accueil() } else { menu() }
        case -45 ..< 45:
            if let s = nav.gestionnaire.suivant { s() } else { lecteur.suivant() }
        case 45 ..< 135:
            if let l = nav.gestionnaire.lecture { l() } else { lecteur.basculer() }
        default:
            if let p = nav.gestionnaire.precedent { p() } else { lecteur.precedent() }
        }
    }

    private func menu() {
        if nav.gestionnaire.menu?() == true { return }
        nav.retour()
    }

    // MARK: - Bouton central

    private func appuieCentre() {
        guard appuiCentre == nil else { return }
        appuiCentre = Date()
        maintenu = false
        centreEnfonce = true
        minuteurMaintien?.cancel()
        guard nav.gestionnaire.centreMaintenu != nil else { return }
        minuteurMaintien = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, appuiCentre != nil else { return }
            maintenu = true
            if haptique { lourd.impactOccurred() }
            nav.gestionnaire.centreMaintenu?()
        }
    }

    private func relacheCentre() {
        minuteurMaintien?.cancel()
        centreEnfonce = false
        appuiCentre = nil
        if maintenu {
            maintenu = false
            nav.gestionnaire.centreRelache?()
        } else {
            if haptique { clic.impactOccurred() }
            nav.gestionnaire.centre?()
        }
    }
}
