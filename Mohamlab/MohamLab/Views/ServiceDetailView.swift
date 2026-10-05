import SwiftUI

/// Fiche technique d'un service, tapée à la machine et pincée sur un porte-bloc.
struct ServiceDetailView: View {
    @Environment(Store.self) private var store
    var service: Service

    @State private var logs: [LogEntry]?
    @State private var restartBusy = false
    @State private var restartMessage: String?
    @State private var restartOK = false

    private var current: Service { store.services.first { $0.id == service.id } ?? service }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                clipboard
                commandPlate
            }
            .padding(.horizontal, 14)
            .padding(.top, 26)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .task { logs = await store.fetchLogs(unit: service.name) }
    }

    // MARK: Porte-bloc

    private var clipboard: some View {
        sheet
            .padding(.horizontal, 14)
            .padding(.top, 34)
            .padding(.bottom, 16)
            .background(board)
            .overlay(alignment: .top) {
                Clip().offset(y: -14)
            }
    }

    private var board: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: 0x8A6440), Color(hex: 0x6B4A2C)], startPoint: .top, endPoint: .bottom))
            .overlay(Image(uiImage: Textures.paper).resizable(resizingMode: .tile).opacity(0.9).blendMode(.multiply)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .black.opacity(0.4)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1.2))
            .shadow(color: .black.opacity(0.6), radius: 14, x: 0, y: 10)
    }

    private var sheet: some View {
        let s = current
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FICHE DE SERVICE  N° \(ficheNumber(s))")
                        .font(.custom("AmericanTypewriter", size: 10))
                        .foregroundStyle(Palette.ribbonBlack.opacity(0.6))
                    Text(s.title)
                        .font(.custom("AmericanTypewriter-Bold", size: 24))
                        .foregroundStyle(Palette.ribbonBlack)
                        .fixedSize(horizontal: false, vertical: true)
                    if !s.subtitle.isEmpty {
                        Text(s.subtitle)
                            .font(.custom("AmericanTypewriter", size: 13))
                            .foregroundStyle(Palette.ribbonBlack.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                RubberStamp(text: s.stateLabel, color: stampColor(s), angle: -11, size: 14)
                    .padding(.top, 14)
            }

            TypedRule()

            VStack(alignment: .leading, spacing: 7) {
                field("Unité", s.id)
                field("État", "\(s.activeState) (\(s.subState))", red: s.isFailed)
                field("Démarrage auto", s.enabled ? "oui" : "non")
                field("En marche depuis", s.uptime.map { Fmt.duration($0) } ?? "—")
                field("Mémoire", memoryText(s))
                if let m = s.memory {
                    PencilBar(fraction: Double(m) / Double(max(s.memoryMax ?? 1_073_741_824, m, 1)))
                        .frame(height: 10)
                        .padding(.leading, 2)
                }
                field("Temps processeur", s.cpuSeconds.map { Fmt.duration(Int($0)) } ?? "—")
                field("Redémarrages", String(s.restarts), red: s.restarts > 3)
                field("PID", s.pid.map { String($0) } ?? "—")
                field("Ports", s.ports.isEmpty ? "aucun" : s.ports.map { String($0) }.joined(separator: ", "))
                field("Famille", s.categoryLabel)
            }

            TypedRule()

            Text("DERNIERS ÉVÉNEMENTS (48 H)")
                .font(.custom("AmericanTypewriter-Bold", size: 12))
                .underline()
                .foregroundStyle(Palette.ribbonBlack)

            logSection
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                Palette.paper
                Image(uiImage: Textures.paper).resizable(resizingMode: .tile)
                // perforations de classeur
                VStack(spacing: 70) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Color(hex: 0x6B4A2C)).frame(width: 9, height: 9)
                            .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 1))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.leading, 5)
                .padding(.top, 60)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
    }

    @ViewBuilder private var logSection: some View {
        if let logs {
            if logs.isEmpty {
                Text("Rien à signaler.")
                    .font(.custom("AmericanTypewriter", size: 12))
                    .foregroundStyle(Palette.ribbonBlack.opacity(0.7))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(logs.prefix(25)) { e in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(Fmt.clock(e.time))
                                .font(.custom("AmericanTypewriter", size: 10.5))
                                .foregroundStyle(Palette.ribbonBlack.opacity(0.55))
                            Text(e.message + (e.count > 1 ? "  ×\(e.count)" : ""))
                                .font(.custom(e.level == "info" ? "AmericanTypewriter" : "AmericanTypewriter-Bold", size: 11.5))
                                .foregroundStyle(e.level == "info" ? Palette.ribbonBlack.opacity(0.85) : Palette.ribbonRed)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().tint(Palette.ribbonBlack)
                Text("Consultation du journal…")
                    .font(.custom("AmericanTypewriter", size: 12))
                    .foregroundStyle(Palette.ribbonBlack.opacity(0.7))
            }
        }
    }

    // MARK: Commande

    @ViewBuilder private var commandPlate: some View {
        let s = current
        if s.canRestart {
            Plate(title: "Commande") {
                HStack(alignment: .center, spacing: 16) {
                    SafetyCoverButton(label: "Redémarrer", busy: restartBusy) { restart() }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            LED(color: restartLEDColor, on: restartBusy || restartMessage != nil, size: 8, blinking: restartBusy)
                            Engraved(text: restartBusy ? "En cours…" : (restartMessage == nil ? "Prêt" : (restartOK ? "Effectué" : "Échec")), size: 9)
                        }
                        Text(restartMessage ?? "Soulève le capot rouge, puis appuie sur le champignon pour relancer « \(s.title) ».")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color(hex: 0x2C2F33, opacity: 0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        } else {
            Plate(title: "Commande verrouillée", style: .anodized) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(Palette.ledAmber)
                    Text("Redémarrer « \(s.title) » depuis l'app couperait la liaison avec le serveur.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var restartLEDColor: Color {
        if restartBusy { return Palette.ledAmber }
        return restartOK ? Palette.ledGreen : Palette.ledRed
    }

    private func restart() {
        restartBusy = true
        restartMessage = nil
        Task {
            let error = await store.restart(current)
            restartBusy = false
            restartOK = error == nil
            restartMessage = error ?? "Service relancé à \(Fmt.clock(Int(Date().timeIntervalSince1970)))."
            if error == nil { Haptics.success() } else { Haptics.error() }
            logs = await store.fetchLogs(unit: service.name)
        }
    }

    // MARK: Aides

    private func field(_ label: String, _ value: String, red: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(.custom("AmericanTypewriter", size: 12.5))
                .foregroundStyle(Palette.ribbonBlack.opacity(0.7))
                .lineLimit(1)
                .fixedSize()
            DottedLeader()
                .stroke(Palette.ribbonBlack.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [1, 3]))
                .frame(height: 1)
            Text(value)
                .font(.custom("AmericanTypewriter-Bold", size: 12.5))
                .foregroundStyle(red ? Palette.ribbonRed : Palette.ribbonBlack)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private func ficheNumber(_ s: Service) -> Int {
        s.name.unicodeScalars.reduce(0) { ($0 * 31 + Int($1.value)) % 9000 } + 1000
    }

    private func memoryText(_ s: Service) -> String {
        guard let m = s.memory else { return "—" }
        if let max = s.memoryMax { return "\(Fmt.bytes(m)) / \(Fmt.bytes(max))" }
        return Fmt.bytes(m)
    }

    private func stampColor(_ s: Service) -> Color {
        switch s.state {
        case "running": return Color(hex: 0x1F7A3A)
        case "failed": return Palette.ribbonRed
        case "done": return Color(hex: 0x1E4FA8)
        default: return Color(hex: 0x6B6B6B)
        }
    }
}

/// Pince métallique du porte-bloc.
private struct Clip: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.66), Color(white: 0.86), Color(white: 0.5)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 150, height: 46)
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.3), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.5), radius: 5, x: 0, y: 5)
            Capsule()
                .stroke(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.45)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 4)
                .frame(width: 70, height: 26)
                .offset(y: -22)
            HStack(spacing: 96) {
                Screw(size: 8, angle: 40)
                Screw(size: 8, angle: -20)
            }
            Engraved(text: "Dipherant", size: 9)
        }
    }
}

/// Barre « crayonnée » à hachures.
private struct PencilBar: View {
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width * CGFloat(min(max(fraction, 0), 1))
            ZStack(alignment: .leading) {
                Rectangle()
                    .stroke(Palette.ribbonBlack.opacity(0.6), lineWidth: 1)
                Hatch()
                    .stroke(Palette.ribbonBlack.opacity(0.55), lineWidth: 0.8)
                    .frame(width: w)
                    .clipped()
            }
        }
    }

    private struct Hatch: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            var x = rect.minX - rect.height
            while x < rect.maxX {
                p.move(to: CGPoint(x: x, y: rect.maxY))
                p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                x += 3.5
            }
            return p
        }
    }
}

/// Ligne tapée « - - - - » à la machine.
struct TypedRule: View {
    var body: some View {
        DottedLeader()
            .stroke(Palette.ribbonBlack.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
            .frame(height: 1)
    }
}
