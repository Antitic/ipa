import Foundation
import UIKit

/// Mises à jour de Pin sans rien réinstaller à la main : Pin regarde les
/// releases GitHub (tags « pin-vX.Y.Z ») et, s'il y a plus récent, demande à
/// LiveContainer de télécharger et d'installer le nouvel IPA par-dessus.
@MainActor
final class MiseAJour: ObservableObject {
    static let partage = MiseAJour()

    struct Version: Equatable {
        let numero: String
        let ipa: URL
        let notes: String
    }

    @Published private(set) var disponible: Version?
    @Published private(set) var verification = false
    @Published private(set) var derniereErreur: String?
    @Published private(set) var verifieeLe: Date?

    static let actuelle = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private static let releases = URL(string: "https://api.github.com/repos/Antitic/IPA/releases?per_page=40")!

    private struct Release: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        let tag_name: String
        let draft: Bool
        let body: String?
        let assets: [Asset]
    }

    /// Vérifie au plus toutes les 20 minutes, sauf si on force.
    func verifier(forcer: Bool = false) async {
        if !forcer, let d = verifieeLe, Date().timeIntervalSince(d) < 20 * 60 { return }
        guard !verification else { return }
        verification = true
        defer { verification = false }
        do {
            var req = URLRequest(url: Self.releases)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            req.cachePolicy = .reloadIgnoringLocalCacheData
            req.timeoutInterval = 20
            let (data, _) = try await URLSession.shared.data(for: req)
            let liste = try JSONDecoder().decode([Release].self, from: data)
            let candidates = liste.compactMap { r -> Version? in
                guard !r.draft, r.tag_name.hasPrefix("pin-v"),
                      let ipa = r.assets.first(where: { $0.name.hasSuffix(".ipa") })?.browser_download_url else { return nil }
                return Version(numero: String(r.tag_name.dropFirst("pin-v".count)), ipa: ipa, notes: r.body ?? "")
            }
            let meilleure = candidates.max { Self.plusPetite($0.numero, $1.numero) }
            disponible = meilleure.flatMap { Self.plusPetite(Self.actuelle, $0.numero) ? $0 : nil }
            derniereErreur = nil
            verifieeLe = Date()
        } catch {
            derniereErreur = "Impossible de vérifier (\(error.localizedDescription))"
        }
    }

    /// Ouvre LiveContainer sur le nouvel IPA ; s'il ne répond pas (Pin installé
    /// autrement), on ouvre le lien de téléchargement dans Safari.
    func installer() {
        guard let v = disponible else { return }
        var c = URLComponents()
        c.scheme = "livecontainer"
        c.host = "install"
        c.queryItems = [URLQueryItem(name: "url", value: v.ipa.absoluteString)]
        guard let lien = c.url else { return }
        UIApplication.shared.open(lien) { ok in
            if !ok { UIApplication.shared.open(v.ipa) }
        }
    }

    /// Comparaison de versions « 1.4.10 » > « 1.4.9 ».
    static func plusPetite(_ a: String, _ b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let u = i < x.count ? x[i] : 0
            let v = i < y.count ? y[i] : 0
            if u != v { return u < v }
        }
        return false
    }
}
