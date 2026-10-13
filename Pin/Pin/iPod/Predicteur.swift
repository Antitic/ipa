import Foundation

/// Devine la lettre suivante à partir du début du mot, comme le clavier d'iOS :
/// les lettres probables reçoivent une zone de toucher plus grande.
/// Le dictionnaire (mots-fr.txt) : ~23 000 mots français sans accents, triés,
/// chacun avec sa fréquence d'usage.
final class Predicteur {
    static let partage = Predicteur()

    private var mots: [[UInt8]] = []
    private var frequences: [Double] = []
    private var cache: [String: [Character: Double]] = [:]
    private let verrou = NSLock()

    private init() {
        guard let url = Bundle.main.url(forResource: "mots-fr", withExtension: "txt"),
              let texte = try? String(contentsOf: url, encoding: .utf8) else { return }
        for ligne in texte.split(separator: "\n") {
            let parties = ligne.split(separator: " ")
            guard parties.count == 2, let f = Double(parties[1]) else { continue }
            mots.append(Array(parties[0].utf8))
            frequences.append(f)
        }
    }

    /// Le début du mot en cours, ramené à a–z (accents retirés), ou nil s'il
    /// contient autre chose que des lettres.
    static func normaliser(_ s: String) -> String? {
        let base = s.lowercased()
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
        guard base.utf8.allSatisfy({ $0 >= 97 && $0 <= 122 }) else { return nil }
        return base
    }

    /// Le fragment de mot juste avant le curseur.
    static func motCourant(_ texte: String) -> String {
        var mot = ""
        for c in texte.reversed() {
            if c.isLetter { mot.insert(c, at: mot.startIndex) } else { break }
        }
        return mot
    }

    /// Probabilité relative de chaque lettre suivante (la plus probable vaut 1).
    /// Vide quand le mot est inconnu : le clavier reste alors neutre.
    func suivantes(apres fragment: String) -> [Character: Double] {
        guard let prefixe = Self.normaliser(fragment), prefixe.count < 12 else { return [:] }
        verrou.lock(); defer { verrou.unlock() }
        if let c = cache[prefixe] { return c }

        let p = Array(prefixe.utf8)
        var debut = borneInf(p)
        var sommes = [Double](repeating: 0, count: 26)
        while debut < mots.count {
            let m = mots[debut]
            guard m.count >= p.count, m.starts(with: p) else { break }
            if m.count > p.count { sommes[Int(m[p.count]) - 97] += frequences[debut] }
            debut += 1
        }
        var resultat: [Character: Double] = [:]
        if let max = sommes.max(), max > 0 {
            for (i, s) in sommes.enumerated() where s > 0 {
                resultat[Character(UnicodeScalar(UInt8(97 + i)))] = s / max
            }
        }
        if cache.count > 400 { cache.removeAll() }
        cache[prefixe] = resultat
        return resultat
    }

    /// Premier mot du dictionnaire >= préfixe (recherche dichotomique).
    private func borneInf(_ p: [UInt8]) -> Int {
        var bas = 0, haut = mots.count
        while bas < haut {
            let milieu = (bas + haut) / 2
            if mots[milieu].lexicographicallyPrecedes(p) { bas = milieu + 1 } else { haut = milieu }
        }
        return bas
    }
}
