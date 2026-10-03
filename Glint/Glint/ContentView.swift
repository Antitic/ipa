import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var detector = GlintDetector()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if detector.authorized {
                CameraView(session: detector.session, glints: detector.glints)
                    .ignoresSafeArea()
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "camera.fill").font(.largeTitle)
                    Text("Autorise la caméra dans Réglages › Glint.")
                        .multilineTextAlignment(.center)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Ouvrir Réglages", destination: url)
                    }
                }
                .foregroundStyle(.white)
                .padding()
            }

            VStack {
                topBar
                Spacer()
                controls
            }
            .padding()
        }
        .statusBarHidden()
        .onAppear { detector.start() }
        .onDisappear { detector.stop() }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Image(systemName: detector.glints.isEmpty ? "sparkles" : "sparkles.rectangle.stack.fill")
                .foregroundStyle(detector.glints.isEmpty ? .secondary : .yellow)
            VStack(alignment: .leading, spacing: 1) {
                Text(detector.glints.isEmpty ? "Aucun reflet" : "\(detector.glints.count) reflet\(detector.glints.count > 1 ? "s" : "")")
                    .font(.headline)
                Text("Balaye lentement le sol")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var controls: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "dial.low")
                Slider(value: $detector.sensitivity)
                Image(systemName: "dial.high")
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())

            HStack {
                Text("Sensibilité")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    detector.setTorch(!detector.torchOn)
                } label: {
                    Label(detector.torchOn ? "Lampe allumée" : "Lampe éteinte",
                          systemImage: detector.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(detector.torchOn ? .yellow : .white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            Text("La lampe fait briller les objets réfléchissants. Un bijou, du métal ou du verre renvoie un reflet vif et fixe, entouré en jaune.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// Aperçu caméra avec cercles dessinés sur les reflets.
struct CameraView: UIViewRepresentable {
    let session: AVCaptureSession
    let glints: [Glint]

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.render(glints)
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private let overlay = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(overlay)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        overlay.frame = bounds
    }

    func render(_ glints: [Glint]) {
        overlay.sublayers?.forEach { $0.removeFromSuperlayer() }
        for (i, g) in glints.enumerated() {
            let center = previewLayer.layerPointConverted(fromCaptureDevicePoint:
                CGPoint(x: g.rect.midX, y: g.rect.midY))
            let size = CGFloat(34 + g.score * 46)
            let ring = CAShapeLayer()
            ring.path = UIBezierPath(ovalIn: CGRect(x: center.x - size / 2, y: center.y - size / 2,
                                                    width: size, height: size)).cgPath
            ring.fillColor = UIColor.clear.cgColor
            // Le plus brillant en jaune vif, les autres plus discrets.
            let strong = i == 0
            ring.strokeColor = (strong ? UIColor.systemYellow : UIColor.white).cgColor
            ring.lineWidth = strong ? 4 : 2
            ring.shadowColor = ring.strokeColor
            ring.shadowRadius = 6
            ring.shadowOpacity = 0.9
            ring.shadowOffset = .zero
            overlay.addSublayer(ring)
        }
    }
}
