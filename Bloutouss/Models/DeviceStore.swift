import Foundation

/// Favoris et noms personnalisés, conservés entre les lancements.
final class DeviceStore: ObservableObject {
    @Published private(set) var favorites: Set<UUID>
    @Published private(set) var customNames: [UUID: String]

    private static let favoritesKey = "favorites"
    private static let customNamesKey = "customNames"

    init() {
        let defaults = UserDefaults.standard
        let storedFavorites = defaults.stringArray(forKey: Self.favoritesKey) ?? []
        favorites = Set(storedFavorites.compactMap(UUID.init(uuidString:)))

        let storedNames = defaults.dictionary(forKey: Self.customNamesKey) as? [String: String] ?? [:]
        var names: [UUID: String] = [:]
        for (key, value) in storedNames {
            if let id = UUID(uuidString: key) { names[id] = value }
        }
        customNames = names
    }

    func isFavorite(_ id: UUID) -> Bool {
        favorites.contains(id)
    }

    func toggleFavorite(_ id: UUID) {
        if favorites.contains(id) {
            favorites.remove(id)
        } else {
            favorites.insert(id)
        }
        save()
    }

    func setCustomName(_ name: String?, for id: UUID) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        customNames[id] = trimmed.isEmpty ? nil : trimmed
        save()
    }

    func displayName(for device: BluetoothDevice) -> String {
        customNames[device.id] ?? device.baseName
    }

    func reset() {
        favorites.removeAll()
        customNames.removeAll()
        save()
    }

    private func save() {
        let defaults = UserDefaults.standard
        defaults.set(favorites.map(\.uuidString), forKey: Self.favoritesKey)
        defaults.set(
            Dictionary(uniqueKeysWithValues: customNames.map { ($0.key.uuidString, $0.value) }),
            forKey: Self.customNamesKey
        )
    }
}
