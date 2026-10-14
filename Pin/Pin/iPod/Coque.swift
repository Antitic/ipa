import SwiftUI

/// Le boîtier : écran en haut, molette en bas, comme un iPod classic.
struct Coque: View {
    @EnvironmentObject var clavier: Clavier

    var body: some View {
        GeometryReader { g in
            // La vue ignore la zone sûre (le boîtier va jusqu'aux bords), donc
            // g.safeAreaInsets vaut 0 : on lit les marges réelles de la fenêtre
            // pour que l'écran passe sous l'encoche (47 pt sur iPhone 13).
            let marges = MargesFenetre.actuelles
            let haut = MargesFenetre.haut(marges) + 10
            let bas = max(marges.bottom, 6)
            let largeur = g.size.width
            let marge: CGFloat = 18
            let disponible = g.size.height - haut
            let hauteurEcran = min(disponible * 0.52, (largeur - marge * 2) * 1.05)
            let cote = max(120, min(largeur * 0.78, disponible - hauteurEcran - bas - 24))
            VStack(spacing: 0) {
                EcranIPod()
                    .frame(height: hauteurEcran)
                    .padding(.horizontal, marge)
                    .padding(.top, haut)
                ZStack {
                    if clavier.actif {
                        // Le clavier Pin prend la place de la molette.
                        ClavierIPod()
                            .padding(.bottom, bas)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        Molette()
                            .frame(width: cote, height: cote)
                            .padding(.bottom, bas / 2)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Boitier())
        }
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .ignoresSafeArea(.keyboard)
    }
}

/// Les marges de sécurité de la fenêtre (encoche, barre d'accueil).
enum MargesFenetre {
    @MainActor static var actuelles: UIEdgeInsets {
        let fenetres = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return (fenetres.first(where: \.isKeyWindow) ?? fenetres.first)?.safeAreaInsets ?? .zero
    }

    /// Marge du haut. Si la fenêtre annonce une marge trop petite (barre d'état
    /// masquée, app lancée dans LiveContainer…) alors que l'iPhone a une barre
    /// d'accueil, c'est qu'il a une encoche ou une Dynamic Island : 47 pt au moins.
    @MainActor static func haut(_ m: UIEdgeInsets) -> CGFloat {
        // Tous les iPhone à encoche font au moins 812 pt de haut ; les autres (SE, 8) moins.
        if m.bottom > 0 || UIScreen.main.bounds.height >= 812 { return max(m.top, 47) }
        return max(m.top, 20)
    }
}

/// Façade blanche légèrement brossée, avec un reflet en haut.
struct Boitier: View {
    @Environment(\.skin) private var skin

    var body: some View {
        ZStack {
            LinearGradient(colors: skin.facade, startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.white.opacity(skin.reflet), .clear], startPoint: .top, endPoint: .center)
                .blendMode(.screen)
        }
        .ignoresSafeArea()
    }
}

/// L'écran de l'iPod : un cadre sombre, l'en-tête, puis l'écran courant.
struct EcranIPod: View {
    @EnvironmentObject var nav: Navigateur

    var body: some View {
        VStack(spacing: 0) {
            Entete(titre: nav.courant.titre)
            ZStack {
                Color.white
                vue(pour: nav.courant)
                    .id(nav.pile.count.description + "\(nav.courant.hashValue)")
                    .transition(.asymmetric(
                        insertion: .move(edge: nav.versAvant ? .trailing : .leading),
                        removal: .move(edge: nav.versAvant ? .leading : .trailing)))
            }
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)], startPoint: .top, endPoint: .bottom))
        )
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }

    @ViewBuilder
    private func vue(pour e: Ecran) -> some View {
        switch e {
        case .menu: MenuPrincipal()
        case .musique: EcranMorceaux()
        case .coverFlow: EcranCoverFlow()
        case .ajoutMusique: EcranAjoutMusique()
        case .enLecture: EcranEnLecture()
        case .whatsapp: EcranDiscussions()
        case .liaisonWhatsApp: EcranLiaisonWhatsApp()
        case .conversation(let jid, let nom): EcranConversation(jid: jid, nom: nom)
        case .imageWhatsApp(let id): EcranImageWhatsApp(id: id)
        case .stickers(let jid): EcranStickers(jid: jid)
        case .vuPar(let id): EcranVuPar(id: id)
        case .audioWhatsApp(let jid): EcranAudioWhatsApp(jid: jid)
        case .photos: MenuPhotos()
        case .camera: EcranCamera()
        case .pellicule: EcranPellicule()
        case .photo(let index): EcranPhoto(indexDepart: index)
        case .choixDiscussion(let assetId): EcranChoixDiscussion(assetId: assetId)
        case .claude: EcranClaude()
        case .discussionClaude(let uuid, let nom): EcranDiscussionClaude(uuidDepart: uuid, nom: nom)
        case .connexionClaude: EcranConnexionClaude()
        case .reglages: EcranReglages()
        case .connexion: EcranConnexion()
        case .telegram: EcranTelegram()
        case .mail: EcranMail()
        case .skins: EcranSkins()
        case .meteo: EcranMeteo()
        case .meteoJour(let i): EcranMeteoJour(index: i)
        case .jeux: MenuJeux()
        case .brick: EcranBrick()
        case .musicQuiz: EcranMusicQuiz()
        case .parachute: EcranParachute()
        case .solitaire: EcranSolitaire()
        case .snake: EcranSnake()
        case .boiteMail(let path, _): EcranBoiteMail(path: path)
        case .lettreMail(let box, let uid): EcranLettreMail(box: box, uid: uid)
        case .ecrireMail(let r): EcranEcrireMail(reponse: r)
        }
    }
}

/// La barre de titre : lecture en cours à gauche, titre au centre, batterie à droite.
struct Entete: View {
    let titre: String
    @EnvironmentObject var lecteur: Lecteur
    @State private var batterie = UIDevice.current.batteryLevel
    @State private var heure = Date()
    private let minuteur = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Text(titre)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 54)
            HStack(spacing: 4) {
                if lecteur.courant != nil {
                    Image(systemName: lecteur.enLecture ? "play.fill" : "pause.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 0.2, green: 0.45, blue: 0.85))
                } else {
                    Text(heure, format: .dateTime.hour().minute())
                        .font(.system(size: 11, weight: .medium))
                }
                Spacer()
                IconeBatterie(niveau: batterie)
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 24)
        .foregroundStyle(.black)
        .background(
            LinearGradient(colors: [Color(white: 0.98), Color(white: 0.84)], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) { Rectangle().fill(Color(white: 0.6)).frame(height: 0.5) }
        .onReceive(minuteur) { _ in
            heure = Date()
            batterie = UIDevice.current.batteryLevel
        }
    }
}

struct IconeBatterie: View {
    let niveau: Float

    var body: some View {
        let n = niveau < 0 ? 1 : CGFloat(niveau)
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).stroke(Color(white: 0.3), lineWidth: 1)
                RoundedRectangle(cornerRadius: 1)
                    .fill(n < 0.2 ? Color.red : Color(red: 0.35, green: 0.75, blue: 0.3))
                    .frame(width: max(2, 18 * n))
                    .padding(1.5)
            }
            .frame(width: 22, height: 10)
            Rectangle().fill(Color(white: 0.3)).frame(width: 1.5, height: 4)
        }
    }
}
