import SwiftUI
import UIKit

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

@MainActor
final class MailStore: ObservableObject {
    @Published private(set) var account: Account?
    @Published var boxes: [Mailbox] = Mailbox.defaults
    @Published var rows: [String: [MailRow]] = [:]
    @Published var more: [String: Bool] = [:]
    @Published var loading: Set<String> = []
    @Published var toast: Toast?
    @Published private(set) var isDemo = false

    private var pollTask: Task<Void, Never>?
    private var messageCache: [String: MailMessage] = [:]

    var api: MailAPI? { account.map { MailAPI(account: $0) } }
    var user: String { account?.user ?? "" }

    init() {
        let d = UserDefaults.standard
        if d.bool(forKey: "forceDemo") {
            enterDemo()
            return
        }
        if let s = d.string(forKey: "server"), let url = Account.normalize(s),
           let u = SecretStore.get("user"), let p = SecretStore.get("pass"), !u.isEmpty, !p.isEmpty {
            account = Account(server: url, user: u, pass: p)
        }
    }

    // MARK: - Connexion

    func login(server: String, user: String, pass: String) async throws {
        guard let url = Account.normalize(server) else { throw MailError.badURL }
        var u = user.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !u.isEmpty && !u.contains("@") { u += "@dipherant.xyz" }
        let acc = Account(server: url, user: u, pass: pass)
        let me = try await MailAPI(account: acc).me()
        UserDefaults.standard.set(url.absoluteString, forKey: "server")
        SecretStore.set(u, for: "user")
        SecretStore.set(pass, for: "pass")
        isDemo = false
        account = acc
        boxes = me.boxes
        rows = [:]
        more = [:]
        messageCache = [:]
        await load("INBOX")
    }

    func logout() {
        pollTask?.cancel()
        pollTask = nil
        SecretStore.set(nil, for: "pass")
        account = nil
        isDemo = false
        rows = [:]
        more = [:]
        messageCache = [:]
        boxes = Mailbox.defaults
    }

    func enterDemo() {
        isDemo = true
        account = Account(server: URL(string: "https://demo.invalid")!, user: DemoData.user, pass: "demo")
        boxes = DemoData.boxes
        rows = DemoData.rows
        more = [:]
    }

    // MARK: - Erreurs

    func report(_ error: Error) {
        if error is CancellationError { return }
        if let e = error as? MailError, e.isAuth, !isDemo {
            logout()
            show("Session refusée : reconnecte-toi.", error: true)
            return
        }
        show(error.localizedDescription, error: true)
    }

    func show(_ text: String, error: Bool = false) {
        let t = Toast(text: text, isError: error)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { toast = t }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            guard let self, self.toast?.id == t.id else { return }
            withAnimation(.easeIn(duration: 0.25)) { self.toast = nil }
        }
    }

    // MARK: - Dossiers

    func refreshCounts() async {
        guard let api, !isDemo else { return }
        do {
            let me = try await api.me()
            boxes = me.boxes
        } catch { report(error) }
    }

    func load(_ box: String) async {
        guard !isDemo else { return }
        guard let api, !loading.contains(box) else { return }
        loading.insert(box)
        defer { loading.remove(box) }
        do {
            async let counts = api.me()
            let r = try await api.list(box)
            rows[box] = r.rows
            more[box] = r.more
            if let me = try? await counts { boxes = me.boxes }
        } catch { report(error) }
    }

    func loadMore(_ box: String) async {
        guard !isDemo, let api, more[box] == true, !loading.contains(box),
              let last = rows[box]?.last else { return }
        loading.insert(box)
        defer { loading.remove(box) }
        do {
            let r = try await api.list(box, before: last.uid)
            let known = Set((rows[box] ?? []).map(\.uid))
            rows[box, default: []].append(contentsOf: r.rows.filter { !known.contains($0.uid) })
            more[box] = r.more
        } catch { report(error) }
    }

    // MARK: - Relève automatique

    func startPolling() {
        guard pollTask == nil, account != nil, !isDemo else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func poll() async {
        guard let api, !isDemo else { return }
        let after = rows["INBOX"]?.map(\.uid).max() ?? 0
        do {
            let r = try await api.poll(after: after)
            for i in boxes.indices {
                if let c = r.counts[boxes[i].path] {
                    boxes[i].total = c.total
                    boxes[i].unseen = c.unseen
                    boxes[i].uidNext = c.uidNext
                }
            }
            if after > 0 && !r.rows.isEmpty {
                let known = Set((rows["INBOX"] ?? []).map(\.uid))
                let fresh = r.rows.filter { !known.contains($0.uid) }
                if !fresh.isEmpty {
                    withAnimation(.spring()) { rows["INBOX", default: []].insert(contentsOf: fresh, at: 0) }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    show(fresh.count == 1 ? "Une lettre de \(fresh[0].name)" : "\(fresh.count) nouvelles lettres")
                }
            }
        } catch {
            if let e = error as? MailError, e.isAuth { report(error) }
        }
    }

    // MARK: - Lecture

    func message(for row: MailRow) async throws -> MailMessage {
        if isDemo {
            markLocally(row, seen: true)
            return DemoData.message(for: row)
        }
        guard let api else { throw MailError.unauthorized("Non connecté.") }
        if let m = messageCache[row.id] {
            markLocally(row, seen: true)
            return m
        }
        let m = try await api.message(row.box, row.uid)
        messageCache[row.id] = m
        markLocally(row, seen: true)
        return m
    }

    func body(for row: MailRow, remoteImages: Bool) async throws -> String {
        if isDemo { return DemoData.html(for: row) }
        guard let api else { throw MailError.unauthorized("Non connecté.") }
        return try await api.bodyHTML(row.box, row.uid, remoteImages: remoteImages)
    }

    func attachmentFile(_ row: MailRow, _ att: Attachment) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("meyl-\(row.box)-\(row.uid)-\(att.index)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = att.name.replacingOccurrences(of: "/", with: "-")
        let file = dir.appendingPathComponent(name.isEmpty ? "piece-jointe" : name)
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let data: Data
        if isDemo {
            data = Data("Pièce jointe de démonstration.".utf8)
        } else {
            guard let api else { throw MailError.unauthorized("Non connecté.") }
            data = try await api.attachment(row.box, row.uid, att.index)
        }
        try data.write(to: file, options: .atomic)
        return file
    }

    private func markLocally(_ row: MailRow, seen: Bool) {
        guard var list = rows[row.box], let i = list.firstIndex(where: { $0.uid == row.uid }) else { return }
        guard list[i].seen != seen else { return }
        list[i].seen = seen
        rows[row.box] = list
        if let b = boxes.firstIndex(where: { $0.path == row.box }) {
            let u = boxes[b].unseen ?? 0
            boxes[b].unseen = max(0, u + (seen ? -1 : 1))
        }
    }

    // MARK: - Actions

    func setSeen(_ row: MailRow, _ seen: Bool) async {
        markLocally(row, seen: seen)
        guard !isDemo, let api else { return }
        do { try await api.flag(row.box, row.uid, seen: seen) } catch {
            markLocally(row, seen: !seen)
            report(error)
        }
    }

    /// Déplace (ou supprime définitivement avec to == "delete"). Retourne true si c'est fait.
    @discardableResult
    func move(_ row: MailRow, to: String) async -> Bool {
        let before = rows[row.box]
        withAnimation(.easeInOut(duration: 0.25)) {
            rows[row.box]?.removeAll { $0.uid == row.uid }
        }
        if !row.seen, let b = boxes.firstIndex(where: { $0.path == row.box }) {
            boxes[b].unseen = max(0, (boxes[b].unseen ?? 0) - 1)
        }
        messageCache[row.id] = nil
        if isDemo {
            show(to == "delete" ? "Lettre détruite." : "Rangée dans « \(Mailbox.label(for: to)) ».")
            return true
        }
        guard let api else { return false }
        do {
            _ = try await api.move(row.box, row.uid, to: to)
            rows[to] = nil // la destination sera rechargée à l'ouverture
            show(to == "delete" ? "Lettre détruite." : "Rangée dans « \(Mailbox.label(for: to)) ».")
            Task { await refreshCounts() }
            return true
        } catch {
            rows[row.box] = before
            report(error)
            return false
        }
    }

    func search(_ q: String) async throws -> [MailRow] {
        if isDemo {
            let all = DemoData.rows.values.flatMap { $0 }
            return all.filter { $0.subject.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q) }
        }
        guard let api else { return [] }
        return try await api.search(q)
    }

    func send(_ draft: Draft) async throws -> Bool {
        if isDemo {
            try await Task.sleep(nanoseconds: 900_000_000)
            return true
        }
        guard let api else { throw MailError.unauthorized("Non connecté.") }
        let r = try await api.send(draft)
        rows["Sent"] = nil
        Task { await refreshCounts() }
        return r.delivered
    }
}
