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
        if let appareil = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let entree = try? AVCaptureDeviceInput(device: appareil), session.canAddInput(entree) {
            session.addInput(entree)
        }
        if !session.outputs.contains(sortie), session.canAddOutput(sortie) {
            session.addOutput(sortie)
        }
        session.commitConfiguration()
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
            Text(camera.message ?? "Centre : photo · ⏮ ⏭ : caméra")
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
            g.centre = { camera.declencher() }
            g.precedent = { camera.changerCamera() }
            g.suivant = { camera.changerCamera() }
            g.lecture = { camera.declencher() }
        }
    }
}
