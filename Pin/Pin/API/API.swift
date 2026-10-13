import Foundation
import UIKit
import ImageIO

/// Erreur renvoyée par le serveur Pin (champ `error` du JSON) ou par le réseau.
struct ErreurPin: LocalizedError {
    let message: String
    let statut: Int
    var errorDescription: String? { message }
}

/// Client du serveur Pin (pin.dipherant.xyz). La session est le cookie `pin.sid`,
/// gardé un an dans HTTPCookieStorage.shared : on se connecte une seule fois.
enum API {
    static let base = URL(string: "https://pin.dipherant.xyz")!

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.httpCookieStorage = .shared
        c.httpCookieAcceptPolicy = .always
        c.httpShouldSetCookies = true
        c.timeoutIntervalForRequest = 40
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    static func url(_ chemin: String) -> URL {
        URL(string: chemin, relativeTo: base)!.absoluteURL
    }

    /// Encode un segment de chemin (un jid contient « @ » et parfois « : »).
    static func segment(_ s: String) -> String {
        var permis = CharacterSet.alphanumerics
        permis.insert(charactersIn: "-._~@")
        return s.addingPercentEncoding(withAllowedCharacters: permis) ?? s
    }

    @discardableResult
    static func requete(_ chemin: String, methode: String = "GET", json: [String: Any]? = nil,
                        corps: Data? = nil, type: String? = nil, delai: TimeInterval = 40) async throws -> Data {
        var req = URLRequest(url: url(chemin))
        req.httpMethod = methode
        req.timeoutInterval = delai
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        } else if let corps {
            req.httpBody = corps
            req.setValue(type ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
        }
        let (data, rep) = try await session.data(for: req)
        let code = (rep as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw ErreurPin(message: msg ?? "Erreur \(code)", statut: code)
        }
        return data
    }

    static let decodeur = JSONDecoder()

    static func get<T: Decodable>(_ chemin: String, _ type: T.Type = T.self) async throws -> T {
        try decodeur.decode(T.self, from: try await requete(chemin))
    }

    static func post<T: Decodable>(_ chemin: String, _ json: [String: Any] = [:], _ type: T.Type = T.self) async throws -> T {
        try decodeur.decode(T.self, from: try await requete(chemin, methode: "POST", json: json))
    }

    /// Données binaires (images, audio) : cache mémoire, puis cache disque
    /// (les médias ne changent jamais, ils s'ouvrent ensuite instantanément).
    private static let cache = NSCache<NSString, NSData>()
    private static let dossierCache: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("medias", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static func fichierCache(_ chemin: String) -> URL {
        let nom = chemin.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return dossierCache.appendingPathComponent(String(nom.suffix(180)))
    }

    static func donnees(_ chemin: String) async throws -> Data {
        if let d = cache.object(forKey: chemin as NSString) { return d as Data }
        let fichier = fichierCache(chemin)
        if let d = try? Data(contentsOf: fichier) {
            cache.setObject(d as NSData, forKey: chemin as NSString)
            return d
        }
        let d = try await requete(chemin, delai: 120)
        cache.setObject(d as NSData, forKey: chemin as NSString)
        try? d.write(to: fichier, options: .atomic)
        return d
    }

    /// Image décodée hors du fil principal, prête à afficher. Les GIF sont animés.
    static func image(_ chemin: String) async -> UIImage? {
        guard let d = try? await donnees(chemin) else { return nil }
        return await Task.detached(priority: .userInitiated) { decoder(d) }.value
    }

    static func decoder(_ d: Data) -> UIImage? {
        if let source = CGImageSourceCreateWithData(d as CFData, nil), CGImageSourceGetCount(source) > 1 {
            var images: [UIImage] = []
            var duree: Double = 0
            for i in 0..<CGImageSourceGetCount(source) {
                guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
                let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
                let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                let delai = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                    ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
                duree += delai < 0.02 ? 0.1 : delai
                images.append(UIImage(cgImage: cg))
            }
            return UIImage.animatedImage(with: images, duration: duree)
        }
        return UIImage(data: d)?.preparingForDisplay()
    }
}

struct Vide: Decodable {}
