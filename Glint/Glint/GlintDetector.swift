import AVFoundation
import UIKit

struct Glint: Identifiable {
    let id = UUID()
    let rect: CGRect      // coordonnées normalisées du capteur (0…1)
    let score: Double     // 0…1, à quel point c'est plus brillant que le reste
}

/// Analyse l'image de la caméra et repère les zones qui réfléchissent la lumière
/// nettement plus que leur entourage (reflet d'un bijou, d'un objectif, de métal…).
final class GlintDetector: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var glints: [Glint] = []
    @Published var topScore: Double = 0
    @Published var authorized = true
    @Published var torchOn = true
    @Published var running = false
    /// Sensibilité 0…1 : plus haut = détecte des reflets plus discrets.
    @Published var sensitivity: Double = 0.5

    let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "glint.camera")
    private var device: AVCaptureDevice?
    private var frame = 0
    private var wanted = false

    // Grille d'analyse
    private let cols = 48
    private let rows = 64

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
        setTorch(false)
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
        running = false
    }

    func setTorch(_ on: Bool) {
        guard let device, device.hasTorch else { torchOn = false; return }
        do {
            try device.lockForConfiguration()
            if on { try device.setTorchModeOn(level: 1.0) } else { device.torchMode = .off }
            device.unlockForConfiguration()
            torchOn = on
        } catch {
            torchOn = false
        }
    }

    private func configure() {
        queue.async {
            self.session.beginConfiguration()
            self.session.sessionPreset = .hd1280x720
            for input in self.session.inputs { self.session.removeInput(input) }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            // Verrouille l'exposition basse pour que seuls les vrais reflets saturent.
            if let _ = try? device.lockForConfiguration() {
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            }
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
            self.device = device
            DispatchQueue.main.async {
                self.running = true
                if self.torchOn { self.setTorch(true) }
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frame += 1
        guard frame % 2 == 0, let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pb, 0)
        let height = CVPixelBufferGetHeightOfPlane(pb, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
        let luma = base.assumingMemoryBound(to: UInt8.self)

        let cellW = width / cols, cellH = height / rows
        guard cellW > 2, cellH > 2 else { return }

        // Luminance moyenne de chaque cellule.
        var cell = [Double](repeating: 0, count: cols * rows)
        var sum = 0.0, sumSq = 0.0
        let step = 2
        for cy in 0..<rows {
            for cx in 0..<cols {
                var acc = 0, n = 0
                var y = cy * cellH
                while y < (cy + 1) * cellH {
                    let row = luma + y * stride
                    var x = cx * cellW
                    while x < (cx + 1) * cellW {
                        acc += Int(row[x]); n += 1; x += step
                    }
                    y += step
                }
                let avg = n > 0 ? Double(acc) / Double(n) : 0
                cell[cy * cols + cx] = avg
                sum += avg; sumSq += avg * avg
            }
        }
        let count = Double(cols * rows)
        let mean = sum / count
        let variance = max(0, sumSq / count - mean * mean)
        let std = sqrt(variance)

        // Un reflet = une cellule bien au-dessus de la moyenne (seuil en écarts-types),
        // et qui est un maximum local pour ne garder qu'un repère par point brillant.
        // sensibilité haute → seuil bas.
        let k = 3.5 - sensitivity * 2.5          // 3.5 (strict) … 1.0 (sensible)
        let threshold = mean + k * max(std, 3)
        var found: [Glint] = []
        for cy in 0..<rows {
            for cx in 0..<cols {
                let v = cell[cy * cols + cx]
                guard v >= threshold, v > 90 else { continue }
                var isMax = true
                loop: for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        let nx = cx + dx, ny = cy + dy
                        if nx >= 0, nx < cols, ny >= 0, ny < rows, cell[ny * cols + nx] > v { isMax = false; break loop }
                    }
                }
                guard isMax else { continue }
                // Score : contraste avec le fond, normalisé.
                let score = min(1, (v - mean) / max(255 - mean, 1))
                let rect = CGRect(x: Double(cx) / Double(cols), y: Double(cy) / Double(rows),
                                  width: 1.0 / Double(cols), height: 1.0 / Double(rows))
                found.append(Glint(rect: rect, score: score))
            }
        }
        let top = found.sorted { $0.score > $1.score }.prefix(12).map { $0 }
        let best = top.first?.score ?? 0
        DispatchQueue.main.async {
            self.glints = Array(top)
            self.topScore = best
        }
    }
}
