import SwiftUI

enum TypeClavier { case texte, email, numero, telephone }

/// Le clavier de Pin. Quand un champ est actif, il prend la place de la
/// molette ; le clavier d'Apple n'apparaît jamais.
@MainActor
final class Clavier: ObservableObject {
    enum Maj { case aucune, une, verrou }
    enum Couche { case lettres, chiffres, symboles }

    @Published private(set) var actif = false
    @Published private(set) var champ: UUID?
    @Published private(set) var type: TypeClavier = .texte
    @Published var maj: Maj = .aucune
    @Published var couche: Couche = .lettres
    @Published private(set) var libelleRetour = "retour"

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
    static let champWeb = UUID()
    private var dernierMaj = Date.distantPast
    private var dernierEspace = Date.distantPast

    func ouvrirWeb(type: TypeClavier, cible: CibleWeb) {
        self.cible = nil
        retour = nil
        web = cible
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

    // MARK: - Saisie

    func taper(_ s: String) {
        let car = majuscules && couche == .lettres ? s.uppercased() : s
        if let web {
            web.inserer(car)
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
        if let web { web.effacer(); return }
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

// MARK: - Le clavier

private enum Touche: Hashable {
    case car(String)
    case maj, effacer, espace, retour, fermer
    case couche(Clavier.Couche, String)

    var largeur: CGFloat {
        switch self {
        case .car: return 1
        case .maj, .effacer: return 1.35
        case .couche: return 1.35
        case .fermer: return 1.1
        case .retour: return 2.3
        case .espace: return 0   // prend le reste
        }
    }
}

struct ClavierIPod: View {
    @EnvironmentObject var clavier: Clavier

    private let ecart: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            let rangees = disposition
            let hauteur = min(50, (g.size.height - CGFloat(rangees.count - 1) * 10 - 12) / CGFloat(rangees.count))
            VStack(spacing: 10) {
                ForEach(Array(rangees.enumerated()), id: \.offset) { _, rangee in
                    ligne(rangee, largeurTotale: g.size.width, hauteur: hauteur)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 3)
        .padding(.top, 14)
    }

    private var estPave: Bool { clavier.type == .numero || clavier.type == .telephone }

    private func largeurUnites(_ t: Touche) -> CGFloat {
        if estPave { return t == .retour ? 2 : 1 }
        return t.largeur
    }

    private func ligne(_ touches: [Touche], largeurTotale: CGFloat, hauteur: CGFloat) -> some View {
        // L'unité : une ligne pleine compte dix touches (trois sur le pavé numérique).
        let colonnes: CGFloat = estPave ? 3 : 10
        let unite = (largeurTotale - (colonnes - 1) * ecart) / colonnes
        let largeurDe: (Touche) -> CGFloat = { t in
            let u = largeurUnites(t)
            return u * unite + (estPave ? max(0, u - 1) * ecart : 0)
        }
        let fixes = touches.filter { $0 != .espace }.reduce(CGFloat(0)) { $0 + largeurDe($1) }
        let nbEcarts = CGFloat(touches.count - 1) * ecart
        let reste = max(unite * 2, largeurTotale - fixes - nbEcarts)
        let decalage = touches.contains(.espace) ? 0 : (largeurTotale - fixes - nbEcarts) / 2
        let n = touches.count
        return HStack(spacing: ecart) {
            ForEach(Array(touches.enumerated()), id: \.offset) { i, t in
                VueTouche(touche: t, largeur: t == .espace ? reste : largeurDe(t), hauteur: hauteur,
                          aDroite: i >= n / 2 + (n % 2))
            }
        }
        .padding(.horizontal, max(0, decalage))
        .frame(maxWidth: .infinity)
    }

    private var disposition: [[Touche]] {
        switch clavier.type {
        case .numero, .telephone:
            return pave
        default:
            break
        }
        switch clavier.couche {
        case .lettres:
            let bas: [Touche] = clavier.type == .email
                ? [.couche(.chiffres, "123"), .fermer, .car("@"), .espace, .car("."), .retour]
                : [.couche(.chiffres, "123"), .fermer, .espace, .retour]
            return [
                "azertyuiop".map { .car(String($0)) },
                "qsdfghjklm".map { .car(String($0)) },
                [.maj] + "wxcvbn".map { .car(String($0)) } + [.car("'"), .effacer],
                bas,
            ]
        case .chiffres:
            return [
                "1234567890".map { .car(String($0)) },
                ["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""].map { .car($0) },
                [.couche(.symboles, "#+=")] + [".", ",", "?", "!", "'"].map { .car($0) } + [.effacer],
                [.couche(.lettres, "ABC"), .fermer, .espace, .retour],
            ]
        case .symboles:
            return [
                ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { .car($0) },
                ["_", "\\", "|", "~", "<", ">", "$", "£", "¥", "•"].map { .car($0) },
                [.couche(.chiffres, "123")] + [".", ",", "?", "!", "'"].map { .car($0) } + [.effacer],
                [.couche(.lettres, "ABC"), .fermer, .espace, .retour],
            ]
        }
    }

    private var pave: [[Touche]] {
        let plus: Touche = clavier.type == .telephone ? .car("+") : .fermer
        return [
            ["1", "2", "3"].map { .car($0) },
            ["4", "5", "6"].map { .car($0) },
            ["7", "8", "9"].map { .car($0) },
            [plus, .car("0"), .effacer],
            [.fermer, .retour],
        ]
    }
}

/// Une touche : dégradé blanc façon iPod, aperçu au-dessus au toucher,
/// accents en appui long, effacement répété en appui long.
private struct VueTouche: View {
    let touche: Touche
    let largeur: CGFloat
    let hauteur: CGFloat
    /// Touche de la moitié droite : les accents s'ouvrent vers la gauche.
    let aDroite: Bool

    @EnvironmentObject var clavier: Clavier
    @AppStorage("haptique") private var haptique = true
    @State private var enfoncee = false
    @State private var accents: [String] = []
    @State private var choixAccent = 0
    @State private var minuteur: Task<Void, Never>?

    private static let variantes: [String: [String]] = [
        "e": ["e", "é", "è", "ê", "ë"],
        "a": ["a", "à", "â", "æ", "ä"],
        "u": ["u", "ù", "û", "ü"],
        "i": ["i", "î", "ï"],
        "o": ["o", "ô", "œ", "ö"],
        "c": ["c", "ç"],
        "y": ["y", "ÿ"],
        "n": ["n", "ñ"],
        "'": ["'", "’", "\""],
        "-": ["-", "–", "—"],
        "€": ["€", "$", "£"],
        ".": [".", "…"],
    ]

    private var pave: Bool { clavier.type == .numero || clavier.type == .telephone }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(fond)
                .shadow(color: .black.opacity(enfoncee ? 0.1 : 0.28), radius: 0, y: enfoncee ? 0 : 1)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 0.5)
            // Reflet qui s'allume sous le doigt.
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(RadialGradient(colors: [Color(red: 0.42, green: 0.66, blue: 0.95).opacity(0.35), .clear],
                                     center: .center, startRadius: 0, endRadius: max(largeur, hauteur) * 0.7))
                .opacity(enfoncee && !speciale ? 1 : 0)
            etiquette
                .scaleEffect(enfoncee ? 1.12 : 1)
        }
        .frame(width: largeur, height: hauteur)
        // La touche s'enfonce puis rebondit en se relâchant.
        .scaleEffect(enfoncee ? 0.88 : 1)
        .offset(y: enfoncee ? 1.5 : 0)
        .animation(.spring(response: 0.16, dampingFraction: 0.5), value: enfoncee)
        .overlay(alignment: .bottom) {
            apercu
                .animation(.spring(response: 0.2, dampingFraction: 0.62), value: enfoncee)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: accents)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in appui(v) }
                .onEnded { _ in relache() }
        )
    }

    // MARK: Apparence

    private var speciale: Bool {
        switch touche {
        case .car, .espace: return false
        default: return true
        }
    }

    private var fond: LinearGradient {
        if case .retour = touche {
            let c: [Color] = enfoncee
                ? [Color(red: 0.12, green: 0.36, blue: 0.75), Color(red: 0.2, green: 0.45, blue: 0.85)]
                : [Color(red: 0.42, green: 0.66, blue: 0.95), Color(red: 0.16, green: 0.44, blue: 0.86)]
            return LinearGradient(colors: c, startPoint: .top, endPoint: .bottom)
        }
        if speciale {
            let haut = enfoncee ? 0.95 : 0.8
            return LinearGradient(colors: [Color(white: haut), Color(white: haut - 0.08)], startPoint: .top, endPoint: .bottom)
        }
        let haut = enfoncee ? 0.82 : 1.0
        return LinearGradient(colors: [Color(white: haut), Color(white: haut - 0.09)], startPoint: .top, endPoint: .bottom)
    }

    @ViewBuilder
    private var etiquette: some View {
        switch touche {
        case .car(let c):
            Text(clavier.majuscules && clavier.couche == .lettres ? c.uppercased() : c)
                .font(.system(size: pave ? 24 : 21, weight: pave ? .regular : .regular))
                .foregroundStyle(.black)
        case .maj:
            Image(systemName: clavier.maj == .verrou ? "capslock.fill" : (clavier.maj == .une ? "shift.fill" : "shift"))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.black)
        case .effacer:
            Image(systemName: enfoncee ? "delete.left.fill" : "delete.left")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.black)
        case .espace:
            Text("espace").font(.system(size: 15)).foregroundStyle(Color(white: 0.3))
        case .retour:
            Text(clavier.libelleRetour).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
        case .fermer:
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 16))
                .foregroundStyle(.black)
        case .couche(_, let libelle):
            Text(libelle).font(.system(size: 15)).foregroundStyle(.black)
        }
    }

    /// L'aperçu de la lettre au-dessus du doigt, ou la rangée d'accents.
    @ViewBuilder
    private var apercu: some View {
        if case .car(let c) = touche, enfoncee, !pave {
            let texte = clavier.majuscules && clavier.couche == .lettres ? c.uppercased() : c
            if accents.isEmpty {
                Text(texte)
                    .font(.system(size: 32))
                    .foregroundStyle(.black)
                    .frame(width: max(largeur + 14, 44), height: hauteur + 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(LinearGradient(colors: [Color.white, Color(white: 0.92)], startPoint: .top, endPoint: .bottom))
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    )
                    .offset(y: -hauteur - 4)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.3, anchor: .bottom).combined(with: .opacity))
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(ordreAffiche.enumerated()), id: \.offset) { _, i in
                        let a = accents[i]
                        Text(clavier.majuscules ? a.uppercased() : a)
                            .font(.system(size: 24))
                            .foregroundStyle(i == choixAccent ? .white : .black)
                            .frame(width: 36, height: hauteur)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(i == choixAccent
                                          ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.42, green: 0.66, blue: 0.95), Color(red: 0.16, green: 0.44, blue: 0.86)], startPoint: .top, endPoint: .bottom))
                                          : AnyShapeStyle(Color.clear))
                            )
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                )
                .fixedSize()
                .offset(x: decalageAccents, y: -hauteur - 6)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.5, anchor: aDroite ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
            }
        }
    }

    /// Les accents s'affichent depuis la touche : de gauche à droite pour la
    /// moitié gauche du clavier, de droite à gauche pour l'autre moitié.
    private var ordreAffiche: [Int] {
        aDroite ? Array(accents.indices.reversed()) : Array(accents.indices)
    }

    private var decalageAccents: CGFloat {
        let demiBarre = CGFloat(accents.count) * 18 + 4
        return aDroite ? largeur / 2 - demiBarre + 4 : -largeur / 2 + demiBarre - 4
    }

    // MARK: Gestes

    private func appui(_ v: DragGesture.Value) {
        if !enfoncee {
            enfoncee = true
            debut()
        } else if !accents.isEmpty {
            // Glisser le doigt pour choisir l'accent.
            // Le premier accent est centré à 22 pt du bord de la touche par lequel la rangée s'ouvre.
            let depuisBord = aDroite ? largeur - v.location.x : v.location.x
            let i = Int(((depuisBord - 22) / 36).rounded())
            choixAccent = min(max(i, 0), accents.count - 1)
        }
    }

    private func debut() {
        if haptique { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6) }
        switch touche {
        case .effacer:
            Son.effacement()
            clavier.effacer()
            minuteur = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                while !Task.isCancelled {
                    clavier.effacer()
                    Son.effacement()
                    try? await Task.sleep(for: .milliseconds(85))
                }
            }
        case .car(let c):
            Son.touche()
            if let v = Self.variantes[c] {
                minuteur = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(420))
                    guard !Task.isCancelled else { return }
                    accents = v
                    choixAccent = 0
                    if haptique { UISelectionFeedbackGenerator().selectionChanged() }
                }
            }
        default:
            Son.modificateur()
        }
    }

    private func relache() {
        minuteur?.cancel()
        minuteur = nil
        defer {
            enfoncee = false
            accents = []
        }
        switch touche {
        case .car(let c):
            clavier.taper(accents.isEmpty ? c : accents[choixAccent])
        case .maj: clavier.toucheMaj()
        case .espace: clavier.espace()
        case .retour: clavier.valider()
        case .fermer: clavier.fermer()
        case .couche(let c, _): clavier.couche = c
        case .effacer: break
        }
    }
}
