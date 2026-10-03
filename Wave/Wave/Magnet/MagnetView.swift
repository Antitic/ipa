import SwiftUI
import CoreMotion

final class MagnetModel: ObservableObject {
    @Published var field: Double = 0                     // µT
    @Published var vector = SIMD3<Double>(0, 0, 0)
    @Published var history: [Double] = []
    @Published var calibrated = false
    @Published var baseline: Double?
    @Published var available = true

    private let motion = CMMotionManager()
    private var lastCalibrated = Date.distantPast

    func start() {
        available = motion.isMagnetometerAvailable || motion.isDeviceMotionAvailable
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 30
            motion.showsDeviceMovementDisplay = true
            motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] m, _ in
                guard let self, let m else { return }
                let f = m.magneticField
                guard f.accuracy != .uncalibrated else { return }
                let v = SIMD3(f.field.x, f.field.y, f.field.z)
                if (v * v).sum() > 0 {
                    self.lastCalibrated = Date()
                    self.update(v, calibrated: true)
                }
            }
        }
        if motion.isMagnetometerAvailable {
            motion.magnetometerUpdateInterval = 1.0 / 30
            motion.startMagnetometerUpdates(to: .main) { [weak self] d, _ in
                guard let self, let d else { return }
                // Valeur brute (inclut le biais de l'iPhone) : utilisée seulement sans calibration.
                if Date().timeIntervalSince(self.lastCalibrated) > 1 {
                    self.update(SIMD3(d.magneticField.x, d.magneticField.y, d.magneticField.z), calibrated: false)
                }
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        motion.stopMagnetometerUpdates()
    }

    private func update(_ v: SIMD3<Double>, calibrated: Bool) {
        vector = v
        let magnitude = (v * v).sum().squareRoot()
        field = field == 0 ? magnitude : field * 0.7 + magnitude * 0.3
        self.calibrated = calibrated
        history.append(field)
        if history.count > 300 { history.removeFirst(history.count - 300) }
    }

    func tare() { baseline = field }
    var delta: Double { abs(field - (baseline ?? field)) }
}

struct MagnetView: View {
    @StateObject private var model = MagnetModel()
    @StateObject private var tone = ToneGenerator()
    @State private var mode: Mode = .field
    @State private var sound = false

    enum Mode: String, CaseIterable, Identifiable {
        case field = "Champ magnétique"
        case metal = "Détecteur de métaux"
        var id: String { rawValue }
    }

    private let earthField = 47.0   // valeur typique en Île-de-France, en µT

    private var anomaly: Double { abs(model.field - earthField) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .field { fieldCard } else { metalCard }

                Card {
                    Text("Composantes").font(.headline)
                    HStack {
                        axis("X", model.vector.x)
                        axis("Y", model.vector.y)
                        axis("Z", model.vector.z)
                    }
                    if !model.calibrated {
                        Label("Magnétomètre non calibré : fais des 8 avec l'iPhone pendant quelques secondes.",
                              systemImage: "infinity")
                            .font(.caption).foregroundStyle(Theme.warn)
                    }
                }
            }
            .padding(16)
        }
        .waveScreen()
        .navigationTitle("Magnéto")
        .onAppear { model.start() }
        .onDisappear {
            model.stop()
            tone.stop()
        }
        .onChange(of: model.field) { _, _ in updateTone() }
        .onChange(of: sound) { _, on in
            if on { tone.start(amplitude: 0) ; updateTone() } else { tone.stop() }
        }
        .onChange(of: mode) { _, m in
            if m == .metal && model.baseline == nil { model.tare() }
        }
    }

    private func updateTone() {
        guard sound else { return }
        let d = mode == .metal ? model.delta : anomaly
        tone.frequency = 220 + min(d, 120) * 12
        tone.setAmplitude(d > 2 ? 0.12 : 0)
    }

    private var fieldCard: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", model.field))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(color(anomaly))
                    .contentTransition(.numericText())
                Text("µT").font(.title3).foregroundStyle(Theme.dim)
                Spacer()
                soundToggle
            }
            Text(anomalyText).font(.headline).foregroundStyle(color(anomaly))
            Sparkline(values: model.history, color: color(anomaly))
                .frame(height: 80)
            Text("Le champ terrestre vaut environ \(Int(earthField)) µT ici. Un écart signale du métal ferreux, un aimant, un haut-parleur ou un appareil électrique proche. Promène l'iPhone lentement le long des murs et des meubles pour repérer les anomalies.")
                .font(.caption).foregroundStyle(Theme.dim)
        }
    }

    private var metalCard: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%+.1f", model.field - (model.baseline ?? model.field)))
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(color(model.delta))
                    .contentTransition(.numericText())
                Text("µT").font(.title3).foregroundStyle(Theme.dim)
                Spacer()
                soundToggle
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.faint)
                    Capsule().fill(color(model.delta))
                        .frame(width: geo.size.width * CGFloat(min(1, max(0.02, model.delta / 100))))
                        .animation(.easeOut(duration: 0.15), value: model.delta)
                }
            }
            .frame(height: 14)
            Text(model.delta > 30 ? "Métal tout proche !" : model.delta > 8 ? "Métal à proximité" : "Rien de notable")
                .font(.headline).foregroundStyle(color(model.delta))
            Button {
                model.tare()
            } label: {
                Label("Tarer (remettre à zéro ici)", systemImage: "scope")
            }
            .buttonStyle(.bordered)
            Text("Tare loin de tout objet métallique, puis approche le haut de l'iPhone (où se trouve le magnétomètre) à quelques centimètres. Détecte le fer et l'acier (clous, vis, rails, câbles sous tension), pas l'or, l'alu ni le cuivre.")
                .font(.caption).foregroundStyle(Theme.dim)
        }
    }

    private var soundToggle: some View {
        Toggle(isOn: $sound) { Image(systemName: sound ? "speaker.wave.2.fill" : "speaker.slash") }
            .toggleStyle(.button)
    }

    private var anomalyText: String {
        switch anomaly {
        case ..<8: return "Champ normal"
        case ..<25: return "Légère anomalie"
        case ..<80: return "Anomalie nette"
        default: return "Champ très fort"
        }
    }

    private func color(_ d: Double) -> Color {
        switch d {
        case ..<8: return Theme.accent
        case ..<25: return Theme.blue
        case ..<80: return Theme.warn
        default: return Theme.danger
        }
    }

    private func axis(_ name: String, _ v: Double) -> some View {
        VStack(spacing: 2) {
            Text(name).font(.caption).foregroundStyle(Theme.dim)
            Text(String(format: "%.1f", v)).font(.callout.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }
}
