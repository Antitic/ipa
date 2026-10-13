import SwiftUI

enum TypeClavier { case texte, email, numero, telephone }

/// Le clavier de Pin. Quand un champ est actif, il prend la place de la
/// molette ; le clavier d'Apple n'apparaît jamais.
@MainActor
final class Clavier: ObservableObject {
    enum Maj { case aucune, une, verrou }
    enum Couche { case lettres, chiffres, symboles, emojis }

    @Published private(set) var actif = false
    @Published private(set) var champ: UUID?
    @Published private(set) var type: TypeClavier = .texte
    @Published var maj: Maj = .aucune
    @Published var couche: Couche = .lettres
    @Published private(set) var libelleRetour = "retour"
    /// Page affichée dans la couche emojis (0 = récents).
    @Published var pageEmoji = 0
    @Published private(set) var emojisRecents: [String] = UserDefaults.standard.stringArray(forKey: "emojisRecents") ?? []

    static let pagesEmojis: [(nom: String, emojis: [String])] = [
        ("Smileys", ["😀","😃","😄","😁","😆","😅","😂","🤣","🥲","😊","😇","🙂","😉","😌","😍","🥰","😘","😗","😙","😚","😋","😛","😝","😜"]),
        ("Émotions", ["🤪","🤨","🧐","🤓","😎","🥸","🤩","🥳","😏","😒","😞","😔","😟","😕","🙁","😣","😖","😫","😩","🥺","😢","😭","😤","😠"]),
        ("Émotions", ["😡","🤬","🤯","😳","🥵","🥶","😱","😨","😰","😥","😓","🤗","🤔","🫡","🤭","🤫","🤥","😶","😐","😑","😬","🙄","😯","😴"]),
        ("Gestes", ["👍","👎","👌","🤌","✌️","🤞","🫶","🤟","🤘","🤙","👈","👉","👆","👇","☝️","✋","👋","👏","🙌","👐","🤲","🙏","💪","🫵"]),
        ("Cœurs", ["❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔","❤️‍🔥","💕","💞","💓","💗","💖","💘","💝","💯","💥","💫","⭐️","🌟","✨"]),
        ("Choses", ["🔥","🎉","🎊","🎁","🎂","🍕","🍔","🍟","🍿","☕️","🍺","🍷","⚽️","🏀","🎮","🎧","🎵","📱","💻","📷","🚗","✈️","🏠","💤"]),
        ("Nature", ["🐶","🐱","🐭","🐰","🦊","🐻","🐼","🐸","🐵","🙈","🙉","🙊","🐔","🐧","🦄","🐝","🌸","🌹","🌻","🌈","☀️","🌙","⚡️","❄️"]),
    ]

    /// Les pages : les récents d'abord (s'il y en a), puis les catégories.
    var pagesEmojis: [[String]] {
        let recents = emojisRecents.isEmpty ? [] : [Array(emojisRecents.prefix(24))]
        return recents + Self.pagesEmojis.map(\.emojis)
    }

    func changerPageEmoji(_ sens: Int) {
        let n = pagesEmojis.count
        pageEmoji = ((pageEmoji + sens) % n + n) % n
    }

    func taperEmoji(_ e: String) {
        if let web {
            web.inserer(e)
        } else if let cible {
            cible.wrappedValue += e
        }
        var r = emojisRecents.filter { $0 != e }
        r.insert(e, at: 0)
        emojisRecents = Array(r.prefix(24))
        UserDefaults.standard.set(emojisRecents, forKey: "emojisRecents")
    }

    private var cible: Binding<String>?
    private var retour: (() -> Void)?

    /// Saisie dans une page web (connexion claude.ai) : le texte n'est pas une
    /// variable de Pin, il est inséré directement dans le champ de la page.
    struct CibleWeb {
        let inserer: (String) -> Void
        let effacer: () -> Void
        let valider: () -> Void
        let quitter: () -> Void
    }
    private var web: CibleWeb?
    /// Ce qui a été tapé dans la page web depuis le dernier espace (pour la prédiction).
    private var tamponWeb = ""
    static let champWeb = UUID()
    private var dernierMaj = Date.distantPast
    private var dernierEspace = Date.distantPast

    func ouvrirWeb(type: TypeClavier, cible: CibleWeb) {
        self.cible = nil
        retour = nil
        web = cible
        tamponWeb = ""
        self.type = type
        libelleRetour = "OK"
        champ = Self.champWeb
        couche = .lettres
        maj = .aucune
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { actif = true }
    }

    func ouvrir(champ id: UUID, texte: Binding<String>, type: TypeClavier, libelleRetour: String, retour: (() -> Void)?) {
        web = nil
        cible = texte
        self.retour = retour
        self.type = type
        self.libelleRetour = libelleRetour
        champ = id
        couche = .lettres
        majAuto()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { actif = true }
    }

    func fermer() {
        guard actif else { return }
        web?.quitter()
        cible = nil
        web = nil
        retour = nil
        champ = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { actif = false }
    }

    /// Ferme seulement si c'est encore ce champ-là qui a le clavier.
    func liberer(_ id: UUID) {
        if champ == id { fermer() }
    }

    var majuscules: Bool { maj != .aucune }

    /// Le début du mot en cours, juste avant le curseur.
    var fragment: String {
        if web != nil { return tamponWeb }
        return Predicteur.motCourant(cible?.wrappedValue ?? "")
    }

    // MARK: - Saisie

    func taper(_ s: String) {
        let car = majuscules && couche == .lettres ? s.uppercased() : s
        if let web {
            web.inserer(car)
            tamponWeb = car.allSatisfy(\.isLetter) ? tamponWeb + car : ""
            if maj == .une { maj = .aucune }
            return
        }
        guard let cible else { return }
        cible.wrappedValue += car
        if maj == .une { maj = .aucune }
        if [".", "!", "?"].contains(s) { majAuto() }
    }

    func espace() {
        if let web {
            tamponWeb = ""
            web.inserer(" ")
            if couche != .lettres { couche = .lettres }
            return
        }
        guard let cible else { return }
        // Double espace = point, comme sur iOS.
        let maintenant = Date()
        if type == .texte, maintenant.timeIntervalSince(dernierEspace) < 0.45, cible.wrappedValue.hasSuffix(" "),
           let avant = cible.wrappedValue.dropLast().last, avant.isLetter || avant.isNumber {
            cible.wrappedValue.removeLast()
            cible.wrappedValue += ". "
            dernierEspace = .distantPast
        } else {
            cible.wrappedValue += " "
            dernierEspace = maintenant
        }
        if couche != .lettres { couche = .lettres }
        majAuto()
    }

    func effacer() {
        if let web {
            if !tamponWeb.isEmpty { tamponWeb.removeLast() }
            web.effacer()
            return
        }
        guard let cible, !cible.wrappedValue.isEmpty else { return }
        cible.wrappedValue.removeLast()
        majAuto()
    }

    func toucheMaj() {
        let maintenant = Date()
        if maintenant.timeIntervalSince(dernierMaj) < 0.3 {
            maj = .verrou
        } else {
            maj = (maj == .aucune) ? .une : .aucune
        }
        dernierMaj = maintenant
    }

    func valider() {
        if let web {
            web.valider()
        } else if let retour {
            retour()
        } else if let cible, type == .texte {
            cible.wrappedValue += "\n"
        } else {
            fermer()
        }
    }

    /// Majuscule automatique en début de phrase (texte seulement).
    private func majAuto() {
        guard maj != .verrou else { return }
        guard type == .texte, let t = cible?.wrappedValue else { maj = .aucune; return }
        let fin = t.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || fin.isEmpty || t.hasSuffix("\n") ||
            (t.hasSuffix(" ") && [".", "!", "?"].contains(fin.last.map(String.init) ?? "")) {
            maj = .une
        } else if maj == .une {
            maj = .aucune
        }
    }
}

// MARK: - Champs

/// Champ de saisie Pin : un toucher ouvre le clavier Pin à la place de la molette.
struct ChampIPod: View {
    let titre: String
    @Binding var texte: String
    var secret = false
    var type: TypeClavier = .texte
    var libelleRetour = "OK"
    var retour: (() -> Void)? = nil

    @EnvironmentObject var clavier: Clavier
    @State private var id = UUID()

    private var actif: Bool { clavier.actif && clavier.champ == id }

    var body: some View {
        TexteAvecCurseur(texte: secret ? String(repeating: "•", count: texte.count) : texte,
                         titre: titre, actif: actif, lignes: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: actif ? 1 : 0.95)))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(actif ? Color(red: 0.16, green: 0.44, blue: 0.86) : Color(white: 0.75), lineWidth: actif ? 1.5 : 0.5))
            .contentShape(Rectangle())
            .onTapGesture { ouvrir() }
            .onDisappear { clavier.liberer(id) }
    }

    private func ouvrir() {
        clavier.ouvrir(champ: id, texte: $texte, type: type, libelleRetour: retour == nil ? "OK" : libelleRetour, retour: retour)
    }
}

/// Zone de message sur plusieurs lignes (WhatsApp, Claude).
struct ZoneSaisie: View {
    /// Identifiant fourni par l'écran, pour pouvoir ouvrir le clavier depuis la molette.
    let id: UUID
    let titre: String
    @Binding var texte: String
    var libelleRetour = "envoyer"
    let envoyer: () -> Void

    @EnvironmentObject var clavier: Clavier

    private var actif: Bool { clavier.actif && clavier.champ == id }

    var body: some View {
        TexteAvecCurseur(texte: texte, titre: titre, actif: actif, lignes: 4)
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(actif ? Color(red: 0.16, green: 0.44, blue: 0.86) : Color(white: 0.75), lineWidth: actif ? 1.5 : 0.5))
            .contentShape(Rectangle())
            .onTapGesture { ouvrir() }
            .onDisappear { clavier.liberer(id) }
    }

    func ouvrir() {
        clavier.ouvrir(champ: id, texte: $texte, type: .texte, libelleRetour: libelleRetour, retour: envoyer)
    }
}

/// Le texte d'un champ, avec un curseur bleu qui clignote quand il est actif.
struct TexteAvecCurseur: View {
    let texte: String
    let titre: String
    let actif: Bool
    let lignes: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { contexte in
            let visible = actif && Int(contexte.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
            let curseur = Text("|").foregroundColor(Color(red: 0.16, green: 0.44, blue: 0.86).opacity(visible ? 1 : 0))
            Group {
                if texte.isEmpty {
                    (actif ? curseur : Text("")) + Text(titre).foregroundColor(Color(white: 0.6))
                } else {
                    Text(texte).foregroundColor(.black) + (actif ? curseur : Text(""))
                }
            }
            .font(.system(size: 14))
            .lineLimit(lignes)
            .truncationMode(.head)
        }
    }
}

