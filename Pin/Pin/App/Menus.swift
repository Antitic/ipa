import SwiftUI

struct MenuPrincipal: View {
    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var lecteur: Lecteur
    @EnvironmentObject var whatsapp: WhatsAppStore

    var body: some View {
        var elements = [
            ElementListe(id: "musique", titre: "Musique"),
            ElementListe(id: "whatsapp", titre: "WhatsApp", badge: whatsapp.nonLus > 0 ? "\(whatsapp.nonLus)" : nil),
            ElementListe(id: "photos", titre: "Photos"),
            ElementListe(id: "claude", titre: "Claude"),
            ElementListe(id: "reglages", titre: "Réglages"),
        ]
        if lecteur.courant != nil {
            elements.append(ElementListe(id: "enlecture", titre: "En lecture"))
        }
        return EcranListe(cle: .menu, elements: elements) { e in
            switch e.id {
            case "musique": nav.ouvrir(.musique)
            case "whatsapp": nav.ouvrir(.whatsapp)
            case "photos": nav.ouvrir(.photos)
            case "claude": nav.ouvrir(.claude)
            case "reglages": nav.ouvrir(.reglages)
            default: nav.ouvrir(.enLecture)
            }
        }
    }
}

struct MenuPhotos: View {
    @EnvironmentObject var nav: Navigateur

    var body: some View {
        EcranListe(cle: .photos, elements: [
            ElementListe(id: "camera", titre: "Appareil photo"),
            ElementListe(id: "pellicule", titre: "Pellicule"),
        ]) { e in
            nav.ouvrir(e.id == "camera" ? .camera : .pellicule)
        }
    }
}

struct EcranReglages: View {
    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var compte: Compte
    @EnvironmentObject var whatsapp: WhatsAppStore
    @EnvironmentObject var lecteur: Lecteur
    @AppStorage("haptique") private var haptique = true
    @AppStorage("clics") private var clics = true
    @State private var telegramLie: Bool?
    @State private var confirmation: String?

    private var detailWhatsApp: String {
        guard compte.connecte else { return "Compte Pin requis" }
        if !whatsapp.lie { return "Non lié" }
        return whatsapp.connecte ? "Lié · connecté" : "Lié"
    }

    private var detailTelegram: String {
        guard compte.connecte else { return "Compte Pin requis" }
        switch telegramLie {
        case .some(true): return "Lié"
        case .some(false): return "Non lié"
        case .none: return "…"
        }
    }

    var body: some View {
        let elements: [ElementListe] = [
            ElementListe(id: "compte", titre: "Compte Pin", detail: compte.email ?? "Non connecté"),
            ElementListe(id: "whatsapp", titre: "WhatsApp", detail: detailWhatsApp),
            ElementListe(id: "telegram", titre: "Telegram (musique)", detail: detailTelegram),
            ElementListe(id: "clics", titre: "Clics", detail: clics ? "Oui (coupés en mode silencieux)" : "Non", chevron: false),
            ElementListe(id: "haptique", titre: "Retour haptique", detail: haptique ? "Oui" : "Non", chevron: false),
            ElementListe(id: "cache", titre: "Vider le cache musique", detail: confirmation, chevron: false),
        ]
        EcranListe(cle: .reglages, elements: elements) { e in
            switch e.id {
            case "compte": nav.ouvrir(.connexion)
            case "whatsapp": if compte.connecte { nav.ouvrir(.liaisonWhatsApp) } else { nav.ouvrir(.connexion) }
            case "telegram": if compte.connecte { nav.ouvrir(.telegram) } else { nav.ouvrir(.connexion) }
            case "haptique": haptique.toggle()
            case "clics": clics.toggle()
            default:
                lecteur.viderCache()
                confirmation = "Cache vidé"
            }
        }
        .task {
            guard compte.connecte else { return }
            await whatsapp.rafraichirStatut()
            telegramLie = (try? await API.get("/api/telegram/statut", StatutTelegram.self))?.lie
        }
    }
}

struct EcranConnexion: View {
    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var compte: Compte
    @State private var email = ""
    @State private var motDePasse = ""
    @State private var erreur: String?
    @State private var enCours = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let e = compte.email {
                    Text("Connecté en tant que").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text(e).font(.system(size: 15, weight: .semibold))
                    BoutonIPod(titre: "Se déconnecter") {
                        Task { await compte.deconnexion() }
                    }
                } else {
                    Text("Connecte-toi avec ton adresse @dipherant.xyz et son mot de passe Mèyl.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    ChampIPod(titre: "adresse@dipherant.xyz", texte: $email, type: .email)
                    ChampIPod(titre: "Mot de passe", texte: $motDePasse, secret: true, type: .email, libelleRetour: "connexion", retour: { connecter() })
                    if let erreur {
                        Text(erreur).font(.system(size: 12)).foregroundStyle(.red)
                    }
                    BoutonIPod(titre: enCours ? "Connexion…" : "Se connecter", actif: !enCours && !email.isEmpty && !motDePasse.isEmpty) {
                        connecter()
                    }
                }
            }
            .padding(12)
        }
        .roue { g in
            g.centre = { connecter() }
        }
    }

    private func connecter() {
        guard compte.email == nil, !email.isEmpty, !motDePasse.isEmpty, !enCours else { return }
        enCours = true
        erreur = nil
        Task {
            do {
                try await compte.connexion(email: email.trimmingCharacters(in: .whitespaces), motDePasse: motDePasse)
                motDePasse = ""
                nav.retour()
            } catch {
                erreur = error.localizedDescription
            }
            enCours = false
        }
    }
}

/// Écran à afficher à la place d'une section qui a besoin du compte Pin.
struct BesoinCompte: View {
    @EnvironmentObject var nav: Navigateur

    var body: some View {
        MessageEcran(icone: "person.crop.circle.badge.exclamationmark", texte: "Connecte-toi à ton compte Pin",
                     detail: "Bouton central pour ouvrir la connexion.")
            .roue { g in g.centre = { nav.ouvrir(.connexion) } }
            .onTapGesture { nav.ouvrir(.connexion) }
    }
}
