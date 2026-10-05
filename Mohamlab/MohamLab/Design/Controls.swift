import SwiftUI

// MARK: - Touche en plastique ivoire

struct KeyCap: View {
    var pressed: Bool
    var radius: CGFloat = 6

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return shape
            .fill(LinearGradient(colors: pressed
                                 ? [Color(hex: 0xC9C5BA), Color(hex: 0xDAD6CB)]
                                 : [Color(hex: 0xFAF7EF), Color(hex: 0xD9D4C7)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(pressed ? 0.4 : 0.95), .black.opacity(0.28)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1))
            .overlay(
                // léger creux concave au centre de la touche
                shape.inset(by: 4).fill(LinearGradient(colors: [.black.opacity(0.05), .white.opacity(0.18)],
                                                        startPoint: .top, endPoint: .bottom))
            )
            .shadow(color: .black.opacity(pressed ? 0.25 : 0.6), radius: pressed ? 0.6 : 2.2, x: 0, y: pressed ? 0.6 : 3)
    }
}

/// Rangée de touches « présélection » à verrouillage (une seule enfoncée).
struct PresetButtons: View {
    var options: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(options.indices, id: \.self) { i in
                let on = i == selection
                Button {
                    guard selection != i else { return }
                    Haptics.thunk()
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.7)) { selection = i }
                } label: {
                    VStack(spacing: 5) {
                        Circle()
                            .fill(on ? Palette.ledGreen : Color.black.opacity(0.3))
                            .frame(width: 5, height: 5)
                            .shadow(color: on ? Palette.ledGreen : .clear, radius: 4)
                        Text(options[i].uppercased())
                            .font(.system(size: 9.5, weight: .heavy).width(.condensed))
                            .tracking(0.9)
                            .foregroundStyle(Color(hex: 0x2A2824, opacity: 0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(KeyCap(pressed: on))
                    .offset(y: on ? 2 : 0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .padding(.bottom, 2)
        .background(Color.black.opacity(0.8))
        .recessed(radius: 8)
    }
}

/// Bouton poussoir simple (ivoire), qui s'enfonce.
struct KeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .heavy).width(.condensed))
            .tracking(1.2)
            .foregroundStyle(Color(hex: 0x2A2824, opacity: 0.85))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(KeyCap(pressed: configuration.isPressed))
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.spring(response: 0.15, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in if pressed { Haptics.click() } }
    }
}

// MARK: - Interrupteur à levier

struct ToggleSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        ZStack {
            // écrou hexagonal
            Hexagon()
                .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.62), Color(white: 0.8)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Hexagon().stroke(Color.black.opacity(0.35), lineWidth: 0.7))
                .frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.45), radius: 2, x: 0, y: 2)
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.3), Color(white: 0.08)], center: .center, startRadius: 0, endRadius: 10))
                .frame(width: 18, height: 18)
            Lever()
                .frame(width: 13, height: 34)
                .scaleEffect(x: 1, y: isOn ? 1 : -1, anchor: .bottom)
                .offset(y: -17)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 2, y: isOn ? 3 : -1)
        }
        .frame(width: 50, height: 80)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.thunk()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) { isOn.toggle() }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "activé" : "désactivé")
    }

    private struct Lever: View {
        var body: some View {
            VStack(spacing: -3) {
                Circle()
                    .fill(RadialGradient(colors: [.white, Color(white: 0.75), Color(white: 0.4)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 9))
                    .frame(width: 13, height: 13)
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.55), .white, Color(white: 0.6), Color(white: 0.35)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 7)
            }
        }
    }
}

struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<6 {
            let a = Double(i) * .pi / 3 + .pi / 6
            let pt = CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Bouton rotatif à crans

struct RotaryKnob: View {
    var options: [String]
    @Binding var selection: Int
    var knobSize: CGFloat = 58
    var arc: Double = 140
    var style: PlateStyle = .aluminum

    private var labelRadius: CGFloat { knobSize / 2 + 16 }
    private var side: CGFloat { knobSize + 70 }

    private var angles: [Double] {
        guard options.count > 1 else { return [0] }
        return options.indices.map { -arc / 2 + arc * Double($0) / Double(options.count - 1) }
    }

    private var currentAngle: Double {
        angles[min(max(selection, 0), angles.count - 1)]
    }

    var body: some View {
        ZStack {
            ForEach(options.indices, id: \.self) { i in
                let a = angles[i] * .pi / 180
                VStack(spacing: 2) {
                    Circle()
                        .fill(i == selection ? Palette.ledAmber : Color.black.opacity(style == .anodized ? 0.6 : 0.25))
                        .frame(width: 4, height: 4)
                        .shadow(color: i == selection ? Palette.ledAmber : .clear, radius: 3)
                    Engraved(text: options[i], size: 8.5, style: style)
                        .fixedSize()
                }
                .position(x: side / 2 + labelRadius * CGFloat(sin(a)),
                          y: side / 2 - labelRadius * CGFloat(cos(a)) - 3)
            }
            KnobBody(size: knobSize, angle: currentAngle)
                .position(x: side / 2, y: side / 2)
        }
        .frame(width: side, height: side / 2 + knobSize / 2 + 10, alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { g in pick(at: g.location) }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selection)
        .accessibilityElement()
        .accessibilityLabel(options[min(max(selection, 0), options.count - 1)])
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: if selection < options.count - 1 { selection += 1 }
            case .decrement: if selection > 0 { selection -= 1 }
            @unknown default: break
            }
        }
    }

    private func pick(at p: CGPoint) {
        let dx = Double(p.x - side / 2)
        let dy = Double(p.y - side / 2)
        guard dx * dx + dy * dy > 64 else { return }
        let deg = atan2(dx, -dy) * 180 / .pi
        var best = selection
        var bestDist = Double.infinity
        for (i, a) in angles.enumerated() {
            let d = abs(a - deg)
            if d < bestDist { bestDist = d; best = i }
        }
        if best != selection {
            Haptics.detent()
            selection = best
        }
    }
}

struct KnobBody: View {
    var size: CGFloat
    var angle: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.5))
                .blur(radius: 4)
                .offset(y: 4)
            // jupe moletée (tourne)
            Circle()
                .fill(Color(white: 0.1))
                .overlay(KnurlShape(count: 54).stroke(Color(white: 0.38), lineWidth: 1))
                .clipShape(Circle())
                .rotationEffect(.degrees(angle))
            // chapeau en alu brossé circulaire (la lumière, elle, ne tourne pas)
            Circle()
                .fill(AngularGradient(colors: [Color(white: 0.93), Color(white: 0.62), Color(white: 0.9), Color(white: 0.56),
                                               Color(white: 0.92), Color(white: 0.6), Color(white: 0.93)],
                                      center: .center))
                .frame(width: size * 0.76, height: size * 0.76)
                .overlay(Circle().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.95), .black.opacity(0.45)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.2))
                .overlay(
                    Circle()
                        .fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .center))
                        .frame(width: size * 0.7, height: size * 0.7)
                )
            // index
            Capsule()
                .fill(Palette.needleRed)
                .frame(width: 3, height: size * 0.2)
                .offset(y: -size * 0.26)
                .rotationEffect(.degrees(angle))
        }
        .frame(width: size, height: size)
    }
}

struct KnurlShape: Shape {
    var count: Int

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        for i in 0..<count {
            let a = Double(i) / Double(count) * 2 * .pi
            p.move(to: CGPoint(x: c.x + r * 0.8 * CGFloat(cos(a)), y: c.y + r * 0.8 * CGFloat(sin(a))))
            p.addLine(to: CGPoint(x: c.x + r * CGFloat(cos(a)), y: c.y + r * CGFloat(sin(a))))
        }
        return p
    }
}

// MARK: - Bouton d'urgence sous capot de sécurité

struct SafetyCoverButton: View {
    var label: String
    var busy: Bool = false
    var action: () -> Void
    @State private var open = false
    @State private var pressed = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                HazardStripes()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.4), radius: 3, x: 0, y: 2)
                Circle()
                    .fill(Color.black)
                    .frame(width: 66, height: 66)
                    .recessed(radius: 33)
                mushroom
                cover
            }
            .frame(width: 100, height: 100)
            Engraved(text: label, size: 10)
        }
        .task(id: open) {
            guard open else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { open = false }
        }
    }

    private var mushroom: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(hex: 0xFF7B6E), Color(hex: 0xD3271C), Color(hex: 0x7A0D08)],
                                 center: UnitPoint(x: 0.4, y: 0.33), startRadius: 1, endRadius: 30))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
            .overlay(
                Ellipse().fill(Color.white.opacity(0.45))
                    .frame(width: 20, height: 10)
                    .offset(x: -6, y: -12)
                    .blur(radius: 1.5)
            )
            .frame(width: 54, height: 54)
            .shadow(color: .black.opacity(pressed ? 0.2 : 0.55), radius: pressed ? 1 : 4, x: 0, y: pressed ? 1 : 4)
            .scaleEffect(pressed ? 0.94 : 1)
            .opacity(busy ? 0.75 : 1)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard open, !busy, !pressed else { return }
                        withAnimation(.spring(response: 0.12)) { pressed = true }
                    }
                    .onEnded { _ in
                        guard pressed else { return }
                        withAnimation(.spring(response: 0.25)) { pressed = false }
                        Haptics.heavy()
                        action()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75).delay(0.3)) { open = false }
                    }
            )
            .allowsHitTesting(open)
    }

    private var cover: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0xFF3B30, opacity: 0.42), Color(hex: 0xB0120A, opacity: 0.5)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .topLeading, endPoint: .center))
                    .frame(width: 60, height: 40)
                    .padding(5)
            }
            .overlay(alignment: .bottom) {
                Text("SOULEVER")
                    .font(.system(size: 7.5, weight: .black).width(.condensed))
                    .tracking(1.5)
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.bottom, 6)
            }
            .frame(width: 92, height: 92)
            .rotation3DEffect(.degrees(open ? 112 : 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.55)
            .shadow(color: .black.opacity(0.35), radius: open ? 0 : 3, x: 0, y: 2)
            .onTapGesture {
                Haptics.click()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { open.toggle() }
            }
            .allowsHitTesting(!busy)
    }
}

struct HazardStripes: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0xF5C518)))
            let w: CGFloat = 11
            var x: CGFloat = -size.height
            while x < size.width + size.height {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + w, y: size.height))
                p.addLine(to: CGPoint(x: x + w + size.height, y: 0))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                p.closeSubpath()
                ctx.fill(p, with: .color(Color(hex: 0x1A1A1A)))
                x += w * 2
            }
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.2)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        }
    }
}
