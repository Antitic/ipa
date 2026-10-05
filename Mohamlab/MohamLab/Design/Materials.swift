import SwiftUI
import UIKit

// MARK: - Couleurs

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum Palette {
    static let walnut = Color(hex: 0x3A2416)
    static let walnutDeep = Color(hex: 0x1C110A)
    static let ink = Color(hex: 0x1C1A17)
    static let needleRed = Color(hex: 0xC8261E)
    static let ledGreen = Color(hex: 0x52FF74)
    static let ledRed = Color(hex: 0xFF3B2F)
    static let ledAmber = Color(hex: 0xFFB01F)
    static let ledBlue = Color(hex: 0x5BC8FF)
    static let segRed = Color(hex: 0xFF4433)
    static let segAmber = Color(hex: 0xFFA62B)
    static let phosphor = Color(hex: 0x6CFF8E)
    static let nixie = Color(hex: 0xFF7A1A)
    static let lcd = Color(hex: 0xA3B784)
    static let lcdInk = Color(hex: 0x1E2812)
    static let paper = Color(hex: 0xFBF8EE)
    static let paperBar = Color(hex: 0xD9EED3)
    static let ribbonBlack = Color(hex: 0x1D2333)
    static let ribbonRed = Color(hex: 0xB0261C)
    static let silkscreen = Color.white.opacity(0.86)
}

// MARK: - Générateur pseudo-aléatoire déterministe (textures identiques à chaque lancement)

struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 &+ 1 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Textures peintes une fois, puis réutilisées partout

enum Textures {
    static let brushed: UIImage = makeBrushed()
    static let wood: UIImage = makeWood()
    static let paper: UIImage = makePaper()
    static let grain: UIImage = makeGrain()

    private static func renderer(_ size: CGSize, opaque: Bool = false) -> UIGraphicsImageRenderer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = opaque
        return UIGraphicsImageRenderer(size: size, format: format)
    }

    /// Stries horizontales claires et sombres sur fond transparent (aluminium brossé).
    private static func makeBrushed() -> UIImage {
        let size = CGSize(width: 640, height: 420)
        return renderer(size).image { ctx in
            let c = ctx.cgContext
            var rng = SeededRandom(seed: 7)
            for _ in 0..<3200 {
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                let x = CGFloat.random(in: -200...size.width, using: &rng)
                let length = CGFloat.random(in: 60...520, using: &rng)
                let alpha = CGFloat.random(in: 0.02...0.085, using: &rng)
                let light = Bool.random(using: &rng)
                c.setStrokeColor(UIColor(white: light ? 1 : 0, alpha: alpha).cgColor)
                c.setLineWidth(CGFloat.random(in: 0.25...1.0, using: &rng))
                c.move(to: CGPoint(x: x, y: y))
                c.addLine(to: CGPoint(x: x + length, y: y))
                c.strokePath()
            }
        }
    }

    /// Noyer : fond chaud, veines ondulées, pores.
    private static func makeWood() -> UIImage {
        let size = CGSize(width: 420, height: 920)
        return renderer(size, opaque: true).image { ctx in
            let c = ctx.cgContext
            var rng = SeededRandom(seed: 42)
            UIColor(red: 0.20, green: 0.12, blue: 0.07, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            // larges bandes de teinte
            for _ in 0..<26 {
                let x = CGFloat.random(in: -40...size.width, using: &rng)
                let w = CGFloat.random(in: 18...90, using: &rng)
                let light = Bool.random(using: &rng)
                c.setFillColor(light ? UIColor(red: 0.42, green: 0.26, blue: 0.14, alpha: CGFloat.random(in: 0.08...0.22, using: &rng)).cgColor
                                     : UIColor(red: 0.07, green: 0.04, blue: 0.02, alpha: CGFloat.random(in: 0.08...0.25, using: &rng)).cgColor)
                c.fill(CGRect(x: x, y: 0, width: w, height: size.height))
            }
            // veines
            for _ in 0..<240 {
                let x0 = CGFloat.random(in: -20...(size.width + 20), using: &rng)
                let amp = CGFloat.random(in: 1.5...16, using: &rng)
                let freq = CGFloat.random(in: 0.003...0.018, using: &rng)
                let phase = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                let dark = Double.random(in: 0...1, using: &rng) < 0.72
                let alpha = CGFloat.random(in: 0.05...0.24, using: &rng)
                c.setStrokeColor(dark ? UIColor(red: 0.06, green: 0.03, blue: 0.015, alpha: alpha).cgColor
                                      : UIColor(red: 0.55, green: 0.36, blue: 0.2, alpha: alpha * 0.7).cgColor)
                c.setLineWidth(CGFloat.random(in: 0.4...3.2, using: &rng))
                var y: CGFloat = -10
                c.move(to: CGPoint(x: x0 + amp * sin(phase), y: y))
                while y < size.height + 10 {
                    y += 6
                    let x = x0 + amp * sin(y * freq + phase) + amp * 0.35 * sin(y * freq * 3.1 + phase * 2)
                    c.addLine(to: CGPoint(x: x, y: y))
                }
                c.strokePath()
            }
            // pores
            for _ in 0..<2200 {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                c.setFillColor(UIColor(white: 0, alpha: CGFloat.random(in: 0.08...0.22, using: &rng)).cgColor)
                c.fill(CGRect(x: x, y: y, width: 0.7, height: CGFloat.random(in: 2...9, using: &rng)))
            }
        }
    }

    /// Fibres et grains de papier, sur fond transparent.
    private static func makePaper() -> UIImage {
        let size = CGSize(width: 400, height: 400)
        return renderer(size).image { ctx in
            let c = ctx.cgContext
            var rng = SeededRandom(seed: 3)
            for _ in 0..<5200 {
                let r = CGFloat.random(in: 0.25...0.9, using: &rng)
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                c.setFillColor(UIColor(red: 0.35, green: 0.28, blue: 0.2, alpha: CGFloat.random(in: 0.025...0.07, using: &rng)).cgColor)
                c.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            for _ in 0..<160 {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                let a = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                let l = CGFloat.random(in: 4...16, using: &rng)
                c.setStrokeColor(UIColor(red: 0.5, green: 0.42, blue: 0.3, alpha: 0.07).cgColor)
                c.setLineWidth(0.4)
                c.move(to: CGPoint(x: x, y: y))
                c.addQuadCurve(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l),
                               control: CGPoint(x: x + cos(a + 0.6) * l * 0.5, y: y + sin(a + 0.6) * l * 0.5))
                c.strokePath()
            }
        }
    }

    /// Masque « encre inégale » pour les tampons.
    private static func makeGrain() -> UIImage {
        let size = CGSize(width: 260, height: 120)
        return renderer(size).image { ctx in
            let c = ctx.cgContext
            var rng = SeededRandom(seed: 11)
            UIColor.white.setFill()
            c.fill(CGRect(origin: .zero, size: size))
            c.setBlendMode(.clear)
            for _ in 0..<1300 {
                let r = CGFloat.random(in: 0.3...1.7, using: &rng)
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                c.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            c.setBlendMode(.normal)
            for _ in 0..<500 {
                let r = CGFloat.random(in: 0.5...2.5, using: &rng)
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                c.setFillColor(UIColor(white: 1, alpha: 0.45).cgColor)
                c.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
        }
    }
}

// MARK: - Fond : caisson en noyer

struct WoodBackground: View {
    var body: some View {
        Color.clear
            .overlay(
                Image(uiImage: Textures.wood)
                    .resizable()
                    .scaledToFill()
            )
            .overlay(
                LinearGradient(colors: [.white.opacity(0.07), .clear, .black.opacity(0.25)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
                RadialGradient(colors: [.clear, .black.opacity(0.6)],
                               center: .center, startRadius: 160, endRadius: 620)
            )
            .clipped()
            .ignoresSafeArea()
    }
}

// MARK: - Plaques

enum PlateStyle {
    case aluminum, anodized, brass
}

struct PlateBackground: View {
    var style: PlateStyle
    var radius: CGFloat = 14
    var shadow = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return shape
            .fill(base)
            .overlay(
                Image(uiImage: Textures.brushed)
                    .resizable()
                    .opacity(style == .anodized ? 0.55 : 1)
                    .clipShape(shape)
            )
            .overlay(shape.fill(sheen))
            .overlay(shape.strokeBorder(bevel, lineWidth: 1.2))
            .shadow(color: .black.opacity(shadow ? 0.55 : 0), radius: 12, x: 0, y: 9)
            .shadow(color: .black.opacity(shadow ? 0.4 : 0), radius: 1.5, x: 0, y: 1.5)
    }

    private var base: LinearGradient {
        let colors: [Color]
        switch style {
        case .aluminum: colors = [Color(hex: 0xEEF0F2), Color(hex: 0xD2D6DA), Color(hex: 0xB4B9BF)]
        case .anodized: colors = [Color(hex: 0x2E3035), Color(hex: 0x1D1F23), Color(hex: 0x131417)]
        case .brass: colors = [Color(hex: 0xF7E09A), Color(hex: 0xD8B25B), Color(hex: 0xA57E2C)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private var sheen: LinearGradient {
        let peak: Double = style == .anodized ? 0.07 : 0.24
        return LinearGradient(stops: [
            .init(color: .white.opacity(0), location: 0),
            .init(color: .white.opacity(peak), location: 0.42),
            .init(color: .white.opacity(0), location: 0.62),
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var bevel: LinearGradient {
        LinearGradient(colors: [.white.opacity(style == .anodized ? 0.22 : 0.9), .white.opacity(0.05), .black.opacity(0.45)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// Une plaque vissée, avec titre gravé facultatif.
struct Plate<Content: View>: View {
    var title: String? = nil
    var style: PlateStyle = .aluminum
    var spacing: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            if let title {
                PlateTitle(text: title, style: style)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, title == nil ? 18 : 15)
        .padding(.bottom, 18)
        .background(PlateBackground(style: style))
        .overlay(ScrewCorners(inset: 8.5))
    }
}

struct PlateTitle: View {
    var text: String
    var style: PlateStyle

    var body: some View {
        HStack(spacing: 8) {
            Engraved(text: text, size: 11, style: style)
            EngravedRule(style: style)
        }
        .padding(.horizontal, 2)
    }
}

/// Filet gravé (creux : ombre en haut, reflet en bas).
struct EngravedRule: View {
    var style: PlateStyle = .aluminum
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.black.opacity(style == .anodized ? 0.6 : 0.28)).frame(height: 1)
            Rectangle().fill(Color.white.opacity(style == .anodized ? 0.08 : 0.7)).frame(height: 1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Texte gravé dans le métal (ou sérigraphié sur l'anodisé).
struct Engraved: View {
    var text: String
    var size: CGFloat = 11
    var style: PlateStyle = .aluminum
    var weight: Font.Weight = .heavy

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: weight).width(.condensed))
            .tracking(size * 0.16)
            .foregroundStyle(ink)
            .shadow(color: highlight, radius: 0, x: 0, y: 1)
            .lineLimit(1)
    }

    private var ink: Color {
        switch style {
        case .aluminum: return Color(hex: 0x2C2F33, opacity: 0.86)
        case .anodized: return Palette.silkscreen
        case .brass: return Color(hex: 0x3A2808, opacity: 0.9)
        }
    }

    private var highlight: Color {
        switch style {
        case .aluminum: return .white.opacity(0.75)
        case .anodized: return .black.opacity(0.55)
        case .brass: return Color(hex: 0xFFF2C4, opacity: 0.65)
        }
    }
}

// MARK: - Vis

struct Screw: View {
    var size: CGFloat = 11
    var angle: Double = 30

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.4))
                .frame(width: size + 1.5, height: size + 1.5)
                .offset(y: 0.5)
                .blur(radius: 0.5)
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.98), Color(white: 0.74), Color(white: 0.42)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.75))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 0.6))
            Capsule()
                .fill(Color.black.opacity(0.6))
                .frame(width: size * 0.78, height: size * 0.15)
                .overlay(Capsule().stroke(Color.white.opacity(0.4), lineWidth: 0.4).offset(y: 0.5))
                .rotationEffect(.degrees(angle))
        }
        .frame(width: size + 2, height: size + 2)
        .allowsHitTesting(false)
    }
}

struct ScrewCorners: View {
    var inset: CGFloat = 9
    var size: CGFloat = 10

    var body: some View {
        VStack {
            HStack {
                Screw(size: size, angle: 28)
                Spacer()
                Screw(size: size, angle: -64)
            }
            Spacer()
            HStack {
                Screw(size: size, angle: 112)
                Spacer()
                Screw(size: size, angle: 7)
            }
        }
        .padding(inset - 1)
        .allowsHitTesting(false)
    }
}

// MARK: - Creux (afficheurs, fentes)

struct Recessed: ViewModifier {
    var radius: CGFloat = 6
    var depth: CGFloat = 1

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return content
            .clipShape(shape)
            .overlay(
                shape
                    .stroke(Color.black.opacity(0.55 * depth), lineWidth: 4)
                    .blur(radius: 2.5)
                    .offset(y: 1.5)
                    .mask(shape)
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.black.opacity(0.55), .white.opacity(0.45)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
    }
}

extension View {
    func recessed(radius: CGFloat = 6, depth: CGFloat = 1) -> some View {
        modifier(Recessed(radius: radius, depth: depth))
    }
}

// MARK: - Retour haptique

enum Haptics {
    static func click() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func thunk() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func detent() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}
