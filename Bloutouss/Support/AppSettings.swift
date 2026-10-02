import Foundation

enum SettingsKey {
    static let staleAfter = "staleAfter"
    static let removeAfter = "removeAfter"
    static let pathLoss = "pathLossExponent"
    static let measuredPower = "measuredPower"
    static let smoothing = "rssiSmoothing"
    static let haptics = "hapticsEnabled"
    static let finderSound = "finderSound"
    static let keepScreenOn = "keepScreenOn"
    static let favoriteAlerts = "favoriteAlerts"
    static let sortOrder = "sortOrder"
}

/// Accès aux réglages depuis le code hors des vues (les vues utilisent @AppStorage).
enum AppSettings {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.staleAfter: 10.0,
            SettingsKey.removeAfter: 0.0,
            SettingsKey.pathLoss: 2.0,
            SettingsKey.measuredPower: -59.0,
            SettingsKey.smoothing: 0.3,
            SettingsKey.haptics: true,
            SettingsKey.finderSound: false,
            SettingsKey.keepScreenOn: false,
            SettingsKey.favoriteAlerts: true,
        ])
    }

    private static var defaults: UserDefaults { .standard }

    /// Secondes sans annonce avant qu'un appareil soit considéré comme absent.
    static var staleAfter: Double { defaults.double(forKey: SettingsKey.staleAfter) }
    /// Secondes avant de retirer un appareil absent de la liste (0 = jamais).
    static var removeAfter: Double { defaults.double(forKey: SettingsKey.removeAfter) }
    /// Exposant d'atténuation du modèle de distance (2 = espace libre).
    static var pathLoss: Double { defaults.double(forKey: SettingsKey.pathLoss) }
    /// RSSI attendu à 1 m quand l'appareil n'annonce pas sa puissance.
    static var measuredPower: Double { defaults.double(forKey: SettingsKey.measuredPower) }
    /// Poids d'une nouvelle mesure dans la moyenne glissante du RSSI.
    static var smoothing: Double { defaults.double(forKey: SettingsKey.smoothing) }
    static var hapticsEnabled: Bool { defaults.bool(forKey: SettingsKey.haptics) }
    static var favoriteAlerts: Bool { defaults.bool(forKey: SettingsKey.favoriteAlerts) }
}
