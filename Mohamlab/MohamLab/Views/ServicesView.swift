import SwiftUI

struct ServicesView: View {
    @Environment(Store.self) private var store
    @State private var filter = 0
    @State private var selected: Service?

    private let filters = ["Tous", "Web", "Média", "Réseau", "Autres"]

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Plate(title: "Baie de services") {
                    HStack(spacing: 14) {
                        tally(color: Palette.ledGreen, count: count("running"), label: "Actifs")
                        tally(color: Palette.ledRed, count: count("failed"), label: "Pannes", blink: count("failed") > 0)
                        tally(color: Palette.ledAmber, count: count("done") + count("stopped"), label: "Repos", lit: false)
                    }
                    PresetButtons(options: filters, selection: $filter)
                }
                if store.services.isEmpty {
                    Plate(style: .anodized) {
                        HStack(spacing: 10) {
                            LED(color: Palette.ledAmber, size: 8, blinking: true)
                            Engraved(text: "Inventaire des modules…", size: 10, style: .anodized)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    RackView(rows: rows) { service in
                        selected = service
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .animation(.easeInOut(duration: 0.25), value: filter)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.refreshServices() }
        .task {
            await store.refreshServices()
            // -openService kloz : ouvre directement une fiche (captures automatiques)
            if let name = UserDefaults.standard.string(forKey: "openService") {
                selected = store.services.first { $0.name == name }
            }
        }
        .sheet(item: $selected) { service in
            ServiceDetailView(service: service)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
                .presentationBackground { WoodBackground() }
        }
    }

    private func count(_ state: String) -> Int {
        store.services.filter { $0.state == state }.count
    }

    private func tally(color: Color, count: Int, label: String, blink: Bool = false, lit: Bool = true) -> some View {
        HStack(spacing: 6) {
            LED(color: color, on: lit && count > 0, size: 8, blinking: blink)
            SegmentWindow(text: String(format: "%02d", count), color: Palette.segRed, height: 14)
            Engraved(text: label, size: 8.5)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rows: [RackRow] {
        let all = store.services
        let filtered: [Service]
        switch filter {
        case 1: filtered = all.filter { $0.category == "web" }
        case 2: filtered = all.filter { $0.category == "media" }
        case 3: filtered = all.filter { $0.category == "reseau" }
        case 4: filtered = all.filter { !["web", "media", "reseau"].contains($0.category) }
        default: filtered = all
        }

        var out: [RackRow] = []
        let failed = filtered.filter(\.isFailed)
        if !failed.isEmpty {
            out.append(.header("En panne", Color(hex: 0x9B1C13)))
            out += failed.map { RackRow.module($0) }
        }
        let healthy = filtered.filter { !$0.isFailed }
        let order: [(String, String, Color)] = [
            ("web", "Web", Color(hex: 0x111111)),
            ("media", "Média", Color(hex: 0x1E3A8A)),
            ("reseau", "Réseau", Color(hex: 0x14532D)),
            ("mail", "Courrier", Color(hex: 0x6B21A8)),
            ("bot", "Bots", Color(hex: 0x7C4A03)),
            ("donnees", "Données", Color(hex: 0x0F5257)),
            ("systeme", "Système", Color(hex: 0x3F3F46)),
        ]
        for (key, label, tape) in order {
            let group = healthy.filter { $0.category == key }
            guard !group.isEmpty else { continue }
            out.append(.header(label, tape))
            out += group.map { RackRow.module($0) }
        }
        return out
    }
}

// MARK: - La baie 19 pouces

enum RackRow: Identifiable {
    case header(String, Color)
    case module(Service)

    var id: String {
        switch self {
        case .header(let t, _): return "h-" + t
        case .module(let s): return s.id
        }
    }
}

struct RackView: View {
    var rows: [RackRow]
    var onSelect: (Service) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows) { row in
                switch row {
                case .header(let title, let tape):
                    RackBlank(title: title, tape: tape)
                case .module(let s):
                    Button {
                        Haptics.click()
                        onSelect(s)
                    } label: {
                        ServiceModule(service: s)
                    }
                    .buttonStyle(ModulePressStyle())
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(RackFrame())
    }
}

struct ModulePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct RackFrame: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x0E0F11), Color(hex: 0x060607)], startPoint: .top, endPoint: .bottom))
            HStack {
                RackRail()
                Spacer()
                RackRail()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color(white: 0.35), Color(white: 0.08)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.6), radius: 12, x: 0, y: 9)
    }
}

struct RackRail: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.85), Color(white: 0.5)],
                                     startPoint: .leading, endPoint: .trailing))
            RackHoles()
                .fill(Color.black.opacity(0.88))
        }
        .frame(width: 15)
    }
}

struct RackHoles: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let side: CGFloat = 5.5
        var y = rect.minY + 6
        var i = 0
        while y + side < rect.maxY {
            p.addRoundedRect(in: CGRect(x: rect.midX - side / 2, y: y, width: side, height: side),
                             cornerSize: CGSize(width: 1, height: 1))
            // 1U = 3 trous inégalement espacés
            y += (i % 3 == 2) ? 16 : 13
            i += 1
        }
        return p
    }
}

/// Panneau vierge avec son étiquette Dymo, pour séparer les familles.
struct RackBlank: View {
    var title: String
    var tape: Color

    var body: some View {
        HStack {
            DymoLabel(text: title, color: tape, size: 10)
            Spacer()
            Screw(size: 7, angle: 20)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(PlateBackground(style: .aluminum, radius: 3, shadow: false))
        .padding(.top, 6)
    }
}

// MARK: - Module 1U

struct ServiceModule: View {
    var service: Service

    var body: some View {
        HStack(spacing: 10) {
            RackHandle()
            LED(color: ledColor, on: service.state != "stopped", size: 9, blinking: service.isFailed || service.state == "starting")
            VStack(alignment: .leading, spacing: 4) {
                Text(service.title.uppercased())
                    .font(.system(size: 13, weight: .heavy).width(.condensed))
                    .tracking(1.1)
                    .foregroundStyle(Palette.silkscreen)
                    .lineLimit(1)
                Text(service.subtitle.isEmpty ? service.name : service.subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    ForEach(service.ports.prefix(2), id: \.self) { port in
                        DymoLabel(text: ":\(port)", color: Color(hex: 0x1D4ED8), size: 8.5)
                    }
                    if service.isFailed {
                        DymoLabel(text: "Panne", color: Color(hex: 0xB91C1C), size: 8.5)
                    } else if let up = service.uptime {
                        Text("↑ " + Fmt.duration(up))
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Palette.ledGreen.opacity(0.75))
                    } else {
                        Text(service.stateLabel.uppercased())
                            .font(.system(size: 9, weight: .heavy).width(.condensed))
                            .tracking(1)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.top, 1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                if let m = service.memory {
                    HLEDMeter(value: memoryFraction(m), segments: 10)
                        .frame(width: 62, height: 8)
                    Text(Fmt.bytes(m))
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Palette.ledAmber.opacity(0.85))
                } else {
                    Text("— —")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            RackHandle()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        .frame(minHeight: 74)
        .background(faceplate)
        .contentShape(Rectangle())
    }

    private var ledColor: Color {
        switch service.state {
        case "running": return Palette.ledGreen
        case "failed": return Palette.ledRed
        case "starting": return Palette.ledAmber
        case "done": return Palette.ledBlue
        default: return Palette.ledAmber
        }
    }

    private func memoryFraction(_ m: Int) -> Double {
        let ceiling = Double(service.memoryMax ?? 1_073_741_824)
        return Double(m) / max(ceiling, Double(m), 1)
    }

    private var faceplate: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return shape
            .fill(LinearGradient(colors: service.isFailed
                                 ? [Color(hex: 0x3A1513), Color(hex: 0x220B0A)]
                                 : [Color(hex: 0x2B2D32), Color(hex: 0x17181B)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(Image(uiImage: Textures.brushed).resizable().opacity(0.5).clipShape(shape))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.2), .black.opacity(0.6)],
                                                       startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: .black.opacity(0.7), radius: 2, x: 0, y: 2)
    }
}

/// Poignée chromée de façade rack.
struct RackHandle: View {
    var body: some View {
        Capsule()
            .fill(LinearGradient(colors: [Color(white: 0.45), Color(white: 0.97), Color(white: 0.6), Color(white: 0.3)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: 5, height: 40)
            .shadow(color: .black.opacity(0.6), radius: 1.5, x: 1, y: 1.5)
    }
}
