import SwiftUI
import AVFoundation

/// Analyse la vidéo pour trouver de petits points très lumineux : LED infrarouges
/// de vision nocturne (caméra frontale) ou reflets d'objectif (caméra arrière + lampe).
final class InfraredDetector: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var spots: [CGRect] = []          // coordonnées normalisées du capteur
    @Published var sceneTooBright = false
    @Published var authorized = true
    @Published var usingFront = true
    @Published var torchOn = false
    @Published var running = false

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "wave.ir")
    private var frameCount = 0
    private var currentDevice: AVCaptureDevice?

    /// Faux si l'écran a été quitté avant la réponse à la demande d'accès à la caméra.
    private var wanted = false

    func start() {
        wanted = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { ok in
                DispatchQueue.main.async {
                    self.authorized = ok
                    if ok && self.wanted { self.configure() }
                }
            }
        default:
            authorized = false
        }
    }

    func stop() {
        wanted = false
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
        setTorch(false)
        running = false
    }

    func switchCamera() {
        usingFront.toggle()
        if usingFront { setTorch(false) }
        configure()
    }

    /// Allumage demandé alors que la caméra arrière n'était pas encore prête.
    private var pendingTorch = false

    func setTorch(_ on: Bool) {
        guard let dev = currentDevice, dev.hasTorch else {
            // La caméra arrière est peut-être encore en cours de configuration.
            pendingTorch = on && !usingFront
            torchOn = false
            return
        }
        do {
            try dev.lockForConfiguration()
            if on { try dev.setTorchModeOn(level: 1.0) } else { dev.torchMode = .off }
            dev.unlockForConfiguration()
            torchOn = on
        } catch {
            torchOn = false
        }
    }

    private func configure() {
        let front = usingFront
        queue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720
            for input in self.session.inputs { self.session.removeInput(input) }
            let position: AVCaptureDevice.Position = front ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            if !self.session.outputs.contains(self.output) {
                self.output.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                ]
                self.output.alwaysDiscardsLateVideoFrames = true
                self.output.setSampleBufferDelegate(self, queue: self.queue)
                if self.session.canAddOutput(self.output) { self.session.addOutput(self.output) }
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async {
                self.currentDevice = device
                self.running = true
                self.spots = []
                if self.pendingTorch {
                    self.pendingTorch = false
                    self.setTorch(true)
                }
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCount += 1
        guard frameCount % 3 == 0, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pb, 0)
        let height = CVPixelBufferGetHeightOfPlane(pb, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)

        let cols = 40, rows = 24
        let cellW = width / cols, cellH = height / rows
        guard cellW > 4, cellH > 4 else { return }
        var bright = [Int](repeating: 0, count: cols * rows)
        var samples = 0
        var total = 0
        let step = 3
        for cy in 0..<rows {
            for cx in 0..<cols {
                var count = 0
                var y = cy * cellH
                while y < (cy + 1) * cellH {
                    let row = luma + y * stride
                    var x = cx * cellW
                    while x < (cx + 1) * cellW {
                        let v = Int(row[x])
                        total += v
                        samples += 1
                        if v >= 245 { count += 1 }
                        x += step
                    }
                    y += step
                }
                bright[cy * cols + cx] = count
            }
        }
        let mean = Double(total) / Double(max(samples, 1))
        let perCell = (cellW / step + 1) * (cellH / step + 1)

        var found: [(Int, CGRect)] = []
        for cy in 0..<rows {
            for cx in 0..<cols {
                let c = bright[cy * cols + cx]
                // Un point lumineux compact : quelques pixels saturés, pas une zone entière.
                guard c >= 1, Double(c) < Double(perCell) * 0.35 else { continue }
                // Maximum local pour ne garder qu'un repère par point.
                var isMax = true
                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let nx = cx + dx, ny = cy + dy
                        if nx >= 0, nx < cols, ny >= 0, ny < rows, bright[ny * cols + nx] > c { isMax = false }
                    }
                }
                guard isMax else { continue }
                let rect = CGRect(x: Double(cx) / Double(cols), y: Double(cy) / Double(rows),
                                  width: 1.0 / Double(cols), height: 1.0 / Double(rows))
                found.append((c, rect))
            }
        }
        let tooBright = mean > 110
        let top: [CGRect] = tooBright ? [] : found.sorted { $0.0 > $1.0 }.prefix(8).map { $0.1 }
        DispatchQueue.main.async {
            self.sceneTooBright = tooBright
            self.spots = top
        }
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    let overlay = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(overlay)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlay.frame = bounds
    }

    func draw(spots: [CGRect]) {
        overlay.sublayers?.forEach { $0.removeFromSuperlayer() }
        for s in spots {
            let r = previewLayer.layerRectConverted(fromMetadataOutputRect: s)
            let size: CGFloat = 44
            let ring = CAShapeLayer()
            ring.path = UIBezierPath(ovalIn: CGRect(x: r.midX - size / 2, y: r.midY - size / 2, width: size, height: size)).cgPath
            ring.strokeColor = UIColor.systemPink.cgColor
            ring.fillColor = UIColor.clear.cgColor
            ring.lineWidth = 3
            overlay.addSublayer(ring)
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let spots: [CGRect]

    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.draw(spots: spots)
    }
}

struct InfraredView: View {
    @StateObject private var detector = InfraredDetector()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if detector.authorized {
                CameraPreview(session: detector.session, spots: detector.spots)
                    .ignoresSafeArea()
            } else {
                ContentUnavailableView {
                    Label("Caméra non autorisée", systemImage: "camera.fill")
                } description: {
                    Text("Autorise l'accès à la caméra dans Réglages › Wave.")
                } actions: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Ouvrir Réglages", destination: url)
                    }
                }
                .foregroundStyle(.white)
            }
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        IconTile(symbol: detector.usingFront ? "camera.aperture" : "flashlight.on.fill",
                                 colors: Feature.infrared.colors, size: 34)
                        Text(detector.usingFront ? "Infrarouge · caméra frontale" : "Reflets d'objectif · caméra arrière")
                            .font(.system(.headline, design: .rounded))
                    }
                    Text(detector.usingFront
                         ? "Éteins la lumière et balaye la pièce lentement, écran tourné vers les murs. Une LED de vision nocturne apparaît comme un point blanc ou violet fixe, invisible à l'œil nu."
                         : "Allume la lampe et balaye lentement les objets (détecteurs de fumée, réveils, chargeurs, peluches). Un objectif renvoie un petit reflet brillant qui reste fixe quand tu bouges.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if detector.sceneTooBright {
                        Pill(text: "Trop de lumière : éteins la pièce", color: Theme.yellow, symbol: "sun.max.fill")
                    } else if !detector.spots.isEmpty {
                        Pill(text: "\(detector.spots.count) point\(detector.spots.count > 1 ? "s" : "") lumineux repéré\(detector.spots.count > 1 ? "s" : "")",
                             color: Theme.pink, symbol: "scope")
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .environment(\.colorScheme, .dark)

                Spacer()

                HStack(spacing: 14) {
                    Button {
                        detector.switchCamera()
                    } label: {
                        Label(detector.usingFront ? "Caméra arrière" : "Caméra frontale",
                              systemImage: "arrow.triangle.2.circlepath.camera.fill")
                    }
                    .buttonStyle(GradientButtonStyle(colors: Feature.infrared.colors))
                    if !detector.usingFront {
                        Button {
                            detector.setTorch(!detector.torchOn)
                        } label: {
                            Image(systemName: detector.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                                .font(.title3)
                                .foregroundStyle(detector.torchOn ? Theme.yellow : .white)
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        .environment(\.colorScheme, .dark)
                        .accessibilityLabel("Lampe")
                    }
                }
                .padding(.bottom, 24)
            }
            .padding(16)
        }
        .navigationTitle("Infrarouge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { detector.start() }
        .onDisappear { detector.stop() }
    }
}
