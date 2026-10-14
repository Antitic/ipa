import SwiftUI
import AVFoundation
import Photos

/// L'appareil photo : aperçu dans l'écran de l'iPod. Mode Photo : centre =
/// photo, centre maintenu = rafale. Mode Vidéo : centre = démarrer / arrêter.
/// ⏮ ⏭ = changer de mode, ⏯ = changer de caméra. Tout va dans la Pellicule.
final class CameraModele: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    enum Mode: String, CaseIterable { case photo = "PHOTO", video = "VIDÉO" }

    let session = AVCaptureSession()
    private let sortie = AVCapturePhotoOutput()
    private let film = AVCaptureMovieFileOutput()
    private var entreeMicro: AVCaptureDeviceInput?
    private var rafaleEnCours = false
    private var minuteurVideo: Timer?
    private let tic = UIImpactFeedbackGenerator(style: .light)

    @Published var mode: Mode = .photo
    @Published var enregistre = false
    @Published var duree: Int = 0
    @Published var compteRafale = 0
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
        rafaleEnCours = false
        file.async {
            if self.film.isRecording { self.film.stopRecording() }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configurer() {
        session.beginConfiguration()
        session.sessionPreset = mode == .video ? .high : .photo
        for e in session.inputs { session.removeInput(e) }
        entreeMicro = nil
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
        if !session.outputs.contains(film), session.canAddOutput(film) {
            session.addOutput(film)
        }
        if mode == .video { ajouterMicro() }
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

    // MARK: - Modes, rafale, vidéo

    private func ajouterMicro() {
        guard entreeMicro == nil, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let micro = AVCaptureDevice.default(for: .audio),
              let e = try? AVCaptureDeviceInput(device: micro), session.canAddInput(e) else { return }
        session.addInput(e)
        entreeMicro = e
    }

    func changerMode(_ sens: Int) {
        guard !enregistre, !rafaleEnCours else { return }
        let tous = Mode.allCases
        let i = (tous.firstIndex(of: mode)! + sens + tous.count) % tous.count
        let nouveau = tous[i]
        mode = nouveau
        Task {
            if nouveau == .video { _ = await AVCaptureDevice.requestAccess(for: .audio) }
            file.async {
                self.session.beginConfiguration()
                self.session.sessionPreset = nouveau == .video ? .high : .photo
                if nouveau == .video {
                    self.ajouterMicro()
                } else if let m = self.entreeMicro {
                    self.session.removeInput(m)
                    self.entreeMicro = nil
                }
                self.session.commitConfiguration()
            }
        }
    }

    /// Centre (appui court) : photo, ou démarrer / arrêter la vidéo.
    func action() {
        if mode == .photo { declencher() } else { basculerVideo() }
    }

    func debutRafale() {
        guard mode == .photo, !rafaleEnCours else { return }
        rafaleEnCours = true
        DispatchQueue.main.async { self.compteRafale = 0 }
        tirRafale()
    }

    func finRafale() {
        guard rafaleEnCours else { return }
        rafaleEnCours = false
        let n = compteRafale
        DispatchQueue.main.async {
            self.compteRafale = 0
            self.message = "Rafale : \(n) photo\(n > 1 ? "s" : "")"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { self.message = nil }
        }
    }

    private func tirRafale() {
        file.async {
            guard self.rafaleEnCours, self.session.isRunning else { return }
            self.prendre(rapide: true)
            DispatchQueue.main.async { self.compteRafale += 1 }
            self.file.asyncAfter(deadline: .now() + 0.15) { self.tirRafale() }
        }
    }

    private func basculerVideo() {
        file.async {
            if self.film.isRecording {
                self.film.stopRecording()
                return
            }
            guard self.session.isRunning else { return }
            if let c = self.film.connection(with: .video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pin-\(UUID().uuidString).mov")
            self.film.startRecording(to: url, recordingDelegate: self)
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.enregistre = true
            self.duree = 0
            self.minuteurVideo?.invalidate()
            self.minuteurVideo = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in self.duree += 1 }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo fileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            self.enregistre = false
            self.minuteurVideo?.invalidate()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        // Une erreur peut accompagner un enregistrement tout de même exploitable (disque plein, appel…).
        let exploitable = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        guard exploitable else {
            try? FileManager.default.removeItem(at: fileURL)
            DispatchQueue.main.async { self.message = "Vidéo impossible" }
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { statut in
            guard statut == .authorized || statut == .limited else {
                DispatchQueue.main.async { self.message = "Accès à la Pellicule refusé" }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
            } completionHandler: { ok, _ in
                try? FileManager.default.removeItem(at: fileURL)
                DispatchQueue.main.async {
                    self.message = ok ? "Vidéo enregistrée" : "Enregistrement impossible"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.message = nil }
                }
            }
        }
    }

    func changerCamera() {
        guard !enregistre else { return }
        file.async {
            self.position = self.position == .back ? .front : .back
            self.configurer()
        }
    }

    func declencher() {
        file.async {
            guard self.session.isRunning else { return }
            self.prendre(rapide: false)
        }
    }

    /// Doit être appelée sur la file de la caméra.
    private func prendre(rapide: Bool) {
        let reglages = AVCapturePhotoSettings()
        if rapide { reglages.photoQualityPrioritization = .speed }
        if let connexion = sortie.connection(with: .video), connexion.isVideoRotationAngleSupported(90) {
            connexion.videoRotationAngle = 90
        }
        sortie.capturePhoto(with: reglages, delegate: self)
        DispatchQueue.main.async {
            self.tic.impactOccurred()
            self.flash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { self.flash = false }
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
                    guard !self.rafaleEnCours else { return }
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
            if camera.enregistre {
                HStack(spacing: 5) {
                    Circle().fill(.red).frame(width: 8, height: 8)
                    Text(String(format: "%d:%02d", camera.duree / 60, camera.duree % 60))
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.55)))
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, camera.zoomVisible || camera.zoomAffiche != 1 ? 36 : 8)
            }
            if camera.compteRafale > 0 {
                Text("\(camera.compteRafale)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(radius: 3)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            VStack(spacing: 4) {
                HStack(spacing: 14) {
                    ForEach(CameraModele.Mode.allCases, id: \.self) { m in
                        Text(m.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(camera.mode == m ? Color.yellow : .white.opacity(0.75))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 3)
                .background(Capsule().fill(.black.opacity(0.5)))
                Text(camera.message ?? (camera.mode == .photo
                     ? "Centre : photo · maintenu : rafale"
                     : (camera.enregistre ? "Centre : arrêter" : "Centre : filmer")))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.55)))
            }
            .padding(6)
        }
        .onAppear { camera.demarrer() }
        .onDisappear { camera.arreter() }
        .roue { g in
            g.tour = { s in camera.zoomer(s) }
            g.centre = { camera.action() }
            g.centreMaintenu = { camera.debutRafale() }
            g.centreRelache = { camera.finRafale() }
            g.precedent = { camera.changerMode(-1) }
            g.suivant = { camera.changerMode(1) }
            g.lecture = { camera.changerCamera() }
        }
    }
}
