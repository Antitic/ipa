import SwiftUI
import Security

// MARK: - Modèles (API /app/v1 du webmail, la même que l'app Meyl)

struct BoiteMail: Codable, Identifiable, Hashable {
    let path: String
    let label: String
    var total: Int?
    var unseen: Int?
    var id: String { path }
}

struct LigneMail: Codable, Identifiable, Hashable {
    let uid: Int
    let box: String
    let subject: String
    let name: String
    let address: String
    let date: Date?
    var seen: Bool
    let att: Bool
    var id: String { box + "/" + String(uid) }
}

struct LettreMail: Codable, Hashable {
    let box: String
    let uid: Int
    let subject: String
    let fromName: String
    let fromAddress: String
    let to: String
    let replyTo: String
    let date: Date?
    let text: String
    let messageId: String
    let references: String
}

/// Le courrier de ton adresse @dipherant.xyz, comme dans Meyl.
@MainActor
final class Courrier: ObservableObject {
    static let partage = Courrier()

    @Published private(set) var boites: [BoiteMail] = []
    @Published private(set) var nonLus = 0
    @Published var motDePasseManquant = false

    private static let base = URL(string: "https://mail.dipherant.xyz/app/v1")!
    private var email: String?

    static let decodeur: JSONDecoder = {
        let d = JSONDecoder()
        let a = ISO8601DateFormatter()
        a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let b = ISO8601DateFormatter()
        b.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = a.date(from: s) ?? b.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: s)
        }
        return d
    }()

    func configurer(email: String?) {
        self.email = email
        motDePasseManquant = email != nil && Self.motDePasse() == nil
    }

    // MARK: Mot de passe (trousseau, avec repli si LiveContainer le refuse)

    private static let service = "com.antitic.pin"

    static func enregistrer(motDePasse: String?) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service, kSecAttrAccount as String: "mail"]
        SecItemDelete(base as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "secours.mail")
        guard let motDePasse, !motDePasse.isEmpty else { return }
        var ajout = base
        ajout[kSecValueData as String] = Data(motDePasse.utf8)
        ajout[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(ajout as CFDictionary, nil) != errSecSuccess {
            UserDefaults.standard.set(motDePasse, forKey: "secours.mail")
        }
    }

    static func motDePasse() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                kSecAttrAccount as String: "mail", kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var sortie: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &sortie) == errSecSuccess, let d = sortie as? Data {
            return String(data: d, encoding: .utf8)
        }
        return UserDefaults.standard.string(forKey: "secours.mail")
    }

    // MARK: Requêtes

    func requete(_ chemin: String, _ query: [URLQueryItem] = [], methode: String = "GET",
                 corps: Data? = nil, type: String? = nil) async throws -> Data {
        guard let email, let mdp = Self.motDePasse() else {
            motDePasseManquant = true
            throw ErreurPin(message: "Mot de passe du courrier requis.", statut: 401)
        }
        var c = URLComponents(url: Self.base.appendingPathComponent(String(chemin.dropFirst())), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { c.queryItems = query }
        var req = URLRequest(url: c.url!)
        req.httpMethod = methode
        req.timeoutInterval = 30
        req.setValue("Basic " + Data("\(email):\(mdp)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let type { req.setValue(type, forHTTPHeaderField: "Content-Type") }
        req.httpBody = corps
        let (data, rep) = try await URLSession.shared.data(for: req)
        let statut = (rep as? HTTPURLResponse)?.statusCode ?? 0
        if statut == 401 {
            motDePasseManquant = true
            throw ErreurPin(message: "Mot de passe du courrier refusé.", statut: 401)
        }
        guard (200..<300).contains(statut) else {
            struct E: Decodable { let error: String }
            let msg = (try? JSONDecoder().decode(E.self, from: data))?.error ?? "Serveur de courrier injoignable."
            throw ErreurPin(message: msg, statut: statut)
        }
        motDePasseManquant = false
        return data
    }

    func get<T: Decodable>(_ chemin: String, _ query: [URLQueryItem] = [], _ t: T.Type = T.self) async throws -> T {
        try Self.decodeur.decode(T.self, from: try await requete(chemin, query))
    }

    func post(_ chemin: String, _ json: [String: Any]) async throws {
        _ = try await requete(chemin, methode: "POST", corps: try JSONSerialization.data(withJSONObject: json), type: "application/json")
    }

    func rafraichir() async {
        struct Moi: Decodable { let boxes: [BoiteMail] }
        guard email != nil, Self.motDePasse() != nil, let m = try? await get("/me", [], Moi.self) else { return }
        boites = m.boxes
        nonLus = m.boxes.first(where: { $0.path == "INBOX" })?.unseen ?? 0
    }

    func liste(_ boite: String, avant: Int? = nil) async throws -> (lignes: [LigneMail], plus: Bool) {
        struct R: Decodable { let rows: [LigneMail]; let more: Bool }
        var q = [URLQueryItem(name: "box", value: boite)]
        if let avant { q.append(URLQueryItem(name: "before", value: String(avant))) }
        let r = try await get("/list", q, R.self)
        return (r.rows, r.more)
    }

    func lettre(_ boite: String, _ uid: Int) async throws -> LettreMail {
        try await get("/message/\(boite)/\(uid)")
    }

    func marquerLu(_ boite: String, _ uid: Int) async {
        try? await post("/flag", ["box": boite, "uid": uid, "seen": true])
        await rafraichir()
    }

    func deplacer(_ boite: String, _ uid: Int, vers: String) async throws {
        try await post("/move", ["box": boite, "uid": uid, "to": vers])
        await rafraichir()
    }

    func envoyer(a: String, objet: String, texte: String, enReponseA: String = "", references: String = "") async throws {
        let frontiere = "pin-" + UUID().uuidString
        var corps = Data()
        func champ(_ nom: String, _ valeur: String) {
            corps.append(Data("--\(frontiere)\r\nContent-Disposition: form-data; name=\"\(nom)\"\r\n\r\n\(valeur)\r\n".utf8))
        }
        champ("to", a)
        champ("cc", "")
        champ("subject", objet)
        champ("body", texte)
        if !enReponseA.isEmpty { champ("inReplyTo", enReponseA) }
        if !references.isEmpty { champ("references", references) }
        corps.append(Data("--\(frontiere)--\r\n".utf8))
        _ = try await requete("/send", methode: "POST", corps: corps, type: "multipart/form-data; boundary=\(frontiere)")
    }
}

// MARK: - Écrans

/// Les casiers : Réception, Envoyés, Archive, Corbeille.
struct EcranMail: View {
    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var compte: Compte
    @ObservedObject private var courrier = Courrier.partage

    var body: some View {
        Group {
            if !compte.connecte {
                BesoinCompte()
            } else if courrier.motDePasseManquant {
                EcranMotDePasseMail()
            } else {
                let boites = courrier.boites.isEmpty
                    ? [BoiteMail(path: "INBOX", label: "Réception"), BoiteMail(path: "Sent", label: "Envoyés"),
                       BoiteMail(path: "Archive", label: "Archive"), BoiteMail(path: "Trash", label: "Corbeille")]
                    : courrier.boites
                let elements = [ElementListe(id: "__ecrire", titre: "Nouveau message")] + boites.map {
                    ElementListe(id: $0.path, titre: $0.label,
                                 badge: ($0.unseen ?? 0) > 0 && $0.path == "INBOX" ? "\($0.unseen!)" : nil)
                }
                EcranListe(cle: .mail, elements: elements) { e in
                    if e.id == "__ecrire" {
                        nav.ouvrir(.ecrireMail(reponse: nil))
                    } else {
                        nav.ouvrir(.boiteMail(path: e.id, nom: e.titre))
                    }
                }
            }
        }
        .task {
            courrier.configurer(email: compte.email)
            await courrier.rafraichir()
        }
    }
}

struct EcranMotDePasseMail: View {
    @ObservedObject private var courrier = Courrier.partage
    @EnvironmentObject var compte: Compte
    @State private var mdp = ""
    @State private var erreur: String?
    @State private var enCours = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Mot de passe de \(compte.email ?? "ton adresse")").font(.system(size: 13, weight: .semibold))
            Text("Le même que dans Meyl. Demandé une seule fois.").font(.system(size: 11)).foregroundStyle(.secondary)
            ChampIPod(titre: "Mot de passe", texte: $mdp, secret: true, type: .email, libelleRetour: "OK", retour: { valider() })
            if let erreur { Text(erreur).font(.system(size: 11)).foregroundStyle(.red) }
            BoutonIPod(titre: enCours ? "Vérification…" : "Valider", actif: !mdp.isEmpty && !enCours) { valider() }
            Spacer()
        }
        .padding(12)
        .roue { g in g.centre = { valider() } }
    }

    private func valider() {
        guard !mdp.isEmpty, !enCours else { return }
        enCours = true
        erreur = nil
        Courrier.enregistrer(motDePasse: mdp)
        Task {
            await courrier.rafraichir()
            if courrier.boites.isEmpty {
                Courrier.enregistrer(motDePasse: nil)
                courrier.motDePasseManquant = true
                erreur = "Mot de passe refusé."
            }
            enCours = false
        }
    }
}

/// Un casier : expéditeur, objet ; les non lus en gras (point bleu).
struct EcranBoiteMail: View {
    let path: String
    @EnvironmentObject var nav: Navigateur
    @State private var lignes: [LigneMail] = []
    @State private var plus = false
    @State private var charge = false
    @State private var erreur: String?

    private var elements: [ElementListe] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.doesRelativeDateFormatting = true
        f.dateStyle = .short
        f.timeStyle = .none
        var e = lignes.map { l in
            ElementListe(id: l.id, titre: (l.seen ? "" : "● ") + (l.name.isEmpty ? l.address : l.name),
                         detail: [l.date.map { f.string(from: $0) }, l.subject.isEmpty ? "(sans objet)" : l.subject]
                            .compactMap { $0 }.joined(separator: " · "),
                         chevron: true)
        }
        if plus { e.append(ElementListe(id: "__plus", titre: "Plus anciens…", chevron: false)) }
        return e
    }

    var body: some View {
        Group {
            if let erreur, lignes.isEmpty {
                MessageEcran(icone: "exclamationmark.triangle", texte: "Courrier indisponible", detail: erreur)
                    .roue { g in g.centre = { Task { await charger() } } }
            } else {
                EcranListe(cle: .boiteMail(path: path, nom: ""), elements: elements,
                           vide: charge ? "Aucun message." : "Relève…") { e in
                    if e.id == "__plus" {
                        Task { await charger(plusAnciens: true) }
                    } else if let l = lignes.first(where: { $0.id == e.id }) {
                        if let i = lignes.firstIndex(of: l) { lignes[i].seen = true }
                        nav.ouvrir(.lettreMail(box: l.box, uid: l.uid))
                    }
                }
            }
        }
        .task { await charger() }
    }

    private func charger(plusAnciens: Bool = false) async {
        do {
            let r = try await Courrier.partage.liste(path, avant: plusAnciens ? lignes.last?.uid : nil)
            lignes = plusAnciens ? lignes + r.lignes : r.lignes
            plus = r.plus
            erreur = nil
        } catch {
            erreur = error.localizedDescription
        }
        charge = true
    }
}

/// Une lettre : la molette fait défiler, le centre répond.
struct EcranLettreMail: View {
    let box: String
    let uid: Int
    @EnvironmentObject var nav: Navigateur
    @StateObject private var defilement = DefilementMolette()
    @State private var lettre: LettreMail?
    @State private var erreur: String?

    var body: some View {
        Group {
            if let l = lettre {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(l.subject.isEmpty ? "(sans objet)" : l.subject).font(.system(size: 15, weight: .bold))
                            Text(l.fromName.isEmpty ? l.fromAddress : "\(l.fromName) <\(l.fromAddress)>")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            if let d = l.date {
                                Text(d, format: .dateTime.day().month(.wide).hour().minute())
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Divider()
                            Text(l.text.isEmpty ? "(message vide)" : l.text)
                                .font(.system(size: 13))
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(AncreDefilement(defilement: defilement).frame(width: 0, height: 0), alignment: .top)
                    }
                    HStack(spacing: 6) {
                        BoutonIPod(titre: "Répondre") { repondre() }
                        BoutonIPod(titre: box == "Archive" ? "Réception" : "Archiver") { ranger(box == "Archive" ? "INBOX" : "Archive") }
                        BoutonIPod(titre: "Corbeille") { ranger("Trash") }
                    }
                    .padding(6)
                    .background(Color(white: 0.93))
                }
            } else if let erreur {
                MessageEcran(icone: "exclamationmark.triangle", texte: "Lettre illisible", detail: erreur)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.white)
        .task {
            do {
                lettre = try await Courrier.partage.lettre(box, uid)
                await Courrier.partage.marquerLu(box, uid)
            } catch {
                erreur = error.localizedDescription
            }
        }
        .roue { g in
            let d = defilement
            g.tour = { s in d.cran(s) }
            g.centre = { repondre() }
        }
    }

    private func repondre() {
        guard let l = lettre else { return }
        nav.ouvrir(.ecrireMail(reponse: ReponseMail(lettre: l)))
    }

    private func ranger(_ vers: String) {
        Task {
            try? await Courrier.partage.deplacer(box, uid, vers: vers)
            nav.retour()
        }
    }
}

/// Ce qu'il faut pour répondre à une lettre.
struct ReponseMail: Hashable {
    let a: String
    let objet: String
    let citation: String
    let messageId: String
    let references: String

    init(lettre l: LettreMail) {
        a = l.replyTo.isEmpty ? l.fromAddress : l.replyTo
        objet = l.subject.lowercased().hasPrefix("re:") ? l.subject : "Re: " + l.subject
        let date = l.date.map { DateFormatter.localizedString(from: $0, dateStyle: .medium, timeStyle: .short) } ?? ""
        let cite = l.text.split(separator: "\n", omittingEmptySubsequences: false).prefix(40).map { "> " + $0 }.joined(separator: "\n")
        citation = "\n\nLe \(date), \(l.fromName.isEmpty ? l.fromAddress : l.fromName) a écrit :\n" + cite
        messageId = l.messageId
        references = (l.references + " " + l.messageId).trimmingCharacters(in: .whitespaces)
    }
}

struct EcranEcrireMail: View {
    let reponse: ReponseMail?
    @EnvironmentObject var nav: Navigateur
    @State private var a = ""
    @State private var objet = ""
    @State private var texte = ""
    @State private var envoi = false
    @State private var erreur: String?
    @State private var idTexte = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ChampIPod(titre: "À : adresse@exemple.fr", texte: $a, type: .email)
                ChampIPod(titre: "Objet", texte: $objet)
                ZoneSaisie(id: idTexte, titre: "Message", texte: $texte, libelleRetour: "retour") { texte += "\n" }
                    .frame(minHeight: 70, alignment: .top)
                if let erreur { Text(erreur).font(.system(size: 11)).foregroundStyle(.red) }
                BoutonIPod(titre: envoi ? "Envoi…" : "Envoyer", actif: !envoi && a.contains("@")) { envoyer() }
            }
            .padding(10)
        }
        .background(Color.white)
        .onAppear {
            guard let r = reponse, a.isEmpty else { return }
            a = r.a
            objet = r.objet
        }
        .roue { g in g.centre = { envoyer() } }
    }

    private func envoyer() {
        guard !envoi, a.contains("@") else { return }
        envoi = true
        erreur = nil
        Task {
            do {
                try await Courrier.partage.envoyer(a: a, objet: objet, texte: texte + (reponse?.citation ?? ""),
                                                   enReponseA: reponse?.messageId ?? "", references: reponse?.references ?? "")
                nav.retour()
            } catch {
                erreur = error.localizedDescription
            }
            envoi = false
        }
    }
}
