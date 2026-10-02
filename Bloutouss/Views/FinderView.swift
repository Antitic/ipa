import AudioToolbox
import SwiftUI

/// Mode « détecteur » : guide vers l'appareil grâce à la force du signal.
struct FinderView: View {
    @EnvironmentObject private var scanner: BluetoothScanner
    @EnvironmentObject private var store: DeviceStore
    @AppStorage(SettingsKey.haptics) private var haptics = true
    @AppStorage(SettingsKey.finderSound) private var sound = false
    let deviceID: UUID

    @State private var pulse = false

    var body: some View {
        let device = scanner.devices[deviceID]
        let stale = device?.isStale(now: scanner.now) ?? true
        let level = stale ? 0 : (device?.signalLevel ?? 0)
        let color = stale ? Color.gray : (device?.signalColor ?? .gray)

        VStack(spacing: 24) {
            Spacer()

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
                    Text(proximityLabel(level: level, stale: stale))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                }
            }
            .frame(width: 250, height: 250)

            trendView(device: device, stale: stale)

            Text("Déplacez-vous lentement et tournez sur vous-même : le signal augmente quand vous vous rapprochez. Votre corps atténue le signal.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            HStack(spacing: 16) {
                Toggle(isOn: $haptics) {
                    Label("Vibrations", systemImage: "iphone.radiowaves.left.and.right")
                }
                .toggleStyle(.button)
                Toggle(isOn: $sound) {
                    Label("Son", systemImage: "speaker.wave.2")
                }
                .toggleStyle(.button)
            }
            .padding(.bottom)
        }
        .padding()
        .navigationTitle(device.map { store.displayName(for: $0) } ?? "Localiser")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            pulse = true
            if !scanner.isScanning { scanner.startScan() }
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = UserDefaults.standard.bool(forKey: SettingsKey.keepScreenOn)
        }
        .task {
            await feedbackLoop()
        }
    }

    @ViewBuilder
    private func trendView(device: BluetoothDevice?, stale: Bool) -> some View {
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

    private func proximityLabel(level: Double, stale: Bool) -> String {
        if stale { return "Hors de portée" }
        switch level {
        case 0.85...: return "Brûlant !"
        case 0.6..<0.85: return "Très proche"
        case 0.35..<0.6: return "Proche"
        case 0.15..<0.35: return "Loin"
        default: return "Très loin"
        }
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
