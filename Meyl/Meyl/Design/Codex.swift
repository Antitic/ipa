import SwiftUI
import UIKit

// MARK: - Thèmes

enum AppTheme: String, CaseIterable, Identifiable {
    case codex
    case ecritoire

    var id: String { rawValue }

    var name: String {
        switch self {
        case .codex: return "Codex"
        case .ecritoire: return "Écritoire"
        }
    }

    var blurb: String {
        switch self {
        case .codex: return "Blanc, Garamond et tramage pixel."
        case .ecritoire: return "Noyer, cuir, laiton et cire."
        }
    }
}

// MARK: - Palette Codex

enum CX {
    static let paper = Color.white
    static let wash = Color(red: 0.965, green: 0.961, blue: 0.945)      // gris chaud très clair
    static let hairline = Color(red: 0.894, green: 0.886, blue: 0.851)
    static let ink = Color(red: 0.035, green: 0.090, blue: 0.090)       // presque noir, teinté
    static let ink2 = Color(red: 0.33, green: 0.38, blue: 0.38)
    static let ink3 = Color(red: 0.58, green: 0.61, blue: 0.60)
    static let teal = Color(red: 0.125, green: 0.502, blue: 0.553)      // #20808D
    static let tealBright = Color(red: 0.122, green: 0.722, blue: 0.804) // #1FB8CD
    static let tealWash = Color(red: 0.125, green: 0.502, blue: 0.553).opacity(0.08)
    static let red = Color(red: 0.72, green: 0.17, blue: 0.13)

    // MARK: Garamond partout

    enum Weight { case regular, medium, semibold }

    static func serif(_ size: CGFloat, _ weight: Weight = .regular, italic: Bool = false) -> Font {
        let name: String
        switch (weight, italic) {
        case (.regular, false): name = "EBGaramond-Regular"
        case (.regular, true): name = "EBGaramond-Italic"
        case (.medium, false): name = "EBGaramond-Medium"
        case (.medium, true): name = "EBGaramond-Italic"
        case (.semibold, false): name = "EBGaramond-SemiBold"
        case (.semibold, true): name = "EBGaramond-SemiBoldItalic"
        }
        return .custom(name, size: size)
    }

    /// Titres façon « Think Different » : Garamond serré.
    static func display(_ size: CGFloat, italic: Bool = false) -> Font {
        serif(size, .medium, italic: italic)
    }

    /// Détails bitmap (dates, compteurs, étiquettes) — toujours en majuscules.
    static func pixel(_ size: CGFloat = 9) -> Font { .custom("Silkscreen-Regular", size: size) }
}

extension View {
    func pixelLabel(_ size: CGFloat = 9, color: Color = CX.ink3) -> some View {
        self.font(CX.pixel(size))
            .foregroundStyle(color)
            .textCase(.uppercase)
            .kerning(0.4)
    }
}

// MARK: - Tramage ordonné (Bayer 8×8)

enum Bayer {
    static let m8: [[Double]] = {
        let b: [[Int]] = [
            [0, 32, 8, 40, 2, 34, 10, 42],
            [48, 16, 56, 24, 50, 18, 58, 26],
            [12, 44, 4, 36, 14, 46, 6, 38],
            [60, 28, 52, 20, 62, 30, 54, 22],
            [3, 35, 11, 43, 1, 33, 9, 41],
            [51, 19, 59, 27, 49, 17, 57, 25],
            [15, 47, 7, 39, 13, 45, 5, 37],
            [63, 31, 55, 23, 61, 29, 53, 21],
        ]
        return b.map { $0.map { (Double($0) + 0.5) / 64 } }
    }()

    static func threshold(_ i: Int, _ j: Int) -> Double { m8[j & 7][i & 7] }
}

/// Un champ d'intensité (0…1) en coordonnées normalisées (0…1), éventuellement animé.
typealias DitherField = (_ x: Double, _ y: Double, _ t: Double) -> Double

/// Rend un champ en pixels tramés : chaque cellule est allumée si l'intensité
/// dépasse le seuil de Bayer, ce qui donne le grain « imprimé » caractéristique.
struct Dither: View {
    var cell: CGFloat = 4
    var color: Color = CX.teal
    var animated = false
    var speed: Double = 1
    let field: DitherField

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 18.0)) { tl in
                canvas(t: tl.date.timeIntervalSinceReferenceDate * speed)
            }
        } else {
            canvas(t: 0)
        }
    }

    private func canvas(t: Double) -> some View {
        Canvas(rendersAsynchronously: false) { ctx, size in
            let cols = max(1, Int(size.width / cell))
            let rows = max(1, Int(size.height / cell))
            var path = Path()
            for j in 0..<rows {
                let y = (Double(j) + 0.5) / Double(rows)
                for i in 0..<cols {
                    let x = (Double(i) + 0.5) / Double(cols)
                    if field(x, y, t) > Bayer.threshold(i, j) {
                        path.addRect(CGRect(x: CGFloat(i) * cell, y: CGFloat(j) * cell, width: cell, height: cell))
                    }
                }
            }
            ctx.fill(path, with: .color(color))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Champs prêts à l'emploi

enum Fields {
    /// Sphère éclairée en haut à gauche ; la lumière tourne doucement si t avance.
    static func orb(_ x: Double, _ y: Double, _ t: Double) -> Double {
        let cx = 0.5, cy = 0.5, r = 0.46
        let dx = (x - cx) / r, dy = (y - cy) / r
        let d2 = dx * dx + dy * dy
        guard d2 <= 1 else {
            // halo très léger autour
            let d = sqrt(d2)
            return max(0, 0.18 - (d - 1) * 0.9)
        }
        let nz = sqrt(1 - d2)
        let a = t * 0.35
        let lx = -0.55 + 0.25 * sin(a), ly = -0.6 + 0.2 * cos(a), lz = 0.6
        let len = sqrt(lx * lx + ly * ly + lz * lz)
        let lambert = max(0, (dx * lx + dy * ly + nz * lz) / len)
        return 0.12 + 0.88 * pow(lambert, 1.25)
    }

    /// Enveloppe vue de face, avec son rabat.
    static func envelope(_ x: Double, _ y: Double, _ t: Double) -> Double {
        let x0 = 0.08, x1 = 0.92, y0 = 0.2, y1 = 0.82
        guard x >= x0, x <= x1, y >= y0, y <= y1 else { return 0 }
        let u = (x - x0) / (x1 - x0), v = (y - y0) / (y1 - y0)
        // plis du rabat : V depuis les coins du haut
        let flapY = 0.55 - abs(u - 0.5) * 1.1
        let onFlapEdge = abs(v - flapY) < 0.035 && v < 0.56
        if onFlapEdge { return 0 }
        let inFlap = v < flapY
        let base = inFlap ? 0.78 - v * 0.6 : 0.42 + (1 - v) * 0.25 - u * 0.12
        return base
    }

    /// Ondes croisées : sert d'indicateur « ça charge ».
    static func waves(_ x: Double, _ y: Double, _ t: Double) -> Double {
        let a = sin(x * 9 + t * 2.2) + sin(y * 7 - t * 1.7) + sin((x + y) * 6 + t * 1.3)
        return 0.5 + a / 6
    }

    /// Dégradé horizontal (barres, soulignements).
    static func ramp(_ x: Double, _ y: Double, _ t: Double) -> Double { 1 - x * 0.9 }

    /// Pile de feuilles (casier vide / état vide).
    static func tray(_ x: Double, _ y: Double, _ t: Double) -> Double {
        // plateau
        if y > 0.62 && y < 0.86 && x > 0.06 && x < 0.94 {
            return 0.35 + (y - 0.62) * 1.8
        }
        // feuilles légèrement décalées
        for k in 0..<3 {
            let off = Double(k) * 0.07
            if x > 0.2 + off && x < 0.8 + off * 0.3 && y > 0.18 + off && y < 0.66 {
                return 0.12 + Double(k) * 0.1
            }
        }
        return 0
    }
}

// MARK: - Petits éléments pixel

/// Carré pixel plein (indicateur « non lu »).
struct PixelDot: View {
    var color: Color = CX.teal
    var size: CGFloat = 7
    var body: some View {
        Rectangle().fill(color).frame(width: size, height: size)
    }
}

/// Indicateur de chargement : ondes tramées animées.
struct PixelLoader: View {
    var width: CGFloat = 64
    var height: CGFloat = 16
    var cell: CGFloat = 3
    var color: Color = CX.teal
    var body: some View {
        Dither(cell: cell, color: color, animated: true, speed: 1.4, field: Fields.waves)
            .frame(width: width, height: height)
    }
}

/// Monogramme pixel de l'expéditeur.
struct PixelMonogram: View {
    let name: String
    var size: CGFloat = 40

    private var letter: String {
        let s = name.trimmingCharacters(in: CharacterSet(charactersIn: "\"' <"))
        return s.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        ZStack {
            Rectangle().fill(CX.tealWash)
            Dither(cell: 2, color: CX.teal.opacity(0.55)) { x, y, _ in 0.55 - y * 0.45 }
            Text(letter)
                .font(CX.serif(size * 0.55, .medium))
                .foregroundStyle(CX.ink)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Boutons

struct CXIconButton: View {
    let symbol: String
    var label: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 15, weight: .regular))
                if let label { Text(label).font(CX.serif(17)) }
            }
            .foregroundStyle(CX.ink)
            .padding(.horizontal, label == nil ? 0 : 12)
            .frame(minWidth: 38, minHeight: 38)
            .background(Capsule().strokeBorder(CX.hairline, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(CXPress())
    }
}

struct CXPrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var busy = false
    let action: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            ZStack {
                Capsule().fill(CX.teal)
                if busy {
                    Dither(cell: 3, color: .white.opacity(0.55), animated: true, speed: 1.6, field: Fields.waves)
                        .clipShape(Capsule())
                }
                HStack(spacing: 8) {
                    if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .semibold)) }
                    Text(title).font(CX.serif(19, .semibold))
                }
                .foregroundStyle(.white)
            }
            .frame(height: 52)
        }
        .buttonStyle(CXPress())
        .disabled(busy)
    }
}

struct CXPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Champ de saisie

struct CXField: View {
    let label: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var placeholder = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).pixelLabel(9, color: focused ? CX.teal : CX.ink3)
            Group {
                if secure {
                    SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(CX.ink3))
                } else {
                    TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(CX.ink3))
                        .keyboardType(keyboard)
                }
            }
            .font(CX.serif(21))
            .foregroundStyle(CX.ink)
            .tint(CX.teal)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($focused)
            Rectangle()
                .fill(focused ? CX.teal : CX.hairline)
                .frame(height: focused ? 2 : 1)
        }
    }
}

// MARK: - Notification interne

struct CXToast: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            PixelDot(color: toast.isError ? Color(red: 1, green: 0.45, blue: 0.4) : CX.tealBright, size: 8)
            Text(toast.text)
                .font(CX.serif(17))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Capsule().fill(CX.ink))
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        .padding(.horizontal, 20)
    }
}

// MARK: - Dates en pixel

extension Fmt {
    static func pixelList(_ date: Date?) -> String {
        list(date).uppercased()
    }

    static func pixelStamp(_ date: Date?) -> String {
        guard let date else { return "" }
        let d = DateFormatter()
        d.locale = fr
        d.timeZone = paris
        d.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        let t = DateFormatter()
        t.locale = fr
        t.timeZone = paris
        t.dateFormat = "HH:mm"
        return (d.string(from: date).replacingOccurrences(of: ".", with: "") + " · " + t.string(from: date)).uppercased()
    }
}
