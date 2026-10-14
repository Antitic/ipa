import SwiftUI
import UniformTypeIdentifiers

/// Fichier choisi dans l'app Fichiers, lu en entier (accès temporaire).
func lireFichierChoisi(_ url: URL) -> (Data, String)? {
    let acces = url.startAccessingSecurityScopedResource()
    defer { if acces { url.stopAccessingSecurityScopedResource() } }
    guard let d = try? Data(contentsOf: url) else { return nil }
    return (d, url.lastPathComponent)
}

/// Musique › Ajouter des morceaux : les audios de ton Telegram (Messages
/// enregistrés et discussions), ou un fichier de l'iPhone, ajoutés à ton profil.
struct EcranAjoutMusique: View {
    @EnvironmentObject var nav: Navigateur
    @State private var recherche = ""
    @State private var audios: [AudioTrouve]?
    @State private var etat: String?
    @State private var choixFichier = false
    @State private var enCours = false
    @State private var ajoutes: Set<String> = []

    struct AudioTrouve: Decodable, Identifiable {
        let chat: String
        let message: Int
        let titre: String
        let artiste: String?
        let duree: Double
        let ou: String
        var id: String { "\(chat):\(message)" }
    }

    private var elements: [ElementListe] {
        var e = [ElementListe(id: "__fichier", titre: "Depuis l'iPhone (Fichiers)…")]
        for a in audios ?? [] {
            let fait = ajoutes.contains(a.id)
            e.append(ElementListe(id: a.id, titre: (fait ? "✓ " : "") + a.titre,
                                  detail: [a.artiste, a.ou].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                                  chevron: false))
        }
        return e
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ChampIPod(titre: "Chercher dans Telegram", texte: $recherche, libelleRetour: "chercher", retour: { Task { await charger() } })
            }
            .padding(6)
            .background(Color(white: 0.93))
            if let etat {
                Text(etat).font(.system(size: 11)).foregroundStyle(.secondary).padding(.vertical, 3)
            }
            if audios == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EcranListe(cle: .ajoutMusique, elements: elements, vide: "Aucun audio trouvé.") { e in
                    if e.id == "__fichier" { choixFichier = true } else { ajouter(e.id) }
                }
            }
        }
        .fileImporter(isPresented: $choixFichier, allowedContentTypes: [.audio], allowsMultipleSelection: true) { r in
            guard case .success(let urls) = r else { return }
            Task { await envoyerFichiers(urls) }
        }
        .task { await charger() }
    }

    private func charger() async {
        let q = recherche.trimmingCharacters(in: .whitespaces)
        let chemin = "/api/telegram/audios" + (q.isEmpty ? "" : "?q=" + (q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""))
        do {
            audios = try await API.get(chemin, [AudioTrouve].self)
            etat = nil
        } catch {
            audios = audios ?? []
            etat = error.localizedDescription
        }
    }

    private func ajouter(_ id: String) {
        guard let a = audios?.first(where: { $0.id == id }), !enCours, !ajoutes.contains(id) else { return }
        enCours = true
        etat = "Ajout de « \(a.titre) »…"
        Task {
            do {
                struct R: Decodable { let ok: Bool }
                _ = try await API.post("/api/telegram/profil/ajouter", ["chat": a.chat, "message": a.message], R.self)
                ajoutes.insert(id)
                etat = "« \(a.titre) » est sur ton profil."
            } catch {
                etat = error.localizedDescription
            }
            enCours = false
        }
    }

    private func envoyerFichiers(_ urls: [URL]) async {
        for (i, url) in urls.enumerated() {
            guard case let (data, nom)? = lireFichierChoisi(url) else { etat = "Fichier illisible."; continue }
            etat = "Envoi \(i + 1)/\(urls.count) : \(nom)…"
            do {
                let chemin = "/api/telegram/profil/fichier?nom=" + (nom.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "audio")
                _ = try await API.requete(chemin, methode: "POST", corps: data, type: "application/octet-stream", delai: 300)
                etat = "« \(nom) » est sur ton profil."
            } catch {
                etat = error.localizedDescription
            }
        }
    }
}
