import SwiftUI
import WebKit

/// La liste de tes discussions claude.ai, façon iPod.
struct EcranClaude: View {
    @EnvironmentObject var nav: Navigateur
    @ObservedObject private var claude = ClaudeWeb.partage
    @State private var erreur: String?
    @State private var charge = false

    private var elements: [ElementListe] {
        var liste = [ElementListe(id: "__nouvelle", titre: "Nouvelle discussion")]
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        for c in claude.conversations {
            liste.append(ElementListe(id: c.id, titre: c.nom, detail: c.misAJour.map { f.localizedString(for: $0, relativeTo: Date()) }))
        }
        return liste
    }

    var body: some View {
        Group {
            switch claude.etat {
            case .chargement:
                MessageEcran(icone: "sparkle", texte: "Connexion à Claude…")
                    .roue { _ in }
            case .connexionRequise:
                MessageEcran(icone: "person.crop.circle.badge.questionmark", texte: "Connecte-toi à claude.ai",
                             detail: "Une seule fois. Bouton central pour ouvrir la connexion.")
                    .roue { g in g.centre = { nav.ouvrir(.connexionClaude) } }
                    .onTapGesture { nav.ouvrir(.connexionClaude) }
            case .erreur(let e):
                MessageEcran(icone: "exclamationmark.triangle", texte: "Claude indisponible", detail: e)
                    .roue { g in g.centre = { Task { await ClaudeWeb.partage.verifier() } } }
            case .pret:
                if let erreur, claude.conversations.isEmpty {
                    MessageEcran(icone: "exclamationmark.triangle", texte: "Discussions illisibles", detail: erreur)
                        .roue { g in g.centre = { Task { await charger() } } }
                } else {
                    EcranListe(cle: .claude, elements: elements, vide: charge ? "Aucune discussion." : "Chargement…") { e in
                        if e.id == "__nouvelle" {
                            nav.ouvrir(.discussionClaude(uuid: "", nom: "Nouvelle discussion"))
                        } else {
                            nav.ouvrir(.discussionClaude(uuid: e.id, nom: e.titre))
                        }
                    }
                }
            }
        }
        .task(id: claude.etat) {
            if claude.etat == .pret { await charger() }
        }
    }

    private func charger() async {
        do {
            try await claude.chargerConversations()
            erreur = nil
        } catch {
            self.erreur = error.localizedDescription
        }
        charge = true
    }
}

/// Une discussion : les messages en bulles, la molette défile paragraphe par
/// paragraphe, le centre ouvre le clavier Pin.
struct EcranDiscussionClaude: View {
    let uuidDepart: String
    let nom: String

    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var clavier: Clavier
    @StateObject private var etat = EtatDiscussionClaude()
    @State private var idSaisie = UUID()

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(etat.blocs.enumerated()), id: \.element.id) { i, b in
                            BlocClaude(bloc: b, selectionne: i == etat.index && !clavier.actif)
                                .id(b.id)
                        }
                        if etat.envoi && etat.reponse.isEmpty {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Claude réfléchit…").font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .id("attente")
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: etat.index) { _, i in
                    if etat.blocs.indices.contains(i) {
                        withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(etat.blocs[i].id, anchor: .center) }
                    }
                }
                .onChange(of: etat.blocs.count) { _, n in
                    guard n > 0 else { return }
                    etat.index = n - 1
                    proxy.scrollTo(etat.blocs[n - 1].id, anchor: .bottom)
                }
                .onChange(of: etat.reponse) { _, _ in
                    if let dernier = etat.blocs.last { proxy.scrollTo(dernier.id, anchor: .bottom) }
                }
            }
            .background(Color(red: 0.97, green: 0.96, blue: 0.94))

            if let e = etat.erreur {
                Text(e).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2).padding(.horizontal, 6)
            }
            HStack(spacing: 6) {
                ZoneSaisie(id: idSaisie, titre: "Écrire à Claude", texte: $etat.texte) { envoyer() }
                if !etat.texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !etat.envoi {
                    Button { envoyer() } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 22))
                            .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                    }
                }
            }
            .padding(5)
            .background(Color(white: 0.9))
        }
        .task {
            etat.uuid = uuidDepart
            await etat.charger()
        }
        .roue { g in
            let e = etat
            g.tour = { s in e.deplacer(s) }
            g.centre = { ouvrirClavier() }
            g.lecture = { ouvrirClavier() }
        }
    }

    private func ouvrirClavier() {
        clavier.ouvrir(champ: idSaisie, texte: $etat.texte, type: .texte, libelleRetour: "envoyer") { envoyer() }
    }

    private func envoyer() {
        Task { await etat.envoyer() }
    }
}

/// Un paragraphe d'un message : la molette avance de l'un à l'autre.
struct BlocMessage: Identifiable, Equatable {
    let id: String
    let humain: Bool
    let texte: String
    let premier: Bool
    let dernier: Bool
}

@MainActor
final class EtatDiscussionClaude: ObservableObject {
    @Published var uuid = ""
    @Published var messages: [MessageClaude] = []
    @Published var index = 0
    @Published var texte = ""
    @Published var erreur: String?
    @Published var envoi = false
    @Published var reponse = ""
    private var feuille: String?

    var blocs: [BlocMessage] {
        var tous = messages
        if envoi && !reponse.isEmpty {
            tous.append(MessageClaude(id: "en-cours", humain: false, texte: reponse))
        }
        return tous.flatMap { m -> [BlocMessage] in
            let paragraphes = m.texte
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .newlines) }
                .filter { !$0.isEmpty }
            let morceaux = paragraphes.isEmpty ? [m.texte] : paragraphes
            return morceaux.enumerated().map { i, p in
                BlocMessage(id: "\(m.id)-\(i)", humain: m.humain, texte: p, premier: i == 0, dernier: i == morceaux.count - 1)
            }
        }
    }

    func deplacer(_ s: Int) {
        let n = blocs.count
        guard n > 0 else { return }
        index = min(max(index + s, 0), n - 1)
    }

    func charger() async {
        guard !uuid.isEmpty else { return }
        do {
            let r = try await ClaudeWeb.partage.messages(uuid)
            messages = r.messages
            feuille = r.feuille
            index = max(blocs.count - 1, 0)
        } catch {
            erreur = error.localizedDescription
        }
    }

    func envoyer() async {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !envoi else { return }
        texte = ""
        erreur = nil
        envoi = true
        reponse = ""
        let premier = uuid.isEmpty
        messages.append(MessageClaude(id: "moi-\(UUID().uuidString)", humain: true, texte: t))
        do {
            if uuid.isEmpty { uuid = try await ClaudeWeb.partage.nouvelleConversation() }
            try await ClaudeWeb.partage.envoyer(t, dans: uuid, parent: feuille) { [weak self] r in
                self?.reponse = r
            }
            envoi = false
            reponse = ""
            // On relit la discussion : les vrais identifiants servent de parent au message suivant.
            await charger()
            if premier { await ClaudeWeb.partage.titrer(uuid, premierMessage: t) }
            try? await ClaudeWeb.partage.chargerConversations()
        } catch {
            envoi = false
            if !reponse.isEmpty {
                messages.append(MessageClaude(id: "partiel-\(UUID().uuidString)", humain: false, texte: reponse))
            }
            reponse = ""
            erreur = error.localizedDescription
        }
    }
}

struct BlocClaude: View {
    let bloc: BlocMessage
    let selectionne: Bool

    private var contenu: AttributedString {
        (try? AttributedString(markdown: bloc.texte,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(bloc.texte)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if bloc.humain { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 2) {
                if bloc.premier && !bloc.humain {
                    Text("Claude").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0.75, green: 0.38, blue: 0.25))
                }
                Text(contenu)
                    .font(.system(size: 13, design: bloc.texte.hasPrefix("```") ? .monospaced : .default))
                    .foregroundStyle(bloc.humain ? Color.white : Color.black)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(bloc.humain
                          ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.42, green: 0.66, blue: 0.95), Color(red: 0.16, green: 0.44, blue: 0.86)], startPoint: .top, endPoint: .bottom))
                          : AnyShapeStyle(Color.white))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(selectionne ? Color(red: 0.85, green: 0.47, blue: 0.34) : Color(white: 0.85),
                            lineWidth: selectionne ? 2 : 0.5)
            )
            if !bloc.humain { Spacer(minLength: 16) }
        }
        .padding(.horizontal, 6)
        .padding(.top, bloc.premier ? 4 : 0)
    }
}

/// L'écran de connexion : le seul endroit où le site de claude.ai apparaît.
struct EcranConnexionClaude: View {
    @EnvironmentObject var nav: Navigateur
    @ObservedObject private var claude = ClaudeWeb.partage

    var body: some View {
        VStack(spacing: 0) {
            Text("Connecte-toi par e-mail (Google ne marche pas ici).")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(3)
                .background(Color(white: 0.95))
            HoteClaude()
        }
        .onChange(of: claude.etat) { _, e in
            if e == .pret { nav.retour() }
        }
        .roue { _ in }
    }
}

/// Affiche la WebView partagée le temps de la connexion, puis la range.
struct HoteClaude: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let conteneur = UIView()
        conteneur.backgroundColor = .white
        DispatchQueue.main.async { ClaudeWeb.partage.afficher(dans: conteneur) }
        return conteneur
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        ClaudeWeb.partage.garer()
    }
}
