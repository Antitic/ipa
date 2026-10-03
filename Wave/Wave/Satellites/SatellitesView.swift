import SwiftUI
import CoreLocation

struct SatellitesView: View {
    @StateObject private var store = SatelliteStore()
    @StateObject private var loc = LocationProvider()
    @State private var followCompass = false
    @State private var hidden: Set<Constellation> = []
    @State private var selected: SatPosition?

    var body: some View {
        // Calculé une seule fois par rendu (auparavant recalculé et retrié pour chaque ligne).
        let visible = store.positions
            .filter { $0.el > 0 && !hidden.contains($0.sat.constellation) }
            .sorted { $0.el > $1.el }
        let counts = Dictionary(grouping: store.positions.filter { $0.el > 0 }, by: { $0.sat.constellation })
            .mapValues(\.count)
        let now = Date()
        let passes = store.issPasses.filter { $0.end > now }

        ScrollView {
            VStack(spacing: 16) {
                header
                skyCard(visible)
                legend(counts)
                if !passes.isEmpty { issCard(passes) }
                listCard(visible)
                Text("Positions calculées à partir des orbites publiées par CelesTrak, pas captées par le téléphone : iOS ne donne pas accès aux signaux GNSS reçus.")
                    .font(.caption2)
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .waveScreen(.satellites)
        .navigationTitle("Satellites")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await store.load(force: true)
                        refresh()
                    }
                } label: {
                    if store.loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(store.loading)
            }
        }
        .task {
            loc.start()
            await store.load()
            refresh()
            // Mise à jour des positions toutes les 2 secondes tant que l'écran est affiché.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                refresh()
            }
        }
        // Corrige le gel : l'ancien `.onReceive(loc.$location.compactMap{$0}.first())` recréait
        // un abonnement à chaque rendu, qui relançait un calcul, qui provoquait un nouveau
        // rendu… en boucle infinie dès que la position et les orbites étaient disponibles.
        .onChange(of: loc.location == nil) { _, isNil in
            if !isNil { refresh() }
        }
        .onDisappear { loc.stop() }
        .sheet(item: $selected) { pos in
            SatelliteDetail(position: pos)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(28)
        }
    }

    private func refresh() {
        guard let l = loc.location else { return }
        store.recompute(for: l)
    }

    // MARK: Sections

    @ViewBuilder private var header: some View {
        if loc.status == .denied || loc.status == .restricted {
            Card {
                Label("Localisation refusée", systemImage: "location.slash.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.danger)
                Text("Active la localisation pour Wave dans Réglages pour calculer le ciel au-dessus de toi.")
                    .font(.footnote).foregroundStyle(Theme.dim)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Ouvrir Réglages", destination: url).font(.callout.weight(.semibold))
                }
            }
        } else if loc.location == nil {
            Card {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Recherche de ta position…").foregroundStyle(Theme.dim)
                }
            }
        }
        if let err = store.error {
            Card {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warn)
                    .font(.footnote)
            }
        }
    }

    private func skyCard(_ visible: [SatPosition]) -> some View {
        Card {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionTitle(text: "Au-dessus de toi", symbol: "sparkles", color: Theme.indigo)
                    BigNumber(value: "\(visible.count)", unit: "satellites",
                              colors: Feature.satellites.colors, size: 48)
                }
                Spacer()
                Button {
                    withAnimation(.spring) { followCompass.toggle() }
                } label: {
                    Image(systemName: followCompass ? "location.north.line.fill" : "location.north.line")
                }
                .buttonStyle(CircleIconButtonStyle(color: followCompass ? Theme.indigo : .primary))
                .disabled(loc.heading == nil)
                .accessibilityLabel("Orienter avec la boussole")
            }
            SkyPlot(positions: visible,
                    rotation: followCompass ? -(loc.heading ?? 0) : 0,
                    onTap: { selected = $0 })
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if store.loading && store.positions.isEmpty {
                        VStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("Chargement des orbites…").font(.caption).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                }
            if let d = store.dataDate {
                Label("Orbites mises à jour \(d.shortAgo)", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private func legend(_ counts: [Constellation: Int]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Constellation.allCases) { c in
                    let isHidden = hidden.contains(c)
                    Button {
                        withAnimation(.snappy) {
                            if isHidden { hidden.remove(c) } else { hidden.insert(c) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(c.color).frame(width: 8, height: 8)
                            Text("\(c.flag) \(c.rawValue)")
                            Text("\(counts[c] ?? 0)")
                                .monospacedDigit()
                                .foregroundStyle(isHidden ? Theme.dim : c.color)
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(isHidden ? Theme.card : c.color.opacity(0.14), in: Capsule())
                        .overlay(Capsule().strokeBorder(isHidden ? Theme.stroke : c.color.opacity(0.35), lineWidth: 1))
                        .opacity(isHidden ? 0.55 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private func issCard(_ passes: [Pass]) -> some View {
        Card {
            HStack(spacing: 12) {
                IconTile(symbol: "airplane", colors: [Theme.violet, Theme.indigo], size: 36)
                Text("Prochains passages de l'ISS")
                    .font(.system(.headline, design: .rounded))
            }
            ForEach(passes.prefix(4)) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.start.formatted(.dateTime.weekday(.wide).hour().minute()).capitalized)
                            .font(.callout.weight(.semibold))
                        Text("\(compassName(p.startAz)) → \(compassName(p.endAz)) · \(max(1, Int(p.end.timeIntervalSince(p.start) / 60))) min")
                            .font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Pill(text: "max \(Int(p.maxEl))°", color: p.maxEl > 45 ? Theme.green : Theme.blue)
                }
                if p.id != passes.prefix(4).last?.id { Divider() }
            }
            Text("Visible à l'œil nu surtout à l'aube et au crépuscule, quand l'ISS est éclairée et le ciel sombre.")
                .font(.caption2).foregroundStyle(Theme.dim)
        }
    }

    private func listCard(_ visible: [SatPosition]) -> some View {
        Card {
            SectionTitle(text: "Liste", symbol: "list.bullet")
            if visible.isEmpty {
                Text(store.loading ? "Chargement des orbites…" : "Aucun satellite à afficher.")
                    .foregroundStyle(Theme.dim).font(.callout)
            }
            let lastID = visible.last?.id
            ForEach(visible) { p in
                Button { selected = p } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(p.sat.constellation.color.gradient)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Text(p.sat.constellation == .iss ? "🛰️" : String(p.sat.constellation.rawValue.prefix(1)))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                            )
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.sat.shortName).font(.callout.weight(.semibold))
                            Text(p.sat.constellation.rawValue).font(.caption2).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(Int(p.el))°").font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                            Text("\(compassName(p.az)) · \(Int(p.az))°").font(.caption2.monospacedDigit()).foregroundStyle(Theme.dim)
                        }
                        Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if p.id != lastID { Divider().padding(.leading, 42) }
            }
        }
    }
}

/// Carte du ciel : un disque « ciel de nuit » (toujours sombre, en clair comme en sombre).
struct SkyPlot: View {
    let positions: [SatPosition]
    let rotation: Double
    let onTap: (SatPosition) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = size / 2 - 22
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 0.13, green: 0.16, blue: 0.38), Color(red: 0.03, green: 0.04, blue: 0.12)],
                        center: .center, startRadius: 0, endRadius: r * 1.1))
                    .frame(width: 2 * r + 36, height: 2 * r + 36)
                    .position(c)
                    .shadow(color: Theme.indigo.opacity(0.35), radius: 16, y: 6)

                // Cercles d'élévation 0°, 30°, 60°
                ForEach([1.0, 2.0 / 3.0, 1.0 / 3.0], id: \.self) { f in
                    Circle()
                        .stroke(Color.white.opacity(0.13), style: StrokeStyle(lineWidth: 1, dash: f == 1 ? [] : [3, 4]))
                        .frame(width: 2 * r * f, height: 2 * r * f)
                        .position(c)
                }
                Path { p in
                    p.move(to: CGPoint(x: c.x - r, y: c.y)); p.addLine(to: CGPoint(x: c.x + r, y: c.y))
                    p.move(to: CGPoint(x: c.x, y: c.y - r)); p.addLine(to: CGPoint(x: c.x, y: c.y + r))
                }
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                .rotationEffect(.degrees(rotation), anchor: UnitPoint(x: c.x / geo.size.width, y: c.y / geo.size.height))

                ForEach(0..<4, id: \.self) { i in
                    let label = ["N", "E", "S", "O"][i]
                    let pt = point(az: Double(i) * 90, el: -10, center: c, radius: r)
                    Text(label)
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                        .foregroundStyle(i == 0 ? Theme.red : Color.white.opacity(0.7))
                        .position(pt)
                }

                ForEach(positions) { p in
                    let pt = point(az: p.az, el: p.el, center: c, radius: r)
                    let isISS = p.sat.constellation == .iss
                    Button { onTap(p) } label: {
                        VStack(spacing: 2) {
                            Circle()
                                .fill(p.sat.constellation.color)
                                .frame(width: isISS ? 14 : 9, height: isISS ? 14 : 9)
                                .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: isISS ? 2 : 1))
                                .shadow(color: p.sat.constellation.color, radius: 6)
                            Text(isISS ? "ISS" : p.sat.shortName)
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: pt.x, y: pt.y + 5)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: rotation)
        }
    }

    private func point(az: Double, el: Double, center: CGPoint, radius: CGFloat) -> CGPoint {
        let d = radius * CGFloat((90 - el) / 90)
        let a = (az + rotation) * .pi / 180
        return CGPoint(x: center.x + d * CGFloat(sin(a)), y: center.y - d * CGFloat(cos(a)))
    }
}

struct SatelliteDetail: View {
    let position: SatPosition

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(position.sat.constellation.color.gradient)
                            .frame(width: 52, height: 52)
                            .overlay(Text(position.sat.constellation.flag).font(.title2))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(position.sat.name).font(.system(.headline, design: .rounded))
                            Text(position.sat.constellation.rawValue).font(.subheadline).foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(.vertical, 4)
                    InfoRow(label: "N° NORAD", value: "\(position.sat.id)", mono: true)
                }
                Section("Dans ton ciel") {
                    InfoRow(label: "Élévation", value: String(format: "%.1f°", position.el))
                    InfoRow(label: "Azimut", value: String(format: "%.1f° (%@)", position.az, compassName(position.az)))
                    InfoRow(label: "Distance", value: "\(Int(position.range).formatted()) km")
                    InfoRow(label: "Altitude", value: "\(Int(position.altitude).formatted()) km")
                }
                Section("Orbite") {
                    InfoRow(label: "Inclinaison", value: String(format: "%.2f°", position.sat.i * 180 / .pi))
                    InfoRow(label: "Période", value: String(format: "%.1f min", 2 * .pi / position.sat.n / 60))
                    InfoRow(label: "Excentricité", value: String(format: "%.5f", position.sat.e))
                    InfoRow(label: "Éléments du", value: position.sat.epoch.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .navigationTitle(position.sat.shortName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
