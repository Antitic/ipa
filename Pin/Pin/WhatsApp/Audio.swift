import Foundation
import AVFoundation
import Speech

/// La session audio passe en enregistrement le temps d'un vocal ou d'une
/// dictée, puis revient en lecture seule pour la musique.
enum SessionAudio {
    static func enregistrement() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try s.setActive(true)
    }

    static func lecture() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true, options: [])
    }

    static func micro() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

/// Enregistre un vocal WhatsApp en M4A (le serveur le convertit en OGG/Opus).
@MainActor
final class Enregistreur: ObservableObject {
    @Published private(set) var actif = false
    @Published private(set) var duree: Double = 0
    private var recorder: AVAudioRecorder?
    private var minuteur: Timer?
    private var url: URL?

    func demarrer() {
        guard !actif else { return }
        Task {
            guard await SessionAudio.micro() else { return }
            do {
                try SessionAudio.enregistrement()
                let u = FileManager.default.temporaryDirectory.appendingPathComponent("vocal-\(UUID().uuidString).m4a")
                let reglages: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                ]
                let r = try AVAudioRecorder(url: u, settings: reglages)
                r.record()
                recorder = r
                url = u
                duree = 0
                actif = true
                minuteur = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let r = self.recorder else { return }
                        self.duree = r.currentTime
                    }
                }
            } catch {
                actif = false
            }
        }
    }

    /// Arrête l'enregistrement et rend le fichier et sa durée.
    func terminer() -> (Data, Double)? {
        minuteur?.invalidate()
        minuteur = nil
        guard actif, let r = recorder, let u = url else { actif = false; return nil }
        let d = r.currentTime
        r.stop()
        recorder = nil
        actif = false
        SessionAudio.lecture()
        defer { try? FileManager.default.removeItem(at: u) }
        guard let data = try? Data(contentsOf: u) else { return nil }
        return (data, d)
    }
}

/// Lit les vocaux WhatsApp (téléchargés en M4A depuis le serveur).
@MainActor
final class LecteurVocal: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var enCours: String?
    private var player: AVAudioPlayer?

    func basculer(_ id: String) {
        if enCours == id {
            arreter()
            return
        }
        arreter()
        enCours = id
        Task {
            guard let data = try? await API.donnees("/api/whatsapp/medias/\(API.segment(id))"),
                  enCours == id else { enCours = nil; return }
            SessionAudio.lecture()
            do {
                let p = try AVAudioPlayer(data: data)
                p.delegate = self
                p.play()
                player = p
            } catch {
                enCours = nil
            }
        }
    }

    func arreter() {
        player?.stop()
        player = nil
        enCours = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.enCours = nil }
    }
}

/// La dictée d'Apple (framework Speech, en français).
@MainActor
final class Dictee: ObservableObject {
    @Published private(set) var actif = false
    private let reconnaissance = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let moteur = AVAudioEngine()
    private var requete: SFSpeechAudioBufferRecognitionRequest?
    private var tache: SFSpeechRecognitionTask?

    func demarrer(_ maj: @escaping (String) -> Void) {
        guard !actif else { return }
        Task {
            let autorise = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
            }
            guard autorise, await SessionAudio.micro(), let reco = reconnaissance, reco.isAvailable else { return }
            do {
                try SessionAudio.enregistrement()
                let req = SFSpeechAudioBufferRecognitionRequest()
                req.shouldReportPartialResults = true
                if reco.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = false }
                requete = req
                let entree = moteur.inputNode
                let format = entree.outputFormat(forBus: 0)
                entree.removeTap(onBus: 0)
                entree.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] tampon, _ in
                    req?.append(tampon)
                }
                moteur.prepare()
                try moteur.start()
                actif = true
                tache = reco.recognitionTask(with: req) { [weak self] resultat, erreur in
                    let texte = resultat?.bestTranscription.formattedString
                    let fini = erreur != nil || (resultat?.isFinal ?? false)
                    Task { @MainActor in
                        if let texte { maj(texte) }
                        if fini { self?.arreter() }
                    }
                }
            } catch {
                arreter()
            }
        }
    }

    func arreter() {
        guard actif || tache != nil else { return }
        moteur.stop()
        moteur.inputNode.removeTap(onBus: 0)
        requete?.endAudio()
        tache?.cancel()
        tache = nil
        requete = nil
        actif = false
        SessionAudio.lecture()
    }
}
