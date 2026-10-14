import Foundation
import WebKit
import UIKit
import ObjectiveC

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
    /// Dernière version connue de chaque discussion : elle s'affiche tout de
    /// suite à l'ouverture, pendant que la version à jour arrive.
    private(set) var memoire: [String: (messages: [MessageClaude], feuille: String?)] = [:]

    private var organisation: String?
    private var flux: [String: (String) -> Void] = [:]
    private var demarre = false
    /// Vrai pendant que la page est montée à l'écran (connexion).
    private var affichee = false
    /// Le clavier Pin, qui remplace celui d'iOS dans la page de connexion.
    weak var clavier: Clavier?

    /// Page de repos : légère, sans champ de saisie, mais sur claude.ai, ce
    /// qui suffit pour appeler le site avec ta session.
    private static let racine = URL(string: "https://claude.ai/robots.txt")!

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // On s'annonce comme le Safari de la vraie version d'iOS : une version
        // inventée ne correspond pas au moteur réel et la protection anti-robots
        // de claude.ai refuse alors d'envoyer le lien de connexion.
        let v = UIDevice.current.systemVersion.split(separator: ".").prefix(2).joined(separator: ".")
        config.applicationNameForUserAgent = "Version/\(v) Mobile/15E148 Safari/604.1"
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: config)
        super.init()
        web.navigationDelegate = self
        web.configuration.userContentController.add(RelaisMessages(self), contentWorld: .page, name: "pin")
        web.configuration.userContentController.add(RelaisMessages(self), contentWorld: .page, name: "pinFocus")
        web.configuration.userContentController.addUserScript(WKUserScript(
            source: Self.scriptFocus, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .page))
        SansClavierSysteme.installer()
    }

    /// Prévient Pin quand un champ de la page prend ou perd le focus.
    private static let scriptFocus = """
    (function () {
      function info(el) {
        if (!el) return null;
        var t = el.tagName;
        var ok = el.isContentEditable || t === 'TEXTAREA' ||
          (t === 'INPUT' && ['button','submit','checkbox','radio','hidden','file','image','reset','range','color'].indexOf(el.type) < 0);
        if (!ok) return null;
        return { focus: true, type: el.type || '', mode: el.inputMode || '', auto: el.autocomplete || '' };
      }
      document.addEventListener('focusin', function (e) {
        var i = info(e.target);
        if (i) window.webkit.messageHandlers.pinFocus.postMessage(i);
      }, true);
      document.addEventListener('focusout', function () {
        setTimeout(function () {
          if (!info(document.activeElement)) window.webkit.messageHandlers.pinFocus.postMessage({ focus: false });
        }, 60);
      }, true);
    })();
    """

    fileprivate func focus(_ corps: Any) {
        guard affichee, let d = corps as? [String: Any], let clavier else { return }
        guard (d["focus"] as? Bool) == true else {
            if clavier.champ == Clavier.champWeb { clavier.fermer() }
            return
        }
        let type = (d["type"] as? String) ?? ""
        let mode = (d["mode"] as? String) ?? ""
        let auto = (d["auto"] as? String) ?? ""
        let typeClavier: TypeClavier
        if type == "email" || auto.contains("email") {
            typeClavier = .email
        } else if mode == "numeric" || mode == "decimal" || type == "number" || auto == "one-time-code" {
            typeClavier = .numero
        } else if type == "tel" || mode == "tel" {
            typeClavier = .telephone
        } else {
            typeClavier = .email   // pas de majuscule automatique dans les formulaires
        }
        let w = web
        clavier.ouvrirWeb(type: typeClavier, cible: .init(
            inserer: { t in
                w.callAsyncJavaScript("document.execCommand('insertText', false, t);", arguments: ["t": t],
                                      in: nil, in: .page, completionHandler: nil)
            },
            effacer: {
                w.evaluateJavaScript("document.execCommand('delete', false);", completionHandler: nil)
            },
            valider: {
                w.evaluateJavaScript("""
                (function () {
                  var el = document.activeElement; if (!el) return;
                  // Un seul envoi : par le formulaire s'il existe (comme Entrée sur
                  // un vrai clavier), sinon par une touche Entrée simulée.
                  if (el.form) {
                    var b = el.form.querySelector('button[type=submit]:not([disabled])');
                    if (b) { b.click(); } else if (el.form.requestSubmit) { el.form.requestSubmit(); }
                    return;
                  }
                  var o = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
                  el.dispatchEvent(new KeyboardEvent('keydown', o));
                  el.dispatchEvent(new KeyboardEvent('keypress', o));
                  el.dispatchEvent(new KeyboardEvent('keyup', o));
                })();
                """, completionHandler: nil)
            },
            quitter: {
                w.evaluateJavaScript("document.activeElement && document.activeElement.blur();", completionHandler: nil)
            },
            deplacer: { n in
                w.callAsyncJavaScript("""
                var e = document.activeElement;
                if (e && typeof e.selectionStart === 'number') {
                  var p = Math.max(0, Math.min(e.value.length, e.selectionStart + n));
                  e.setSelectionRange(p, p);
                }
                """, arguments: ["n": n], in: nil, in: .page, completionHandler: nil)
            }))
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
        affichee = false
        if let clavier, clavier.champ == Clavier.champWeb { clavier.fermer() }
        if etat == .pret, envoisActifs == 0, web.url?.path != Self.racine.path { web.load(URLRequest(url: Self.racine)) }
        guard web.superview !== fenetre else { return }
        web.removeFromSuperview()
        web.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
        web.alpha = 0.01
        web.isUserInteractionEnabled = false
        fenetre.insertSubview(web, at: 0)
    }

    /// Molette sur la page affichée.
    func defiler(_ dy: CGFloat) {
        guard affichee else { return }
        DefilementMolette.defiler(web.scrollView, de: dy)
    }

    /// Montre la WebView dans un conteneur (écran de connexion).
    func afficher(dans conteneur: UIView) {
        affichee = true
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
            organisation = nil
            etat = .connexionRequise
        } catch let e as ErreurHTTP where e.passagere {
            // Réseau ou page pas encore prête : ce n'est pas une déconnexion, on réessaie.
            if etat != .pret {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    await self?.verifier()
                }
            }
        } catch {
            if etat != .pret { etat = .connexionRequise }
        }
    }

    // MARK: - Appels

    struct ErreurHTTP: LocalizedError {
        let statut: Int
        let corps: String

        /// 0 = la requête n'a pas abouti (réseau coupé, page rechargée, iPhone en veille).
        var passagere: Bool { statut == 0 || statut == 408 || statut == 502 || statut == 503 || statut == 504 || statut == 529 }

        private var messageServeur: String? {
            guard let d = corps.data(using: .utf8),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
            if let e = j["error"] as? [String: Any], let m = e["message"] as? String { return m }
            if let m = j["detail"] as? String { return m }
            return nil
        }

        var errorDescription: String? {
            switch statut {
            case 0: return "Connexion à claude.ai perdue."
            case 401, 403: return "Session claude.ai expirée : reconnecte-toi."
            case 429: return messageServeur.map { "Limite claude.ai atteinte : \($0)" } ?? "Limite de messages claude.ai atteinte, réessaie plus tard."
            case 500...599: return "claude.ai est surchargé, réessaie dans un instant."
            default: return messageServeur ?? "claude.ai a répondu \(statut)."
            }
        }
    }

    /// Envois en cours : tant qu'il y en a, la page de repos n'est jamais rechargée.
    private var envoisActifs = 0

    /// Avant chaque appel : la page doit être sur claude.ai et le compte connu.
    /// Si iOS a tué ou vidé la page (veille, mémoire), on la recharge.
    func assurerPret() async throws {
        if web.url?.host?.hasSuffix("claude.ai") != true || web.isLoading {
            if web.url?.host?.hasSuffix("claude.ai") != true { web.load(URLRequest(url: Self.racine)) }
            for _ in 0..<40 where web.isLoading || web.url?.host?.hasSuffix("claude.ai") != true {
                try await Task.sleep(for: .milliseconds(250))
            }
        }
        if organisation == nil { await verifier() }
        if organisation == nil {
            throw etat == .connexionRequise ? ErreurClaude(message: "Connecte-toi à claude.ai.") : ErreurHTTP(statut: 0, corps: "")
        }
    }

    /// Au retour au premier plan : la page a pu être suspendue. Un petit appel
    /// vérifie qu'elle répond ; sinon on la recharge.
    func reveil() async {
        guard demarre, !affichee, envoisActifs == 0 else { return }
        do {
            _ = try await appel("/api/organizations")
        } catch let e as ErreurHTTP where e.statut == 0 {
            web.load(URLRequest(url: Self.racine))
        } catch {}
    }

    /// iOS a tué le processus de la page (mémoire) : on la relance.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        web.load(URLRequest(url: affichee ? URL(string: "https://claude.ai/login")! : Self.racine))
    }

    /// Un appel à claude.ai, fait par la page elle-même (avec tes cookies).
    @discardableResult
    func appel(_ chemin: String, methode: String = "GET", corps: [String: Any]? = nil) async throws -> Any? {
        let json = corps.flatMap { try? JSONSerialization.data(withJSONObject: $0) }.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let script = """
        try {
          const r = await fetch(chemin, {
            method: methode, credentials: 'include', cache: 'no-store',
            headers: { 'content-type': 'application/json', 'accept': 'application/json' },
            body: corps === '' ? undefined : corps
          });
          return { statut: r.status, texte: await r.text() };
        } catch (e) {
          return { statut: 0, texte: String(e) };
        }
        """
        let res: Any?
        do {
            res = try await web.callAsyncJavaScript(script, arguments: ["chemin": chemin, "methode": methode, "corps": json],
                                                    in: nil, contentWorld: .page)
        } catch {
            // Page en cours de rechargement, ou processus de la page tué.
            throw ErreurHTTP(statut: 0, corps: error.localizedDescription)
        }
        guard let d = res as? [String: Any], let statut = (d["statut"] as? NSNumber)?.intValue else {
            throw ErreurClaude(message: "Réponse illisible de claude.ai.")
        }
        let texte = d["texte"] as? String ?? ""
        guard (200..<300).contains(statut) else {
            if statut == 401 || statut == 403, !chemin.hasSuffix("/api/organizations") { etat = .connexionRequise }
            throw ErreurHTTP(statut: statut, corps: texte)
        }
        guard !texte.isEmpty, let donnees = texte.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: donnees)
    }

    private func org() throws -> String {
        guard let organisation else { throw ErreurClaude(message: "Connecte-toi à claude.ai.") }
        return organisation
    }

    // MARK: - Discussions

    func chargerConversations() async throws {
        try await assurerPret()
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
        try await assurerPret()
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
            // Le contenu détaillé est la version complète (plusieurs blocs de
            // texte quand Claude a utilisé des outils) : on le préfère.
            if let blocs = m["content"] as? [[String: Any]] {
                let complet = blocs.filter { ($0["type"] as? String) == "text" }
                    .compactMap { $0["text"] as? String }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n\n")
                if complet.count >= texte.count { texte = complet }
            }
            return MessageClaude(id: id, humain: humain, texte: texte)
        }
        let r2 = (resultat, chemin.last?["uuid"] as? String)
        memoire[uuid] = r2
        return r2
    }

    /// Crée une discussion vide et rend son identifiant.
    func nouvelleConversation() async throws -> String {
        try await assurerPret()
        let o = try org()
        let uuid = UUID().uuidString.lowercased()
        try await appel("/api/organizations/\(o)/chat_conversations", methode: "POST",
                        corps: ["uuid": uuid, "name": "", "include_conversation_preferences": true])
        return uuid
    }

    /// Envoie un message et reçoit la réponse au fil de l'eau.
    func envoyer(_ texte: String, dans uuid: String, parent: String?, recu: @escaping (String) -> Void) async throws {
        try await assurerPret()
        let o = try org()
        envoisActifs += 1
        defer { envoisActifs -= 1 }
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
        try {
          const r = await fetch(chemin, {
            method: 'POST', credentials: 'include', cache: 'no-store',
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
        } catch (e) {
          return { statut: 0, texte: String(e) };
        }
        """
        let res: Any?
        do {
            res = try await web.callAsyncJavaScript(
                script,
                arguments: ["chemin": "/api/organizations/\(o)/chat_conversations/\(uuid)/completion", "corps": json, "idFlux": idFlux],
                in: nil, contentWorld: .page)
        } catch {
            throw ErreurHTTP(statut: 0, corps: error.localizedDescription)
        }
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
        if message.name == "pinFocus" { cible?.focus(message.body) } else { cible?.recevoir(message.body) }
    }
}

/// Empêche le clavier d'iOS d'apparaître dans les pages web de Pin : la vue
/// de saisie de WebKit reçoit une vue vide à la place du clavier système, et
/// c'est le clavier Pin qui s'affiche sous l'écran.
private enum SansClavierSysteme {
    private static var fait = false
    private static let vide: UIView = {
        let v = UIView(frame: .zero)
        v.autoresizingMask = []
        return v
    }()

    static func installer() {
        guard !fait, let classe = NSClassFromString("WKContentView") else { return }
        fait = true
        let videBloc: @convention(block) (AnyObject) -> UIView? = { _ in SansClavierSysteme.vide }
        let rienBloc: @convention(block) (AnyObject) -> UIView? = { _ in nil }
        remplacer(classe, #selector(getter: UIResponder.inputView), imp_implementationWithBlock(videBloc))
        remplacer(classe, #selector(getter: UIResponder.inputAccessoryView), imp_implementationWithBlock(rienBloc))
    }

    /// Ajoute la méthode à WKContentView seulement (jamais à UIResponder).
    private static func remplacer(_ classe: AnyClass, _ sel: Selector, _ imp: IMP) {
        if !class_addMethod(classe, sel, imp, "@@:"), let m = class_getInstanceMethod(classe, sel) {
            method_setImplementation(m, imp)
        }
    }
}
