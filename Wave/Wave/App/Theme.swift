import SwiftUI

enum Theme {
    static let bg = Color(red: 0.035, green: 0.055, blue: 0.10)
    static let card = Color(red: 0.075, green: 0.105, blue: 0.17)
    static let cardHi = Color(red: 0.11, green: 0.15, blue: 0.23)
    static let accent = Color(red: 0.20, green: 0.90, blue: 0.78)
    static let blue = Color(red: 0.31, green: 0.67, blue: 1.0)
    static let violet = Color(red: 0.67, green: 0.47, blue: 1.0)
    static let warn = Color(red: 1.0, green: 0.66, blue: 0.25)
    static let danger = Color(red: 1.0, green: 0.38, blue: 0.43)
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.08)
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct Pill: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
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
    case (-60)...: return Theme.accent
    case (-75)...: return Theme.blue
    case (-88)...: return Theme.warn
    default: return Theme.danger
    }
}

/// Petite courbe pour les historiques (RSSI, champ magnétique…).
struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.accent
    var minValue: Double? = nil
    var maxValue: Double? = nil

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let lo = minValue ?? (values.min() ?? 0)
            var hi = maxValue ?? (values.max() ?? 1)
            if hi - lo < 0.0001 { hi = lo + 1 }
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = size.width * CGFloat(i) / CGFloat(values.count - 1)
                let t = (min(max(v, lo), hi) - lo) / (hi - lo)
                let y = size.height * (1 - CGFloat(t))
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
    }
}

extension View {
    func waveScreen() -> some View { modifier(ScreenBackground()) }
}

extension Date {
    var shortAgo: String {
        let s = Int(-timeIntervalSinceNow)
        if s < 5 { return "à l'instant" }
        if s < 60 { return "il y a \(s) s" }
        if s < 3600 { return "il y a \(s / 60) min" }
        return "il y a \(s / 3600) h"
    }
}

extension Data {
    var hex: String { map { String(format: "%02X", $0) }.joined(separator: " ") }
}
