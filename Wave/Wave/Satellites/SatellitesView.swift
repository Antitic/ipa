import SwiftUI
import Combine
import CoreLocation

struct SatellitesView: View {
    @StateObject private var store = SatelliteStore()
    @StateObject private var loc = LocationProvider()
    @State private var followCompass = false
    @State private var hidden: Set<Constellation> = []
    @State private var selected: SatPosition?

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var visible: [SatPosition] {
        store.positions
            .filter { $0.el > 0 && !hidden.contains($0.sat.constellation) }
            .sorted { $0.el > $1.el }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                skyCard
                legend
                if !store.issPasses.isEmpty { issCard }
                listCard
                Text("Positions calculées à partir des orbites publiées par CelesTrak, pas captées par le téléphone. iOS ne donne pas accès aux signaux GNSS reçus.")
                    .font(.caption2)
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .waveScreen()
        .navigationTitle("Satellites")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.load(force: true); refresh() }
                } label: {
                    if store.loading { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .task {
            loc.start()
            await store.load()
            refresh()
        }
        .onReceive(timer) { _ in refresh() }
        .onReceive(loc.$location.compactMap { $0 }.first()) { _ in refresh() }
        .onDisappear { loc.stop() }
        .sheet(item: $selected) { pos in
            SatelliteDetail(position: pos)
                .presentationDetents([.medium])
        }
    }

    private func refresh() {
        guard let l = loc.location, !store.satellites.isEmpty else { return }
        store.recompute(for: l)
    }

    // MARK: Sections

    @ViewBuilder private var header: some View {
        if loc.status == .denied || loc.status == .restricted {
            Card {
                Label("Localisation refusée", systemImage: "location.slash")
                    .foregroundStyle(Theme.danger)
                Text("Active la localisation pour Wave dans Réglages pour calculer le ciel au-dessus de toi.")
                    .font(.footnote).foregroundStyle(Theme.dim)
            }
        } else if loc.location == nil {
            Card {
                HStack { ProgressView(); Text("Recherche de ta position…").foregroundStyle(Theme.dim) }
            }
        }
        if let err = store.error {
            Card {
                Label(err, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.warn).font(.footnote)
            }
        }
    }

    private var skyCard: some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(visible.count)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("satellites au-dessus de l'horizon").font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                Toggle(isOn: $followCompass) {
                    Image(systemName: "location.north.line")
                }
                .toggleStyle(.button)
                .disabled(loc.heading == nil)
            }
            SkyPlot(positions: visible,
                    rotation: followCompass ? -(loc.heading ?? 0) : 0,
                    onTap: { selected = $0 })
                .aspectRatio(1, contentMode: .fit)
            if let d = store.dataDate {
                Text("Orbites mises à jour \(d.shortAgo)").font(.caption2).foregroundStyle(Theme.dim)
            }
        }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Constellation.allCases) { c in
                    let count = store.positions.filter { $0.sat.constellation == c && $0.el > 0 }.count
                    Button {
                        if hidden.contains(c) { hidden.remove(c) } else { hidden.insert(c) }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(c.color).frame(width: 8, height: 8)
                            Text("\(c.flag) \(c.rawValue) \(count)").font(.footnote.weight(.medium))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(hidden.contains(c) ? Theme.faint : c.color.opacity(0.15), in: Capsule())
                        .opacity(hidden.contains(c) ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var issCard: some View {
        Card {
            Label("Prochains passages de l'ISS", systemImage: "airplane")
                .font(.headline)
            ForEach(store.issPasses.prefix(4)) { p in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                            .font(.callout.weight(.semibold))
                        Text("\(compassName(p.startAz)) → \(compassName(p.endAz)) · \(Int(p.end.timeIntervalSince(p.start) / 60)) min")
                            .font(.caption).foregroundStyle(Theme.dim)
                    }
                    Spacer()
                    Pill(text: "max \(Int(p.maxEl))°", color: p.maxEl > 45 ? Theme.accent : Theme.blue)
                }
            }
            Text("Visible à l'œil nu surtout à l'aube et au crépuscule, quand l'ISS est éclairée et le ciel sombre.")
                .font(.caption2).foregroundStyle(Theme.dim)
        }
    }

    private var listCard: some View {
        Card {
            Text("Liste").font(.headline)
            if visible.isEmpty {
                Text(store.loading ? "Chargement des orbites…" : "Aucun satellite à afficher.")
                    .foregroundStyle(Theme.dim).font(.callout)
            }
            ForEach(visible) { p in
                Button { selected = p } label: {
                    HStack(spacing: 10) {
                        Circle().fill(p.sat.constellation.color).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.sat.shortName).font(.callout.weight(.semibold))
                            Text(p.sat.constellation.rawValue).font(.caption2).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("\(Int(p.el))° haut").font(.callout.monospacedDigit())
                            Text("\(compassName(p.az)) · \(Int(p.az))°").font(.caption2.monospacedDigit()).foregroundStyle(Theme.dim)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if p.id != visible.last?.id { Divider().overlay(Theme.faint) }
            }
        }
    }
}

struct SkyPlot: View {
    let positions: [SatPosition]
    let rotation: Double
    let onTap: (SatPosition) -> Void

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let r = size / 2 - 18
            let c = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                // Cercles d'élévation 0°, 30°, 60°
                ForEach([1.0, 2.0 / 3.0, 1.0 / 3.0], id: \.self) { f in
                    Circle()
                        .stroke(Theme.faint, lineWidth: 1)
                        .frame(width: 2 * r * f, height: 2 * r * f)
                        .position(c)
                }
                Circle()
                    .fill(RadialGradient(colors: [Theme.blue.opacity(0.12), .clear], center: .center, startRadius: 0, endRadius: r))
                    .frame(width: 2 * r, height: 2 * r)
                    .position(c)
                Path { p in
                    p.move(to: CGPoint(x: c.x - r, y: c.y)); p.addLine(to: CGPoint(x: c.x + r, y: c.y))
                    p.move(to: CGPoint(x: c.x, y: c.y - r)); p.addLine(to: CGPoint(x: c.x, y: c.y + r))
                }
                .stroke(Theme.faint, lineWidth: 1)
                .rotationEffect(.degrees(rotation), anchor: UnitPoint(x: c.x / geo.size.width, y: c.y / geo.size.height))

                ForEach(0..<4, id: \.self) { i in
                    let label = ["N", "E", "S", "O"][i]
                    let pt = point(az: Double(i) * 90, el: -8, center: c, radius: r)
                    Text(label)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(i == 0 ? Theme.danger : Theme.dim)
                        .position(pt)
                }

                ForEach(positions) { p in
                    let pt = point(az: p.az, el: p.el, center: c, radius: r)
                    Button { onTap(p) } label: {
                        VStack(spacing: 1) {
                            Circle()
                                .fill(p.sat.constellation.color)
                                .frame(width: p.sat.constellation == .iss ? 14 : 10,
                                       height: p.sat.constellation == .iss ? 14 : 10)
                                .shadow(color: p.sat.constellation.color, radius: 5)
                            Text(p.sat.constellation == .iss ? "ISS" : p.sat.shortName)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .buttonStyle(.plain)
                    .position(x: pt.x, y: pt.y + 5)
                }
            }
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
                    InfoRow(label: "Constellation", value: "\(position.sat.constellation.flag) \(position.sat.constellation.rawValue)")
                    InfoRow(label: "Nom", value: position.sat.name)
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
            .waveScreen()
            .navigationTitle(position.sat.shortName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
