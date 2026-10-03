import AudioToolbox
import SwiftUI

/// Guide vers l'appareil : flèche directionnelle (façon Recherche précise) ou jauge de proximité.
struct FinderView: View {
    @EnvironmentObject private var scanner: BluetoothScanner
    @EnvironmentObject private var store: DeviceStore
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.finderSound) private var sound = false
    @AppStorage("finderArrowMode") private var arrowMode = true
    let deviceID: UUID

    @StateObject private var direction = DirectionFinder()

    var body: some View {
        let device = scanner.devices[deviceID]
        let stale = device?.isStale(now: scanner.now) ?? true
        let level = stale ? 0 : (device?.signalLevel ?? 0)

        VStack(spacing: 16) {
            Picker("Mode", selection: $arrowMode) {
                Text("Flèche").tag(true)
                Text("Jauge").tag(false)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if arrowMode {
                ArrowFinderContent(direction: direction, device: device, stale: stale, level: level)
            } else {
                GaugeFinderContent(device: device, stale: stale, level: level)
            }

            HStack(spacing: 16) {
                Toggle(isOn: $haptics) {
                    Label("Vibrations", systemImage: "iphone.radiowaves.left.and.right")
                }
                .toggleStyle(.button)
                Toggle(isOn: $sound) {
                    Label("Son", systemImage: "speaker.wave.2")
                }
                .toggleStyle(.button)
                if arrowMode {
                    Button {
                        direction.reset()
                    } label: {
                        Label("Recommencer", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .tint(arrowMode ? .white : .accentColor)
            .padding(.bottom)
        }
        .padding(.top)
        .background {
            if arrowMode {
                arrowBackground(level: level, stale: stale)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.6), value: level)
            }
        }
        .navigationTitle(device.map { store.displayName(for: $0) } ?? "Localiser")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !scanner.isScanning { scanner.startScan() }
            UIApplication.shared.isIdleTimerDisabled = true
            direction.start()
        }
        .onDisappear {
            direction.stop()
            UIApplication.shared.isIdleTimerDisabled = UserDefaults.standard.bool(forKey: SettingsKey.keepScreenOn)
        }
        .onChange(of: scanner.now) { _ in
            if let device = scanner.devices[deviceID] {
                direction.ingest(device.rssiHistory)
            }
        }
        .task {
            await feedbackLoop()
        }
    }

    private func arrowBackground(level: Double, stale: Bool) -> Color {
        if stale { return Color(white: 0.12) }
        let aligned = direction.hasDirection && abs(direction.relativeAngle) < .pi / 8
        // Du rouge-orangé (loin) au vert (tout près), plus lumineux quand on fait face à l'appareil.
        return Color(hue: 0.03 + 0.30 * level, saturation: 0.75, brightness: aligned ? 0.62 : 0.42)
    }

    private func feedbackLoop() async {
        while !Task.isCancelled {
            let device = scanner.devices[deviceID]
            let level = device.map { $0.isStale(now: Date()) ? 0 : $0.signalLevel } ?? 0
            if level > 0 {
                if haptics {
                    Haptics.impact(intensity: 0.3 + 0.7 * level)
                }
                if sound {
                    AudioServicesPlaySystemSound(1104)
                }
            }
            // De 1,6 s (loin) à 0,15 s (tout près), comme un compteur Geiger.
            let interval = 1.6 - 1.45 * level
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                return
            }
        }
    }
}

// MARK: - Mode flèche

private struct ArrowFinderContent: View {
    @ObservedObject var direction: DirectionFinder
    let device: BluetoothDevice?
    let stale: Bool
    let level: Double

    @State private var pulse = false

    private var isHere: Bool {
        guard let device, !stale else { return false }
        return device.estimatedDistance < 0.5 || level > 0.9
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            ZStack {
                if stale {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 90, weight: .semibold))
                        .opacity(0.7)
                } else if isHere {
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 220, height: 220)
                        .scaleEffect(pulse ? 1.1 : 0.85)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 120, height: 120)
                } else if direction.hasDirection {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 170, weight: .bold))
                        .rotationEffect(.radians(direction.arrowAngle))
                        .animation(.interpolatingSpring(stiffness: 120, damping: 16), value: direction.arrowAngle)
                        .opacity(0.45 + 0.55 * direction.confidence)
                } else {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 14)
                        .frame(width: 200, height: 200)
                    Circle()
                        .trim(from: 0, to: min(direction.coverage / 0.6, 1))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 200, height: 200)
                        .animation(.easeOut, value: direction.coverage)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 64, weight: .semibold))
                        .rotationEffect(.degrees(pulse ? 360 : 0))
                        .animation(.linear(duration: 4).repeatForever(autoreverses: false), value: pulse)
                }
            }
            .frame(height: 260)

            VStack(spacing: 6) {
                Text(headline)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(subtitle)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                if let device, !stale {
                    Text("\(device.rssi) dBm")
                        .font(.subheadline.monospacedDigit())
                        .opacity(0.7)
                }
            }

            Spacer(minLength: 0)

            Text(footnote)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .opacity(0.75)
                .padding(.horizontal, 24)
        }
        .foregroundStyle(.white)
        .onAppear { pulse = true }
    }

    private var headline: String {
        if stale { return "—" }
        if isHere { return "Ici" }
        return device?.estimatedDistance.formattedDistance ?? "—"
    }

    private var subtitle: String {
        if stale { return "Signal perdu" }
        if isHere { return "L'appareil est tout près de vous" }
        if !direction.isAvailable { return "Gyroscope indisponible" }
        guard direction.hasDirection else { return "Tournez lentement sur vous-même" }
        let degrees = direction.relativeAngle * 180 / .pi
        switch abs(degrees) {
        case ..<20: return "Devant vous"
        case 150...: return "Derrière vous"
        default:
            if abs(degrees) < 60 {
                return degrees > 0 ? "Légèrement à droite" : "Légèrement à gauche"
            }
            return degrees > 0 ? "À droite" : "À gauche"
        }
    }

    private var footnote: String {
        if direction.hasDirection {
            return "Marchez dans la direction de la flèche. Si elle hésite, refaites un tour complet sur vous-même, téléphone devant vous."
        }
        return "Tenez le téléphone devant vous et faites un tour complet lentement (environ 10 secondes). Votre corps bloque une partie du signal, ce qui révèle la direction."
    }
}

// MARK: - Mode jauge

private struct GaugeFinderContent: View {
    let device: BluetoothDevice?
    let stale: Bool
    let level: Double

    @State private var pulse = false

    var body: some View {
        let color = stale ? Color.gray : (device?.signalColor ?? .gray)

        VStack(spacing: 24) {
            Spacer(minLength: 0)

            ZStack {
                ForEach(0..<3) { index in
                    Circle()
                        .stroke(color.opacity(0.4), lineWidth: 2)
                        .scaleEffect(pulse ? 1.25 + CGFloat(index) * 0.15 : 0.7)
                        .opacity(pulse ? 0 : 0.8)
                        .animation(
                            .easeOut(duration: 1.6)
                                .repeatForever(autoreverses: false)
                                .delay(Double(index) * 0.5),
                            value: pulse
                        )
                }
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: level)
                    .stroke(color, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: level)
                VStack(spacing: 6) {
                    Text(stale ? "—" : (device?.estimatedDistance.formattedDistance ?? "—"))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if let device {
                        Text("\(device.rssi) dBm")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(proximityLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 250, height: 250)

            trendView

            Text("Déplacez-vous lentement : le signal augmente quand vous vous rapprochez. Votre corps atténue le signal.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .onAppear { pulse = true }
    }

    @ViewBuilder
    private var trendView: some View {
        let trend = device?.trend ?? 0
        if stale {
            Label("Signal perdu", systemImage: "antenna.radiowaves.left.and.right.slash")
                .foregroundStyle(.secondary)
        } else if trend > 2 {
            Label("Vous vous rapprochez", systemImage: "arrow.up.circle.fill")
                .foregroundStyle(.green)
        } else if trend < -2 {
            Label("Vous vous éloignez", systemImage: "arrow.down.circle.fill")
                .foregroundStyle(.red)
        } else {
            Label("Signal stable", systemImage: "equal.circle.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var proximityLabel: String {
        if stale { return "Hors de portée" }
        switch level {
        case 0.85...: return "Brûlant !"
        case 0.6..<0.85: return "Très proche"
        case 0.35..<0.6: return "Proche"
        case 0.15..<0.35: return "Loin"
        default: return "Très loin"
        }
    }
}
