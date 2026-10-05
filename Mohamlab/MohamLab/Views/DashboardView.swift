import SwiftUI

struct DashboardView: View {
    @Environment(Store.self) private var store
    @State private var selfTest = false
    @State private var scopeChannel = 0
    @State private var processMode = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 18) {
                    NameplatePanel().id(0)
                    if let message = store.errorMessage, !store.isDemo {
                        FaultSlip(message: message)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    StatusPanel().id(1)
                    GaugePanel(selfTest: selfTest).id(2)
                    NetworkPanel(selfTest: selfTest).id(3)
                    ScopePanel(channel: $scopeChannel).id(4)
                    CorePanel().id(5)
                    ProcessPanel(mode: $processMode).id(6)
                    SystemPanel().id(7)
                    Text("DIPHERANT INSTRUMENTS · SAINT-MAUR")
                        .font(.system(size: 9, weight: .heavy).width(.condensed))
                        .tracking(2.5)
                        .foregroundStyle(Color.white.opacity(0.22))
                        .shadow(color: .black.opacity(0.8), radius: 0, x: 0, y: -1)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .animation(.easeInOut(duration: 0.3), value: store.errorMessage)
            }
            .scrollIndicators(.hidden)
            .refreshable { await store.refreshAll() }
            .onAppear(perform: runSelfTest)
            .task {
                // -dashScroll 4 : ouvre directement sur un panneau (captures automatiques)
                if let target = UserDefaults.standard.string(forKey: "dashScroll").flatMap(Int.init) {
                    try? await Task.sleep(for: .milliseconds(300))
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    /// Au premier affichage, toutes les aiguilles balaient leur cadran (comme un vrai banc de mesure).
    private func runSelfTest() {
        guard !store.didSelfTest else { return }
        store.didSelfTest = true
        selfTest = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { selfTest = false }
    }
}

// MARK: - Plaque de firme en laiton

private struct NameplatePanel: View {
    @Environment(Store.self) private var store

    var body: some View {
        let o = store.overview
        let up = Fmt.uptimeParts(o?.uptime ?? 0)
        Plate(style: .brass, spacing: 12) {
            HStack(spacing: 14) {
                JewelLamp(color: lampColor, blinking: store.link == .connecting || store.link == .offline, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MOHAMLAB")
                        .font(.custom("Copperplate-Bold", size: 27))
                        .tracking(2.5)
                        .foregroundStyle(Color(hex: 0x3A2808, opacity: 0.92))
                        .shadow(color: Color(hex: 0xFFF3C8, opacity: 0.7), radius: 0, x: 0, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Engraved(text: "\(o?.hostname ?? "Homelab") · \(o?.shortOS ?? "—")", size: 9.5, style: .brass)
                }
                Spacer(minLength: 0)
                DymoLabel(text: linkLabel, color: linkTape)
            }
            EngravedRule(style: .brass)
            HStack(spacing: 6) {
                Engraved(text: "En marche depuis", size: 9, style: .brass)
                Spacer(minLength: 4)
                Odometer(digits: String(format: "%03d", min(up.days, 999)), size: 15)
                Engraved(text: "j", size: 9, style: .brass)
                Odometer(digits: String(format: "%02d", up.hours), size: 15)
                Engraved(text: "h", size: 9, style: .brass)
                Odometer(digits: String(format: "%02d", up.minutes), size: 15)
                Engraved(text: "m", size: 9, style: .brass)
            }
        }
    }

    private var lampColor: Color {
        switch store.link {
        case .online: return Palette.ledGreen
        case .demo: return Palette.ledBlue
        case .connecting: return Palette.ledAmber
        case .offline: return Palette.ledRed
        }
    }

    private var linkLabel: String {
        switch store.link {
        case .online: return "En ligne"
        case .demo: return "Démo"
        case .connecting: return "Liaison…"
        case .offline: return "Hors ligne"
        }
    }

    private var linkTape: Color {
        switch store.link {
        case .online: return Color(hex: 0x14532D)
        case .demo: return Color(hex: 0x1E3A8A)
        case .connecting: return Color(hex: 0x7C4A03)
        case .offline: return Color(hex: 0x8B1A12)
        }
    }
}

// MARK: - Bandeau de défaut

struct FaultSlip: View {
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            LED(color: Palette.ledRed, size: 11, blinking: true)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("LIAISON PERDUE")
                    .font(.system(size: 12, weight: .black).width(.condensed))
                    .tracking(2)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x8E1F17), Color(hex: 0x5A100B)], startPoint: .top, endPoint: .bottom))
                .overlay(Image(uiImage: Textures.brushed).resizable().opacity(0.5)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.4)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 6)
        )
    }
}

// MARK: - Tableau d'état (Nixie)

private struct StatusPanel: View {
    @Environment(Store.self) private var store

    var body: some View {
        let s = store.overview?.services
        let alerts = store.overview.map { $0.alerts.errors + $0.alerts.warnings } ?? 0
        Plate(title: "Tableau d'état", style: .anodized) {
            HStack(alignment: .top, spacing: 0) {
                NixieGroup(value: s?.running ?? 0, digits: 2, label: "En marche",
                           led: Palette.ledGreen, alarm: false) { store.tab = .services }
                Spacer(minLength: 6)
                NixieGroup(value: s?.failed ?? 0, digits: 2, label: "En panne",
                           led: Palette.ledRed, alarm: (s?.failed ?? 0) > 0) { store.tab = .services }
                Spacer(minLength: 6)
                NixieGroup(value: alerts, digits: 3, label: "Alertes 24 h",
                           led: Palette.ledAmber, alarm: false) {
                    store.logLevelIndex = 1
                    store.logHoursIndex = 2
                    store.tab = .journal
                }
            }
        }
    }
}

private struct NixieGroup: View {
    var value: Int
    var digits: Int
    var label: String
    var led: Color
    var alarm: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.click()
            action()
        } label: {
            VStack(spacing: 9) {
                NixieCounter(value: value, digits: digits, tubeWidth: 23)
                HStack(spacing: 5) {
                    LED(color: led, on: alarm || value > 0, size: 6, blinking: alarm)
                    Engraved(text: label, size: 8.5, style: .anodized)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) : \(value)")
    }
}

// MARK: - Les quatre manomètres

private struct GaugePanel: View {
    @Environment(Store.self) private var store
    var selfTest: Bool

    private let percentLabels = ["0", "20", "40", "60", "80", "100"]

    var body: some View {
        let o = store.overview
        let disk = o?.mainDisk
        let temp = o?.temperature
        Plate(title: "Ressources") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())], spacing: 18) {
                AnalogGauge(value: selfTest ? 1 : (o?.cpu.percent ?? 0) / 100,
                            title: "Processeur", unit: "%", labels: percentLabels, redFrom: 0.85,
                            readout: o.map { String(format: "%.1f", $0.cpu.percent) } ?? "---")
                AnalogGauge(value: selfTest ? 1 : (o?.memory.percent ?? 0) / 100,
                            title: "Mémoire", unit: o.map { "Go sur " + Fmt.gigabytes($0.memory.total).replacingOccurrences(of: ".", with: ",") } ?? "Go",
                            labels: percentLabels, redFrom: 0.85,
                            readout: o.map { Fmt.gigabytes($0.memory.used) } ?? "---")
                AnalogGauge(value: selfTest ? 1 : (disk?.percent ?? 0) / 100,
                            title: "Disque", unit: "Go libres", labels: percentLabels, redFrom: 0.9,
                            readout: disk.map { Fmt.gigabytes($0.free) } ?? "---")
                AnalogGauge(value: selfTest ? 1 : ((temp ?? 20) - 20) / 80,
                            title: "Température", unit: "°C", labels: ["20", "40", "60", "80", "100"], redFrom: 0.75,
                            readout: temp.map { String(format: "%.0f", $0) } ?? "---")
            }
            if let o {
                HStack(spacing: 10) {
                    Engraved(text: "Swap", size: 9)
                    HLEDMeter(value: o.swap.percent / 100, segments: 20)
                        .frame(height: 10)
                    Text("\(Fmt.bytes(o.swap.used)) / \(Fmt.bytes(o.swap.total))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: 0x2C2F33, opacity: 0.8))
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Réseau (vu-mètres)

private struct NetworkPanel: View {
    @Environment(Store.self) private var store
    var selfTest: Bool

    var body: some View {
        let net = store.overview?.network
        let io = store.overview?.diskIO
        Plate(title: "Réseau") {
            HStack(spacing: 12) {
                meter(title: "Réception", bytes: net?.rx)
                meter(title: "Émission", bytes: net?.tx)
            }
            HStack(spacing: 8) {
                Engraved(text: "Disque", size: 9)
                Spacer(minLength: 0)
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: 0x2C2F33, opacity: 0.7))
                SegmentWindow(text: Fmt.rateParts(io?.read ?? 0).0, color: Palette.segAmber, height: 13)
                Engraved(text: Fmt.rateParts(io?.read ?? 0).1, size: 8)
                Image(systemName: "arrow.up.to.line")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: 0x2C2F33, opacity: 0.7))
                    .padding(.leading, 4)
                SegmentWindow(text: Fmt.rateParts(io?.write ?? 0).0, color: Palette.segAmber, height: 13)
                Engraved(text: Fmt.rateParts(io?.write ?? 0).1, size: 8)
            }
        }
    }

    private func meter(title: String, bytes: Int?) -> some View {
        let parts = Fmt.rateParts(bytes ?? 0)
        return VStack(spacing: 9) {
            VUMeter(value: selfTest ? 1 : Fmt.logRate(bytes ?? 0), title: title)
            HStack(spacing: 6) {
                SegmentWindow(text: bytes == nil ? "---" : parts.0, color: Palette.segAmber, height: 15)
                Engraved(text: parts.1, size: 8.5)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Oscilloscope (historique)

private struct ScopePanel: View {
    @Environment(Store.self) private var store
    @Binding var channel: Int

    private let channels = ["CPU", "RAM", "Temp", "Réseau"]

    var body: some View {
        let h = store.history
        Plate(title: "Oscilloscope · 1 h") {
            Oscilloscope(points: series(h), channel: "CH\(channel + 1) · \(channels[channel].uppercased())",
                         valueText: current(h), span: "−60 MIN")
            HStack(alignment: .center) {
                RotaryKnob(options: channels, selection: $channel, knobSize: 54)
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 6) {
                        LED(color: Palette.ledGreen, on: !h.isEmpty, size: 7)
                        Engraved(text: "Synchro", size: 8.5)
                    }
                    HStack(spacing: 6) {
                        Engraved(text: "Base de temps", size: 8.5)
                        SegmentWindow(text: "15", color: Palette.segRed, height: 13)
                        Engraved(text: "s", size: 8.5)
                    }
                    HStack(spacing: 6) {
                        Engraved(text: "Points", size: 8.5)
                        SegmentWindow(text: String(format: "%03d", h.count), color: Palette.segRed, height: 13)
                    }
                }
            }
        }
    }

    private func series(_ h: [HistoryPoint]) -> [Double] {
        switch channel {
        case 0: return h.map { $0.cpu / 100 }
        case 1: return h.map { $0.mem / 100 }
        case 2: return h.map { (($0.temp ?? 20) - 20) / 80 }
        default: return h.map { Fmt.logRate($0.rx + $0.tx) }
        }
    }

    private func current(_ h: [HistoryPoint]) -> String {
        guard let last = h.last else { return "ACQUISITION…" }
        switch channel {
        case 0: return String(format: "%.0f %%", last.cpu)
        case 1: return String(format: "%.0f %%", last.mem)
        case 2: return last.temp.map { String(format: "%.0f °C", $0) } ?? "—"
        default: return Fmt.rate(last.rx + last.tx)
        }
    }
}

// MARK: - Processeur : cœurs + charge

private struct CorePanel: View {
    @Environment(Store.self) private var store

    var body: some View {
        let o = store.overview
        let cores = o?.cpu.cores ?? [0, 0, 0, 0]
        Plate(title: "Cœurs et charge") {
            HStack(alignment: .top, spacing: 12) {
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(cores.enumerated()), id: \.offset) { i, v in
                        VStack(spacing: 6) {
                            LEDBarMeter(value: v / 100, segments: 14)
                                .frame(width: 22, height: 128)
                            Engraved(text: "C\(i + 1)", size: 8.5)
                        }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 10) {
                    Engraved(text: "Charge moyenne", size: 8.5)
                    LCDWindow {
                        VStack(alignment: .trailing, spacing: 5) {
                            ForEach(0..<3, id: \.self) { i in
                                let label = ["1 min", "5 min", "15 min"][i]
                                let loads = o?.cpu.load ?? []
                                let value = i < loads.count ? loads[i] : 0
                                HStack(spacing: 8) {
                                    Text(label.uppercased())
                                        .font(.system(size: 8, weight: .bold).width(.condensed))
                                        .foregroundStyle(Palette.lcdInk.opacity(0.75))
                                    SevenSegmentText(text: String(format: "%.2f", value), color: Palette.lcdInk,
                                                     height: 16, ghost: 0.07, glow: false)
                                }
                            }
                        }
                    }
                    HStack(spacing: 6) {
                        SegmentWindow(text: o?.cpu.frequency.map { String(format: "%.0f", $0) } ?? "----",
                                      color: Palette.segAmber, height: 13)
                        Engraved(text: "MHz", size: 8.5)
                    }
                    HStack(spacing: 6) {
                        SegmentWindow(text: o.map { String($0.processes) } ?? "---", color: Palette.segAmber, height: 13)
                        Engraved(text: "Proc.", size: 8.5)
                    }
                }
            }
        }
    }
}

// MARK: - Gros consommateurs

private struct ProcessPanel: View {
    @Environment(Store.self) private var store
    @Binding var mode: Int

    var body: some View {
        let o = store.overview
        let list = mode == 0 ? (o?.topMemory ?? []) : (o?.topCPU ?? [])
        Plate(title: "Gros consommateurs", style: .anodized) {
            PresetButtons(options: ["Mémoire", "Processeur"], selection: $mode)
            VStack(spacing: 9) {
                ForEach(list) { p in
                    HStack(spacing: 10) {
                        Text(p.name)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.silkscreen)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        HLEDMeter(value: fraction(p, o), segments: 12)
                            .frame(width: 84, height: 9)
                        Text(mode == 0 ? Fmt.bytes(p.memory) : String(format: "%.1f %%", p.cpu ?? 0))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Palette.ledAmber.opacity(0.9))
                            .frame(width: 66, alignment: .trailing)
                    }
                }
                if list.isEmpty {
                    Text("— en attente de mesures —")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: list.map(\.pid))
        }
    }

    private func fraction(_ p: ProcessInfoItem, _ o: Overview?) -> Double {
        if mode == 0 {
            guard let total = o?.memory.total, total > 0 else { return 0 }
            return Double(p.memory) / Double(total) * 2.5   // 40 % de la RAM = barre pleine
        }
        return (p.cpu ?? 0) / 100
    }
}

// MARK: - Plaque signalétique

private struct SystemPanel: View {
    @Environment(Store.self) private var store

    var body: some View {
        let o = store.overview
        Plate(title: "Plaque signalétique", spacing: 10) {
            row("Système", o?.shortOS ?? "—")
            row("Noyau", o?.kernel ?? "—")
            row("Tailscale", o?.tailscaleIP ?? "—")
            ForEach(o?.lanIPs ?? []) { a in
                row(a.iface.hasPrefix("wl") ? "Wi-Fi" : "Ethernet", a.ip)
            }
            row("Ventilateur", fanText(o))
            row("Alimentation", powerText(o))
            row("Agent", o.map { "mlab-agent \($0.agentVersion)" } ?? "—")
            row("Relevé", Fmt.ago(store.lastUpdate))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Engraved(text: label, size: 9)
            DottedLeader()
                .stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .frame(height: 1)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: 0x1F2226, opacity: 0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func fanText(_ o: Overview?) -> String {
        guard let fan = o?.fans.first else { return "—" }
        return fan.rpm < 1 ? "à l'arrêt" : "\(Int(fan.rpm)) tr/min"
    }

    private func powerText(_ o: Overview?) -> String {
        guard let b = o?.battery else { return "secteur" }
        if b.percent < 1 { return b.plugged ? "secteur (sans batterie)" : "batterie vide" }
        return "\(b.plugged ? "secteur" : "batterie") · \(Int(b.percent)) %"
    }
}

struct DottedLeader: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}
