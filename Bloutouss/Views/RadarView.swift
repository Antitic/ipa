import SwiftUI

struct RadarView: View {
    @EnvironmentObject private var scanner: BluetoothScanner
    @EnvironmentObject private var store: DeviceStore
    @State private var onlyFavorites = false
    @State private var showLabels = true

    private let maxDistance = 30.0
    private let rings: [Double] = [1, 3, 10, 30]

    private var visibleDevices: [BluetoothDevice] {
        scanner.devices.values
            .filter { !$0.isStale(now: scanner.now) }
            .filter { !onlyFavorites || store.isFavorite($0.id) }
            .sorted { $0.smoothedRSSI < $1.smoothedRSSI }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GeometryReader { geometry in
                    let size = min(geometry.size.width, geometry.size.height)
                    let radius = size / 2 - 20
                    let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

                    ZStack {
                        ForEach(rings, id: \.self) { distance in
                            let ringRadius = scaledRadius(distance, radius: radius)
                            Circle()
                                .stroke(Color.green.opacity(0.35), lineWidth: 1)
                                .frame(width: ringRadius * 2, height: ringRadius * 2)
                                .position(center)
                            Text("\(Int(distance)) m")
                                .font(.caption2)
                                .foregroundStyle(Color.green.opacity(0.8))
                                .position(x: center.x + 14, y: center.y - ringRadius + 8)
                        }

                        Path { path in
                            path.move(to: CGPoint(x: center.x - radius, y: center.y))
                            path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
                            path.move(to: CGPoint(x: center.x, y: center.y - radius))
                            path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
                        }
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)

                        if scanner.isScanning {
                            RadarSweep(radius: radius)
                                .position(center)
                        }

                        ForEach(visibleDevices) { device in
                            let position = blipPosition(for: device, center: center, radius: radius)
                            NavigationLink(value: Route.device(device.id)) {
                                RadarBlip(
                                    device: device,
                                    name: store.displayName(for: device),
                                    isFavorite: store.isFavorite(device.id),
                                    showLabel: showLabels && (store.isFavorite(device.id) || device.estimatedDistance < 3)
                                )
                            }
                            .buttonStyle(.plain)
                            .position(position)
                            .animation(.easeInOut(duration: 0.8), value: position)
                        }

                        Circle()
                            .fill(Color.blue)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .position(center)
                    }
                }
                .background(Color.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal)

                HStack {
                    Text("\(visibleDevices.count) appareil\(visibleDevices.count > 1 ? "s" : "") à portée")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle(isOn: $showLabels) {
                        Image(systemName: "textformat")
                    }
                    .toggleStyle(.button)
                    Toggle(isOn: $onlyFavorites) {
                        Image(systemName: "star")
                    }
                    .toggleStyle(.button)
                }
                .padding(.horizontal)

                Text("La distance est estimée ; la direction est arbitraire (le Bluetooth ne donne pas l'orientation).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            .navigationTitle("Radar")
            .bloutoussDestinations()
        }
    }

    /// Échelle logarithmique pour bien voir les appareils proches.
    private func scaledRadius(_ distance: Double, radius: CGFloat) -> CGFloat {
        let clamped = min(max(distance, 0), maxDistance)
        return radius * CGFloat(log10(1 + clamped) / log10(1 + maxDistance))
    }

    private func blipPosition(for device: BluetoothDevice, center: CGPoint, radius: CGFloat) -> CGPoint {
        // Angle stable propre à chaque appareil, dérivé de son identifiant.
        let bytes = device.id.uuid
        let angle = (Double(bytes.0) * 256 + Double(bytes.1)) / 65_536 * 2 * .pi
        let distance = scaledRadius(device.estimatedDistance, radius: radius)
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * distance,
            y: center.y + CGFloat(sin(angle)) * distance
        )
    }
}

private struct RadarSweep: View {
    let radius: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let angle = seconds.truncatingRemainder(dividingBy: 4) / 4 * 360
            Circle()
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.green.opacity(0), location: 0),
                            .init(color: Color.green.opacity(0), location: 0.8),
                            .init(color: Color.green.opacity(0.45), location: 1),
                        ]),
                        center: .center
                    )
                )
                .frame(width: radius * 2, height: radius * 2)
                .rotationEffect(.degrees(angle))
        }
        .allowsHitTesting(false)
    }
}

private struct RadarBlip: View {
    let device: BluetoothDevice
    let name: String
    let isFavorite: Bool
    let showLabel: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(isFavorite ? Color.yellow : device.signalColor)
                    .frame(width: 24, height: 24)
                    .shadow(color: (isFavorite ? Color.yellow : device.signalColor).opacity(0.8), radius: 6)
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
            }
            if showLabel {
                Text(name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 80)
            }
        }
    }
}
