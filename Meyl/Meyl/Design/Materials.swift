import SwiftUI

// MARK: - Palette « écritoire »

enum Ink {
    static let walnutDark = Color(red: 0.16, green: 0.09, blue: 0.05)
    static let walnut = Color(red: 0.30, green: 0.18, blue: 0.10)
    static let walnutLight = Color(red: 0.42, green: 0.27, blue: 0.15)

    static let leatherDark = Color(red: 0.17, green: 0.08, blue: 0.05)
    static let leather = Color(red: 0.36, green: 0.16, blue: 0.09)
    static let leatherLight = Color(red: 0.47, green: 0.23, blue: 0.13)
    static let stitch = Color(red: 0.93, green: 0.84, blue: 0.63)

    static let paper = Color(red: 0.97, green: 0.94, blue: 0.86)
    static let paperShade = Color(red: 0.90, green: 0.85, blue: 0.74)
    static let envelope = Color(red: 0.95, green: 0.91, blue: 0.80)

    static let ink = Color(red: 0.16, green: 0.12, blue: 0.09)
    static let inkSoft = Color(red: 0.38, green: 0.32, blue: 0.26)
    static let redInk = Color(red: 0.62, green: 0.13, blue: 0.10)
    static let blueInk = Color(red: 0.12, green: 0.22, blue: 0.45)

    static let brassHi = Color(red: 1.00, green: 0.91, blue: 0.62)
    static let brass = Color(red: 0.82, green: 0.65, blue: 0.30)
    static let brassDeep = Color(red: 0.52, green: 0.38, blue: 0.14)

    static let waxHi = Color(red: 0.86, green: 0.22, blue: 0.18)
    static let wax = Color(red: 0.62, green: 0.08, blue: 0.07)
    static let waxDeep = Color(red: 0.35, green: 0.03, blue: 0.03)

    static let brassGradient = LinearGradient(
        stops: [
            .init(color: brassHi, location: 0.0),
            .init(color: brass, location: 0.28),
            .init(color: brassDeep, location: 0.55),
            .init(color: brass, location: 0.78),
            .init(color: brassHi.opacity(0.9), location: 1.0),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Polices

enum Typo {
    static func serif(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "Baskerville-SemiBold" : "Baskerville", size: size)
    }
    static func display(_ size: CGFloat) -> Font { .custom("Didot-Bold", size: size) }
    static func typewriter(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "AmericanTypewriter-Semibold" : "AmericanTypewriter", size: size)
    }
    static func engraved(_ size: CGFloat) -> Font { .custom("Copperplate-Bold", size: size) }
}

// MARK: - Hasard reproductible (textures stables d'une image à l'autre)

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Bois de noyer

struct WalnutBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Ink.walnutLight, Ink.walnut, Ink.walnutDark],
                           startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in
                var rng = SeededRNG(42)
                // Veines : longues ondulations horizontales
                for i in 0..<70 {
                    let y0 = CGFloat(i) / 70 * size.height + CGFloat.random(in: -6...6, using: &rng)
                    let amp = CGFloat.random(in: 2...9, using: &rng)
                    let freq = CGFloat.random(in: 0.004...0.012, using: &rng)
                    let phase = CGFloat.random(in: 0...6.28, using: &rng)
                    var p = Path()
                    p.move(to: CGPoint(x: -10, y: y0))
                    var x: CGFloat = -10
                    while x <= size.width + 10 {
                        let y = y0 + sin(x * freq + phase) * amp + sin(x * freq * 3.1 + phase) * amp * 0.25
                        p.addLine(to: CGPoint(x: x, y: y))
                        x += 6
                    }
                    let dark = Bool.random(using: &rng)
                    ctx.stroke(p, with: .color(dark ? Color.black.opacity(Double.random(in: 0.06...0.18, using: &rng))
                                                    : Color(red: 0.75, green: 0.5, blue: 0.3).opacity(Double.random(in: 0.04...0.10, using: &rng))),
                               lineWidth: CGFloat.random(in: 0.6...2.4, using: &rng))
                }
                // Nœuds
                for _ in 0..<3 {
                    let c = CGPoint(x: CGFloat.random(in: 0...size.width, using: &rng),
                                    y: CGFloat.random(in: 0...size.height, using: &rng))
                    for r in stride(from: 4.0, through: 26.0, by: 4.0) {
                        let rect = CGRect(x: c.x - r * 1.8, y: c.y - r * 0.6, width: r * 3.6, height: r * 1.2)
                        ctx.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.10)), lineWidth: 1.2)
                    }
                }
            }
            // Vernis : reflet doux
            LinearGradient(colors: [.white.opacity(0.07), .clear, .black.opacity(0.25)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Grain (papier, cuir)

struct Grain: View {
    var seed: UInt64 = 7
    var density: Double = 0.0009
    var dark: Double = 0.06
    var light: Double = 0.05

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRNG(seed)
            let n = Int(Double(size.width * size.height) * density)
            for _ in 0..<min(n, 6000) {
                let x = CGFloat.random(in: 0...size.width, using: &rng)
                let y = CGFloat.random(in: 0...size.height, using: &rng)
                let s = CGFloat.random(in: 0.6...1.8, using: &rng)
                let isDark = Bool.random(using: &rng)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                         with: .color(isDark ? .black.opacity(dark) : .white.opacity(light)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Papier

struct PaperSheet: View {
    var corner: CGFloat = 6
    var tint: Color = Ink.paper

    var body: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(LinearGradient(colors: [tint, tint.opacity(0.96), Ink.paperShade.opacity(0.9)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Grain(seed: 11, density: 0.0012, dark: 0.05, light: 0.25)
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous)))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 4)
    }
}

// MARK: - Cuir surpiqué

struct Leather<S: InsettableShape>: View {
    var shape: S
    var stitchInset: CGFloat = 5

    var body: some View {
        shape
            .fill(LinearGradient(colors: [Ink.leatherLight, Ink.leather, Ink.leatherDark],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Grain(seed: 3, density: 0.004, dark: 0.22, light: 0.06).clipShape(shape))
            .overlay(shape.inset(by: stitchInset)
                .stroke(Ink.stitch.opacity(0.75), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [5, 3.5])))
            .overlay(shape.inset(by: stitchInset)
                .offset(y: 1)
                .stroke(Color.black.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [5, 3.5])))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.18), .black.opacity(0.5)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

// MARK: - Texte gravé / embossé

struct Embossed: ViewModifier {
    var light: Color = .white.opacity(0.35)
    var dark: Color = .black.opacity(0.7)
    func body(content: Content) -> some View {
        content
            .shadow(color: dark, radius: 0, x: 0, y: -1)
            .shadow(color: light, radius: 0, x: 0, y: 1)
    }
}

extension View {
    func embossed(light: Color = .white.opacity(0.35), dark: Color = .black.opacity(0.7)) -> some View {
        modifier(Embossed(light: light, dark: dark))
    }

    /// Texte creusé dans le laiton : sombre avec un liseré clair dessous.
    func engraved() -> some View {
        self.foregroundStyle(Color(red: 0.24, green: 0.15, blue: 0.04))
            .shadow(color: Ink.brassHi.opacity(0.9), radius: 0, x: 0, y: 1)
            .shadow(color: .black.opacity(0.35), radius: 0, x: 0, y: -0.5)
    }
}
