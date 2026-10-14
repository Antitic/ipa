import SwiftUI

/// Les coques de Pin, au choix dans Réglages › Skin.
enum Skin: String, CaseIterable, Identifiable {
    case blanc, noir, rouge, argent, bleu, rose, u2

    var id: String { rawValue }

    var nom: String {
        switch self {
        case .blanc: return "Blanc (classic)"
        case .noir: return "Noir"
        case .rouge: return "Rouge"
        case .argent: return "Aluminium"
        case .bleu: return "Bleu nano"
        case .rose: return "Rose Dipherant"
        case .u2: return "Noir et rouge"
        }
    }

    /// Façade du boîtier (haut → bas).
    var facade: [Color] {
        switch self {
        case .blanc: return [Color(white: 0.985), Color(white: 0.93), Color(white: 0.955)]
        case .noir: return [Color(white: 0.2), Color(white: 0.08), Color(white: 0.13)]
        case .rouge: return [Color(red: 0.86, green: 0.1, blue: 0.14), Color(red: 0.62, green: 0.04, blue: 0.08), Color(red: 0.74, green: 0.06, blue: 0.1)]
        case .argent: return [Color(white: 0.88), Color(white: 0.72), Color(white: 0.82)]
        case .bleu: return [Color(red: 0.36, green: 0.62, blue: 0.95), Color(red: 0.16, green: 0.4, blue: 0.78), Color(red: 0.25, green: 0.5, blue: 0.86)]
        case .rose: return [Color(red: 1, green: 0.35, blue: 0.56), Color(red: 0.85, green: 0.07, blue: 0.37), Color(red: 0.95, green: 0.18, blue: 0.45)]
        case .u2: return [Color(white: 0.16), Color(white: 0.04), Color(white: 0.1)]
        }
    }

    var reflet: Double {
        switch self {
        case .noir, .u2: return 0.18
        case .argent: return 0.55
        default: return 0.6
        }
    }

    /// Molette : fond (haut → bas), libellés, contour.
    var molette: [Color] {
        switch self {
        case .blanc: return [Color(white: 0.97), Color(white: 0.88)]
        case .noir: return [Color(white: 0.3), Color(white: 0.18)]
        case .rouge, .rose, .bleu: return [Color(white: 0.99), Color(white: 0.9)]
        case .argent: return [Color(white: 0.98), Color(white: 0.9)]
        case .u2: return [Color(red: 0.82, green: 0.08, blue: 0.12), Color(red: 0.6, green: 0.03, blue: 0.07)]
        }
    }

    var libellesMolette: Color {
        switch self {
        case .noir: return Color(white: 0.75)
        case .u2: return Color(white: 0.12)
        default: return Color(white: 0.62)
        }
    }

    var contourMolette: Color {
        switch self {
        case .noir, .u2: return Color(white: 0.05)
        default: return Color(white: 0.78)
        }
    }

    /// Bouton central (haut → bas, au repos).
    var centre: [Color] {
        switch self {
        case .noir, .u2: return [Color(white: 0.16), Color(white: 0.08)]
        case .rouge: return [Color(red: 0.86, green: 0.1, blue: 0.14), Color(red: 0.66, green: 0.05, blue: 0.09)]
        case .bleu: return [Color(red: 0.36, green: 0.62, blue: 0.95), Color(red: 0.2, green: 0.45, blue: 0.82)]
        case .rose: return [Color(red: 1, green: 0.35, blue: 0.56), Color(red: 0.88, green: 0.1, blue: 0.4)]
        default: return [Color(white: 0.99), Color(white: 0.9)]
        }
    }

    var centreEnfonce: [Color] { centre.reversed().map { $0.opacity(0.92) } }
}

/// La skin choisie, lue partout.
struct ModificateurSkin: ViewModifier {
    @AppStorage("skin") private var choix = Skin.blanc.rawValue
    func body(content: Content) -> some View {
        content.environment(\.skin, Skin(rawValue: choix) ?? .blanc)
    }
}

private struct CleSkin: EnvironmentKey { static let defaultValue = Skin.blanc }
extension EnvironmentValues {
    var skin: Skin {
        get { self[CleSkin.self] }
        set { self[CleSkin.self] = newValue }
    }
}

/// Réglages › Skin : la molette parcourt les coques, l'aperçu change en direct.
struct EcranSkins: View {
    @AppStorage("skin") private var choix = Skin.blanc.rawValue

    var body: some View {
        EcranListe(cle: .skins,
                   elements: Skin.allCases.map { ElementListe(id: $0.rawValue, titre: $0.nom, detail: $0.rawValue == choix ? "✓ Actuelle" : nil, chevron: false) }) { e in
            withAnimation(.easeInOut(duration: 0.35)) { choix = e.id }
        }
    }
}
