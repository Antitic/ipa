import SwiftUI

// MARK: - Manomètre à aiguille (cadran crème, lunette chromée, verre bombé)

struct AnalogGauge: View {
    var value: Double              // 0…1
    var title: String
    var unit: String
    var labels: [String]           // graduations principales, réparties de 0 à 1
    var redFrom: Double = 0.8
    var readout: String

    static let start = -135.0
    static let sweep = 270.0

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let rf = s * 0.44
            ZStack {
                GaugeBezel(size: s)
                GaugeFace(radius: rf, title: title, unit: unit, labels: labels, redFrom: redFrom)
                SegmentWindow(text: readout, color: Palette.segRed, height: s * 0.075)
                    .offset(y: rf * 0.5)
                GaugeNeedle(value: value, radius: rf, size: s)
                GaugeGlass(radius: rf)
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("\(title) : \(readout) \(unit)")
    }

    static func point(center c: CGPoint, radius r: CGFloat, fraction f: Double) -> CGPoint {
        let deg = start + f * sweep - 90
        let rad = deg * .pi / 180
        return CGPoint(x: c.x + r * CGFloat(cos(rad)), y: c.y + r * CGFloat(sin(rad)))
    }
}

struct GaugeBezel: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.55))
                .blur(radius: size * 0.025)
                .offset(y: size * 0.025)
            Circle()
                .fill(AngularGradient(colors: [Color(white: 0.98), Color(white: 0.52), Color(white: 0.93), Color(white: 0.38),
                                               Color(white: 0.88), Color(white: 0.48), Color(white: 0.98)],
                                      center: .center))
            Circle()
                .strokeBorder(Color.black.opacity(0.35), lineWidth: 0.8)
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.3), Color(white: 0.9)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.915, height: size * 0.915)
        }
        .frame(width: size, height: size)
    }
}

struct GaugeFace: View, Equatable {
    var radius: CGFloat
    var title: String
    var unit: String
    var labels: [String]
    var redFrom: Double

    var body: some View {
        let d = radius * 2
        let sweepFraction = AnalogGauge.sweep / 360
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(hex: 0xFCF6E6), Color(hex: 0xF0E3C3), Color(hex: 0xD6C396)],
                                     center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: radius))
            Image(uiImage: Textures.paper)
                .resizable()
                .opacity(0.8)
                .clipShape(Circle())
            // zone rouge
            Circle()
                .trim(from: 0, to: (1 - redFrom) * sweepFraction)
                .stroke(Palette.needleRed.opacity(0.78), style: StrokeStyle(lineWidth: radius * 0.075, lineCap: .butt))
                .frame(width: radius * 1.68, height: radius * 1.68)
                .rotationEffect(.degrees(-90 + AnalogGauge.start + redFrom * AnalogGauge.sweep))
            // graduations
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let ink = Palette.ink
                var arc = Path()
                arc.addArc(center: c, radius: radius * 0.88,
                           startAngle: .degrees(AnalogGauge.start - 90),
                           endAngle: .degrees(AnalogGauge.start + AnalogGauge.sweep - 90), clockwise: false)
                ctx.stroke(arc, with: .color(ink.opacity(0.85)), lineWidth: 1)

                let majors = max(labels.count - 1, 1)
                let minorsPer = 5
                for i in 0...(majors * minorsPer) {
                    let f = Double(i) / Double(majors * minorsPer)
                    let major = i % minorsPer == 0
                    let inner = radius * (major ? 0.73 : 0.81)
                    var tick = Path()
                    tick.move(to: AnalogGauge.point(center: c, radius: radius * 0.88, fraction: f))
                    tick.addLine(to: AnalogGauge.point(center: c, radius: inner, fraction: f))
                    ctx.stroke(tick, with: .color(ink), lineWidth: major ? 2 : 0.9)
                }
                for (i, label) in labels.enumerated() {
                    let f = Double(i) / Double(majors)
                    let p = AnalogGauge.point(center: c, radius: radius * 0.6, fraction: f)
                    ctx.draw(Text(label)
                                .font(.system(size: radius * 0.15, weight: .bold).width(.condensed))
                                .foregroundStyle(ink),
                             at: p, anchor: .center)
                }
                ctx.draw(Text(title.uppercased())
                            .font(.system(size: radius * 0.15, weight: .heavy).width(.condensed))
                            .tracking(radius * 0.02)
                            .foregroundStyle(ink),
                         at: CGPoint(x: c.x, y: c.y - radius * 0.3), anchor: .center)
                ctx.draw(Text(unit.uppercased())
                            .font(.system(size: radius * 0.095, weight: .semibold))
                            .foregroundStyle(ink.opacity(0.7)),
                         at: CGPoint(x: c.x, y: c.y - radius * 0.14), anchor: .center)
                ctx.draw(Text("DIPHERANT")
                            .font(.system(size: radius * 0.065, weight: .bold, design: .serif))
                            .tracking(radius * 0.02)
                            .foregroundStyle(ink.opacity(0.45)),
                         at: CGPoint(x: c.x, y: c.y + radius * 0.25), anchor: .center)
            }
        }
        .frame(width: d, height: d)
        .overlay(
            Circle()
                .stroke(Color.black.opacity(0.45), lineWidth: radius * 0.07)
                .blur(radius: radius * 0.035)
                .offset(y: radius * 0.02)
                .clipShape(Circle())
        )
    }
}

struct GaugeNeedle: View {
    var value: Double
    var radius: CGFloat
    var size: CGFloat

    private var angle: Double {
        AnalogGauge.start + min(max(value, -0.02), 1.03) * AnalogGauge.sweep
    }

    var body: some View {
        let d = radius * 2
        ZStack {
            NeedleShape()
                .fill(Color.black.opacity(0.32))
                .frame(width: d, height: d)
                .rotationEffect(.degrees(angle))
                .offset(x: size * 0.012, y: size * 0.02)
                .blur(radius: size * 0.008)
            NeedleShape()
                .fill(LinearGradient(colors: [Color(hex: 0xE2392E), Palette.needleRed, Color(hex: 0x7E120C)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: d, height: d)
                .rotationEffect(.degrees(angle))
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.98), Color(white: 0.55), Color(white: 0.2)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: radius * 0.1))
                .frame(width: radius * 0.17, height: radius * 0.17)
                .shadow(color: .black.opacity(0.5), radius: 1.5, x: 0.5, y: 1.5)
            Circle()
                .fill(Color.black.opacity(0.7))
                .frame(width: radius * 0.04, height: radius * 0.04)
        }
        .animation(.interpolatingSpring(stiffness: 55, damping: 7), value: angle)
    }
}

struct NeedleShape: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY)
        let len = r.width / 2
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - len * 0.9))
        p.addLine(to: CGPoint(x: c.x + len * 0.024, y: c.y))
        p.addLine(to: CGPoint(x: c.x + len * 0.04, y: c.y + len * 0.22))
        p.addLine(to: CGPoint(x: c.x - len * 0.04, y: c.y + len * 0.22))
        p.addLine(to: CGPoint(x: c.x - len * 0.024, y: c.y))
        p.closeSubpath()
        return p
    }
}

struct GaugeGlass: View {
    var radius: CGFloat

    var body: some View {
        let d = radius * 2
        ZStack {
            Ellipse()
                .fill(LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                .frame(width: radius * 1.55, height: radius * 0.95)
                .offset(x: -radius * 0.08, y: -radius * 0.48)
            Circle()
                .fill(RadialGradient(colors: [.clear, .black.opacity(0.14)], center: .center,
                                     startRadius: radius * 0.6, endRadius: radius))
            Circle()
                .trim(from: 0.56, to: 0.72)
                .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: radius * 0.025, lineCap: .round))
                .frame(width: d * 0.93, height: d * 0.93)
                .blur(radius: 0.6)
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
        .allowsHitTesting(false)
    }
}

// MARK: - Vu-mètre rétroéclairé

struct VUMeter: View {
    var value: Double       // 0…1
    var title: String

    static let halfArc = 38.0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let faceW = w - 14, faceH = h - 14
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.04)], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.4), Color(white: 0.75)],
                                                         startPoint: .top, endPoint: .bottom),
                                          lineWidth: 1.6)
                    )
                    .shadow(color: .black.opacity(0.55), radius: 5, x: 0, y: 4)
                ZStack {
                    VUFace(title: title)
                    VUNeedle(angle: -VUMeter.halfArc + min(max(value, 0), 1.04) * VUMeter.halfArc * 2)
                        .stroke(Color.black.opacity(0.3), lineWidth: 1.6)
                        .offset(x: 2, y: 2.5)
                        .blur(radius: 1)
                    VUNeedle(angle: -VUMeter.halfArc + min(max(value, 0), 1.04) * VUMeter.halfArc * 2)
                        .stroke(Color(hex: 0x141414), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    // capot du pivot
                    Ellipse()
                        .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.02)], startPoint: .top, endPoint: .bottom))
                        .frame(width: faceW * 0.34, height: faceH * 0.34)
                        .offset(y: faceH * 0.53)
                    // verre
                    LinearGradient(stops: [
                        .init(color: .white.opacity(0.32), location: 0),
                        .init(color: .white.opacity(0.06), location: 0.4),
                        .init(color: .clear, location: 0.41),
                    ], startPoint: .top, endPoint: .bottom)
                }
                .frame(width: faceW, height: faceH)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.black.opacity(0.6), lineWidth: 3)
                        .blur(radius: 2)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                )
                .animation(.interpolatingSpring(stiffness: 70, damping: 9), value: value)
            }
        }
        .aspectRatio(1.32, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(title)
    }
}

struct VUNeedle: Shape {
    var angle: Double
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func path(in r: CGRect) -> Path {
        let pivot = CGPoint(x: r.midX, y: r.minY + r.height)
        let len = r.height * 0.86
        let th = (angle - 90) * .pi / 180
        var p = Path()
        p.move(to: CGPoint(x: pivot.x + len * 0.05 * CGFloat(cos(th)), y: pivot.y + len * 0.05 * CGFloat(sin(th))))
        p.addLine(to: CGPoint(x: pivot.x + len * CGFloat(cos(th)), y: pivot.y + len * CGFloat(sin(th))))
        return p
    }
}

struct VUFace: View, Equatable {
    var title: String

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(Gradient(colors: [Color(hex: 0xFFEDB8), Color(hex: 0xF5C96E), Color(hex: 0xC48A33)]),
                                           center: CGPoint(x: w / 2, y: h * 0.7), startRadius: 0, endRadius: w * 0.78))
            let pivot = CGPoint(x: w / 2, y: h)
            let R = h * 0.74
            let ink = Color(hex: 0x24180C)
            func pt(_ f: Double, _ r: CGFloat) -> CGPoint {
                let a = (-VUMeter.halfArc + f * VUMeter.halfArc * 2 - 90) * .pi / 180
                return CGPoint(x: pivot.x + r * CGFloat(cos(a)), y: pivot.y + r * CGFloat(sin(a)))
            }
            var arc = Path()
            arc.addArc(center: pivot, radius: R, startAngle: .degrees(-VUMeter.halfArc - 90),
                       endAngle: .degrees(VUMeter.halfArc - 90), clockwise: false)
            ctx.stroke(arc, with: .color(ink), lineWidth: 1.2)
            var red = Path()
            red.addArc(center: pivot, radius: R + h * 0.03, startAngle: .degrees(-VUMeter.halfArc + 0.78 * VUMeter.halfArc * 2 - 90),
                       endAngle: .degrees(VUMeter.halfArc - 90), clockwise: false)
            ctx.stroke(red, with: .color(Palette.needleRed), lineWidth: h * 0.05)

            let labels = ["100", "1K", "10K", "100K", "1M", "10M", "100M"]
            let steps = 24
            for i in 0...steps {
                let f = Double(i) / Double(steps)
                let major = i % 4 == 0
                var t = Path()
                t.move(to: pt(f, R))
                t.addLine(to: pt(f, R + h * (major ? 0.08 : 0.04)))
                ctx.stroke(t, with: .color(f >= 0.78 ? Palette.needleRed : ink), lineWidth: major ? 1.6 : 0.8)
            }
            for (i, l) in labels.enumerated() {
                let f = Double(i) / Double(labels.count - 1)
                ctx.draw(Text(l).font(.system(size: h * 0.085, weight: .bold).width(.condensed))
                            .foregroundStyle(f >= 0.78 ? Palette.needleRed : ink),
                         at: pt(f, h * 0.89), anchor: .center)
            }
            ctx.draw(Text(title.uppercased()).font(.system(size: h * 0.1, weight: .heavy).width(.condensed))
                        .tracking(2).foregroundStyle(ink),
                     at: CGPoint(x: w / 2, y: h * 0.58), anchor: .center)
            ctx.draw(Text("OCTETS / SECONDE").font(.system(size: h * 0.055, weight: .semibold))
                        .tracking(1).foregroundStyle(ink.opacity(0.65)),
                     at: CGPoint(x: w / 2, y: h * 0.68), anchor: .center)
            ctx.draw(Text("VU").font(.system(size: h * 0.12, weight: .black, design: .serif))
                        .foregroundStyle(ink.opacity(0.8)),
                     at: CGPoint(x: w * 0.1, y: h * 0.86), anchor: .center)
        }
    }
}
