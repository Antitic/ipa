import Foundation
import WebKit
import UIKit

struct ConversationClaude: Identifiable, Equatable {
    let id: String
    let nom: String
    let misAJour: Date?
}

struct MessageClaude: Identifiable, Equatable {
    let id: String
    let humain: Bool
    var texte: String
}

struct ErreurClaude: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// claude.ai, en coulisses. Une WKWebView invisible reste ouverte sur
/// claude.ai avec TA session (tu t'y connectes une fois, à la main, sur
/// l'écran de connexion). Pin ne montre jamais le site : il lit tes
/// discussions et envoie tes messages en appelant, depuis cette page, les
/// mêmes adresses que le site lui-même. Tout se passe sur ton iPhone.
///
/// Ces adresses ne sont pas une API publique : si claude.ai les change, cette
/// partie de Pin devra suivre.
@MainActor
final class ClaudeWeb: NSObject, ObservableObject, WKNavigationDelegate {
    enum Etat: Equatable { case chargement, connexionRequise, pret, erreur(String) }

    static let partage = ClaudeWeb()

    let web: WKWebView
    @Published private(set) var etat: Etat = .chargement
    @Published private(set) var conversations: [ConversationClaude] = []

    private var organisation: String?
    private var flux: [String: (String) -> Void] = [:]
    private var demarre = false

    private static let racine = URL(string: "https://claude.ai/")!

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: config)
        super.init()
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"
        web.navigationDelegate = self
        web.configuration.userContentController.add(RelaisMessages(self), contentWorld: .page, name: "pin")
    }

    func demarrer() {
        guard !demarre else { return }
        demarre = true
        garer()
        web.load(URLRequest(url: Self.racine))
    }

    /// Range la WebView dans la fenêtre, invisible : une page hors fenêtre
    /// peut être mise en pause par iOS.
    func garer() {
        guard let fenetre = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.garer() }
            return
        }
        guard web.superview !== fenetre else { return }
        web.removeFromSuperview()
        web.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
        web.alpha = 0.01
        web.isUserInteractionEnabled = false
        fenetre.insertSubview(web, at: 0)
    }

    /// Montre la WebView dans un conteneur (écran de connexion).
    func afficher(dans conteneur: UIView) {
        web.removeFromSuperview()
        web.alpha = 1
        web.isUserInteractionEnabled = true
        web.frame = conteneur.bounds
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        conteneur.addSubview(web)
        if web.url?.host?.hasSuffix("claude.ai") != true || etat == .connexionRequise {
            web.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        }
    }

    // MARK: - Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await verifier() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Les nouvelles fenêtres (connexion) restent dans la même vue.
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
            return .cancel
        }
        return .allow
    }

    /// Vérifie la session et retrouve l'organisation (le compte) à utiliser.
    func verifier() async {
        guard web.url?.host?.hasSuffix("claude.ai") == true else { return }
        do {
            let r = try await appel("/api/organizations")
            guard let orgs = r as? [[String: Any]], !orgs.isEmpty else { throw ErreurClaude(message: "Aucun compte claude.ai.") }
            let avecChat = orgs.first { (($0["capabilities"] as? [String]) ?? []).contains("chat") }
            organisation = (avecChat ?? orgs[0])["uuid"] as? String
            etat = .pret
        } catch let e as ErreurHTTP where e.statut == 401 || e.statut == 403 {
            etat = .connexionRequise
        } catch {
            if etat != .pret { etat = .connexionRequise }
        }
    }

    // MARK: - Appels

    struct ErreurHTTP: LocalizedError {
        let statut: Int
        let corps: String
        var errorDescription: String? {
            if let d = corps.data(using: .utf8),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
               let e = j["error"] as? [String: Any], let m = e["message"] as? String {
                return m
            }
            return "claude.ai a répondu \(statut)."
        }
    }

    /// Un appel à claude.ai, fait par la page elle-même (avec tes cookies).
    @discardableResult
    func appel(_ chemin: String, methode: String = "GET", corps: [String: Any]? = nil) async throws -> Any? {
        let json = corps.flatMap { try? JSONSerialization.data(withJSONObject: $0) }.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let script = """
        const r = await fetch(chemin, {
          method: methode, credentials: 'include',
          headers: { 'content-type': 'application/json', 'accept': 'application/json' },
          body: corps === '' ? undefined : corps
        });
        return { statut: r.status, texte: await r.text() };
        """
        let res = try await web.callAsyncJavaScript(script, arguments: ["chemin": chemin, "methode": methode, "corps": json],
                                                    in: nil, contentWorld: .page)
        guard let d = res as? [String: Any], let statut = (d["statut"] as? NSNumber)?.intValue else {
            throw ErreurClaude(message: "Réponse illisible de claude.ai.")
        }
        let texte = d["texte"] as? String ?? ""
        guard (200..<300).contains(statut) else { throw ErreurHTTP(statut: statut, corps: texte) }
        guard !texte.isEmpty, let donnees = texte.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: donnees)
    }

    private func org() throws -> String {
        guard let organisation else { throw ErreurClaude(message: "Connecte-toi à claude.ai.") }
        return organisation
    }

    // MARK: - Discussions

    func chargerConversations() async throws {
        let o = try org()
        let r = try await appel("/api/organizations/\(o)/chat_conversations?limit=80")
        let liste = (r as? [[String: Any]]) ?? ((r as? [String: Any])?["data"] as? [[String: Any]]) ?? []
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        conversations = liste.compactMap { c in
            guard let id = c["uuid"] as? String else { return nil }
            let nom = (c["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Sans titre"
            let date = (c["updated_at"] as? String).flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            return ConversationClaude(id: id, nom: nom, misAJour: date)
        }
    }

    /// Les messages de la branche affichée sur claude.ai, et le dernier message
    /// (le parent du prochain).
    func messages(_ uuid: String) async throws -> (messages: [MessageClaude], feuille: String?) {
        let o = try org()
        let r = try await appel("/api/organizations/\(o)/chat_conversations/\(uuid)?tree=True&rendering_mode=messages&render_all_tools=true")
        guard let c = r as? [String: Any] else { return ([], nil) }
        let bruts = (c["chat_messages"] as? [[String: Any]]) ?? []
        var parId: [String: [String: Any]] = [:]
        for m in bruts { if let id = m["uuid"] as? String { parId[id] = m } }

        var chemin: [[String: Any]] = []
        if let feuille = c["current_leaf_message_uuid"] as? String, parId[feuille] != nil {
            var courant: String? = feuille
            var vus = Set<String>()
            while let id = courant, let m = parId[id], !vus.contains(id) {
                vus.insert(id)
                chemin.append(m)
                courant = m["parent_message_uuid"] as? String
            }
            chemin.reverse()
        } else {
            chemin = bruts.sorted { (($0["index"] as? Int) ?? 0) < (($1["index"] as? Int) ?? 0) }
        }

        let resultat = chemin.compactMap { m -> MessageClaude? in
            guard let id = m["uuid"] as? String else { return nil }
            let humain = (m["sender"] as? String) == "human"
            var texte = (m["text"] as? String) ?? ""
            if texte.isEmpty, let blocs = m["content"] as? [[String: Any]] {
                texte = blocs.filter { ($0["type"] as? String) == "text" }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n\n")
            }
            return MessageClaude(id: id, humain: humain, texte: texte)
        }
        return (resultat, chemin.last?["uuid"] as? String)
    }

    /// Crée une discussion vide et rend son identifiant.
    func nouvelleConversation() async throws -> String {
        let o = try org()
        let uuid = UUID().uuidString.lowercased()
        try await appel("/api/organizations/\(o)/chat_conversations", methode: "POST",
                        corps: ["uuid": uuid, "name": "", "include_conversation_preferences": true])
        return uuid
    }

    /// Envoie un message et reçoit la réponse au fil de l'eau.
    func envoyer(_ texte: String, dans uuid: String, parent: String?, recu: @escaping (String) -> Void) async throws {
        let o = try org()
        let idFlux = UUID().uuidString
        var reponse = ""
        var erreurFlux: String?
        flux[idFlux] = { donnee in
            guard let d = donnee.data(using: .utf8),
                  let e = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
            switch e["type"] as? String {
            case "completion":
                if let t = e["completion"] as? String { reponse += t }
            case "content_block_delta":
                if let delta = e["delta"] as? [String: Any], (delta["type"] as? String) == "text_delta",
                   let t = delta["text"] as? String { reponse += t }
            case "content_block_start":
                if let b = e["content_block"] as? [String: Any], (b["type"] as? String) == "text",
                   let t = b["text"] as? String, !t.isEmpty { reponse += t }
            case "error":
                erreurFlux = ((e["error"] as? [String: Any])?["message"] as? String) ?? "Erreur de claude.ai."
            default:
                return
            }
            recu(reponse)
        }
        defer { flux[idFlux] = nil }

        let corps: [String: Any] = [
            "prompt": texte,
            "parent_message_uuid": parent ?? "00000000-0000-4000-8000-000000000000",
            "timezone": TimeZone.current.identifier,
            "locale": "fr-FR",
            "attachments": [],
            "files": [],
            "sync_sources": [],
            "rendering_mode": "messages",
        ]
        let json = String(data: try JSONSerialization.data(withJSONObject: corps), encoding: .utf8) ?? "{}"
        let script = """
        const r = await fetch(chemin, {
          method: 'POST', credentials: 'include',
          headers: { 'content-type': 'application/json', 'accept': 'text/event-stream' },
          body: corps
        });
        if (!r.ok) { return { statut: r.status, texte: await r.text() }; }
        const lecteur = r.body.getReader();
        const dec = new TextDecoder();
        let tampon = '';
        for (;;) {
          const { done, value } = await lecteur.read();
          if (done) break;
          tampon += dec.decode(value, { stream: true });
          let i;
          while ((i = tampon.indexOf('\\n')) >= 0) {
            const ligne = tampon.slice(0, i).trim();
            tampon = tampon.slice(i + 1);
            if (ligne.startsWith('data:')) {
              window.webkit.messageHandlers.pin.postMessage({ id: idFlux, data: ligne.slice(5).trim() });
            }
          }
        }
        return { statut: r.status, texte: '' };
        """
        let res = try await web.callAsyncJavaScript(
            script,
            arguments: ["chemin": "/api/organizations/\(o)/chat_conversations/\(uuid)/completion", "corps": json, "idFlux": idFlux],
            in: nil, contentWorld: .page)
        if let d = res as? [String: Any], let statut = (d["statut"] as? NSNumber)?.intValue, !(200..<300).contains(statut) {
            throw ErreurHTTP(statut: statut, corps: d["texte"] as? String ?? "")
        }
        if let erreurFlux { throw ErreurClaude(message: erreurFlux) }
    }

    /// Demande à claude.ai de titrer une nouvelle discussion (sans conséquence si ça échoue).
    func titrer(_ uuid: String, premierMessage: String) async {
        guard let o = organisation else { return }
        _ = try? await appel("/api/organizations/\(o)/chat_conversations/\(uuid)/title", methode: "POST",
                             corps: ["message_content": premierMessage, "recent_titles": conversations.prefix(5).map(\.nom)])
    }

    fileprivate func recevoir(_ corps: Any) {
        guard let d = corps as? [String: Any], let id = d["id"] as? String, let donnee = d["data"] as? String else { return }
        flux[id]?(donnee)
    }
}

/// Évite le cycle de rétention entre WKUserContentController et ClaudeWeb.
@MainActor
private final class RelaisMessages: NSObject, WKScriptMessageHandler {
    weak var cible: ClaudeWeb?
    init(_ cible: ClaudeWeb) { self.cible = cible }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        cible?.recevoir(message.body)
    }
}
