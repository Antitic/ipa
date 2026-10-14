import SwiftUI
import UIKit

// MARK: - Les touches

enum Touche: Hashable {
    case car(String)
    case emoji(String)
    case pageEmoji(Int)
    case maj, effacer, espace, retour, fermer
    case couche(Clavier.Couche, String)

    var largeur: CGFloat {
        switch self {
        case .car: return 1
        case .emoji: return 1.25
        case .pageEmoji(let sens): return sens < 0 ? 1.35 : 1.1   // mêmes places que 😀 et ⌄
        case .maj, .effacer: return 1.35
        case .couche: return 1.35
        case .fermer: return 1.1
        case .retour: return 2.3
        case .espace: return 0   // prend le reste
        }
    }

    /// Lettre simple (a–z) : seules celles-ci profitent de la prédiction.
    var lettre: Character? {
        if case .car(let c) = self, c.count == 1, let l = c.first, l.isLetter, l.isASCII { return l }
        return nil
    }

    var speciale: Bool {
        switch self {
        case .car, .espace, .emoji: return false
        default: return true
        }
    }
}

/// Une touche posée sur le clavier, avec son rectangle à l'écran.
struct TouchePlacee: Identifiable {
    let id: Int
    let touche: Touche
    let cadre: CGRect
    /// Moitié droite du clavier : les accents s'ouvrent vers la gauche.
    let aDroite: Bool
}

// MARK: - Le clavier

/// Le clavier Pin, réglé comme celui d'iOS :
/// - une seule surface tactile multitouch : on peut taper vite des deux pouces,
///   la touche précédente est validée dès que le doigt suivant se pose ;
/// - la lettre est validée au relâchement, et glisser le doigt change de touche ;
/// - pas de zone morte : un toucher entre deux touches va à la plus proche ;
/// - les zones de toucher bougent : les lettres probables (d'après le début du
///   mot) grandissent, les lettres impossibles rétrécissent ;
/// - la touche appuyée devient grise.
struct ClavierIPod: View {
    @EnvironmentObject var clavier: Clavier
    @StateObject private var saisie = SaisieTactile()

    private let ecart: CGFloat = 6
    private let interligne: CGFloat = 10

    var body: some View {
        GeometryReader { g in
            let places = placer(dans: g.size)
            ZStack(alignment: .topLeading) {
                ForEach(places) { p in
                    VueTouche(touche: p.touche,
                              largeur: p.cadre.width,
                              hauteur: p.cadre.height,
                              aDroite: p.aDroite,
                              enfoncee: saisie.enfoncees.contains(p.id),
                              accents: saisie.idAccents == p.id ? saisie.accents : [],
                              choixAccent: saisie.choixAccent)
                        .position(x: p.cadre.midX, y: p.cadre.midY)
                        .zIndex(saisie.enfoncees.contains(p.id) ? 1 : 0)
                }
                SurfaceTactile(saisie: saisie)
                    .frame(width: g.size.width, height: g.size.height)
            }
            .onAppear { saisie.configurer(clavier: clavier, places: places) }
            .onChange(of: g.size) { _, _ in saisie.configurer(clavier: clavier, places: placer(dans: g.size)) }
            .onChange(of: clavier.couche) { _, _ in saisie.configurer(clavier: clavier, places: placer(dans: g.size)) }
            .onChange(of: clavier.type) { _, _ in saisie.configurer(clavier: clavier, places: placer(dans: g.size)) }
            .onChange(of: clavier.pageEmoji) { _, _ in saisie.configurer(clavier: clavier, places: placer(dans: g.size)) }
        }
        .padding(.horizontal, 3)
        .padding(.top, 14)
    }

    private var estPave: Bool { clavier.type == .numero || clavier.type == .telephone }

    // MARK: Disposition

    private func placer(dans taille: CGSize) -> [TouchePlacee] {
        let rangees = disposition
        let n = CGFloat(rangees.count)
        let hauteur = max(28, min(50, (taille.height - (n - 1) * interligne - 12) / n))
        let total = n * hauteur + (n - 1) * interligne
        let haut = taille.height - 4 - total
        var places: [TouchePlacee] = []
        for (r, rangee) in rangees.enumerated() {
            let y = haut + CGFloat(r) * (hauteur + interligne)
            for (x, largeur, touche, droite) in ligne(rangee, largeurTotale: taille.width) {
                places.append(TouchePlacee(id: places.count, touche: touche,
                                           cadre: CGRect(x: x, y: y, width: largeur, height: hauteur),
                                           aDroite: droite))
            }
        }
        return places
    }

    private func largeurUnites(_ t: Touche) -> CGFloat {
        if estPave { return t == .retour ? 2 : 1 }
        return t.largeur
    }

    /// Position x et largeur de chaque touche d'une rangée.
    private func ligne(_ touches: [Touche], largeurTotale: CGFloat) -> [(CGFloat, CGFloat, Touche, Bool)] {
        // L'unité : une ligne pleine compte dix touches (trois sur le pavé numérique).
        let colonnes: CGFloat = estPave ? 3 : 10
        let unite = (largeurTotale - (colonnes - 1) * ecart) / colonnes
        let largeurBase: (Touche) -> CGFloat = { t in
            let u = largeurUnites(t)
            return u * unite + (estPave ? max(0, u - 1) * ecart : 0)
        }
        // Rangée du milieu à touches fixes (⇧ / #+= / 123 … ⌫) : la première et
        // la dernière restent collées aux bords à la même place dans toutes
        // les couches ; seules les touches du milieu s'élargissent.
        var debutFixe = touches.first == .maj
        if case .couche? = touches.first { debutFixe = true }
        if !estPave, debutFixe, !touches.contains(.espace), touches.count >= 3, touches.last == .effacer {
            let cote = largeurBase(.maj)
            let total = 10 * unite + 9 * ecart
            let marge = (total - 2 * cote - (7 * unite + 6 * ecart)) / 2
            let milieu = total - 2 * cote - 2 * marge
            let n = CGFloat(touches.count - 2)
            let l = (milieu - (n - 1) * ecart) / n
            var resultat: [(CGFloat, CGFloat, Touche, Bool)] = [(0, cote, touches[0], false)]
            var x = cote + marge
            for (i, t) in touches.dropFirst().dropLast().enumerated() {
                resultat.append((x, l, t, CGFloat(i) >= n / 2))
                x += l + ecart
            }
            resultat.append((total - cote, cote, touches.last!, true))
            return resultat
        }
        // En bas de la couche emojis, ⌫ prend la place (et la taille) de « retour ».
        let largeurDe: (Touche) -> CGFloat = { t in
            if t == .effacer, touches.contains(.espace) { return largeurBase(.retour) }
            return largeurBase(t)
        }
        let fixes = touches.filter { $0 != .espace }.reduce(CGFloat(0)) { $0 + largeurDe($1) }
        let nbEcarts = CGFloat(touches.count - 1) * ecart
        let reste = max(unite * 2, largeurTotale - fixes - nbEcarts)
        var x = touches.contains(.espace) ? 0 : max(0, (largeurTotale - fixes - nbEcarts) / 2)
        let n = touches.count
        return touches.enumerated().map { i, t in
            let l = t == .espace ? reste : largeurDe(t)
            defer { x += l + ecart }
            return (x, l, t, i >= n / 2 + (n % 2))
        }
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
                : [.couche(.chiffres, "123"), .couche(.emojis, "😀"), .fermer, .espace, .retour]
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
                [.couche(.lettres, "ABC"), .couche(.emojis, "😀"), .fermer, .espace, .retour],
            ]
        case .emojis:
            let pages = clavier.pagesEmojis
            let page = pages[min(clavier.pageEmoji, pages.count - 1)]
            var rangees: [[Touche]] = stride(from: 0, to: 24, by: 8).map { i in
                Array(page.dropFirst(i).prefix(8)).map { .emoji($0) }
            }
            rangees = rangees.filter { !$0.isEmpty }
            return rangees + [[.couche(.lettres, "ABC"), .pageEmoji(-1), .pageEmoji(1), .espace, .effacer]]
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

// MARK: - La logique des doigts

@MainActor
final class SaisieTactile: ObservableObject {
    @Published private(set) var enfoncees: Set<Int> = []
    @Published private(set) var idAccents: Int?
    @Published private(set) var accents: [String] = []
    @Published private(set) var choixAccent = 0

    private weak var clavier: Clavier?
    private var places: [TouchePlacee] = []

    /// Un doigt posé : la touche qu'il tient, et s'il a déjà été validé.
    private struct Doigt {
        var id: Int
        var valide = false
    }
    private var doigts: [ObjectIdentifier: Doigt] = [:]
    private var minuteurs: [ObjectIdentifier: Task<Void, Never>] = [:]

    private var haptique: Bool { UserDefaults.standard.bool(forKey: "haptique") }

    static let variantes: [String: [String]] = [
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

    func configurer(clavier: Clavier, places: [TouchePlacee]) {
        self.clavier = clavier
        if places.map(\.touche) != self.places.map(\.touche) { annulerTout() }
        self.places = places
    }

    // MARK: Trouver la touche

    /// La touche visée par un point : distance au bord de chaque touche (négative
    /// à l'intérieur), corrigée par la probabilité de la lettre. Il n'y a jamais
    /// de « trou » : le point le plus éloigné revient quand même à une touche.
    private func touche(en p: CGPoint) -> Int? {
        guard let clavier else { return nil }
        let predictions = clavier.couche == .lettres && clavier.type != .numero && clavier.type != .telephone
            ? Predicteur.partage.suivantes(apres: clavier.fragment)
            : [:]
        var meilleur: (id: Int, score: CGFloat)?
        for t in places {
            let r = t.cadre
            let dx = abs(p.x - r.midX) - r.width / 2
            let dy = abs(p.y - r.midY) - r.height / 2
            var score: CGFloat
            if dx <= 0 && dy <= 0 {
                score = max(dx, dy)   // à l'intérieur : profondeur (négative)
            } else {
                score = hypot(max(dx, 0), max(dy, 0))
            }
            if let l = t.touche.lettre, !predictions.isEmpty {
                let pr = predictions[Character(l.lowercased())] ?? 0
                let unite = min(r.width, r.height)
                if pr > 0 {
                    // Jusqu'à ~40 % d'une touche de plus pour la lettre la plus probable.
                    score -= unite * 0.4 * CGFloat(pr.squareRoot())
                } else {
                    // Lettre qui ne peut pas suivre : sa zone rétrécit un peu.
                    score += unite * 0.15
                }
            }
            if meilleur == nil || score < meilleur!.score { meilleur = (t.id, score) }
        }
        return meilleur?.id
    }

    // MARK: Doigts

    func debut(_ cle: ObjectIdentifier, en p: CGPoint) {
        // Frappe rapide : le doigt précédent est validé dès que le suivant se pose.
        for (autre, d) in doigts where !d.valide && idAccents == nil {
            if case .car(_)? = places[safe: d.id]?.touche {
                valider(autre)
                withAnimation(.easeOut(duration: 0.12)) { _ = enfoncees.remove(d.id) }
            }
        }
        guard let id = touche(en: p) else { return }
        doigts[cle] = Doigt(id: id)
        enfoncees.insert(id)
        appuyer(cle, id: id)
    }

    func deplacement(_ cle: ObjectIdentifier, en p: CGPoint) {
        guard var d = doigts[cle], !d.valide, let place = places[safe: d.id] else { return }
        if idAccents == d.id, !accents.isEmpty {
            // Glisser pour choisir l'accent : le premier est centré à 22 pt du
            // bord de la touche par lequel la rangée s'ouvre, puis tous les 36 pt.
            let local = p.x - place.cadre.minX
            let depuisBord = place.aDroite ? place.cadre.width - local : local
            let i = Int(((depuisBord - 22) / 36).rounded())
            let nouveau = min(max(i, 0), accents.count - 1)
            if nouveau != choixAccent {
                choixAccent = nouveau
                if haptique { UISelectionFeedbackGenerator().selectionChanged() }
            }
            return
        }
        // Le doigt glisse sur une autre touche : c'est elle qui sera tapée.
        guard place.touche != .effacer, let id = touche(en: p), id != d.id else { return }
        minuteurs[cle]?.cancel()
        minuteurs[cle] = nil
        enfoncees.remove(d.id)
        d.id = id
        doigts[cle] = d
        enfoncees.insert(id)
        if case .car(let c)? = places[safe: id]?.touche { programmerAccents(cle, id: id, c) }
    }

    func fin(_ cle: ObjectIdentifier) {
        if let d = doigts[cle], !d.valide { valider(cle) }
        liberer(cle)
    }

    func annulation(_ cle: ObjectIdentifier) {
        liberer(cle)
    }

    private func annulerTout() {
        for cle in Array(doigts.keys) { liberer(cle) }
    }

    private func liberer(_ cle: ObjectIdentifier) {
        minuteurs[cle]?.cancel()
        minuteurs[cle] = nil
        if let d = doigts.removeValue(forKey: cle) {
            if !doigts.values.contains(where: { $0.id == d.id }) {
                withAnimation(.easeOut(duration: 0.12)) { _ = enfoncees.remove(d.id) }
            }
            if idAccents == d.id {
                idAccents = nil
                accents = []
            }
        }
    }

    // MARK: Actions

    private func appuyer(_ cle: ObjectIdentifier, id: Int) {
        guard let clavier, let t = places[safe: id]?.touche else { return }
        if haptique { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6) }
        switch t {
        case .effacer:
            Son.effacement()
            clavier.effacer()
            doigts[cle]?.valide = true
            minuteurs[cle] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                var n = 0
                while !Task.isCancelled {
                    // Comme iOS : après une vingtaine de caractères, on efface plus vite.
                    self?.clavier?.effacer()
                    Son.effacement()
                    n += 1
                    try? await Task.sleep(for: .milliseconds(n > 20 ? 45 : 85))
                }
            }
        case .emoji:
            Son.touche()
        case .car(let c):
            Son.touche()
            programmerAccents(cle, id: id, c)
        default:
            Son.modificateur()
        }
    }

    private func programmerAccents(_ cle: ObjectIdentifier, id: Int, _ c: String) {
        guard let v = Self.variantes[c] else { return }
        minuteurs[cle] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard let self, !Task.isCancelled, self.doigts[cle]?.id == id else { return }
            self.idAccents = id
            self.accents = v
            self.choixAccent = 0
            if self.haptique { UISelectionFeedbackGenerator().selectionChanged() }
        }
    }

    private func valider(_ cle: ObjectIdentifier) {
        guard let clavier, var d = doigts[cle], !d.valide, let t = places[safe: d.id]?.touche else { return }
        d.valide = true
        doigts[cle] = d
        minuteurs[cle]?.cancel()
        minuteurs[cle] = nil
        switch t {
        case .car(let c):
            let choix = (idAccents == d.id && accents.indices.contains(choixAccent)) ? accents[choixAccent] : c
            clavier.taper(choix)
        case .maj: clavier.toucheMaj()
        case .espace: clavier.espace()
        case .retour: clavier.valider()
        case .fermer: clavier.fermer()
        case .couche(let c, _):
            if c == .emojis { clavier.pageEmoji = 0 }
            clavier.couche = c
        case .emoji(let e): clavier.taperEmoji(e)
        case .pageEmoji(let sens): clavier.changerPageEmoji(sens)
        case .effacer: break
        }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - La surface tactile (UIKit, pour le multitouch)

struct SurfaceTactile: UIViewRepresentable {
    let saisie: SaisieTactile

    func makeUIView(context: Context) -> VueTactile {
        let v = VueTactile()
        v.saisie = saisie
        return v
    }

    func updateUIView(_ v: VueTactile, context: Context) {
        v.saisie = saisie
    }

    final class VueTactile: UIView {
        weak var saisie: SaisieTactile?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = true
            isExclusiveTouch = false
        }

        required init?(coder: NSCoder) { fatalError() }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches.sorted(by: { $0.timestamp < $1.timestamp }) {
                let p = t.location(in: self)
                MainActor.assumeIsolated { saisie?.debut(ObjectIdentifier(t), en: p) }
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches {
                let p = t.location(in: self)
                MainActor.assumeIsolated { saisie?.deplacement(ObjectIdentifier(t), en: p) }
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches {
                MainActor.assumeIsolated { saisie?.fin(ObjectIdentifier(t)) }
            }
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            for t in touches {
                MainActor.assumeIsolated { saisie?.annulation(ObjectIdentifier(t)) }
            }
        }
    }
}

// MARK: - Le dessin d'une touche

/// Une touche : blanche (lettres) ou grise (fonctions), comme iOS. Appuyée,
/// une lettre devient grise et sa bulle d'aperçu sort au-dessus ; une touche de
/// fonction s'éclaircit.
struct VueTouche: View {
    let touche: Touche
    let largeur: CGFloat
    let hauteur: CGFloat
    let aDroite: Bool
    let enfoncee: Bool
    let accents: [String]
    let choixAccent: Int

    @EnvironmentObject var clavier: Clavier

    private var pave: Bool { clavier.type == .numero || clavier.type == .telephone }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(fond)
                .shadow(color: .black.opacity(0.3), radius: 0, y: 1)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.black.opacity(0.1), lineWidth: 0.5)
            etiquette
        }
        .frame(width: largeur, height: hauteur)
        .overlay(alignment: .bottom) {
            apercu
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: accents)
        }
    }

    // MARK: Apparence

    private var fond: Color {
        if case .retour = touche {
            return enfoncee ? Color(white: 0.98) : Color(red: 0.2, green: 0.47, blue: 0.96)
        }
        if touche.speciale {
            // Touche de fonction : grise, blanche quand on appuie (comme iOS).
            return enfoncee ? Color(white: 0.99) : Color(white: 0.69)
        }
        // Lettre ou espace : blanche, grise quand on appuie.
        return enfoncee ? Color(white: 0.69) : .white
    }

    @ViewBuilder
    private var etiquette: some View {
        switch touche {
        case .car(let c):
            Text(clavier.majuscules && clavier.couche == .lettres ? c.uppercased() : c)
                .font(.system(size: pave ? 24 : 22, weight: .light))
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
            Text("espace").font(.system(size: 15)).foregroundStyle(.black)
        case .retour:
            Text(clavier.libelleRetour).font(.system(size: 15, weight: .medium))
                .foregroundStyle(enfoncee ? Color.black : Color.white)
        case .fermer:
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 16))
                .foregroundStyle(.black)
        case .couche(_, let libelle):
            Text(libelle).font(.system(size: libelle.unicodeScalars.first?.properties.isEmojiPresentation == true ? 19 : 15))
                .foregroundStyle(.black)
        case .emoji(let e):
            Text(e).font(.system(size: 26))
        case .pageEmoji(let sens):
            VStack(spacing: 0) {
                Image(systemName: sens < 0 ? "chevron.left" : "chevron.right").font(.system(size: 15, weight: .semibold))
                Text(nomPage).font(.system(size: 8)).lineLimit(1).minimumScaleFactor(0.6)
            }
            .foregroundStyle(.black)
        }
    }

    private var nomPage: String {
        let recents = clavier.emojisRecents.isEmpty ? 0 : 1
        if clavier.pageEmoji < recents { return "Récents" }
        let i = clavier.pageEmoji - recents
        return Clavier.pagesEmojis.indices.contains(i) ? Clavier.pagesEmojis[i].nom : ""
    }

    /// La bulle de la lettre au-dessus du doigt, ou la rangée d'accents.
    @ViewBuilder
    private var apercu: some View {
        if case .car(let c) = touche, enfoncee, !pave {
            let texte = clavier.majuscules && clavier.couche == .lettres ? c.uppercased() : c
            if accents.isEmpty {
                Text(texte)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.black)
                    .frame(width: max(largeur + 14, 44), height: hauteur + 6)
                    .background(
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    )
                    .offset(y: -hauteur - 4)
                    .allowsHitTesting(false)
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(ordreAffiche.enumerated()), id: \.offset) { _, i in
                        let a = accents[i]
                        Text(clavier.majuscules ? a.uppercased() : a)
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(i == choixAccent ? .white : .black)
                            .frame(width: 36, height: hauteur)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(i == choixAccent ? Color(red: 0.2, green: 0.47, blue: 0.96) : Color.clear)
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
}
