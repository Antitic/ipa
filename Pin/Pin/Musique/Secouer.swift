import SwiftUI
import UIKit

extension Notification.Name {
    static let pinSecoue = Notification.Name("pin.secoue")
}

/// iOS signale la secousse à la fenêtre ; on la relaie à SwiftUI.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .pinSecoue, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}

/// Secouer l'iPhone = Shuffle : toute ta musique en ordre aléatoire, comme
/// l'iPod nano. Ignoré pendant la saisie (le clavier Pin est ouvert).
struct ShuffleSecousse: ViewModifier {
    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var lecteur: Lecteur
    @EnvironmentObject var compte: Compte
    @EnvironmentObject var clavier: Clavier
    @AppStorage("haptique") private var haptique = true
    @State private var enCours = false

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .pinSecoue)) { _ in
            guard compte.connecte, !clavier.actif, !enCours else { return }
            enCours = true
            Task {
                defer { enCours = false }
                guard let morceaux = try? await API.get("/api/musique", [Morceau].self), !morceaux.isEmpty else { return }
                if haptique { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                lecteur.jouer(morceaux.shuffled(), depuis: 0)
                if nav.courant != .enLecture { nav.ouvrir(.enLecture) }
            }
        }
    }
}
