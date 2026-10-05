import SwiftUI

// MARK: - Voyant LED encastré

struct LED: View {
    var color: Color
    var on: Bool = true
    var size: CGFloat = 10
    var blinking: Bool = false
    @State private var dim = false

    private var glow: Double { on ? (blinking && dim ? 0.18 : 1) : 0 }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.7))
                .frame(width: size + 4, height: size + 4)
                .overlay(Circle().strokeBorder(
                    LinearGradient(colors: [.black.opacity(0.7), .white.opacity(0.5)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1))
            Circle()
                .fill(color.opacity(0.22 + 0.78 * glow))
                .frame(width: size, height: size)
                .overlay(
                    Circle().fill(RadialGradient(colors: [.white.opacity(0.85 * glow + 0.12), .clear],
                                                 center: UnitPoint(x: 0.38, y: 0.32), startRadius: 0, endRadius: size * 0.5))
                )
                .overlay(
                    Circle().fill(RadialGradient(colors: [.clear, .black.opacity(0.5)],
                                                 center: .center, startRadius: size * 0.2, endRadius: size * 0.6))
                )
                .shadow(color: color.opacity(0.95 * glow), radius: size * 0.5)
                .shadow(color: color.opacity(0.55 * glow), radius: size * 1.3)
        }
        .onAppear { updateBlink(blinking) }
        .onChange(of: blinking) { _, new in updateBlink(new) }
    }

    private func updateBlink(_ blink: Bool) {
        if blink {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { dim = true }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { dim = false }
        }
    }
}

// MARK: - Voyant « bijou » à facettes

struct JewelLamp: View {
    var color: Color
    var blinking = false
    var size: CGFloat = 32
    @State private var dim = false

    private var glow: Double { blinking && dim ? 0.3 : 1 }

    var body: some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: [Color(white: 0.97), Color(white: 0.45), Color(white: 0.9),
                                               Color(white: 0.35), Color(white: 0.95), Color(white: 0.5), Color(white: 0.97)],
                                      center: .center))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 2)
            Circle()
                .fill(Color.black)
                .frame(width: size * 0.76, height: size * 0.76)
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.9 * glow), color.opacity(0.35 + 0.65 * glow), Color.black.opacity(0.7)],
                                     center: UnitPoint(x: 0.42, y: 0.38), startRadius: 0, endRadius: size * 0.42))
                .frame(width: size * 0.7, height: size * 0.7)
            Circle()
                .fill(AngularGradient(colors: Array(repeating: [Color.white.opacity(0.22), Color.clear], count: 8).flatMap { $0 },
                                      center: .center))
                .frame(width: size * 0.7, height: size * 0.7)
                .blendMode(.overlay)
            Ellipse()
                .fill(Color.white.opacity(0.8))
                .frame(width: size * 0.2, height: size * 0.11)
                .offset(x: -size * 0.1, y: -size * 0.16)
                .blur(radius: 0.6)
        }
        .shadow(color: color.opacity(0.75 * glow), radius: size * 0.4)
        .onAppear { setBlink(blinking) }
        .onChange(of: blinking) { _, new in setBlink(new) }
    }

    private func setBlink(_ b: Bool) {
        if b {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { dim = true }
        } else {
            withAnimation(.easeOut(duration: 0.2)) { dim = false }
        }
    }
}

// MARK: - Étiquette Dymo en relief

struct DymoLabel: View {
    var text: String
    var color: Color = Color(hex: 0x111111)
    var size: CGFloat = 10.5

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .heavy, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(Color.white.opacity(0.9))
            .shadow(color: .black.opacity(0.55), radius: 0, x: 0.5, y: 0.8)
            .shadow(color: .white.opacity(0.25), radius: 0, x: -0.3, y: -0.4)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .overlay(
                        LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04), .black.opacity(0.2)],
                                       startPoint: .top, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    )
            )
            .rotationEffect(.degrees(tilt))
            .shadow(color: .black.opacity(0.45), radius: 1, x: 0, y: 1)
    }

    private var tilt: Double {
        let h = text.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 997 }
        return Double(h % 7 - 3) * 0.4
    }
}

// MARK: - Tampon encreur

struct RubberStamp: View {
    var text: String
    var color: Color
    var angle: Double = -8
    var size: CGFloat = 11

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .black).width(.condensed))
            .tracking(1.3)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color, lineWidth: 1.6))
            .padding(2)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(color, lineWidth: 0.7))
            .mask(Image(uiImage: Textures.grain).resizable(resizingMode: .tile))
            .opacity(0.8)
            .rotationEffect(.degrees(angle))
            .allowsHitTesting(false)
    }
}

// MARK: - Compteur à tambour (odomètre)

struct Odometer: View {
    var digits: String
    var size: CGFloat = 17

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(Array(digits.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(.system(size: size, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(white: 0.94))
                    .contentTransition(.numericText())
                    .frame(width: size * 0.86, height: size * 1.42)
                    .background(LinearGradient(colors: [Color(white: 0.02), Color(white: 0.2), Color(white: 0.02)],
                                               startPoint: .top, endPoint: .bottom))
                    .overlay(LinearGradient(stops: [
                        .init(color: .black.opacity(0.75), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .clear, location: 0.7),
                        .init(color: .black.opacity(0.75), location: 1),
                    ], startPoint: .top, endPoint: .bottom))
                    .overlay(Rectangle().fill(Color.black.opacity(0.6)).frame(height: 0.6))
            }
        }
        .padding(2.5)
        .background(Color.black)
        .recessed(radius: 3)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: digits)
    }
}

// MARK: - Afficheur 7 segments

struct SevenSegmentText: View {
    var text: String
    var color: Color = Palette.segRed
    var height: CGFloat = 22
    var ghost: Double = 0.09
    var glow: Bool = true

    var body: some View {
        HStack(spacing: height * 0.1) {
            ForEach(Array(SevenSegmentText.cells(text).enumerated()), id: \.offset) { _, cell in
                SevenSegmentDigit(mask: cell.mask, dot: cell.dot, colon: cell.colon,
                                  color: color, ghost: ghost, glow: glow)
                    .frame(width: cell.colon ? height * 0.22 : height * 0.58, height: height)
            }
        }
    }

    struct Cell { var mask: Int; var dot: Bool; var colon: Bool }

    static func cells(_ s: String) -> [Cell] {
        var out: [Cell] = []
        for ch in s {
            if ch == "." || ch == "," {
                if let last = out.last, !last.dot, !last.colon {
                    out[out.count - 1].dot = true
                } else {
                    out.append(Cell(mask: 0, dot: true, colon: false))
                }
            } else if ch == ":" {
                out.append(Cell(mask: 0, dot: false, colon: true))
            } else {
                out.append(Cell(mask: segments[ch] ?? 0, dot: false, colon: false))
            }
        }
        return out
    }

    // bits : a=1 (haut) b=2 c=4 d=8 (bas) e=16 f=32 g=64 (milieu)
    static let segments: [Character: Int] = [
        "0": 63, "1": 6, "2": 91, "3": 79, "4": 102, "5": 109, "6": 125, "7": 7, "8": 127, "9": 111,
        "-": 64, "_": 8, " ": 0,
        "A": 119, "a": 119, "b": 124, "B": 124, "C": 57, "c": 88, "d": 94, "D": 94, "E": 121, "e": 121,
        "F": 113, "f": 113, "H": 118, "h": 116, "I": 6, "i": 4, "J": 30, "j": 30, "L": 56, "l": 56,
        "n": 84, "N": 84, "O": 63, "o": 92, "P": 115, "p": 115, "r": 80, "R": 80, "S": 109, "s": 109,
        "t": 120, "T": 120, "U": 62, "u": 28, "Y": 110, "y": 110,
    ]
}

struct SevenSegmentDigit: View {
    var mask: Int
    var dot: Bool
    var colon: Bool
    var color: Color
    var ghost: Double
    var glow: Bool

    var body: some View {
        Canvas { ctx, size in
            if colon {
                let r = size.width * 0.36
                for y in [size.height * 0.32, size.height * 0.7] {
                    let rect = CGRect(x: size.width / 2 - r, y: y - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(color))
                }
                return
            }
            let segs = SevenSegmentDigit.segmentPaths(in: size)
            for (i, p) in segs.enumerated() where mask & (1 << i) == 0 {
                ctx.fill(p, with: .color(color.opacity(ghost)))
            }
            if glow && mask != 0 {
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: size.height * 0.07))
                    for (i, p) in segs.enumerated() where mask & (1 << i) != 0 {
                        layer.fill(p, with: .color(color.opacity(0.85)))
                    }
                }
            }
            for (i, p) in segs.enumerated() where mask & (1 << i) != 0 {
                ctx.fill(p, with: .color(color))
            }
            let t = size.width * 0.16
            let dotRect = CGRect(x: size.width - t * 1.05, y: size.height - t * 1.05, width: t, height: t)
            ctx.fill(Path(ellipseIn: dotRect), with: .color(dot ? color : color.opacity(ghost)))
        }
    }

    static func segmentPaths(in size: CGSize) -> [Path] {
        let h = size.height
        let w = size.width * 0.74
        let t = w * 0.21
        let g = t * 0.12
        let left = t / 2, right = w - t / 2
        let top = t / 2, mid = h / 2, bottom = h - t / 2

        func hs(_ y: CGFloat) -> Path {
            let x0 = left + g, x1 = right - g
            var p = Path()
            p.move(to: CGPoint(x: x0, y: y))
            p.addLine(to: CGPoint(x: x0 + t / 2, y: y - t / 2))
            p.addLine(to: CGPoint(x: x1 - t / 2, y: y - t / 2))
            p.addLine(to: CGPoint(x: x1, y: y))
            p.addLine(to: CGPoint(x: x1 - t / 2, y: y + t / 2))
            p.addLine(to: CGPoint(x: x0 + t / 2, y: y + t / 2))
            p.closeSubpath()
            return p
        }

        func vs(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: x, y: y0))
            p.addLine(to: CGPoint(x: x + t / 2, y: y0 + t / 2))
            p.addLine(to: CGPoint(x: x + t / 2, y: y1 - t / 2))
            p.addLine(to: CGPoint(x: x, y: y1))
            p.addLine(to: CGPoint(x: x - t / 2, y: y1 - t / 2))
            p.addLine(to: CGPoint(x: x - t / 2, y: y0 + t / 2))
            p.closeSubpath()
            return p
        }

        let raw = [
            hs(top),                            // a
            vs(right, top + g, mid - g),        // b
            vs(right, mid + g, bottom - g),     // c
            hs(bottom),                         // d
            vs(left, mid + g, bottom - g),      // e
            vs(left, top + g, mid - g),         // f
            hs(mid),                            // g
        ]
        let slant: CGFloat = 0.09
        let skew = CGAffineTransform(a: 1, b: 0, c: -slant, d: 1, tx: slant * h, ty: 0)
        return raw.map { $0.applying(skew) }
    }
}

/// Afficheur 7 segments dans sa fenêtre noire.
struct SegmentWindow: View {
    var text: String
    var color: Color = Palette.segRed
    var height: CGFloat = 18

    var body: some View {
        SevenSegmentText(text: text, color: color, height: height)
            .padding(.horizontal, height * 0.35)
            .padding(.vertical, height * 0.28)
            .background(
                LinearGradient(colors: [Color(hex: 0x120606), Color(hex: 0x050202)], startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .center)
            )
            .recessed(radius: 4)
    }
}

/// Écran LCD réfléchissant (vert-de-gris, segments sombres).
struct LCDWindow<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                LinearGradient(colors: [Color(hex: 0xB4C695), Palette.lcd, Color(hex: 0x8DA06E)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .overlay(
                LinearGradient(colors: [.white.opacity(0.18), .clear], startPoint: .top, endPoint: .center)
            )
            .recessed(radius: 5)
    }
}

// MARK: - Tubes Nixie

struct NixieTube: View {
    var digit: Character
    var width: CGFloat = 24

    var body: some View {
        let h = width * 1.8
        let shape = RoundedRectangle(cornerRadius: width * 0.46, style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(colors: [Color(hex: 0x2A190F), Color(hex: 0x0C0604)], startPoint: .top, endPoint: .bottom))
            NixieMesh(spacing: width * 0.16)
                .stroke(Palette.nixie.opacity(0.11), lineWidth: 0.5)
                .padding(width * 0.14)
                .clipShape(shape)
            ZStack {
                Text("8")
                Text("0").offset(x: width * 0.05)
                Text("3").offset(x: -width * 0.04)
            }
            .font(.system(size: h * 0.6, weight: .light))
            .foregroundStyle(Color(hex: 0x8A5A38, opacity: 0.22))
            Text(String(digit))
                .font(.system(size: h * 0.6, weight: .light))
                .foregroundStyle(Color(hex: 0xFFD3A0))
                .shadow(color: Palette.nixie, radius: 1.2)
                .shadow(color: Palette.nixie.opacity(0.95), radius: 4.5)
                .shadow(color: Palette.nixie.opacity(0.6), radius: 11)
                .contentTransition(.opacity)
            shape.fill(LinearGradient(stops: [
                .init(color: .white.opacity(0.3), location: 0),
                .init(color: .white.opacity(0.06), location: 0.16),
                .init(color: .clear, location: 0.5),
                .init(color: .white.opacity(0.1), location: 0.9),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing))
            shape.strokeBorder(Color.white.opacity(0.2), lineWidth: 0.8)
        }
        .frame(width: width, height: h)
        .animation(.easeInOut(duration: 0.25), value: digit)
    }
}

struct NixieMesh: Shape {
    var spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX + rect.height {
            p.move(to: CGPoint(x: x, y: rect.minY))
            p.addLine(to: CGPoint(x: x + rect.height * 0.6, y: rect.maxY))
            p.move(to: CGPoint(x: x + rect.height * 0.6, y: rect.minY))
            p.addLine(to: CGPoint(x: x, y: rect.maxY))
            x += spacing
        }
        return p
    }
}

/// Plusieurs tubes côte à côte, sur leur socle.
struct NixieCounter: View {
    var value: Int
    var digits: Int
    var tubeWidth: CGFloat = 24

    var body: some View {
        let capped = min(max(value, 0), Int(pow(10, Double(digits))) - 1)
        let text = String(format: "%0\(digits)d", capped)
        return HStack(spacing: 3) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                NixieTube(digit: ch, width: tubeWidth)
            }
        }
        .padding(5)
        .background(Color.black.opacity(0.85))
        .recessed(radius: 7)
    }
}

// MARK: - Barres de LED

/// Bargraphe vertical (vert → ambre → rouge).
struct LEDBarMeter: View {
    var value: Double
    var segments: Int = 12

    var body: some View {
        let lit = Int((min(max(value, 0), 1) * Double(segments)).rounded())
        return VStack(spacing: 2.5) {
            ForEach((0..<segments).reversed(), id: \.self) { i in
                let c = LEDBarMeter.color(i, of: segments)
                let on = i < lit
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(on ? c : c.opacity(0.13))
                    .shadow(color: on ? c.opacity(0.85) : .clear, radius: 3)
            }
        }
        .padding(4)
        .background(Color.black)
        .recessed(radius: 4)
        .animation(.easeOut(duration: 0.25), value: lit)
    }

    static func color(_ i: Int, of n: Int) -> Color {
        let f = Double(i) / Double(max(n - 1, 1))
        if f >= 0.82 { return Palette.ledRed }
        if f >= 0.64 { return Palette.ledAmber }
        return Palette.ledGreen
    }
}

/// Bargraphe horizontal compact.
struct HLEDMeter: View {
    var value: Double
    var segments: Int = 10

    var body: some View {
        let lit = Int((min(max(value, 0), 1) * Double(segments)).rounded(.up))
        return HStack(spacing: 1.5) {
            ForEach(0..<segments, id: \.self) { i in
                let c = LEDBarMeter.color(i, of: segments)
                let on = i < lit
                RoundedRectangle(cornerRadius: 1)
                    .fill(on ? c : c.opacity(0.14))
                    .shadow(color: on ? c.opacity(0.8) : .clear, radius: 2)
            }
        }
        .padding(2)
        .background(Color.black)
        .recessed(radius: 2)
    }
}
