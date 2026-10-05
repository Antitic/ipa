import Foundation

/// Abonnements stockés localement sur le téléphone. Pas de compte, pas de sync Google.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var subscriptions: [ChannelRef] = [] {
        didSet { save() }
    }

    private let key = "subscriptions"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let subs = try? JSONDecoder().decode([ChannelRef].self, from: data) {
            subscriptions = subs
        }
    }

    var subscriptionIDs: [String] { subscriptions.map(\.id) }

    func isSubscribed(_ id: String) -> Bool {
        subscriptions.contains { $0.id == id }
    }

    func toggle(_ ref: ChannelRef) {
        if isSubscribed(ref.id) {
            subscriptions.removeAll { $0.id == ref.id }
        } else {
            subscriptions.append(ref)
            sort()
        }
    }

    func remove(at offsets: IndexSet) {
        subscriptions.remove(atOffsets: offsets)
    }

    /// Import depuis Google Takeout (subscriptions.csv) ou NewPipe / Piped (JSON).
    @discardableResult
    func importFile(_ url: URL) throws -> Int {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)

        var found: [ChannelRef] = []
        if let json = try? JSONDecoder().decode(NewPipeExport.self, from: data) {
            for sub in json.subscriptions {
                if let id = PipedItem.channelID(from: sub.url) {
                    found.append(ChannelRef(id: id, name: sub.name, avatar: nil))
                }
            }
        } else if let text = String(data: data, encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline).dropFirst() {
                let parts = line.split(separator: ",", omittingEmptySubsequences: false)
                guard parts.count >= 3 else { continue }
                let id = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let name = parts[2...].joined(separator: ",").trimmingCharacters(in: .whitespaces)
                if id.hasPrefix("UC") { found.append(ChannelRef(id: id, name: name, avatar: nil)) }
            }
        }

        let new = found.filter { !isSubscribed($0.id) }
        subscriptions.append(contentsOf: new)
        sort()
        return new.count
    }

    private func sort() {
        subscriptions.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(subscriptions) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

private struct NewPipeExport: Decodable {
    struct Sub: Decodable { let url: String; let name: String }
    let subscriptions: [Sub]
}
