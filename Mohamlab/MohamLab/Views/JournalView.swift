import SwiftUI

/// Le journal sort d'une imprimante à aiguilles, sur du papier listing à bandes vertes.
struct JournalView: View {
    @Environment(Store.self) private var store
    @State private var expanded: Set<String> = []

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(spacing: 0) {
                PrinterHead(level: $store.logLevelIndex, hours: $store.logHoursIndex,
                            busy: store.logsLoading, counts: store.logs?.counts ?? [:])
                    .zIndex(1)
                ListingPaper(response: store.logs, loading: store.logsLoading, expanded: $expanded)
                    .padding(.horizontal, 12)
                    .padding(.top, -16)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refreshLogs() }
        .task { await store.refreshLogs() }
        .onChange(of: store.logLevelIndex) { _, _ in Task { await store.refreshLogs() } }
        .onChange(of: store.logHoursIndex) { _, _ in Task { await store.refreshLogs() } }
    }
}

// MARK: - L'imprimante

private struct PrinterHead: View {
    @Binding var level: Int
    @Binding var hours: Int
    var busy: Bool
    var counts: [String: Int]

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DIPHERANT")
                        .font(.custom("Copperplate-Bold", size: 15))
                        .tracking(2)
                        .foregroundStyle(Color(white: 0.85))
                        .shadow(color: .black, radius: 0, x: 0, y: -1)
                    Engraved(text: "Imprimante LP-80 · journal simplifié", size: 8, style: .anodized)
                }
                Spacer()
                HStack(spacing: 6) {
                    LED(color: busy ? Palette.ledAmber : Palette.ledGreen, size: 8, blinking: busy)
                    Engraved(text: busy ? "Impression" : "Prêt", size: 8.5, style: .anodized)
                }
            }
            HStack(alignment: .center, spacing: 0) {
                RotaryKnob(options: Store.logLevelLabels, selection: $level, knobSize: 46, style: .anodized)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 7) {
                    counter(Palette.ledRed, counts["error"] ?? 0, "Err.")
                    counter(Palette.ledAmber, counts["warning"] ?? 0, "Alr.")
                    counter(Palette.ledGreen, counts["info"] ?? 0, "Inf.")
                }
                Spacer(minLength: 0)
                RotaryKnob(options: Store.logHourLabels, selection: $hours, knobSize: 46, style: .anodized)
            }
            // fente de sortie du papier
            Capsule()
                .fill(Color.black)
                .frame(height: 10)
                .overlay(
                    Capsule().stroke(LinearGradient(colors: [.black, .white.opacity(0.25)], startPoint: .top, endPoint: .bottom),
                                     lineWidth: 1)
                )
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(PlateBackground(style: .anodized, radius: 18))
        .overlay(ScrewCorners(inset: 8, size: 9))
    }

    private func counter(_ color: Color, _ value: Int, _ label: String) -> some View {
        HStack(spacing: 6) {
            LED(color: color, on: value > 0, size: 6)
            SegmentWindow(text: String(format: "%03d", min(value, 999)), color: color == Palette.ledGreen ? Palette.segAmber : Palette.segRed,
                          height: 12)
            Engraved(text: label, size: 8, style: .anodized)
        }
    }
}

// MARK: - Le papier listing

private struct ListingPaper: View {
    var response: LogResponse?
    var loading: Bool
    @Binding var expanded: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let entries = response?.entries {
                if entries.isEmpty {
                    Text("— RIEN À SIGNALER —")
                        .font(.custom("CourierNewPS-BoldMT", size: 13))
                        .foregroundStyle(Palette.ribbonBlack.opacity(0.75))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                } else {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        LogRow(entry: entry, shaded: (index / 2) % 2 == 0, expanded: expanded.contains(entry.id))
                            .onTapGesture {
                                Haptics.click()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expanded.contains(entry.id) { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                                }
                            }
                    }
                }
            } else {
                Text(loading ? "IMPRESSION EN COURS…" : "— PAS DE DONNÉES —")
                    .font(.custom("CourierNewPS-BoldMT", size: 13))
                    .foregroundStyle(Palette.ribbonBlack.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
            Text("— FIN DU RAPPORT —")
                .font(.custom("CourierNewPSMT", size: 11))
                .foregroundStyle(Palette.ribbonBlack.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.top, 18)
                .padding(.bottom, 26)
        }
        .padding(.horizontal, 30)
        .padding(.top, 28)
        .background(PaperBackground())
        .clipShape(TornEdge())
        .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 8)
        .animation(.easeOut(duration: 0.35), value: response?.entries.map(\.id) ?? [])
    }

    private var header: some View {
        let c = response?.counts ?? [:]
        return VStack(alignment: .leading, spacing: 4) {
            TypedRule()
            Text("MOHAMLAB — JOURNAL SIMPLIFIÉ")
                .font(.custom("CourierNewPS-BoldMT", size: 13))
            Text("IMPRIMÉ LE \(Fmt.long(Date())) · \(hoursLabel)")
                .font(.custom("CourierNewPSMT", size: 11))
            Text("\(c["error"] ?? 0) ERREUR(S) · \(c["warning"] ?? 0) ALERTE(S) · \(c["info"] ?? 0) INFO(S)")
                .font(.custom("CourierNewPSMT", size: 11))
            TypedRule()
                .padding(.top, 2)
        }
        .foregroundStyle(Palette.ribbonBlack.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.bottom, 10)
    }

    private var hoursLabel: String {
        guard let h = response?.hours else { return "—" }
        return h >= 48 ? "\(h / 24) JOURS" : "\(h) H"
    }
}

private struct LogRow: View {
    var entry: LogEntry
    var shaded: Bool
    var expanded: Bool

    private var ink: Color { entry.level == "error" ? Palette.ribbonRed : Palette.ribbonBlack }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Fmt.clock(entry.time))
                    .font(.custom("CourierNewPSMT", size: 11))
                    .foregroundStyle(Palette.ribbonBlack.opacity(0.6))
                Text(entry.title.uppercased())
                    .font(.custom("CourierNewPS-BoldMT", size: 12))
                    .foregroundStyle(ink.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if entry.count > 1 {
                    Text("×\(entry.count)")
                        .font(.custom("CourierNewPS-BoldMT", size: 11))
                        .foregroundStyle(ink.opacity(0.85))
                }
            }
            Text(entry.message)
                .font(.custom("CourierNewPSMT", size: 12.5))
                .foregroundStyle(ink.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, entry.level == "info" ? 0 : 54)
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    if entry.raw != entry.message {
                        Text("BRUT : " + entry.raw)
                    }
                    if entry.count > 1 {
                        Text("PREMIÈRE FOIS : \(Fmt.clock(entry.firstTime)) · DERNIÈRE : \(Fmt.clock(entry.time))")
                    }
                    if !entry.unit.isEmpty {
                        Text("UNITÉ : \(entry.unit)")
                    }
                }
                .font(.custom("CourierNewPSMT", size: 10.5))
                .foregroundStyle(Palette.ribbonBlack.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shaded ? Palette.paperBar.opacity(0.65) : Color.clear)
        .overlay(alignment: .bottomTrailing) {
            if entry.level != "info" {
                RubberStamp(text: entry.level == "error" ? "Erreur" : "Alerte",
                            color: entry.level == "error" ? Palette.ribbonRed : Color(hex: 0xC2610C),
                            angle: entry.level == "error" ? -9 : 7, size: 10)
                    .padding(.trailing, 6)
                    .padding(.bottom, 8)
            }
        }
        .contentShape(Rectangle())
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Le papier lui-même

private struct PaperBackground: View {
    var body: some View {
        ZStack {
            Palette.paper
            Image(uiImage: Textures.paper)
                .resizable(resizingMode: .tile)
            HStack(spacing: 0) {
                TractorMargin()
                Spacer()
                TractorMargin()
            }
        }
    }
}

/// Marge d'entraînement : trous ronds + ligne de pré-découpe.
private struct TractorMargin: View {
    var body: some View {
        ZStack {
            TractorHoles()
                .fill(Palette.walnutDeep)
            TractorHoles()
                .stroke(Color.black.opacity(0.25), lineWidth: 0.8)
        }
        .frame(width: 22)
        .overlay(alignment: .trailing) {
            VerticalRule()
                .stroke(Palette.ribbonBlack.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(width: 1)
        }
    }
}

private struct VerticalRule: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

private struct TractorHoles: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let d: CGFloat = 7
        var y = rect.minY + 8
        while y + d < rect.maxY {
            p.addEllipse(in: CGRect(x: rect.midX - d / 2, y: y, width: d, height: d))
            y += 18
        }
        return p
    }
}

/// Bas de feuille arraché en dents de scie.
private struct TornEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 6))
        var x = rect.maxX
        var up = false
        var rng = SeededRandom(seed: 5)
        while x > rect.minX {
            x -= CGFloat.random(in: 4...9, using: &rng)
            p.addLine(to: CGPoint(x: max(x, rect.minX), y: rect.maxY - (up ? 7 : CGFloat.random(in: 0...2, using: &rng))))
            up.toggle()
        }
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
