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
                let aleatoire: [ElementListe] = morceaux.isEmpty ? [] : [ElementListe(id: "__aleatoire", titre: "Lecture aléatoire", chevron: false)]
                let pistes: [ElementListe] = morceaux.map { ElementListe(id: $0.id, titre: $0.titre, detail: $0.artiste, chevron: false) }
                let elements = aleatoire + pistes
                EcranListe(cle: .musique, elements: elements,
                           vide: "Aucun morceau épinglé sur ton profil Telegram.") { e in
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
    @State private var etape = "telephone"
    @State private var telephone = "+33"
    @State private var code = ""
    @State private var motDePasse = ""
    @State private var erreur: String?
    @State private var enCours = false

    private struct Reponse: Decodable { let etape: String?; let lie: Bool? }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let s = statut, s.lie {
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
                } else if statut?.configure == false {
                    Text("Le serveur n'a pas encore d'identifiants Telegram (TG_API_ID et TG_API_HASH dans pin.env).")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else if etape == "telephone" {
                    Text("Ton numéro Telegram, avec l'indicatif.").font(.system(size: 12)).foregroundStyle(.secondary)
                    ChampIPod(titre: "+33 6 12 34 56 78", texte: $telephone, type: .telephone, libelleRetour: "envoyer", retour: { valider() })
                    BoutonIPod(titre: enCours ? "Envoi…" : "Recevoir le code", actif: !enCours) { valider() }
                } else if etape == "code" {
                    Text("Tape le code reçu dans Telegram.").font(.system(size: 12)).foregroundStyle(.secondary)
                    ChampIPod(titre: "Code", texte: $code, type: .numero, libelleRetour: "valider", retour: { valider() })
                    BoutonIPod(titre: enCours ? "Vérification…" : "Valider", actif: !enCours && !code.isEmpty) { valider() }
                } else {
                    Text("Ton compte a un mot de passe (validation en deux étapes).")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    ChampIPod(titre: "Mot de passe Telegram", texte: $motDePasse, secret: true, libelleRetour: "valider", retour: { valider() })
                    BoutonIPod(titre: enCours ? "Vérification…" : "Valider", actif: !enCours && !motDePasse.isEmpty) { valider() }
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
        statut = try? await API.get("/api/telegram/statut", StatutTelegram.self)
        if let e = statut?.etape { etape = e } else if statut?.lie == false { etape = "telephone" }
    }

    private func valider() {
        guard !enCours, statut?.lie != true else { return }
        enCours = true
        erreur = nil
        Task {
            do {
                let r: Reponse
                switch etape {
                case "telephone":
                    r = try await API.post("/api/telegram/code", ["telephone": telephone], Reponse.self)
                case "code":
                    r = try await API.post("/api/telegram/connexion", ["code": code], Reponse.self)
                default:
                    r = try await API.post("/api/telegram/connexion", ["motDePasse": motDePasse], Reponse.self)
                }
                if r.lie == true {
                    await rafraichir()
                    nav.retour()
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
