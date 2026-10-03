import SwiftUI

// Composants volontairement simples : couleurs et styles système, sans dégradés ni effets.

enum Theme {
    static let bg = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardHi = Color(uiColor: .tertiarySystemFill)

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

    static let accent = Color.accentColor
    static let warn = Color.orange
    static let danger = Color.red
    static let dim = Color.secondary
    static let faint = Color(uiColor: .quaternaryLabel)
}

/// Couleur et icône de chaque outil.
enum Feature {
    case bluetooth, lan, infrared, ultrasound, satellites, network, magnet

    var tint: Color {
        switch self {
        case .bluetooth: return .blue
        case .lan: return .purple
        case .infrared: return .red
        case .ultrasound: return .orange
        case .satellites: return .indigo
        case .network: return .green
        case .magnet: return .pink
        }
    }

    /// Conservé pour les écrans qui passent une liste de couleurs : une seule teinte.
    var colors: [Color] { [tint, tint] }

    var symbol: String {
        switch self {
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .lan: return "wifi.router"
        case .infrared: return "camera.aperture"
        case .ultrasound: return "waveform"
        case .satellites: return "globe.europe.africa"
        case .network: return "network"
        case .magnet: return "location.north.circle"
        }
    }
}

extension View {
    func waveScreen(_ feature: Feature? = nil) -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
    }

    func waveRow() -> some View { listRowBackground(Theme.card) }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Symbole SF dans une couleur unie, comme dans les listes système.
struct IconTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5))
            .foregroundStyle(colors.first ?? .accentColor)
            .frame(width: size, height: size)
    }
}

struct SectionTitle: View {
    let text: String
    var symbol: String?
    var color: Color = Theme.dim

    var body: some View {
        Text(text)
            .font(.headline)
    }
}

struct BigNumber: View {
    let value: String
    var unit: String?
    var colors: [Color] = [.primary]
    var size: CGFloat = 56

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let unit {
                Text(unit)
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Pill: View {
    let text: String
    var color: Color = .accentColor
    var symbol: String?

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var mono = false

    var body: some View {
        LabeledContent(label) {
            Text(value)
                .font(mono ? .callout.monospaced() : .callout)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

/// Bouton principal : style système `borderedProminent`.
struct GradientButtonStyle: PrimitiveButtonStyle {
    var colors: [Color]

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
        }
        .buttonStyle(.borderedProminent)
        .tint(colors.first)
    }
}

/// Bouton icône : style système `bordered`.
struct CircleIconButtonStyle: PrimitiveButtonStyle {
    var color: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(color)
    }
}

struct SignalBars: View {
    let rssi: Int

    private var level: Double {
        Double(min(max(rssi + 100, 0), 60)) / 60
    }

    var body: some View {
        Image(systemName: "cellularbars", variableValue: level)
            .foregroundStyle(rssiColor(rssi))
    }
}

func rssiColor(_ rssi: Int) -> Color {
    switch rssi {
    case (-60)...: return .green
    case (-75)...: return .teal
    case (-88)...: return .orange
    default: return .red
    }
}

/// Courbe simple d'historique.
struct Sparkline: View {
    let values: [Double]
    var color: Color = .accentColor
    var minValue: Double? = nil
    var maxValue: Double? = nil
    var filled = false

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
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Jauge circulaire simple, une seule couleur.
struct GaugeRing: View {
    let progress: Double
    var colors: [Color]
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(uiColor: .systemFill), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(colors.first ?? .accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.3), value: progress)
    }
}

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
