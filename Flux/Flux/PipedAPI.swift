import Foundation

enum Prefs {
    static let instanceKey = "instance"
    static let regionKey = "region"
    static let fallbackKey = "fallback"

    /// Instances publiques connues. Le mieux reste ta propre instance (voir README).
    static let defaultInstances = [
        "https://pipedapi.kavin.rocks",
        "https://api.piped.private.coffee",
        "https://pipedapi.adminforge.de",
        "https://pipedapi.leptons.xyz",
        "https://pipedapi.nosebs.ru",
    ]

    static var instance: String {
        normalize(UserDefaults.standard.string(forKey: instanceKey) ?? defaultInstances[0])
    }

    static var region: String {
        let r = UserDefaults.standard.string(forKey: regionKey) ?? "FR"
        return r.isEmpty ? "FR" : r.uppercased()
    }

    static var fallback: Bool {
        UserDefaults.standard.object(forKey: fallbackKey) as? Bool ?? true
    }

    static var orderedInstances: [String] {
        let main = instance
        guard fallback else { return [main] }
        return [main] + defaultInstances.filter { $0 != main }
    }

    static func normalize(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix("/") { t.removeLast() }
        if !t.lowercased().hasPrefix("http") { t = "https://" + t }
        return t
    }
}

enum APIError: LocalizedError {
    case http(Int)
    case noStream
    case badURL

    var errorDescription: String? {
        switch self {
        case .http(let code): return "L'instance a répondu \(code). Change d'instance dans Réglages."
        case .noStream: return "Aucun flux lisible pour cette vidéo."
        case .badURL: return "URL invalide."
        }
    }
}

/// Client Piped. Toutes les requêtes passent par l'instance : l'app ne contacte jamais Google.
final class PipedAPI {
    static let shared = PipedAPI()

    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = ["User-Agent": "Flux/1.0"]
        session = URLSession(configuration: config)
    }

    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    private func makeURL(base: String, path: String, query: [String: String]) -> URL? {
        var s = base + path
        if !query.isEmpty {
            let q = query.map { key, value in
                let v = value.addingPercentEncoding(withAllowedCharacters: Self.allowed) ?? value
                return "\(key)=\(v)"
            }.joined(separator: "&")
            s += "?" + q
        }
        return URL(string: s)
    }

    func get<T: Decodable>(_ path: String, _ query: [String: String] = [:]) async throws -> T {
        var lastError: Error = APIError.badURL
        for base in Prefs.orderedInstances {
            try Task.checkCancellation()
            guard let url = makeURL(base: base, path: path, query: query) else { continue }
            do {
                let (data, response) = try await session.data(from: url)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard (200..<300).contains(code) else {
                    lastError = APIError.http(code)
                    continue
                }
                return try decoder.decode(T.self, from: data)
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func trending() async throws -> [PipedItem] {
        try await get("/trending", ["region": Prefs.region])
    }

    func search(_ q: String) async throws -> SearchPage {
        try await get("/search", ["q": q, "filter": "all"])
    }

    func searchNext(_ q: String, page: String) async throws -> SearchPage {
        try await get("/nextpage/search", ["q": q, "filter": "all", "nextpage": page])
    }

    func suggestions(_ q: String) async throws -> [String] {
        try await get("/suggestions", ["query": q])
    }

    func streams(_ id: String) async throws -> StreamDetail {
        try await get("/streams/\(id)")
    }

    func channel(_ id: String) async throws -> ChannelPage {
        try await get("/channel/\(id)")
    }

    func channelNext(_ id: String, page: String) async throws -> ChannelNextPage {
        try await get("/nextpage/channel/\(id)", ["nextpage": page])
    }

    func feed(_ channelIDs: [String]) async throws -> [PipedItem] {
        try await get("/feed/unauthenticated", ["channels": channelIDs.joined(separator: ",")])
    }

    /// Teste une instance précise (sans bascule), renvoie la latence en ms.
    func ping(_ base: String) async throws -> Int {
        guard let url = makeURL(base: Prefs.normalize(base), path: "/suggestions", query: ["query": "test"]) else {
            throw APIError.badURL
        }
        let start = Date()
        let (_, response) = try await session.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw APIError.http(code) }
        return Int(Date().timeIntervalSince(start) * 1000)
    }
}
