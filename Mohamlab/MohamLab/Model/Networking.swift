import Foundation
import Security

// MARK: - Erreurs lisibles

enum APIError: LocalizedError {
    case badURL
    case unauthorized
    case unreachable(String)
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "Adresse du serveur invalide."
        case .unauthorized:
            return "Jeton refusé par le serveur."
        case .unreachable:
            return "Serveur injoignable. Tailscale est-il actif sur l'iPhone ?"
        case .http(let code, let message):
            return "Le serveur a répondu \(code) : \(message)"
        case .decoding:
            return "Réponse du serveur illisible (versions app/agent différentes ?)."
        }
    }
}

// MARK: - Client HTTP

struct API {
    let base: URL
    let token: String

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    init?(baseURL: String, token: String) {
        var s = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "http://" + s
        }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { return nil }
        self.base = url
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.badURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await send(request)
    }

    func post(_ path: String) async throws {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 70
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let _: OKResponse = try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let result: (Data, URLResponse)
        do {
            result = try await API.session.data(for: request)
        } catch {
            throw APIError.unreachable(error.localizedDescription)
        }
        let data = result.0
        guard let http = result.1 as? HTTPURLResponse else {
            throw APIError.unreachable("Réponse invalide")
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error ?? "erreur"
            throw APIError.http(http.statusCode, message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}

// MARK: - Trousseau (le jeton ne traîne pas dans les préférences)

enum Keychain {
    private static let service = "xyz.dipherant.mohamlab"

    static func set(_ value: String, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Mise en forme (à la française)

enum Fmt {
    private static let units = ["o", "Ko", "Mo", "Go", "To"]

    /// 1 234 567 → « 1,2 Mo »
    static func bytes(_ value: Int?) -> String {
        guard let value else { return "—" }
        let (n, u) = scaled(Double(value))
        return frNumber(n, decimals: (u == 0 || n >= 100) ? 0 : 1) + " " + units[u]
    }

    static func rate(_ value: Int) -> String { bytes(value) + "/s" }

    /// Pour les afficheurs 7 segments : (« 812.3 », « KO/S »)
    static func rateParts(_ value: Int) -> (String, String) {
        let (n, u) = scaled(Double(value))
        let digits = u == 0 ? String(format: "%.0f", n) : (n >= 100 ? String(format: "%.0f", n) : String(format: "%.1f", n))
        return (digits, units[u].uppercased() + "/S")
    }

    static func gigabytes(_ value: Int) -> String {
        let g = Double(value) / 1_073_741_824
        return g >= 100 ? String(format: "%.0f", g) : String(format: "%.1f", g)
    }

    private static func scaled(_ value: Double) -> (Double, Int) {
        var v = max(value, 0)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return (v, i)
    }

    static func frNumber(_ v: Double, decimals: Int) -> String {
        String(format: "%.\(decimals)f", v).replacingOccurrences(of: ".", with: ",")
    }

    /// 669354 s → « 7 j 17 h »
    static func duration(_ seconds: Int?) -> String {
        guard let s = seconds, s >= 0 else { return "—" }
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return h > 0 ? "\(d) j \(h) h" : "\(d) j" }
        if h > 0 { return m > 0 ? "\(h) h \(m) min" : "\(h) h" }
        if m > 0 { return "\(m) min" }
        return "\(s) s"
    }

    static func uptimeParts(_ seconds: Int) -> (days: Int, hours: Int, minutes: Int) {
        (seconds / 86400, (seconds % 86400) / 3600, (seconds % 3600) / 60)
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayClockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "dd/MM HH:mm"
        return f
    }()

    private static let longFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "dd/MM/yyyy 'À' HH:mm"
        return f
    }()

    static func clock(_ t: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(t))
        return Calendar.current.isDateInToday(date) ? clockFormatter.string(from: date) : dayClockFormatter.string(from: date)
    }

    static func long(_ date: Date) -> String { longFormatter.string(from: date) }

    static func ago(_ date: Date?) -> String {
        guard let date else { return "jamais" }
        let s = Int(Date().timeIntervalSince(date))
        if s < 5 { return "à l'instant" }
        if s < 60 { return "il y a \(s) s" }
        return "il y a " + duration(s)
    }

    /// Débit (octets/s) → position 0…1 sur une échelle logarithmique 100 o/s … 100 Mo/s.
    static func logRate(_ bytes: Int) -> Double {
        let v = log10(max(Double(bytes), 1))
        return min(max((v - 2) / 6, 0), 1)
    }
}
