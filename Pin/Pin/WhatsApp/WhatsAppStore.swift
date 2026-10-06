import Foundation

struct Discussion: Codable, Identifiable, Equatable {
    let jid: String
    let nom: String
    let dernierTexte: String?
    let dernierTimestamp: Double
    let nonLus: Int?
    var id: String { jid }
}

struct MessageWA: Codable, Identifiable, Equatable {
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
}

private struct Evenement: Decodable {
    let type: String
    let message: MessageWA?
    let lie: Bool?
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

    var nonLus: Int { discussions.reduce(0) { $0 + ($1.nonLus ?? 0) } }
    var discussionOuverte: String?

    private var flux: Task<Void, Never>?

    func demarrer() {
        Task {
            await rafraichirStatut()
            await rafraichirDiscussions()
        }
        guard flux == nil else { return }
        flux = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    var req = URLRequest(url: API.url("/api/whatsapp/flux"))
                    req.timeoutInterval = 3600
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    let (octets, rep) = try await API.session.bytes(for: req)
                    guard (rep as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    for try await ligne in octets.lines {
                        guard ligne.hasPrefix("data: "), let d = ligne.dropFirst(6).data(using: .utf8),
                              let e = try? API.decodeur.decode(Evenement.self, from: d) else { continue }
                        self?.recevoir(e)
                    }
                } catch {}
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }

    func arreter() {
        flux?.cancel()
        flux = nil
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
        if s.code != nil { codeJumelage = s.code }
        if s.connecte == true { codeJumelage = nil }
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

    func envoyerTexte(_ texte: String, a jid: String) async throws {
        let data = try await API.requete("/api/whatsapp/discussions/\(API.segment(jid))/messages", methode: "POST", json: ["texte": texte])
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

    func envoyerVocal(_ m4a: Data, duree: Double, a jid: String) async throws {
        let chemin = "/api/whatsapp/discussions/\(API.segment(jid))/vocal?duree=\(Int(duree.rounded()))"
        let data = try await API.requete(chemin, methode: "POST", corps: m4a, type: "audio/mp4", delai: 120)
        if let m = try? API.decodeur.decode(MessageWA.self, from: data) { ajouter([m], a: jid) }
    }

    func lier(numero: String) async throws -> String {
        struct R: Decodable { let code: String }
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
