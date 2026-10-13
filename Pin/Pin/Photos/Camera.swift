import SwiftUI
import AVFoundation
import Photos

/// L'appareil photo : aperçu dans l'écran de l'iPod, centre = déclencher,
/// ⏮ ⏭ = changer de caméra. Chaque photo va directement dans la Pellicule.
final class CameraModele: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let sortie = AVCapturePhotoOutput()
    private let file = DispatchQueue(label: "pin.camera")
    private var position: AVCaptureDevice.Position = .back
    private var appareil: AVCaptureDevice?
    /// Facteur où la caméra virtuelle passe de l'ultra grand-angle au grand-angle :
    /// c'est le « 1× » affiché, comme dans l'app Appareil photo.
    private var base: CGFloat = 1

    /// Zoom affiché (0,5× sur l'ultra grand-angle, 1× normal…).
    @Published var zoomAffiche: Double = 1
    @Published var zoomVisible = false
    private var masquageZoom: DispatchWorkItem?

    @Published var message: String?
    @Published var flash = false
    @Published var autorise: Bool?

    func demarrer() {
        Task {
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            await MainActor.run { self.autorise = ok }
            guard ok else { return }
            file.async {
                self.configurer()
                if !self.session.isRunning { self.session.startRunning() }
            }
        }
    }

    func arreter() {
        file.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    private func configurer() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        for e in session.inputs { session.removeInput(e) }
        // Caméra virtuelle à l'arrière (ultra grand-angle + grand-angle [+ télé]) : le zoom
        // passe d'un objectif à l'autre tout seul, de 0,5× au maximum.
        let types: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        let choisi = types.lazy.compactMap { AVCaptureDevice.default($0, for: .video, position: self.position) }.first
        if let choisi, let entree = try? AVCaptureDeviceInput(device: choisi), session.canAddInput(entree) {
            session.addInput(entree)
            appareil = choisi
            let bascules = choisi.virtualDeviceSwitchOverVideoZoomFactors.map { CGFloat(truncating: $0) }
            // Sur une double caméra grand-angle + télé, le premier seuil est le télé : 1× reste 1.
            base = choisi.deviceType == .builtInDualCamera ? 1 : (bascules.first ?? 1)
            try? choisi.lockForConfiguration()
            choisi.videoZoomFactor = min(max(base, choisi.minAvailableVideoZoomFactor), choisi.maxAvailableVideoZoomFactor)
            choisi.unlockForConfiguration()
            let affiche = Double(choisi.videoZoomFactor / base)
            DispatchQueue.main.async { self.zoomAffiche = affiche }
        }
        if !session.outputs.contains(sortie), session.canAddOutput(sortie) {
            session.addOutput(sortie)
        }
        session.commitConfiguration()
    }

    /// Un cran de molette : ~7 % de zoom, en douceur.
    func zoomer(_ crans: Int) {
        file.async {
            guard let a = self.appareil else { return }
            let maxi = min(a.maxAvailableVideoZoomFactor, self.base * 15)
            let cible = min(max(a.videoZoomFactor * pow(1.07, CGFloat(crans)), a.minAvailableVideoZoomFactor), maxi)
            guard (try? a.lockForConfiguration()) != nil else { return }
            a.ramp(toVideoZoomFactor: cible, withRate: 12)
            a.unlockForConfiguration()
            let affiche = Double(cible / self.base)
            DispatchQueue.main.async {
                self.zoomAffiche = affiche
                self.zoomVisible = true
                self.masquageZoom?.cancel()
                let m = DispatchWorkItem { self.zoomVisible = false }
                self.masquageZoom = m
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: m)
            }
        }
    }

    func changerCamera() {
        file.async {
            self.position = self.position == .back ? .front : .back
            self.configurer()
        }
    }

    func declencher() {
        file.async {
            guard self.session.isRunning else { return }
            let reglages = AVCapturePhotoSettings()
            if let connexion = self.sortie.connection(with: .video), connexion.isVideoRotationAngleSupported(90) {
                connexion.videoRotationAngle = 90
            }
            self.sortie.capturePhoto(with: reglages, delegate: self)
        }
        DispatchQueue.main.async {
            self.flash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self.flash = false }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            DispatchQueue.main.async { self.message = "Prise de vue impossible" }
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { statut in
            guard statut == .authorized || statut == .limited else {
                DispatchQueue.main.async { self.message = "Accès à la Pellicule refusé" }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            } completionHandler: { ok, _ in
                DispatchQueue.main.async {
                    self.message = ok ? "Enregistrée dans la Pellicule" : "Enregistrement impossible"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.message = nil }
                }
            }
        }
    }
}

struct ApercuCamera: UIViewRepresentable {
    let session: AVCaptureSession

    final class Vue: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var apercu: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> Vue {
        let v = Vue()
        v.apercu.session = session
        v.apercu.videoGravity = .resizeAspectFill
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: Vue, context: Context) {}
}

struct EcranCamera: View {
    @StateObject private var camera = CameraModele()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            if camera.autorise == false {
                MessageEcran(icone: "camera", texte: "Accès à la caméra refusé", detail: "Réglages iPhone › Pin › Appareil photo.")
                    .foregroundStyle(.white)
            } else {
                ApercuCamera(session: camera.session)
            }
            Color.white.opacity(camera.flash ? 0.85 : 0).allowsHitTesting(false)
            if camera.zoomVisible || camera.zoomAffiche != 1 {
                Text(camera.zoomAffiche < 0.95 ? String(format: "%.1f×", camera.zoomAffiche).replacingOccurrences(of: ".", with: ",")
                     : (camera.zoomAffiche < 9.95 ? String(format: "%.1f×", camera.zoomAffiche).replacingOccurrences(of: ".", with: ",")
                        : String(format: "%.0f×", camera.zoomAffiche)))
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    .animation(.easeOut(duration: 0.2), value: camera.zoomVisible)
            }
            Text(camera.message ?? "Molette : zoom · Centre : photo · ⏮ ⏭ : caméra")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.55)))
                .padding(6)
        }
        .onAppear { camera.demarrer() }
        .onDisappear { camera.arreter() }
        .roue { g in
            g.tour = { s in camera.zoomer(s) }
            g.centre = { camera.declencher() }
            g.precedent = { camera.changerCamera() }
            g.suivant = { camera.changerCamera() }
            g.lecture = { camera.declencher() }
        }
    }
}
