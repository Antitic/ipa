import SwiftUI

/// Les écrans de l'iPod. Un seul est affiché : celui du haut de la pile.
enum Ecran: Hashable {
    case menu
    case musique, enLecture
    case whatsapp, liaisonWhatsApp
    case conversation(jid: String, nom: String)
    case imageWhatsApp(id: String)
    case photos, camera, pellicule
    case photo(index: Int)
    case choixDiscussion(assetId: String)
    case claude
    case discussionClaude(uuid: String, nom: String)
    case connexionClaude
    case reglages, connexion, telegram

    var titre: String {
        switch self {
        case .menu: return "Pin"
        case .musique: return "Musique"
        case .enLecture: return "En lecture"
        case .whatsapp, .liaisonWhatsApp: return "WhatsApp"
        case .conversation(_, let nom): return nom
        case .imageWhatsApp: return "Photo"
        case .photos: return "Photos"
        case .camera: return "Appareil photo"
        case .pellicule: return "Pellicule"
        case .photo: return "Photo"
        case .choixDiscussion: return "Envoyer à"
        case .claude: return "Claude"
        case .discussionClaude(_, let nom): return nom
        case .connexionClaude: return "claude.ai"
        case .reglages: return "Réglages"
        case .connexion: return "Compte Pin"
        case .telegram: return "Telegram"
        }
    }
}

/// Ce que l'écran affiché fait des commandes de la molette.
/// Chaque écran remplit le sien quand il apparaît (modificateur `.roue`).
final class GestionnaireRoue {
    var tour: ((Int) -> Void)?
    var centre: (() -> Void)?
    var centreMaintenu: (() -> Void)?
    var centreRelache: (() -> Void)?
    /// Renvoie true si l'écran a géré MENU lui-même (sinon : retour).
    var menu: (() -> Bool)?
    var precedent: (() -> Void)?
    var suivant: (() -> Void)?
    var lecture: (() -> Void)?
}

@MainActor
final class Navigateur: ObservableObject {
    @Published private(set) var pile: [Ecran] = [.menu]
    @Published private(set) var versAvant = true
    var gestionnaire = GestionnaireRoue()
    /// Ligne sélectionnée par écran, pour la retrouver en revenant en arrière.
    var selections: [Ecran: Int] = [:]

    var courant: Ecran { pile.last ?? .menu }

    func ouvrir(_ e: Ecran) {
        versAvant = true
        withAnimation(.easeInOut(duration: 0.22)) { pile.append(e) }
    }

    func retour() {
        guard pile.count > 1 else { return }
        versAvant = false
        withAnimation(.easeInOut(duration: 0.22)) { _ = pile.removeLast() }
    }

    func remplacer(_ e: Ecran) {
        versAvant = true
        withAnimation(.easeInOut(duration: 0.22)) {
            _ = pile.popLast()
            pile.append(e)
        }
    }

    func accueil() {
        guard pile.count > 1 else { return }
        versAvant = false
        withAnimation(.easeInOut(duration: 0.22)) { pile = [.menu] }
    }
}

private struct RoueModifier: ViewModifier {
    @EnvironmentObject var nav: Navigateur
    let config: (GestionnaireRoue) -> Void

    func body(content: Content) -> some View {
        content.onAppear {
            let g = GestionnaireRoue()
            config(g)
            nav.gestionnaire = g
        }
    }
}

extension View {
    /// Branche la molette sur cet écran tant qu'il est affiché.
    func roue(_ config: @escaping (GestionnaireRoue) -> Void) -> some View {
        modifier(RoueModifier(config: config))
    }
}
