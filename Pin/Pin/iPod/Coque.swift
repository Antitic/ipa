import SwiftUI

/// Le boîtier : écran en haut, molette en bas, comme un iPod classic.
struct Coque: View {
    var body: some View {
        GeometryReader { g in
            let largeur = g.size.width
            let marge: CGFloat = 18
            let hauteurEcran = min(g.size.height * 0.5, (largeur - marge * 2) * 1.05)
            VStack(spacing: 0) {
                EcranIPod()
                    .frame(height: hauteurEcran)
                    .padding(.horizontal, marge)
                    .padding(.top, max(g.safeAreaInsets.top, 14))
                Spacer(minLength: 12)
                Molette()
                    .frame(width: min(largeur * 0.78, g.size.height - hauteurEcran - 60),
                           height: min(largeur * 0.78, g.size.height - hauteurEcran - 60))
                Spacer(minLength: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Boitier())
        }
        .ignoresSafeArea(.container, edges: .top)
        .ignoresSafeArea(.keyboard)
    }
}

/// Façade blanche légèrement brossée, avec un reflet en haut.
struct Boitier: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(white: 0.985), Color(white: 0.93), Color(white: 0.955)],
                           startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [.white.opacity(0.7), .clear], startPoint: .top, endPoint: .center)
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
        case .enLecture: EcranEnLecture()
        case .whatsapp: EcranDiscussions()
        case .liaisonWhatsApp: EcranLiaisonWhatsApp()
        case .conversation(let jid, let nom): EcranConversation(jid: jid, nom: nom)
        case .imageWhatsApp(let id): EcranImageWhatsApp(id: id)
        case .photos: MenuPhotos()
        case .camera: EcranCamera()
        case .pellicule: EcranPellicule()
        case .photo(let index): EcranPhoto(indexDepart: index)
        case .choixDiscussion(let assetId): EcranChoixDiscussion(assetId: assetId)
        case .claude: EcranClaude()
        case .reglages: EcranReglages()
        case .connexion: EcranConnexion()
        case .telegram: EcranTelegram()
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
