import SwiftUI
import PhotosUI
import AVFoundation

struct EcranDiscussions: View {
    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var compte: Compte
    @EnvironmentObject var whatsapp: WhatsAppStore
    @State private var charge = false

    private var elementsDiscussions: [ElementListe] {
        whatsapp.discussions.map { d -> ElementListe in
            let n = d.nonLus ?? 0
            return ElementListe(id: d.jid, titre: d.nom, detail: d.dernierTexte, badge: n > 0 ? "\(n)" : nil)
        }
    }

    var body: some View {
        Group {
            if !compte.connecte {
                BesoinCompte()
            } else if charge && !whatsapp.lie {
                MessageEcran(icone: "link", texte: "WhatsApp n'est pas lié", detail: "Bouton central pour lier ton compte.")
                    .roue { g in g.centre = { nav.ouvrir(.liaisonWhatsApp) } }
                    .onTapGesture { nav.ouvrir(.liaisonWhatsApp) }
            } else {
                EcranListe(cle: .whatsapp,
                           elements: elementsDiscussions,
                           vide: charge ? "Aucune discussion pour l'instant. Les nouveaux messages apparaîtront ici." : "Chargement…") { e in
                    nav.ouvrir(.conversation(jid: e.id, nom: e.titre))
                }
            }
        }
        .task {
            guard compte.connecte else { return }
            await whatsapp.rafraichirStatut()
            await whatsapp.rafraichirDiscussions()
            charge = true
        }
    }
}

struct EcranLiaisonWhatsApp: View {
    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var whatsapp: WhatsAppStore
    @EnvironmentObject var clavier: Clavier
    @State private var numero = "33"
    @State private var erreur: String?
    @State private var enCours = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if whatsapp.lie {
                    Text(whatsapp.connecte ? "WhatsApp est lié et connecté." : "WhatsApp est lié (connexion en cours…).")
                        .font(.system(size: 14, weight: .semibold))
                    BoutonIPod(titre: "Délier WhatsApp") { Task { await whatsapp.delier() } }
                } else if let code = whatsapp.codeJumelage {
                    Text("Sur ton téléphone : WhatsApp › Appareils connectés › Connecter un appareil › Connecter avec un numéro, puis tape :")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(code)
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity)
                        .textSelection(.enabled)
                    Text("En attente de la liaison… (le code reste valable environ 3 minutes)")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    BoutonIPod(titre: enCours ? "Demande…" : "Nouveau code", actif: !enCours) { lier(nouveau: true) }
                } else {
                    Text("Ton numéro WhatsApp avec l'indicatif, sans + ni 0 (ex. 33612345678).")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    ChampIPod(titre: "33612345678", texte: $numero, type: .numero, libelleRetour: "code", retour: { lier() })
                    BoutonIPod(titre: enCours ? "Demande…" : "Obtenir un code", actif: !enCours) { lier() }
                }
                if let e = erreur ?? whatsapp.erreurLiaison {
                    Text(e).font(.system(size: 12)).foregroundStyle(.red)
                }
            }
            .padding(12)
        }
        .roue { g in g.centre = { lier() } }
        .task {
            while !Task.isCancelled {
                await whatsapp.rafraichirStatut()
                if whatsapp.connecte { break }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func lier(nouveau: Bool = false) {
        guard !whatsapp.lie, nouveau || whatsapp.codeJumelage == nil, !enCours else { return }
        clavier.fermer()
        enCours = true
        erreur = nil
        Task {
            do { _ = try await whatsapp.lier(numero: numero) } catch { erreur = error.localizedDescription }
            enCours = false
        }
    }
}

/// Une conversation : la molette parcourt les messages, le centre envoie le
/// texte saisi (ou ouvre / lit le message sélectionné), le centre maintenu
/// enregistre un vocal, ⏮ lance la dictée, ⏭ joint une photo.
struct EcranConversation: View {
    let jid: String
    let nom: String

    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var whatsapp: WhatsAppStore
    @StateObject private var etat = EtatConversation()
    @StateObject private var dictee = Dictee()
    @StateObject private var enregistreur = Enregistreur()
    @StateObject private var lecteurVocal = LecteurVocal()
    @EnvironmentObject var clavier: Clavier
    @State private var idSaisie = UUID()
    @State private var choixPhoto: PhotosPickerItem?
    @State private var choixOuvert = false

    private var liste: [MessageWA] { whatsapp.messages[jid] ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(liste.enumerated()), id: \.element.id) { i, m in
                            Bulle(message: m, selectionne: i == etat.index, groupe: jid.hasSuffix("@g.us"),
                                  enLecture: lecteurVocal.enCours == m.id,
                                  chargement: lecteurVocal.chargement == m.id,
                                  progression: lecteurVocal.enCours == m.id ? lecteurVocal.progression : 0,
                                  position: lecteurVocal.enCours == m.id ? lecteurVocal.position : 0)
                                .id(m.id)
                                .onTapGesture {
                                    etat.index = i
                                    activer(m)
                                }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: etat.index) { _, i in
                    if liste.indices.contains(i) {
                        withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(liste[i].id, anchor: .center) }
                    }
                }
                .onChange(of: liste.count) { ancien, nouveau in
                    // Nouveau message en bas : on suit si on était déjà en bas.
                    if etat.index >= ancien - 1 || ancien == 0 {
                        etat.index = nouveau - 1
                        if let dernier = liste.last { proxy.scrollTo(dernier.id, anchor: .bottom) }
                    } else if etat.chargementAncien {
                        etat.index += nouveau - ancien
                    }
                }
            }
            .background(Color(red: 0.93, green: 0.95, blue: 0.97))

            if enregistreur.actif {
                HStack {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text("Vocal \(Int(enregistreur.duree))s — relâche pour envoyer")
                        .font(.system(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(6)
                .background(Color(white: 0.96))
            }
            if let e = etat.erreur {
                Text(e).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2).padding(.horizontal, 6)
            }
            barreSaisie
        }
        .photosPicker(isPresented: $choixOuvert, selection: $choixPhoto, matching: .images)
        .onChange(of: choixPhoto) { _, item in
            guard let item else { return }
            Task { await envoyerPhoto(item) }
        }
        .task {
            whatsapp.discussionOuverte = jid
            await whatsapp.chargerMessages(jid)
            etat.index = max(liste.count - 1, 0)
        }
        .onDisappear {
            whatsapp.discussionOuverte = nil
            dictee.arreter()
            lecteurVocal.arreter()
        }
        .roue { g in
            g.tour = { s in tourner(s) }
            g.centre = { centre() }
            g.centreMaintenu = { enregistreur.demarrer() }
            g.centreRelache = { envoyerVocal() }
            g.precedent = { basculerDictee() }
            g.suivant = { choixOuvert = true }
            g.menu = { false }
        }
    }

    private var barreSaisie: some View {
        HStack(spacing: 6) {
            Button { basculerDictee() } label: {
                Image(systemName: dictee.actif ? "waveform.circle.fill" : "mic.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(dictee.actif ? .red : Color(white: 0.4))
            }
            Button { choixOuvert = true } label: {
                Image(systemName: "photo.circle").font(.system(size: 20)).foregroundStyle(Color(white: 0.4))
            }
            Button { nav.ouvrir(.stickers(jid: jid)) } label: {
                Image(systemName: "face.smiling").font(.system(size: 19)).foregroundStyle(Color(white: 0.4))
            }
            ZoneSaisie(id: idSaisie, titre: "Message", texte: $etat.texte) { envoyerTexte() }
            if !etat.texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { envoyerTexte() } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 22))
                        .foregroundStyle(Color(red: 0.16, green: 0.44, blue: 0.86))
                }
            }
        }
        .padding(5)
        .background(Color(white: 0.9))
    }

    // MARK: - Actions

    private func ouvrirClavier() {
        clavier.ouvrir(champ: idSaisie, texte: $etat.texte, type: .texte, libelleRetour: "envoyer") { envoyerTexte() }
    }

    private func tourner(_ s: Int) {
        guard !liste.isEmpty else { return }
        if let id = lecteurVocal.enCours, liste.indices.contains(etat.index), liste[etat.index].id == id {
            lecteurVocal.deplacer(Double(s) * 3)
            return
        }
        let n = min(max(etat.index + s, 0), liste.count - 1)
        etat.index = n
        if n == 0, s < 0, !etat.chargementAncien {
            etat.chargementAncien = true
            Task {
                _ = await whatsapp.chargerPlusAnciens(jid)
                etat.chargementAncien = false
            }
        }
    }

    private func centre() {
        if !etat.texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            envoyerTexte()
        } else if liste.indices.contains(etat.index) {
            activer(liste[etat.index])
        }
    }

    private func activer(_ m: MessageWA) {
        switch m.type {
        case "image": nav.ouvrir(.imageWhatsApp(id: m.id))
        case "vocal", "audio": lecteurVocal.basculer(m.id)
        default: ouvrirClavier()
        }
    }

    private func envoyerTexte() {
        let t = etat.texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        dictee.arreter()
        etat.texte = ""
        etat.erreur = nil
        Task {
            do { try await whatsapp.envoyerTexte(t, a: jid) } catch {
                etat.texte = t
                etat.erreur = error.localizedDescription
            }
        }
    }

    private func envoyerVocal() {
        guard let resultat = enregistreur.terminer() else { return }
        let (data, duree) = resultat
        guard duree >= 1 else { etat.erreur = "Vocal trop court."; return }
        etat.erreur = nil
        Task {
            do { try await whatsapp.envoyerVocal(data, duree: duree, a: jid) } catch { etat.erreur = error.localizedDescription }
        }
    }

    private func envoyerPhoto(_ item: PhotosPickerItem) async {
        choixPhoto = nil
        guard let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data),
              let jpeg = img.jpegRedimensionne() else {
            etat.erreur = "Photo illisible."
            return
        }
        let legende = etat.texte.trimmingCharacters(in: .whitespacesAndNewlines)
        etat.texte = ""
        do { try await whatsapp.envoyerImage(jpeg, legende: legende, a: jid) } catch { etat.erreur = error.localizedDescription }
    }

    private func basculerDictee() {
        if dictee.actif {
            dictee.arreter()
        } else {
            let base = etat.texte
            dictee.demarrer { transcription in
                etat.texte = base.isEmpty ? transcription : base + " " + transcription
            }
        }
    }
}

@MainActor
final class EtatConversation: ObservableObject {
    @Published var index = 0
    @Published var texte = ""
    @Published var erreur: String?
    var chargementAncien = false
}

struct Bulle: View {
    let message: MessageWA
    let selectionne: Bool
    let groupe: Bool
    let enLecture: Bool
    var chargement = false
    var progression: Double = 0
    var position: Double = 0
    @State private var image: UIImage?

    private var envoiEnCours: Bool { message.id.hasPrefix("envoi-") }
    /// Un sticker en cours d'envoi s'affiche avec l'image du sticker choisi.
    private var idSticker: String? {
        if message.type == "sticker" { return message.id }
        if message.type.hasPrefix("sticker-local:") { return String(message.type.dropFirst("sticker-local:".count)) }
        return nil
    }

    var body: some View {
        HStack {
            if message.deMoi { Spacer(minLength: 36) }
            VStack(alignment: .leading, spacing: 2) {
                if groupe, !message.deMoi, let a = message.auteur {
                    Text(a).font(.system(size: 10, weight: .bold)).foregroundStyle(Color(red: 0.1, green: 0.5, blue: 0.4))
                }
                contenu
                HStack(spacing: 3) {
                    Spacer(minLength: 0)
                    Text(Date(timeIntervalSince1970: message.timestamp / 1000), format: .dateTime.hour().minute())
                    if message.deMoi {
                        Image(systemName: envoiEnCours ? "clock" : "checkmark")
                            .font(.system(size: 8, weight: .semibold))
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(idSticker != nil ? Color.clear : (message.deMoi ? Color(red: 0.86, green: 0.97, blue: 0.78) : .white))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectionne ? Color(red: 0.16, green: 0.44, blue: 0.86) : (idSticker != nil ? Color.clear : Color(white: 0.85)),
                            lineWidth: selectionne ? 2 : 0.5)
            )
            if !message.deMoi { Spacer(minLength: 36) }
        }
    }

    @ViewBuilder
    private var contenu: some View {
        if let id = idSticker {
            Group {
                if let image {
                    ImageAnimee(image: image)
                } else {
                    Color.clear.overlay(ProgressView().scaleEffect(0.7))
                }
            }
            .frame(width: 96, height: 96)
            .opacity(envoiEnCours ? 0.6 : 1)
            .task(id: id) { image = await API.image("/api/whatsapp/medias/\(API.segment(id))") }
        } else {
            contenuSimple
        }
    }

    @ViewBuilder
    private var contenuSimple: some View {
        switch message.type {
        case "image":
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color(white: 0.9).overlay(ProgressView())
                }
            }
            .frame(width: 140, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task { image = await API.image("/api/whatsapp/medias/\(API.segment(message.id))?taille=vignette") }
            if let t = message.texte { Text(t).font(.system(size: 13)) }
        case "audio":
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    iconeLecture
                    VStack(alignment: .leading, spacing: 1) {
                        Text(message.texte ?? "Audio").font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(enLecture ? "\(minutes(position)) / \(message.duree.map(minutes) ?? "–")"
                                       : (message.duree.map(minutes) ?? "Audio"))
                            .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: progression).tint(Color(red: 0.16, green: 0.44, blue: 0.86)).frame(width: 150)
            }
        case "vocal":
            HStack(spacing: 6) {
                iconeLecture
                ProgressView(value: progression).tint(Color(red: 0.16, green: 0.44, blue: 0.86)).frame(width: 70)
                Text(message.duree.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) } ?? "🎤")
                    .font(.system(size: 11).monospacedDigit())
            }
        default:
            Text(message.texte ?? "").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                .opacity(envoiEnCours ? 0.7 : 1)
        }
    }

    @ViewBuilder
    private var iconeLecture: some View {
        if chargement {
            ProgressView().scaleEffect(0.8).frame(width: 22, height: 22)
        } else {
            Image(systemName: enLecture ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color(red: 0.16, green: 0.44, blue: 0.86))
        }
    }

    private func minutes(_ s: Double) -> String {
        String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}

/// Image qui joue son animation (UIImage animée : stickers animés).
struct ImageAnimee: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        if v.image !== image {
            v.image = image
            if image.images != nil { v.startAnimating() }
        }
    }
}

struct EcranImageWhatsApp: View {
    let id: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
        }
        .task { image = await API.image("/api/whatsapp/medias/\(API.segment(id))") }
        .roue { _ in }
    }
}

/// Liste des discussions pour envoyer une photo de la Pellicule.
struct EcranChoixDiscussion: View {
    let assetId: String
    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var compte: Compte
    @EnvironmentObject var whatsapp: WhatsAppStore
    @State private var etat: String?

    var body: some View {
        Group {
            if !compte.connecte {
                BesoinCompte()
            } else if let etat {
                MessageEcran(icone: etat == "Envoyée" ? "checkmark.circle" : "paperplane", texte: etat)
                    .roue { _ in }
            } else {
                EcranListe(cle: .choixDiscussion(assetId: ""),
                           elements: whatsapp.discussions.map { ElementListe(id: $0.jid, titre: $0.nom, chevron: false) },
                           vide: "Aucune discussion.") { e in
                    envoyer(a: e.id)
                }
            }
        }
        .task { await whatsapp.rafraichirDiscussions() }
    }

    private func envoyer(a jid: String) {
        etat = "Envoi…"
        Task {
            guard let img = await Galerie.imagePleine(assetId), let jpeg = img.jpegRedimensionne() else {
                etat = "Photo illisible"
                return
            }
            do {
                try await whatsapp.envoyerImage(jpeg, a: jid)
                etat = "Envoyée"
                try? await Task.sleep(for: .seconds(1))
                nav.retour()
            } catch {
                etat = error.localizedDescription
            }
        }
    }
}

extension UIImage {
    /// JPEG d'au plus 1600 px de côté, comme WhatsApp le ferait.
    func jpegRedimensionne(cote: CGFloat = 1600) -> Data? {
        let echelle = min(1, cote / max(size.width, size.height))
        guard echelle < 1 else { return jpegData(compressionQuality: 0.82) }
        let cible = CGSize(width: size.width * echelle, height: size.height * echelle)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let img = UIGraphicsImageRenderer(size: cible, format: format).image { _ in draw(in: CGRect(origin: .zero, size: cible)) }
        return img.jpegData(compressionQuality: 0.82)
    }
}


/// Les stickers déjà vus (reçus ou envoyés) : la molette choisit, le centre envoie.
struct EcranStickers: View {
    let jid: String
    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var whatsapp: WhatsAppStore
    @State private var index = 0
    @State private var charge = false
    @State private var erreur: String?

    private let colonnes = 4

    var body: some View {
        Group {
            if whatsapp.stickers.isEmpty {
                MessageEcran(icone: "face.smiling", texte: charge ? "Aucun sticker" : "Chargement…",
                             detail: charge ? "Les stickers que tu reçois ou envoies apparaîtront ici." : nil)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: colonnes), spacing: 6) {
                            ForEach(Array(whatsapp.stickers.enumerated()), id: \.element.id) { i, st in
                                VignetteSticker(id: st.id)
                                    .frame(height: 64)
                                    .padding(3)
                                    .background(RoundedRectangle(cornerRadius: 8)
                                        .fill(i == index ? Color(red: 0.16, green: 0.44, blue: 0.86).opacity(0.18) : .clear))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(i == index ? Color(red: 0.16, green: 0.44, blue: 0.86) : .clear, lineWidth: 2))
                                    .id(st.id)
                                    .onTapGesture { index = i; envoyer() }
                            }
                        }
                        .padding(6)
                        if let erreur { Text(erreur).font(.system(size: 11)).foregroundStyle(.red).padding(6) }
                    }
                    .onChange(of: index) { _, i in
                        if whatsapp.stickers.indices.contains(i) {
                            withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(whatsapp.stickers[i].id, anchor: .center) }
                        }
                    }
                }
            }
        }
        .background(Color.white)
        .task {
            await whatsapp.chargerStickers()
            charge = true
        }
        .roue { g in
            g.tour = { s in
                let n = whatsapp.stickers.count
                guard n > 0 else { return }
                index = min(max(index + s, 0), n - 1)
            }
            g.centre = { envoyer() }
        }
    }

    private func envoyer() {
        guard whatsapp.stickers.indices.contains(index) else { return }
        let id = whatsapp.stickers[index].id
        let cible = jid
        let store = whatsapp
        nav.retour()
        Task { try? await store.envoyerSticker(id, a: cible) }
    }
}

struct VignetteSticker: View {
    let id: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { ImageAnimee(image: image) } else { Color.clear.overlay(ProgressView().scaleEffect(0.6)) }
        }
        .task(id: id) { image = await API.image("/api/whatsapp/medias/\(API.segment(id))") }
    }
}
