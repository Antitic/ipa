import SwiftUI

struct EcranMorceaux: View {
    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var compte: Compte
    @EnvironmentObject var lecteur: Lecteur
    @State private var morceaux: [Morceau]?
    @State private var erreur: String?
    @State private var nonLie = false

    var body: some View {
        Group {
            if !compte.connecte {
                BesoinCompte()
            } else if nonLie {
                MessageEcran(icone: "music.note.list", texte: "Telegram n'est pas lié",
                             detail: "Bouton central : lier ton compte Telegram.")
                    .roue { g in g.centre = { nav.ouvrir(.telegram) } }
            } else if let erreur {
                MessageEcran(icone: "exclamationmark.triangle", texte: "Musique indisponible", detail: erreur)
                    .roue { g in g.centre = { Task { await charger() } } }
            } else if let morceaux {
                let aleatoire: [ElementListe] = morceaux.isEmpty ? [] : [
                    ElementListe(id: "__coverflow", titre: "Cover Flow"),
                    ElementListe(id: "__aleatoire", titre: "Lecture aléatoire", detail: "ou secoue l'iPhone", chevron: false),
                ]
                let pistes: [ElementListe] = morceaux.map { ElementListe(id: $0.id, titre: $0.titre, detail: $0.artiste, chevron: false) }
                let elements = aleatoire + pistes
                EcranListe(cle: .musique, elements: elements,
                           vide: "Aucun morceau épinglé sur ton profil Telegram.") { e in
                    if e.id == "__coverflow" {
                        nav.ouvrir(.coverFlow)
                        return
                    }
                    if e.id == "__aleatoire" {
                        lecteur.jouer(morceaux.shuffled(), depuis: 0)
                    } else if let i = morceaux.firstIndex(where: { $0.id == e.id }) {
                        lecteur.jouer(morceaux, depuis: i)
                    }
                    nav.ouvrir(.enLecture)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await charger() }
    }

    private func charger() async {
        guard compte.connecte else { return }
        erreur = nil
        do {
            morceaux = try await API.get("/api/musique", [Morceau].self)
            nonLie = false
        } catch let e as ErreurPin where e.statut == 409 {
            nonLie = true
        } catch {
            erreur = error.localizedDescription
        }
    }
}

struct EcranEnLecture: View {
    @EnvironmentObject var lecteur: Lecteur
    @State private var mode: Mode = .volume
    @State private var volumeVisible = false
    @State private var masquage: Task<Void, Never>?

    enum Mode { case volume, avance }

    var body: some View {
        Group {
            if let m = lecteur.courant {
                VStack(spacing: 8) {
                    HStack(alignment: .top, spacing: 10) {
                        pochette
                        VStack(alignment: .leading, spacing: 3) {
                            Text(m.titre).font(.system(size: 15, weight: .bold)).lineLimit(2)
                            if let a = m.artiste {
                                Text(a).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Text("\(lecteur.index + 1) sur \(lecteur.file.count)")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                            if lecteur.chargement {
                                Text("Chargement…").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            if let e = lecteur.erreur {
                                Text(e).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                    if mode == .volume && volumeVisible {
                        barreVolume
                    } else {
                        barreTemps
                    }
                }
                .padding(10)
            } else {
                MessageEcran(icone: "music.note", texte: "Rien en lecture")
            }
        }
        .roue { g in
            g.tour = { s in tourner(s) }
            g.centre = {
                mode = (mode == .volume) ? .avance : .volume
                volumeVisible = false
            }
        }
    }

    private func tourner(_ s: Int) {
        switch mode {
        case .volume:
            lecteur.volume = min(max(lecteur.volume + Float(s) * 0.05, 0), 1)
            volumeVisible = true
            masquage?.cancel()
            masquage = Task {
                try? await Task.sleep(for: .seconds(1.5))
                if !Task.isCancelled { volumeVisible = false }
            }
        case .avance:
            lecteur.avancer(Double(s) * 5)
        }
    }

    private var pochette: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.9))
            if let img = lecteur.pochette {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Image(systemName: "music.note").font(.system(size: 28)).foregroundStyle(Color(white: 0.6))
            }
        }
        .frame(width: 92, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .rotation3DEffect(.degrees(12), axis: (x: 0, y: 1, z: 0))
        .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
    }

    private var barreTemps: some View {
        VStack(spacing: 3) {
            BarreProgression(valeur: lecteur.duree > 0 ? lecteur.position / lecteur.duree : 0, avance: mode == .avance)
            HStack {
                Text(temps(lecteur.position))
                Spacer()
                Text("-" + temps(max(lecteur.duree - lecteur.position, 0)))
            }
            .font(.system(size: 11, weight: .medium).monospacedDigit())
        }
    }

    private var barreVolume: some View {
        HStack(spacing: 6) {
            Image(systemName: "speaker.fill").font(.system(size: 10))
            BarreProgression(valeur: Double(lecteur.volume), avance: false)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10))
        }
        .padding(.bottom, 14)
    }

    private func temps(_ s: Double) -> String {
        guard s.isFinite else { return "0:00" }
        let t = Int(s)
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

struct BarreProgression: View {
    let valeur: Double
    var avance: Bool

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(white: 0.85))
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.66, blue: 0.95), Color(red: 0.16, green: 0.44, blue: 0.86)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: max(0, g.size.width * min(max(valeur, 0), 1)))
                if avance {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.3))
                        .offset(x: max(0, g.size.width * min(max(valeur, 0), 1) - 5))
                }
            }
        }
        .frame(height: 8)
        .overlay(Capsule().stroke(Color(white: 0.6), lineWidth: 0.5))
    }
}

struct EcranTelegram: View {
    @EnvironmentObject var nav: Navigateur
    @State private var statut: StatutTelegram?
    /// "api-telephone", "api-code", "api-manuel" (identifiants d'API), puis "telephone", "code", "mot-de-passe".
    @State private var etape = "telephone"
    @State private var telephone = "+33"
    @State private var code = ""
    @State private var codeApi = ""
    @State private var apiId = ""
    @State private var apiHash = ""
    @State private var motDePasse = ""
    @State private var erreur: String?
    @State private var enCours = false

    private struct Reponse: Decodable { let etape: String?; let lie: Bool?; let etapeApi: String?; let configure: Bool? }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if statut == nil {
                    Text("Chargement…").font(.system(size: 12)).foregroundStyle(.secondary)
                } else if let s = statut, s.lie {
                    Text("Telegram est lié").font(.system(size: 15, weight: .semibold))
                    if let nom = s.nom { Text(nom).font(.system(size: 13)).foregroundStyle(.secondary) }
                    Text("La musique épinglée sur ton profil apparaît dans Musique.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    BoutonIPod(titre: "Délier Telegram") {
                        Task {
                            _ = try? await API.requete("/api/telegram/deconnexion", methode: "POST", json: [:])
                            await rafraichir()
                        }
                    }
                } else {
                    switch etape {
                    case "api-telephone":
                        Text("Étape 1 sur 2").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Text("Pin doit d'abord obtenir une clé d'API Telegram. Ton numéro, avec l'indicatif : Telegram t'enverra un code (dans l'app, pas par SMS).")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        ChampIPod(titre: "+33 6 12 34 56 78", texte: $telephone, type: .telephone, libelleRetour: "envoyer", retour: { valider() })
                        BoutonIPod(titre: enCours ? "Envoi…" : "Recevoir le code", actif: !enCours) { valider() }
                        BoutonIPod(titre: "J'ai déjà api_id et api_hash") { erreur = nil; etape = "api-manuel" }
                    case "api-code":
                        Text("Étape 1 sur 2").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Text("Tape le code envoyé par Telegram (message de « Telegram », il contient des lettres et des chiffres).")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        ChampIPod(titre: "Code", texte: $codeApi, type: .texte, libelleRetour: "valider", retour: { valider() })
                        BoutonIPod(titre: enCours ? "Création de la clé…" : "Valider", actif: !enCours && !codeApi.isEmpty) { valider() }
                        BoutonIPod(titre: "Redemander un code") { erreur = nil; codeApi = ""; etape = "api-telephone" }
                    case "api-manuel":
                        Text("Copie-les depuis my.telegram.org › API development tools.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        ChampIPod(titre: "api_id", texte: $apiId, type: .numero)
                        ChampIPod(titre: "api_hash", texte: $apiHash, type: .texte, libelleRetour: "valider", retour: { valider() })
                        BoutonIPod(titre: enCours ? "Enregistrement…" : "Enregistrer", actif: !enCours && !apiId.isEmpty && !apiHash.isEmpty) { valider() }
                        BoutonIPod(titre: "Plutôt par code") { erreur = nil; etape = "api-telephone" }
                    case "telephone":
                        Text("Étape 2 sur 2").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Text("Connecte ton compte : Telegram va t'envoyer un nouveau code.").font(.system(size: 12)).foregroundStyle(.secondary)
                        ChampIPod(titre: "+33 6 12 34 56 78", texte: $telephone, type: .telephone, libelleRetour: "envoyer", retour: { valider() })
                        BoutonIPod(titre: enCours ? "Envoi…" : "Recevoir le code", actif: !enCours) { valider() }
                    case "code":
                        Text("Tape le code reçu dans Telegram.").font(.system(size: 12)).foregroundStyle(.secondary)
                        ChampIPod(titre: "Code", texte: $code, type: .numero, libelleRetour: "valider", retour: { valider() })
                        BoutonIPod(titre: enCours ? "Vérification…" : "Valider", actif: !enCours && !code.isEmpty) { valider() }
                    default:
                        Text("Ton compte a un mot de passe (validation en deux étapes).")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        ChampIPod(titre: "Mot de passe Telegram", texte: $motDePasse, secret: true, libelleRetour: "valider", retour: { valider() })
                        BoutonIPod(titre: enCours ? "Vérification…" : "Valider", actif: !enCours && !motDePasse.isEmpty) { valider() }
                    }
                }
                if let erreur {
                    Text(erreur).font(.system(size: 12)).foregroundStyle(.red)
                }
            }
            .padding(12)
        }
        .task { await rafraichir() }
        .roue { g in g.centre = { valider() } }
    }

    private func rafraichir() async {
        do {
            let s = try await API.get("/api/telegram/statut", StatutTelegram.self)
            statut = s
            if s.lie { return }
            if s.configure == false {
                if s.etapeApi == "code" { etape = "api-code" }
                else if !etape.hasPrefix("api-") { etape = "api-telephone" }
            } else if let e = s.etape {
                etape = e
            } else if etape.hasPrefix("api-") || etape == "telephone" {
                etape = "telephone"
            }
        } catch {
            erreur = error.localizedDescription
        }
    }

    private func valider() {
        guard !enCours, statut?.lie != true else { return }
        enCours = true
        erreur = nil
        Task {
            do {
                let r: Reponse
                switch etape {
                case "api-telephone":
                    r = try await API.post("/api/telegram/api/code", ["telephone": telephone], Reponse.self)
                case "api-code":
                    r = try await API.post("/api/telegram/api/valider", ["code": codeApi], Reponse.self)
                case "api-manuel":
                    r = try await API.post("/api/telegram/api/manuel", ["apiId": apiId, "apiHash": apiHash], Reponse.self)
                case "telephone":
                    r = try await API.post("/api/telegram/code", ["telephone": telephone], Reponse.self)
                case "code":
                    r = try await API.post("/api/telegram/connexion", ["code": code], Reponse.self)
                default:
                    r = try await API.post("/api/telegram/connexion", ["motDePasse": motDePasse], Reponse.self)
                }
                if r.configure == true {
                    // Clé obtenue : on enchaîne sur la connexion du compte.
                    etape = "telephone"
                    await rafraichir()
                } else if r.lie == true {
                    await rafraichir()
                    nav.retour()
                } else if r.etapeApi == "code" {
                    etape = "api-code"
                } else if let e = r.etape {
                    etape = e
                }
            } catch {
                erreur = error.localizedDescription
            }
            enCours = false
        }
    }
}
