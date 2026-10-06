import SwiftUI
import UIKit

// MARK: - Barre en cuir (en-tête de chaque écran)

struct LeatherHeader<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        ZStack {
            HStack {
                leading()
                Spacer()
                trailing()
            }
            .padding(.horizontal, 12)

            VStack(spacing: 0) {
                Text(title)
                    .font(Typo.serif(23, bold: true))
                    .foregroundStyle(Ink.stitch)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .embossed(light: .white.opacity(0.15), dark: .black.opacity(0.9))
                if let subtitle {
                    Text(subtitle)
                        .font(Typo.typewriter(11))
                        .foregroundStyle(Ink.stitch.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 64)
        }
        .frame(height: 62)
        .frame(maxWidth: .infinity)
        .background(
            Leather(shape: Rectangle(), stitchInset: 5)
                .ignoresSafeArea(edges: .top)
                .shadow(color: .black.opacity(0.6), radius: 5, x: 0, y: 3)
        )
    }
}

extension LeatherHeader where Leading == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.leading = { EmptyView() }
        self.trailing = trailing
    }
}

// MARK: - Bouton rond en cuir repoussé

struct LeatherButton: View {
    let symbol: String
    var label: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                if let label {
                    Text(label).font(Typo.serif(15, bold: true))
                }
            }
            .foregroundStyle(Ink.stitch)
            .embossed(light: .white.opacity(0.12), dark: .black.opacity(0.8))
            .padding(.horizontal, label == nil ? 0 : 12)
            .frame(minWidth: 38, minHeight: 34)
            .background(
                Capsule()
                    .fill(LinearGradient(colors: [Ink.leatherDark, Ink.leather], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(LinearGradient(colors: [.black.opacity(0.7), .white.opacity(0.2)],
                                                                    startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 1, x: 0, y: 1)
            )
        }
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.08 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Vis de laiton

struct Screw: View {
    var angle: Double = 30
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Ink.brassHi, Ink.brass, Ink.brassDeep],
                                         center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 6))
            Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 0.6)
            Rectangle()
                .fill(Ink.brassDeep)
                .frame(width: 7, height: 1.4)
                .rotationEffect(.degrees(angle))
                .shadow(color: Ink.brassHi, radius: 0, x: 0, y: 0.6)
        }
        .frame(width: 9, height: 9)
        .shadow(color: .black.opacity(0.4), radius: 0.5, x: 0, y: 0.6)
    }
}

// MARK: - Plaque de laiton vissée

struct BrassPlate: View {
    var corner: CGFloat = 10
    var screws = true

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        shape
            .fill(Ink.brassGradient)
            .overlay(
                // brossé : fines lignes horizontales
                Canvas { ctx, size in
                    var rng = SeededRNG(5)
                    var y: CGFloat = 0
                    while y < size.height {
                        let p = Path(CGRect(x: 0, y: y, width: size.width, height: 0.5))
                        ctx.fill(p, with: .color(Bool.random(using: &rng) ? .white.opacity(0.12) : .black.opacity(0.07)))
                        y += CGFloat.random(in: 1...2.5, using: &rng)
                    }
                }
                .clipShape(shape)
            )
            .overlay(shape.strokeBorder(LinearGradient(colors: [Ink.brassHi, Ink.brassDeep],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
            .overlay(shape.inset(by: 2).strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
            .overlay(alignment: .topLeading) { if screws { Screw(angle: 20).padding(7) } }
            .overlay(alignment: .topTrailing) { if screws { Screw(angle: 80).padding(7) } }
            .overlay(alignment: .bottomLeading) { if screws { Screw(angle: 140).padding(7) } }
            .overlay(alignment: .bottomTrailing) { if screws { Screw(angle: 45).padding(7) } }
            .shadow(color: .black.opacity(0.55), radius: 5, x: 0, y: 4)
    }
}

// MARK: - Pastille émaillée (compteur de non-lus)

struct EnamelBadge: View {
    let count: Int

    var body: some View {
        Text(count > 999 ? "999+" : String(count))
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: -1)
            .padding(.horizontal, 8)
            .frame(minWidth: 28, minHeight: 26)
            .background(
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.95, green: 0.32, blue: 0.27), Color(red: 0.70, green: 0.06, blue: 0.05)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(
                        Capsule()
                            .fill(LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.05)],
                                                 startPoint: .top, endPoint: .center))
                            .padding(.horizontal, 3)
                            .padding(.top, 2)
                            .mask(VStack(spacing: 0) { Rectangle(); Color.clear })
                    )
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 2)
            )
    }
}

// MARK: - Cachet de cire

struct WaxBlob: View {
    var body: some View {
        ZStack {
            // bavures irrégulières de la cire
            ForEach(0..<9, id: \.self) { i in
                let a = Double(i) / 9 * 2 * .pi
                Circle()
                    .fill(Ink.wax)
                    .frame(width: 26, height: 26)
                    .offset(x: cos(a) * 24, y: sin(a) * 24)
            }
            Circle()
                .fill(RadialGradient(colors: [Ink.waxHi, Ink.wax, Ink.waxDeep],
                                     center: .init(x: 0.38, y: 0.32), startRadius: 2, endRadius: 40))
                .frame(width: 66, height: 66)
            Circle()
                .strokeBorder(Ink.waxDeep.opacity(0.8), lineWidth: 2)
                .frame(width: 50, height: 50)
            Circle()
                .stroke(Ink.waxHi.opacity(0.6), lineWidth: 1)
                .frame(width: 52, height: 52)
                .offset(y: 1)
        }
        .frame(width: 84, height: 84)
        .shadow(color: .black.opacity(0.55), radius: 4, x: 0, y: 3)
    }
}

struct WaxSealButton: View {
    let symbol: String
    var caption: String? = nil
    var busy = false
    let action: () -> Void

    @State private var spin = 0.0

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    WaxBlob()
                    Image(systemName: busy ? "hourglass" : symbol)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(Ink.waxDeep)
                        .shadow(color: Ink.waxHi.opacity(0.9), radius: 0, x: 0, y: 1)
                        .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: -1)
                        .rotationEffect(.degrees(spin))
                }
                if let caption {
                    Text(caption)
                        .font(Typo.serif(14, bold: true))
                        .foregroundStyle(Ink.stitch)
                        .embossed(light: .clear, dark: .black.opacity(0.8))
                }
            }
        }
        .buttonStyle(PressStyle())
        .disabled(busy)
        .onChange(of: busy) { _, now in
            if now {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { spin = 360 }
            } else {
                withAnimation(.default) { spin = 0 }
            }
        }
    }
}

// MARK: - Étiquette Dymo

struct DymoLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .heavy, design: .monospaced))
            .kerning(1.5)
            .foregroundStyle(.white.opacity(0.92))
            .shadow(color: .black.opacity(0.8), radius: 0, x: 0, y: 1)
            .shadow(color: .white.opacity(0.25), radius: 0, x: 0, y: -0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
                    .overlay(Grain(seed: 9, density: 0.02, dark: 0.3, light: 0.08).clipShape(RoundedRectangle(cornerRadius: 2)))
            )
            .rotationEffect(.degrees(-1.2))
            .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 2)
    }
}

// MARK: - Champ dactylographié

struct TypedField: View {
    let label: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default
    var placeholder = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(Typo.serif(15, bold: true))
                .foregroundStyle(Ink.inkSoft)
                .frame(width: 74, alignment: .leading)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                }
            }
            .font(Typo.typewriter(16))
            .foregroundStyle(Ink.ink)
            .tint(Ink.redInk)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Ink.blueInk.opacity(0.35))
                .frame(height: 1)
        }
    }
}

// MARK: - Télégramme (notifications internes)

struct TelegramToast: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "envelope.fill")
                .foregroundStyle(toast.isError ? Ink.redInk : Ink.blueInk)
            Text(toast.text)
                .font(Typo.typewriter(14))
                .foregroundStyle(Ink.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            PaperSheet(corner: 3, tint: Color(red: 0.98, green: 0.93, blue: 0.72))
        )
        .overlay(alignment: .leading) {
            Rectangle().fill(toast.isError ? Ink.redInk : Ink.blueInk).frame(width: 4)
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 4)
        .rotationEffect(.degrees(-0.6))
        .padding(.horizontal, 20)
    }
}

// MARK: - Cachet « non lu » (petite goutte de cire)

struct WaxDot: View {
    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Ink.waxHi, Ink.wax, Ink.waxDeep],
                                 center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 7))
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
    }
}
