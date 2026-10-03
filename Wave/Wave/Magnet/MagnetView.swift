import SwiftUI
import CoreMotion

final class MagnetModel: ObservableObject {
    /// Champ terrestre local (calibré par iOS, sans le magnétisme propre de l'iPhone), en µT.
    @Published var field: Double = 0
    @Published var vector = SIMD3<Double>(0, 0, 0)
    @Published var history: [Double] = []
    @Published var calibrated = false
    /// Mesure brute du capteur, utilisée par le détecteur de métaux. Elle inclut le
    /// magnétisme de l'iPhone, mais ce biais est constant et disparaît avec la remise à zéro.
    @Published var raw: Double = 0
    @Published var baseline: Double?
    @Published var available = true

    private let motion = CMMotionManager()
    private var lastPublish = Date.distantPast

    /// Écart par rapport à la remise à zéro (détecteur de métaux), toujours sur la mesure brute.
    var delta: Double { abs(raw - (baseline ?? raw)) }
    var signedDelta: Double { raw - (baseline ?? raw) }

    func start() {
        available = motion.isMagnetometerAvailable
        // Champ calibré (mode « Champ magnétique »).
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 20
            motion.showsDeviceMovementDisplay = true
            motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] m, _ in
                guard let self, let m else { return }
                let f = m.magneticField
                self.calibrated = f.accuracy != .uncalibrated
                guard self.calibrated else { return }
                let v = SIMD3(f.field.x, f.field.y, f.field.z)
                let magnitude = (v * v).sum().squareRoot()
                guard magnitude > 0 else { return }
                self.vector = v
                self.field = self.field == 0 ? magnitude : self.field * 0.7 + magnitude * 0.3
            }
        }
        // Mesure brute rapide (détecteur de métaux), une seule source : plus de sauts.
        if motion.isMagnetometerAvailable {
            motion.magnetometerUpdateInterval = 1.0 / 50
            motion.startMagnetometerUpdates(to: .main) { [weak self] d, _ in
                guard let self, let d else { return }
                let v = SIMD3(d.magneticField.x, d.magneticField.y, d.magneticField.z)
                let magnitude = (v * v).sum().squareRoot()
                self.raw = self.raw == 0 ? magnitude : self.raw * 0.6 + magnitude * 0.4
                if !self.calibrated { self.vector = v }
                // Historique à 10 Hz pour ne pas surcharger l'affichage.
                if Date().timeIntervalSince(self.lastPublish) > 0.1 {
                    self.lastPublish = Date()
                    self.history.append(self.calibrated ? self.field : self.raw)
                    if self.history.count > 200 { self.history.removeFirst(self.history.count - 200) }
                }
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        motion.stopMagnetometerUpdates()
    }

    func tare() { baseline = raw }
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

    private let earthField = 47.0   // valeur typique en France, en µT

    /// Sans calibration, le champ affiché inclut le magnétisme de l'iPhone : pas d'anomalie calculée.
    private var anomaly: Double { model.calibrated ? abs(model.field - earthField) : 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if mode == .field { fieldCard } else { metalCard }

                Card {
                    SectionTitle(text: "Composantes (µT)", symbol: "move.3d")
                    HStack(spacing: 10) {
                        axis("X", model.vector.x, Theme.red)
                        axis("Y", model.vector.y, Theme.green)
                        axis("Z", model.vector.z, Theme.blue)
                    }
                    if !model.calibrated {
                        Label("Magnétomètre non calibré : fais des 8 avec l'iPhone pendant quelques secondes.",
                              systemImage: "infinity")
                            .font(.caption).foregroundStyle(Theme.warn)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .waveScreen(.magnet)
        .navigationTitle("Magnéto")
        .onAppear { model.start() }
        .onDisappear {
            model.stop()
            tone.stop()
            // L'onglet reste en mémoire : sans cette remise à zéro, le bouton son restait
            // « activé » au retour alors que le son était coupé.
            sound = false
        }
        .onChange(of: model.field) { _, _ in if mode == .field { updateTone() } }
        .onChange(of: model.raw) { _, _ in if mode == .metal { updateTone() } }
        .onChange(of: sound) { _, on in
            if on { tone.start(amplitude: 0); updateTone() } else { tone.stop() }
        }
        .onChange(of: mode) { _, m in
            if m == .metal && model.baseline == nil { model.tare() }
            updateTone()
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
            HStack {
                SectionTitle(text: "Intensité", symbol: "location.north.circle.fill", color: color(anomaly))
                Spacer()
                soundToggle
            }
            HStack(spacing: 20) {
                ZStack {
                    GaugeRing(progress: min(1, (model.calibrated ? model.field : model.raw) / 200), colors: colors(anomaly), lineWidth: 16)
                    VStack(spacing: 0) {
                        Text(String(format: "%.0f", model.calibrated ? model.field : model.raw))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("µT").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                    }
                }
                .frame(width: 140, height: 140)
                VStack(alignment: .leading, spacing: 6) {
                    Text(anomalyText)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(color(anomaly))
                    Text("Écart : \(String(format: "%.0f", anomaly)) µT")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.dim)
                    Text("Référence terrestre ≈ \(Int(earthField)) µT")
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                }
            }
            Sparkline(values: model.history, color: color(anomaly))
                .frame(height: 80)
            Text("Un écart signale du métal ferreux, un aimant, un haut-parleur ou un appareil électrique proche. Promène l'iPhone lentement le long des murs et des meubles pour repérer les anomalies.")
                .font(.caption).foregroundStyle(Theme.dim)
        }
    }

    private var metalCard: some View {
        let delta = model.signedDelta
        return Card {
            HStack {
                SectionTitle(text: "Détecteur", symbol: "scope", color: color(model.delta))
                Spacer()
                soundToggle
            }
            BigNumber(value: String(format: "%+.1f", delta), unit: "µT", colors: colors(model.delta), size: 60)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.cardHi)
                    Capsule()
                        .fill(color(model.delta))
                        // Échelle 0–50 µT : la barre bouge dès les premiers centimètres.
                        .frame(width: geo.size.width * CGFloat(min(1, max(0.02, model.delta / 50))))
                        .animation(.easeOut(duration: 0.15), value: model.delta)
                }
            }
            .frame(height: 14)
            Text(model.delta > 20 ? "Métal tout proche !" : model.delta > 4 ? "Métal à proximité" : "Rien de notable")
                .font(.system(.headline, design: .rounded)).foregroundStyle(color(model.delta))
            Button {
                model.tare()
            } label: {
                Label("Remettre à zéro ici", systemImage: "scope")
            }
            .buttonStyle(GradientButtonStyle(colors: Feature.magnet.colors))
            Text("Remets à zéro loin de tout objet métallique, puis approche le haut de l'iPhone (où se trouve le magnétomètre) à quelques centimètres. Détecte le fer et l'acier (clous, vis, rails, câbles sous tension), pas l'or, l'alu ni le cuivre.")
                .font(.caption).foregroundStyle(Theme.dim)
        }
    }

    private var soundToggle: some View {
        Button {
            sound.toggle()
        } label: {
            Image(systemName: sound ? "speaker.wave.2.fill" : "speaker.slash.fill")
        }
        .buttonStyle(CircleIconButtonStyle(color: sound ? Theme.orange : .primary))
        .accessibilityLabel("Son")
    }

    private var anomalyText: String {
        if !model.calibrated { return "Calibration en cours" }
        switch anomaly {
        case ..<8: return "Champ normal"
        case ..<25: return "Légère anomalie"
        case ..<80: return "Anomalie nette"
        default: return "Champ très fort"
        }
    }

    private func color(_ d: Double) -> Color {
        switch d {
        case ..<8: return Theme.green
        case ..<25: return Theme.teal
        case ..<80: return Theme.orange
        default: return Theme.red
        }
    }

    private func colors(_ d: Double) -> [Color] {
        switch d {
        case ..<8: return [Theme.green, Theme.mint]
        case ..<25: return [Theme.teal, Theme.blue]
        case ..<80: return [Theme.orange, Theme.yellow]
        default: return [Theme.red, Theme.pink]
        }
    }

    private func axis(_ name: String, _ v: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption.weight(.bold)).foregroundStyle(c)
            Text(String(format: "%.1f", v))
                .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(c.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
