import SwiftUI

// MARK: - Couleurs

/// Palette basée sur les couleurs système d'Apple, en clair comme en sombre.
enum Theme {
    // Fonds adaptatifs (clair / sombre), comme Réglages et Santé.
    static let bg = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardHi = Color(uiColor: .tertiarySystemFill)
    static let stroke = Color.primary.opacity(0.06)

    // Couleurs système vives, qui s'ajustent automatiquement au mode clair/sombre.
    static let blue = Color.blue
    static let cyan = Color.cyan
    static let teal = Color.teal
    static let mint = Color.mint
    static let green = Color.green
    static let indigo = Color.indigo
    static let violet = Color.purple
    static let pink = Color.pink
    static let red = Color.red
    static let orange = Color.orange
    static let yellow = Color.yellow

    /// Couleur de marque (onglets, éléments positifs).
    static let accent = Color.teal
    static let warn = Color.orange
    static let danger = Color.red
    static let dim = Color.secondary
    static let faint = Color(uiColor: .quaternaryLabel)
}

/// Chaque outil a son dégradé signature, utilisé pour ses icônes, chiffres et lueurs.
enum Feature {
    case bluetooth, lan, infrared, ultrasound, satellites, network, magnet

    var colors: [Color] {
        switch self {
        case .bluetooth: return [Theme.blue, Theme.cyan]
        case .lan: return [Theme.indigo, Theme.violet]
        case .infrared: return [Theme.pink, Theme.red]
        case .ultrasound: return [Theme.orange, Theme.yellow]
        case .satellites: return [Theme.indigo, Theme.teal]
        case .network: return [Theme.green, Theme.mint]
        case .magnet: return [Theme.red, Theme.orange]
        }
    }

    var tint: Color { colors[0] }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var symbol: String {
        switch self {
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .lan: return "wifi.router.fill"
        case .infrared: return "camera.aperture"
        case .ultrasound: return "waveform"
        case .satellites: return "globe.europe.africa.fill"
        case .network: return "network"
        case .magnet: return "location.north.circle.fill"
        }
    }
}

extension LinearGradient {
    static func wave(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Fond d'écran

struct ScreenBackground: ViewModifier {
    var feature: Feature?

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    Theme.bg
                    if let feature {
                        // Lueur colorée en haut de l'écran, très discrète.
                        RadialGradient(
                            colors: [feature.colors[0].opacity(0.22), feature.colors[1].opacity(0.06), .clear],
                            center: UnitPoint(x: 0.15, y: -0.05),
                            startRadius: 10,
                            endRadius: 520
                        )
                        RadialGradient(
                            colors: [feature.colors[1].opacity(0.16), .clear],
                            center: UnitPoint(x: 1.0, y: 0.05),
                            startRadius: 10,
                            endRadius: 380
                        )
                    }
                }
                .ignoresSafeArea()
            }
    }
}

extension View {
    func waveScreen(_ feature: Feature? = nil) -> some View { modifier(ScreenBackground(feature: feature)) }

    /// Fond de ligne de liste assorti aux cartes.
    func waveRow() -> some View { listRowBackground(Theme.card) }
}

// MARK: - Composants

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 0.5))
    }
}

/// Icône carrée arrondie à fond dégradé, comme dans Réglages.
struct IconTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(LinearGradient.wave(colors))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: .center))
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            )
            .shadow(color: colors[0].opacity(0.35), radius: size * 0.18, y: size * 0.06)
    }
}

/// Titre de section en petites capitales, façon Santé.
struct SectionTitle: View {
    let text: String
    var symbol: String?
    var color: Color = Theme.dim

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.footnote.weight(.semibold))
        .textCase(.uppercase)
        .foregroundStyle(color)
    }
}

/// Grand chiffre arrondi avec dégradé.
struct BigNumber: View {
    let value: String
    var unit: String?
    var colors: [Color] = Feature.bluetooth.colors
    var size: CGFloat = 56

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let unit {
                Text(unit)
                    .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.dim)
            }
        }
    }
}

/// Petite tuile de statistique (valeur + légende).
struct StatTile: View {
    let value: String
    let label: String
    var color: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.cardHi, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.accent
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.16), in: Capsule())
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var mono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(Theme.dim)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? .callout.monospaced() : .callout)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

/// Bouton principal en capsule dégradée.
struct GradientButtonStyle: ButtonStyle {
    var colors: [Color]

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(LinearGradient.wave(colors), in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Bouton secondaire rond (icône seule), fond translucide.
struct CircleIconButtonStyle: ButtonStyle {
    var color: Color = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: 40, height: 40)
            .background(Theme.cardHi, in: Circle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

struct SignalBars: View {
    let rssi: Int

    private var level: Int {
        switch rssi {
        case (-55)...: return 5
        case (-65)...: return 4
        case (-75)...: return 3
        case (-85)...: return 2
        default: return 1
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i <= level ? rssiColor(rssi) : Theme.faint)
                    .frame(width: 4, height: CGFloat(4 + i * 3))
            }
        }
    }
}

func rssiColor(_ rssi: Int) -> Color {
    switch rssi {
    case (-60)...: return Theme.green
    case (-75)...: return Theme.teal
    case (-88)...: return Theme.orange
    default: return Theme.red
    }
}

/// Courbe d'historique avec remplissage dégradé.
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.accent
    var minValue: Double? = nil
    var maxValue: Double? = nil
    var filled = true

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let lo = minValue ?? (values.min() ?? 0)
            var hi = maxValue ?? (values.max() ?? 1)
            if hi - lo < 0.0001 { hi = lo + 1 }
            var line = Path()
            for (i, v) in values.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
                let t = (min(max(v, lo), hi) - lo) / (hi - lo)
                let y = size.height * (1 - CGFloat(t))
                if i == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            if filled {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.35), color.opacity(0)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Anneau de progression dégradé, façon anneaux d'activité.
struct GaugeRing: View {
    let progress: Double
    var colors: [Color]
    var lineWidth: CGFloat = 18

    var body: some View {
        ZStack {
            Circle()
                .stroke(colors[0].opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    AngularGradient(colors: colors + [colors[0]], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: colors.last!.opacity(0.45), radius: 8)
        }
        .animation(.easeOut(duration: 0.3), value: progress)
    }
}

// MARK: - Utilitaires

extension Date {
    var shortAgo: String {
        let s = Int(-timeIntervalSinceNow)
        if s < 5 { return "à l'instant" }
        if s < 60 { return "il y a \(s) s" }
        if s < 3600 { return "il y a \(s / 60) min" }
        if s < 86400 { return "il y a \(s / 3600) h" }
        return "il y a \(s / 86400) j"
    }
}

extension Data {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}
