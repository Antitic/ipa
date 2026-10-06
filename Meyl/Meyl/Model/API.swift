import Foundation
import Security

// MARK: - Erreurs lisibles

enum MailError: LocalizedError {
    case badURL
    case unauthorized(String)
    case unreachable
    case server(Int, String)
    case decoding

    var errorDescription: String? {
        switch self {
        case .badURL: return "Adresse du bureau de poste invalide."
        case .unauthorized(let m): return m
        case .unreachable: return "Bureau de poste injoignable. Vérifie ta connexion et le tunnel du homelab."
        case .server(_, let m): return m
        case .decoding: return "Réponse illisible du serveur."
        }
    }

    var isAuth: Bool {
        if case .unauthorized = self { return true }
        return false
    }
}

// MARK: - Compte

struct Account: Equatable {
    var server: URL
    var user: String
    var pass: String

    static let defaultServer = "https://mail.dipherant.xyz"

    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { s = defaultServer }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "https://" + s }
        while s.hasSuffix("/") { s.removeLast() }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }
}

// MARK: - Client HTTP

struct MailAPI {
    let account: Account

    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 120
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.httpCookieStorage = nil
        return URLSession(configuration: c)
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = withFrac.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "date: \(s)")
        }
        return d
    }()

    private var authHeader: String {
        "Basic " + Data((account.user + ":" + account.pass).utf8).base64EncodedString()
    }

    func url(_ path: String, _ query: [URLQueryItem] = []) throws -> URL {
        guard var comps = URLComponents(url: account.server, resolvingAgainstBaseURL: false) else { throw MailError.badURL }
        comps.path = (comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path) + "/app/v1" + path
        if !query.isEmpty { comps.queryItems = query }
        guard let u = comps.url else { throw MailError.badURL }
        return u
    }

    func raw(_ path: String, query: [URLQueryItem] = [], method: String = "GET",
             body: Data? = nil, contentType: String? = nil, timeout: TimeInterval = 20) async throws -> Data {
        var req = URLRequest(url: try url(path, query))
        req.httpMethod = method
        req.timeoutInterval = timeout
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        req.httpBody = body

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await MailAPI.session.data(for: req)
        } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw MailError.unreachable
        }
        guard let http = resp as? HTTPURLResponse else { throw MailError.unreachable }
        if (200..<300).contains(http.statusCode) { return data }
        let decoded = (try? MailAPI.decoder.decode(ErrorResponse.self, from: data))?.error
        if http.statusCode == 401 { throw MailError.unauthorized(decoded ?? "Adresse ou mot de passe incorrect.") }
        guard let msg = decoded else {
            // Page d'erreur Cloudflare (origine éteinte, tunnel coupé…) : pas de JSON.
            if http.statusCode >= 500 { throw MailError.unreachable }
            throw MailError.server(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        throw MailError.server(http.statusCode, msg)
    }

    func get<T: Decodable>(_ path: String, _ query: [URLQueryItem] = []) async throws -> T {
        let data = try await raw(path, query: query)
        do { return try MailAPI.decoder.decode(T.self, from: data) } catch { throw MailError.decoding }
    }

    func post<T: Decodable>(_ path: String, json: [String: Any]) async throws -> T {
        let body = try JSONSerialization.data(withJSONObject: json)
        let data = try await raw(path, method: "POST", body: body, contentType: "application/json")
        do { return try MailAPI.decoder.decode(T.self, from: data) } catch { throw MailError.decoding }
    }

    // MARK: Routes

    func me() async throws -> MeResponse { try await get("/me") }

    func list(_ box: String, before: Int? = nil) async throws -> ListResponse {
        var q = [URLQueryItem(name: "box", value: box)]
        if let before { q.append(URLQueryItem(name: "before", value: String(before))) }
        return try await get("/list", q)
    }

    func poll(after: Int) async throws -> PollResponse {
        try await get("/poll", [URLQueryItem(name: "after", value: String(after))])
    }

    func search(_ q: String) async throws -> [MailRow] {
        let r: SearchResponse = try await get("/search", [URLQueryItem(name: "q", value: q)])
        return r.rows
    }

    func message(_ box: String, _ uid: Int) async throws -> MailMessage {
        try await get("/message/\(box)/\(uid)")
    }

    func bodyHTML(_ box: String, _ uid: Int, remoteImages: Bool) async throws -> String {
        let q = remoteImages ? [URLQueryItem(name: "img", value: "1")] : []
        let data = try await raw("/message/\(box)/\(uid)/body", query: q)
        return String(decoding: data, as: UTF8.self)
    }

    func attachment(_ box: String, _ uid: Int, _ index: Int) async throws -> Data {
        try await raw("/attachment/\(box)/\(uid)/\(index)", timeout: 120)
    }

    func move(_ box: String, _ uid: Int, to: String) async throws -> MoveResponse {
        try await post("/move", json: ["box": box, "uid": uid, "to": to])
    }

    func flag(_ box: String, _ uid: Int, seen: Bool) async throws {
        let _: OKResponse = try await post("/flag", json: ["box": box, "uid": uid, "seen": seen])
    }

    func send(_ d: Draft) async throws -> SendResponse {
        let boundary = "meyl-" + UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data(value.utf8))
            body.append(Data("\r\n".utf8))
        }
        field("to", d.to)
        field("cc", d.cc)
        field("subject", d.subject)
        field("body", d.body)
        if !d.inReplyTo.isEmpty { field("inReplyTo", d.inReplyTo) }
        if !d.references.isEmpty { field("references", d.references) }
        for f in d.files {
            let safe = f.name.replacingOccurrences(of: "\"", with: "'")
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(safe)\"\r\nContent-Type: \(f.mime)\r\n\r\n".utf8))
            body.append(f.data)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        let data = try await raw("/send", method: "POST", body: body,
                                 contentType: "multipart/form-data; boundary=\(boundary)", timeout: 120)
        do { return try MailAPI.decoder.decode(SendResponse.self, from: data) } catch { throw MailError.decoding }
    }
}

// MARK: - Trousseau (avec repli si LiveContainer refuse le trousseau)

enum SecretStore {
    private static let service = "com.antitic.meyl"

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "fallback." + key)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(add as CFDictionary, nil) != errSecSuccess {
            UserDefaults.standard.set(value, forKey: "fallback." + key)
        }
    }

    static func get(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data {
            return String(data: d, encoding: .utf8)
        }
        return UserDefaults.standard.string(forKey: "fallback." + key)
    }
}
