import SwiftUI

/// Écran cathodique à phosphore vert : trace, grille, lignes de balayage, verre bombé.
struct Oscilloscope: View {
    var points: [Double]          // valeurs 0…1, de la plus ancienne à la plus récente
    var capacity: Int = 240       // nombre de points sur toute la largeur
    var channel: String
    var valueText: String
    var span: String

    var body: some View {
        let screen = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return ZStack {
            screen.fill(RadialGradient(colors: [Color(hex: 0x10301C), Color(hex: 0x071A0E), Color(hex: 0x020604)],
                                       center: .center, startRadius: 8, endRadius: 230))
            ScopeGrid()
            ScopeTrace(points: points, capacity: capacity)
            VStack {
                HStack {
                    Text(channel)
                    Spacer()
                    Text(valueText)
                }
                Spacer()
                HStack {
                    Text(span)
                    Spacer()
                    Text("MAINTENANT")
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Palette.phosphor.opacity(0.9))
            .shadow(color: Palette.phosphor.opacity(0.8), radius: 3)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            ScanLines()
                .fill(Color.black.opacity(0.22))
            screen.fill(RadialGradient(colors: [.clear, .black.opacity(0.7)], center: .center,
                                       startRadius: 70, endRadius: 240))
            screen.fill(LinearGradient(colors: [.white.opacity(0.11), .clear], startPoint: .topLeading, endPoint: .center))
        }
        .clipShape(screen)
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.07)], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 27, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.6)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                )
                .overlay(
                    screen.stroke(Color.black, lineWidth: 3)
                        .padding(8)
                        .blur(radius: 1.5)
                )
        )
        .aspectRatio(1.45, contentMode: .fit)
    }
}

struct ScopeGrid: View, Equatable {
    var body: some View {
        Canvas { ctx, size in
            let cols = 10, rows = 8
            let color = Palette.phosphor
            for i in 1..<cols {
                let x = size.width * CGFloat(i) / CGFloat(cols)
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(color.opacity(i == cols / 2 ? 0.22 : 0.1)), lineWidth: 0.6)
            }
            for j in 1..<rows {
                let y = size.height * CGFloat(j) / CGFloat(rows)
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(p, with: .color(color.opacity(j == rows / 2 ? 0.22 : 0.1)), lineWidth: 0.6)
            }
            // petites graduations sur les axes centraux
            let cx = size.width / 2, cy = size.height / 2
            for k in 0...(cols * 5) {
                let x = size.width * CGFloat(k) / CGFloat(cols * 5)
                var p = Path()
                p.move(to: CGPoint(x: x, y: cy - 2.5))
                p.addLine(to: CGPoint(x: x, y: cy + 2.5))
                ctx.stroke(p, with: .color(color.opacity(0.22)), lineWidth: 0.6)
            }
            for k in 0...(rows * 5) {
                let y = size.height * CGFloat(k) / CGFloat(rows * 5)
                var p = Path()
                p.move(to: CGPoint(x: cx - 2.5, y: y))
                p.addLine(to: CGPoint(x: cx + 2.5, y: y))
                ctx.stroke(p, with: .color(color.opacity(0.22)), lineWidth: 0.6)
            }
        }
    }
}

struct ScopeTrace: View {
    var points: [Double]
    var capacity: Int

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 26)
            let n = points.count
            guard n > 1 else {
                var flat = Path()
                flat.move(to: CGPoint(x: rect.minX, y: rect.midY))
                flat.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 3))
                    l.stroke(flat, with: .color(Palette.phosphor.opacity(0.6)), lineWidth: 2.5)
                }
                ctx.stroke(flat, with: .color(Color(hex: 0xC8FFD6)), lineWidth: 1)
                return
            }
            let step = rect.width / CGFloat(max(capacity - 1, 1))
            let count = min(n, capacity)
            let firstX = rect.maxX - CGFloat(count - 1) * step
            var line = Path()
            var last = CGPoint.zero
            for (i, v) in points.suffix(capacity).enumerated() {
                let x = rect.maxX - CGFloat(count - 1 - i) * step
                let y = rect.maxY - rect.height * CGFloat(min(max(v, 0), 1))
                let p = CGPoint(x: x, y: y)
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
                last = p
            }
            var area = line
            area.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            area.addLine(to: CGPoint(x: firstX, y: rect.maxY))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [Palette.phosphor.opacity(0.2), Palette.phosphor.opacity(0.0)]),
                                                 startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 4))
                l.stroke(line, with: .color(Palette.phosphor.opacity(0.85)), lineWidth: 3.2)
            }
            ctx.stroke(line, with: .color(Color(hex: 0xC8FFD6)), style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))

            // spot du faisceau
            let glowR: CGFloat = 7
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 5))
                l.fill(Path(ellipseIn: CGRect(x: last.x - glowR, y: last.y - glowR, width: glowR * 2, height: glowR * 2)),
                       with: .color(Palette.phosphor))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: last.x - 2.6, y: last.y - 2.6, width: 5.2, height: 5.2)), with: .color(.white))
        }
    }
}

struct ScanLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var y = rect.minY
        while y < rect.maxY {
            p.addRect(CGRect(x: rect.minX, y: y, width: rect.width, height: 1))
            y += 3
        }
        return p
    }
}
