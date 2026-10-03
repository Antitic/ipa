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

        List {
            header
            Section {
                skyCard(visible)
                legend(counts)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            } footer: {
                if let d = store.dataDate {
                    Text("Orbites CelesTrak mises à jour \(d.shortAgo). Positions calculées, pas captées : iOS ne donne pas accès aux signaux GNSS reçus.")
                }
            }
            if !passes.isEmpty { issSection(passes) }
            listSection(visible)
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
        }
    }

    private func refresh() {
        guard let l = loc.location else { return }
        store.recompute(for: l)
    }

    // MARK: Sections

    @ViewBuilder private var header: some View {
        if loc.status == .denied || loc.status == .restricted {
            Section {
                Label("Localisation refusée", systemImage: "location.slash")
                    .foregroundStyle(.red)
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    Link("Autoriser dans Réglages", destination: url)
                }
            }
        } else if loc.location == nil {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Recherche de ta position…").foregroundStyle(.secondary)
                }
            }
        }
        if let err = store.error {
            Section {
                Label(err, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private func skyCard(_ visible: [SatPosition]) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(visible.count)")
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                Text("satellites au-dessus de l'horizon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(isOn: $followCompass) {
                Image(systemName: "location.north.line")
            }
            .toggleStyle(.button)
            .disabled(loc.heading == nil)
            .accessibilityLabel("Orienter avec la boussole")
        }
        SkyPlot(positions: visible,
                rotation: followCompass ? -(loc.heading ?? 0) : 0,
                onTap: { selected = $0 })
            .aspectRatio(1, contentMode: .fit)
            .padding(.vertical, 4)
            .overlay {
                if store.loading && store.positions.isEmpty {
                    ProgressView("Chargement des orbites…")
                }
            }
    }

    private func legend(_ counts: [Constellation: Int]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Constellation.allCases) { c in
                    let isHidden = hidden.contains(c)
                    Button {
                        if isHidden { hidden.remove(c) } else { hidden.insert(c) }
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(c.color).frame(width: 8, height: 8)
                            Text("\(c.rawValue) \(counts[c] ?? 0)").monospacedDigit()
                        }
                        .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                    .tint(isHidden ? .gray : c.color)
                    .opacity(isHidden ? 0.5 : 1)
                }
            }
        }
    }

    private func issSection(_ passes: [Pass]) -> some View {
        Section {
            ForEach(passes.prefix(4)) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.start.formatted(.dateTime.weekday(.wide).hour().minute()).capitalized)
                        Text("\(compassName(p.startAz)) → \(compassName(p.endAz)) · \(max(1, Int(p.end.timeIntervalSince(p.start) / 60))) min")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("max \(Int(p.maxEl))°")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Prochains passages de l'ISS")
        } footer: {
            Text("Visible à l'œil nu surtout à l'aube et au crépuscule.")
        }
    }

    private func listSection(_ visible: [SatPosition]) -> some View {
        Section("Satellites visibles") {
            if visible.isEmpty {
                Text(store.loading ? "Chargement des orbites…" : "Aucun satellite à afficher.")
                    .foregroundStyle(.secondary)
            }
            ForEach(visible) { p in
                Button { selected = p } label: {
                    HStack(spacing: 12) {
                        Circle().fill(p.sat.constellation.color).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.sat.shortName)
                            Text(p.sat.constellation.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(Int(p.el))°").monospacedDigit()
                            Text("\(compassName(p.az)) · \(Int(p.az))°").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
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
                // Cercles d'élévation 0°, 30°, 60°
                ForEach([1.0, 2.0 / 3.0, 1.0 / 3.0], id: \.self) { f in
                    Circle()
                        .stroke(Color(uiColor: .separator), style: StrokeStyle(lineWidth: 1, dash: f == 1 ? [] : [3, 4]))
                        .frame(width: 2 * r * f, height: 2 * r * f)
                        .position(c)
                }
                Path { p in
                    p.move(to: CGPoint(x: c.x - r, y: c.y)); p.addLine(to: CGPoint(x: c.x + r, y: c.y))
                    p.move(to: CGPoint(x: c.x, y: c.y - r)); p.addLine(to: CGPoint(x: c.x, y: c.y + r))
                }
                .stroke(Color(uiColor: .separator), lineWidth: 0.5)
                .rotationEffect(.degrees(rotation), anchor: UnitPoint(x: c.x / geo.size.width, y: c.y / geo.size.height))

                ForEach(0..<4, id: \.self) { i in
                    let label = ["N", "E", "S", "O"][i]
                    let pt = point(az: Double(i) * 90, el: -10, center: c, radius: r)
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(i == 0 ? Color.red : Color.secondary)
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

                            Text(isISS ? "ISS" : p.sat.shortName)
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
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
            .animation(.easeInOut(duration: 0.3), value: rotation)
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
                        Text(position.sat.constellation.flag).font(.largeTitle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(position.sat.name).font(.headline)
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
