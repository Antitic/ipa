import SwiftUI
import AVFoundation
import Accelerate

struct UltraDetection: Identifiable {
    let id = UUID()
    let date: Date
    let frequency: Double
    let strength: Float
}

/// Analyse spectrale du micro (FFT) pour repérer les balises ultrasonores (17–22 kHz).
final class UltrasoundAnalyzer: ObservableObject {
    @Published var spectrum: [Float] = []       // dB, 0 Hz → Nyquist, réduit à `displayBins` points
    @Published var peakHold: [Float] = []
    @Published var ultraPeakFreq: Double = 0
    @Published var ultraPeakDB: Float = -120
    @Published var ultraMargin: Float = 0
    @Published var detections: [UltraDetection] = []
    @Published var sampleRate: Double = 48_000
    @Published var running = false
    @Published var denied = false

    static let fftSize = 4096
    static let displayBins = 192
    private let log2n = vDSP_Length(12)
    private var fftSetup: FFTSetup?
    private var window: [Float]
    private var ring: [Float] = []
    private var engine: AVAudioEngine?
    private var sustained = 0
    private var lastPublish = Date.distantPast

    init() {
        window = [Float](repeating: 0, count: UltrasoundAnalyzer.fftSize)
        vDSP_hann_window(&window, vDSP_Length(UltrasoundAnalyzer.fftSize), Int32(vDSP_HANN_NORM))
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }

    deinit {
        engine?.stop()
        if let s = fftSetup { vDSP_destroy_fftsetup(s) }
    }

    func start() {
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            DispatchQueue.main.async {
                if ok { self.startEngine() } else { self.denied = true }
            }
        }
    }

    func stop() {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        running = false
    }

    func resetPeaks() {
        peakHold = []
        detections = []
    }

    private func startEngine() {
        guard engine == nil else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement)
            try session.setPreferredSampleRate(48_000)
            try session.setActive(true)
        } catch {}

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        sampleRate = format.sampleRate
        ring.removeAll()

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            self.ring.append(contentsOf: UnsafeBufferPointer(start: ch, count: n))
            let size = UltrasoundAnalyzer.fftSize
            while self.ring.count >= size {
                let frame = Array(self.ring.prefix(size))
                self.ring.removeFirst(size / 2)
                self.analyze(frame)
            }
        }
        do {
            try engine.start()
            self.engine = engine
            running = true
        } catch {
            input.removeTap(onBus: 0)
        }
    }

    private func analyze(_ samples: [Float]) {
        guard let setup = fftSetup else { return }
        let size = UltrasoundAnalyzer.fftSize
        let half = size / 2
        var windowed = [Float](repeating: 0, count: size)
        vDSP_vmul(samples, 1, window, 1, &windowed, 1, vDSP_Length(size))

        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &mags, 1, vDSP_Length(half))
            }
        }
        let norm = Float(size * size) / 4
        let db = mags.map { 10 * log10f($0 / norm + 1e-14) }

        // Bande ultrasonore 17 kHz → Nyquist (avec une petite marge)
        let binHz = sampleRate / Double(size)
        let lo = Int(17_000 / binHz)
        let hi = min(half - 4, Int((sampleRate / 2 - 300) / binHz))
        var peakIdx = lo
        var peak: Float = -200
        if hi > lo {
            for i in lo...hi where db[i] > peak { peak = db[i]; peakIdx = i }
        }
        let band = hi > lo ? Array(db[lo...hi]).sorted() : [-120]
        let median = band[band.count / 2]
        let margin = peak - median
        let freq = Double(peakIdx) * binHz

        if margin > 22 && peak > -100 { sustained += 1 } else { sustained = 0 }
        let detected = sustained == 4

        // Réduction pour l'affichage
        let groups = UltrasoundAnalyzer.displayBins
        let per = half / groups
        var display = [Float](repeating: -120, count: groups)
        for g in 0..<groups {
            var m: Float = -160
            for i in (g * per)..<((g + 1) * per) where db[i] > m { m = db[i] }
            display[g] = m
        }

        let now = Date()
        guard detected || now.timeIntervalSince(lastPublish) > 0.08 else { return }
        lastPublish = now
        DispatchQueue.main.async {
            self.spectrum = display
            if self.peakHold.count != display.count {
                self.peakHold = display
            } else {
                for i in 0..<display.count { self.peakHold[i] = max(self.peakHold[i] - 0.15, display[i]) }
            }
            self.ultraPeakFreq = freq
            self.ultraPeakDB = peak
            self.ultraMargin = margin
            if detected {
                let d = UltraDetection(date: now, frequency: freq, strength: margin)
                self.detections.insert(d, at: 0)
                if self.detections.count > 30 { self.detections.removeLast() }
            }
        }
    }
}

struct UltrasoundView: View {
    @StateObject private var analyzer = UltrasoundAnalyzer()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if analyzer.denied {
                    Card {
                        Label("Micro refusé : autorise-le dans Réglages > Wave.", systemImage: "mic.slash")
                            .foregroundStyle(Theme.danger)
                    }
                }
                Card {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(analyzer.ultraMargin > 22 ? "Signal ultrasonore !" : "Pas de balise")
                                .font(.headline)
                                .foregroundStyle(analyzer.ultraMargin > 22 ? Theme.danger : Theme.accent)
                            Text("Pic 17–\(Int(analyzer.sampleRate / 2000)) kHz : \(String(format: "%.2f", analyzer.ultraPeakFreq / 1000)) kHz, \(Int(analyzer.ultraMargin)) dB au-dessus du bruit")
                                .font(.caption.monospacedDigit()).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        Button { analyzer.resetPeaks() } label: { Image(systemName: "arrow.counterclockwise") }
                            .buttonStyle(.bordered)
                    }
                    SpectrumView(values: analyzer.spectrum, hold: analyzer.peakHold, nyquist: analyzer.sampleRate / 2)
                        .frame(height: 220)
                }
                Card {
                    Text("Détections").font(.headline)
                    if analyzer.detections.isEmpty {
                        Text("Aucune pour l'instant. Laisse l'iPhone posé quelques minutes près de la TV, d'une enceinte ou dans un magasin.")
                            .font(.callout).foregroundStyle(Theme.dim)
                    }
                    ForEach(analyzer.detections.prefix(10)) { d in
                        HStack {
                            Text(d.date.formatted(date: .omitted, time: .standard)).font(.callout.monospacedDigit())
                            Spacer()
                            Text(String(format: "%.2f kHz", d.frequency / 1000)).font(.callout.monospacedDigit())
                            Pill(text: "+\(Int(d.strength)) dB", color: Theme.danger)
                        }
                    }
                }
                Card {
                    Text("À quoi ça sert").font(.headline)
                    Text("Certaines pubs TV, applis et magasins émettent des sons inaudibles (17–20 kHz) pour pister les téléphones à proximité. Des micros espions bon marché émettent aussi parfois un sifflement aigu. Le micro de l'iPhone capte jusqu'à environ 20 kHz.")
                        .font(.caption).foregroundStyle(Theme.dim)
                }
            }
            .padding(16)
        }
        .waveScreen()
        .navigationTitle("Ultrasons")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { analyzer.start() }
        .onDisappear { analyzer.stop() }
    }
}

struct SpectrumView: View {
    let values: [Float]
    let hold: [Float]
    let nyquist: Double

    private let minDB: Float = -130
    private let maxDB: Float = -20

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height - 16
            // Zone ultrasonore
            let ux = w * CGFloat(17_000 / nyquist)
            ctx.fill(Path(CGRect(x: ux, y: 0, width: w - ux, height: h)), with: .color(Theme.danger.opacity(0.08)))
            // Graduations tous les 4 kHz
            var f = 0.0
            while f <= nyquist {
                let x = w * CGFloat(f / nyquist)
                ctx.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h)) },
                           with: .color(Theme.faint), lineWidth: 1)
                ctx.draw(Text("\(Int(f / 1000))k").font(.system(size: 9)).foregroundColor(Theme.dim),
                         at: CGPoint(x: min(max(x, 8), w - 8), y: h + 8))
                f += 4000
            }
            func path(_ v: [Float]) -> Path {
                var p = Path()
                guard v.count > 1 else { return p }
                for (i, d) in v.enumerated() {
                    let x = w * CGFloat(i) / CGFloat(v.count - 1)
                    let t = (min(max(d, minDB), maxDB) - minDB) / (maxDB - minDB)
                    let y = h * (1 - CGFloat(t))
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
                return p
            }
            ctx.stroke(path(hold), with: .color(Theme.violet.opacity(0.5)), lineWidth: 1)
            ctx.stroke(path(values), with: .color(Theme.accent), lineWidth: 1.6)
        }
    }
}
