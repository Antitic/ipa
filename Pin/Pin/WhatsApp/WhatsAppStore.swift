import Foundation

struct Discussion: Codable, Identifiable, Equatable {
    let jid: String
    let nom: String
    let dernierTexte: String?
    let dernierTimestamp: Double
    let nonLus: Int?
    var id: String { jid }
}

struct ReactionWA: Codable, Equatable, Hashable {
    let emoji: String
    let moi: Bool
}

/// État d'un de mes messages : 1 envoyé, 2 reçu, 3 lu, 4 écouté.
struct VuWA: Codable, Equatable {
    let niveau: Int
    let lus: Int
    let total: Int
}

struct MessageWA: Codable, Identifiable, Equatable {
    var vu: VuWA? = nil
    var reactions: [ReactionWA]? = nil
    let id: String
    let jid: String
    let deMoi: Bool
    let auteur: String?
    let type: String
    let texte: String?
    let duree: Double?
    let timestamp: Double
}

private struct StatutWA: Decodable {
    let lie: Bool
    let connecte: Bool?
    let code: String?
    let erreur: String?
}

struct StickerWA: Decodable, Identifiable, Equatable {
    let id: String
    let anime: Bool
}

private struct Evenement: Decodable {
    let type: String
    let message: MessageWA?
    let lie: Bool?
    let id: String?
    let jid: String?
    let reactions: [ReactionWA]?
    let vu: VuWA?
}

/// État WhatsApp partagé : statut, discussions, messages par discussion, et le
/// flux temps réel (SSE) du serveur tant que l'app est ouverte.
@MainActor
final class WhatsAppStore: ObservableObject {
    @Published private(set) var lie = false
    @Published private(set) var connecte = false
    @Published private(set) var discussions: [Discussion] = []
    @Published private(set) var messages: [String: [MessageWA]] = [:]
    @Published private(set) var codeJumelage: String?
    @Published private(set) var erreurLiaison: String?

    var nonLus: Int { discussions.reduce(0) { $0 + ($1.nonLus ?? 0) } }
    var discussionOuverte: String?

    @Published private(set) var stickers: [StickerWA] = []

    private var flux: Task<Void, Never>?
    private var surveillance: Task<Void, Never>?
    /// Dernière ligne reçue du flux (le serveur envoie un battement toutes les 25 s).
    private var derniereActivite = Date()

    func demarrer() {
        Task {
            await rafraichirStatut()
            await rafraichirDiscussions()
        }
        guard flux == nil else { return }
        lancerFlux()
        // Un flux silencieux depuis 40 s est mort (iPhone verrouillé, réseau
        // changé…) : on le relance au lieu d'attendre qu'iOS le remarque.
        surveillance = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self else { return }
                if Date().timeIntervalSince(self.derniereActivite) > 40 { self.reconnecter() }
            }
        }
    }

    /// Retour au premier plan : le flux ouvert avant la mise en veille est
    /// presque toujours mort. On le rouvre tout de suite et on rattrape.
    func reconnecter() {
        guard flux != nil else { demarrer(); return }
        flux?.cancel()
        lancerFlux()
        Task {
            await rafraichirStatut()
            await rafraichirDiscussions()
            if let jid = discussionOuverte { await chargerMessages(jid) }
        }
    }

    private func lancerFlux() {
        derniereActivite = Date()
        flux = Task { [weak self] in
            var attente: Double = 0.5
            while !Task.isCancelled {
                do {
                    var req = URLRequest(url: API.url("/api/whatsapp/flux"))
                    req.timeoutInterval = 3600
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (octets, rep) = try await API.session.bytes(for: req)
                    guard (rep as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    attente = 0.5
                    self?.derniereActivite = Date()
                    for try await ligne in octets.lines {
                        if Task.isCancelled { return }
                        self?.derniereActivite = Date()
                        guard ligne.hasPrefix("data: "), let d = ligne.dropFirst(6).data(using: .utf8),
                              let e = try? API.decodeur.decode(Evenement.self, from: d) else { continue }
                        self?.recevoir(e)
                    }
                } catch {}
                if Task.isCancelled { return }
                try? await Task.sleep(for: .seconds(attente))
                attente = min(attente * 2, 8)
            }
        }
    }

    func arreter() {
        flux?.cancel()
        flux = nil
        surveillance?.cancel()
        surveillance = nil
        discussions = []
        messages = [:]
        lie = false
        connecte = false
    }

    private func recevoir(_ e: Evenement) {
        switch e.type {
        case "message":
            guard let m = e.message else { return }
            ajouter([m], a: m.jid)
            Task { await rafraichirDiscussions() }
        case "vu":
            if let id = e.id, let jid = e.jid, var liste = messages[jid], let i = liste.firstIndex(where: { $0.id == id }) {
                liste[i].vu = e.vu
                messages[jid] = liste
            }
        case "reaction":
            if let id = e.id, let jid = e.jid { appliquerReactions(e.reactions ?? [], a: id, dans: jid) }
        case "statut":
            lie = e.lie ?? lie
            Task { await rafraichirStatut() }
        case "discussions":
            Task { await rafraichirDiscussions() }
        default:
            break
        }
    }

    private func ajouter(_ nouveaux: [MessageWA], a jid: String) {
        var liste = messages[jid] ?? []
        let connus = Set(liste.map(\.id))
        liste.append(contentsOf: nouveaux.filter { !connus.contains($0.id) })
        liste.sort { $0.timestamp < $1.timestamp }
        messages[jid] = liste
    }

    func rafraichirStatut() async {
        guard let s = try? await API.get("/api/whatsapp/statut", StatutWA.self) else { return }
        lie = s.lie
        connecte = s.connecte ?? false
        // Le code affiché suit le serveur : s'il a expiré là-bas, il disparaît ici.
        codeJumelage = (s.connecte == true || s.lie) ? nil : s.code
        erreurLiaison = s.erreur
    }

    func rafraichirDiscussions() async {
        if let d = try? await API.get("/api/whatsapp/discussions", [Discussion].self) {
            discussions = d
        }
    }

    func chargerMessages(_ jid: String) async {
        guard let liste = try? await API.get("/api/whatsapp/discussions/\(API.segment(jid))/messages?limite=80", [MessageWA].self) else { return }
        ajouter(liste, a: jid)
        await rafraichirDiscussions()
    }

    /// Charge les messages plus anciens ; renvoie combien sont arrivés.
    func chargerPlusAnciens(_ jid: String) async -> Int {
        guard let premier = messages[jid]?.first else { return 0 }
        let chemin = "/api/whatsapp/discussions/\(API.segment(jid))/messages?limite=60&avant=\(Int(premier.timestamp))"
        guard let liste = try? await API.get(chemin, [MessageWA].self) else { return 0 }
        let avant = messages[jid]?.count ?? 0
        ajouter(liste, a: jid)
        return (messages[jid]?.count ?? 0) - avant
    }

    /// Le message s'affiche tout de suite (avec une horloge), sans attendre
    /// que WhatsApp confirme, ce qui prend souvent plus d'une seconde.
    func envoyerTexte(_ texte: String, a jid: String) async throws {
        let provisoire = MessageWA(id: "envoi-\(UUID().uuidString)", jid: jid, deMoi: true, auteur: nil,
                                   type: "texte", texte: texte, duree: nil, timestamp: Date().timeIntervalSince1970 * 1000)
        ajouter([provisoire], a: jid)
        defer { messages[jid]?.removeAll { $0.id == provisoire.id } }
        let data = try await API.requete("/api/whatsapp/discussions/\(API.segment(jid))/messages", methode: "POST", json: ["texte": texte])
        if let m = try? API.decodeur.decode(MessageWA.self, from: data) { ajouter([m], a: jid) }
    }

    private func appliquerReactions(_ r: [ReactionWA], a id: String, dans jid: String) {
        guard var liste = messages[jid], let i = liste.firstIndex(where: { $0.id == id }) else { return }
        liste[i].reactions = r
        messages[jid] = liste
    }

    /// Réagit à un message (emoji vide = retirer sa réaction). Affiché tout de suite.
    func reagir(_ emoji: String, a id: String, dans jid: String) async {
        let avant = messages[jid]?.first(where: { $0.id == id })?.reactions ?? []
        var apres = avant.filter { !$0.moi }
        if !emoji.isEmpty { apres.append(ReactionWA(emoji: emoji, moi: true)) }
        appliquerReactions(apres, a: id, dans: jid)
        struct R: Decodable { let reactions: [ReactionWA] }
        if let r = try? await API.post("/api/whatsapp/discussions/\(API.segment(jid))/reaction", ["id": id, "emoji": emoji], R.self) {
            appliquerReactions(r.reactions, a: id, dans: jid)
        } else {
            appliquerReactions(avant, a: id, dans: jid)
        }
    }

    func chargerStickers() async {
        if let s = try? await API.get("/api/whatsapp/stickers", [StickerWA].self) { stickers = s }
    }

    func envoyerSticker(_ id: String, a jid: String) async throws {
        let provisoire = MessageWA(id: "envoi-\(UUID().uuidString)", jid: jid, deMoi: true, auteur: nil,
                                   type: "sticker-local:\(id)", texte: nil, duree: nil, timestamp: Date().timeIntervalSince1970 * 1000)
        ajouter([provisoire], a: jid)
        defer { messages[jid]?.removeAll { $0.id == provisoire.id } }
        let data = try await API.requete("/api/whatsapp/discussions/\(API.segment(jid))/sticker", methode: "POST", json: ["id": id])
        if let m = try? API.decodeur.decode(MessageWA.self, from: data) { ajouter([m], a: jid) }
    }

    func envoyerImage(_ jpeg: Data, legende: String? = nil, a jid: String) async throws {
        var chemin = "/api/whatsapp/discussions/\(API.segment(jid))/image"
        if let l = legende, !l.isEmpty, let enc = l.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            chemin += "?legende=\(enc)"
        }
        let data = try await API.requete(chemin, methode: "POST", corps: jpeg, type: "image/jpeg", delai: 120)
        if let m = try? API.decodeur.decode(MessageWA.self, from: data) { ajouter([m], a: jid) }
    }

    /// Un fichier audio (pas un vocal) : depuis Fichiers, ou un morceau de Musique.
    func envoyerAudio(fichier: Data? = nil, nom: String = "", musique: String? = nil, a jid: String) async throws {
        let provisoire = MessageWA(id: "envoi-\(UUID().uuidString)", jid: jid, deMoi: true, auteur: nil,
                                   type: "audio", texte: nom.isEmpty ? "Audio" : nom, duree: nil,
                                   timestamp: Date().timeIntervalSince1970 * 1000)
        ajouter([provisoire], a: jid)
        defer { messages[jid]?.removeAll { $0.id == provisoire.id } }
        var chemin = "/api/whatsapp/discussions/\(API.segment(jid))/audio"
        if let musique { chemin += "?musique=\(API.segment(musique))" }
        else { chemin += "?nom=" + (nom.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "audio") }
        let data = try await API.requete(chemin, methode: "POST", corps: fichier ?? Data(), type: "application/octet-stream", delai: 300)
        if let m = try? API.decodeur.decode(MessageWA.self, from: data) { ajouter([m], a: jid) }
    }

    func envoyerVocal(_ m4a: Data, duree: Double, a jid: String) async throws {
        let chemin = "/api/whatsapp/discussions/\(API.segment(jid))/vocal?duree=\(Int(duree.rounded()))"
        let data = try await API.requete(chemin, methode: "POST", corps: m4a, type: "audio/mp4", delai: 120)
        if let m = try? API.decodeur.decode(MessageWA.self, from: data) { ajouter([m], a: jid) }
    }

    func lier(numero: String) async throws -> String {
        struct R: Decodable { let code: String }
        erreurLiaison = nil
        let r = try await API.post("/api/whatsapp/lier-numero", ["numero": numero], R.self)
        codeJumelage = r.code
        return r.code
    }

    func delier() async {
        _ = try? await API.requete("/api/whatsapp/delier", methode: "POST", json: [:])
        lie = false
        connecte = false
        discussions = []
        messages = [:]
    }
}
