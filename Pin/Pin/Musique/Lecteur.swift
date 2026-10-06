import Foundation
import AVFoundation
import MediaPlayer
import UIKit

struct Morceau: Codable, Identifiable, Equatable {
    let id: String
    let titre: String
    let artiste: String?
    let duree: Double
    let pochette: Bool
}

struct StatutTelegram: Decodable {
    let lie: Bool
    let nom: String?
    let etape: String?
    let configure: Bool?
}

/// Le lecteur de musique. Chaque morceau est d'abord téléchargé dans le cache
/// de l'app (Caches/Musique), puis lu depuis le disque : il reste disponible
/// hors connexion, et AVPlayer n'a pas à gérer le cookie de session.
@MainActor
final class Lecteur: ObservableObject {
    @Published private(set) var file: [Morceau] = []
    @Published private(set) var index = 0
    @Published private(set) var enLecture = false
    @Published private(set) var chargement = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duree: Double = 0
    @Published var volume: Float = 0.8 { didSet { player.volume = volume } }
    @Published var erreur: String?
    @Published var pochette: UIImage?

    var courant: Morceau? { file.indices.contains(index) ? file[index] : nil }

    private let player = AVPlayer()
    private var observateur: Any?
    private var finObservateur: NSObjectProtocol?
    private var tacheChargement: Task<Void, Never>?

    nonisolated static let dossier: URL = {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Musique", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    init() {
        player.volume = volume
        observateur = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.position = t.seconds.isFinite ? t.seconds : 0
                if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 { self.duree = d }
            }
        }
        finObservateur = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.suivant() }
        }
        configurerTelecommande()
    }

    // MARK: - Commandes

    func jouer(_ morceaux: [Morceau], depuis i: Int) {
        file = morceaux
        index = i
        charger()
    }

    func basculer() {
        guard courant != nil else { return }
        if enLecture { pause() } else { reprendre() }
    }

    func reprendre() {
        guard player.currentItem != nil else { charger(); return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        enLecture = true
        majInfos()
    }

    func pause() {
        player.pause()
        enLecture = false
        majInfos()
    }

    func suivant() {
        guard !file.isEmpty else { return }
        guard index + 1 < file.count else { pause(); player.seek(to: .zero); return }
        index += 1
        charger()
    }

    func precedent() {
        guard !file.isEmpty else { return }
        if position > 3 || index == 0 {
            player.seek(to: .zero)
            return
        }
        index -= 1
        charger()
    }

    func avancer(_ secondes: Double) {
        let cible = min(max(position + secondes, 0), max(duree - 1, 0))
        position = cible
        player.seek(to: CMTime(seconds: cible, preferredTimescale: 600))
        majInfos()
    }

    func viderCache() {
        try? FileManager.default.removeItem(at: Self.dossier)
        try? FileManager.default.createDirectory(at: Self.dossier, withIntermediateDirectories: true)
    }

    // MARK: - Chargement

    nonisolated private static let extensions = ["mp3", "m4a", "flac", "wav", "aiff"]

    /// Fichier déjà en cache pour ce morceau, quelle que soit son extension.
    nonisolated static func fichierEnCache(_ id: String) -> URL? {
        for ext in extensions {
            let u = dossier.appendingPathComponent(id).appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    /// AVFoundation choisit son décodeur d'après l'extension : on la déduit des premiers octets.
    nonisolated static func extensionPour(_ d: Data) -> String {
        let o = [UInt8](d.prefix(12))
        if o.count >= 3, o[0] == 0x49, o[1] == 0x44, o[2] == 0x33 { return "mp3" }          // ID3
        if o.count >= 2, o[0] == 0xFF, (o[1] & 0xE0) == 0xE0 { return "mp3" }               // trame MPEG
        if o.count >= 8, o[4] == 0x66, o[5] == 0x74, o[6] == 0x79, o[7] == 0x70 { return "m4a" } // ftyp
        if o.count >= 4, o[0] == 0x66, o[1] == 0x4C, o[2] == 0x61, o[3] == 0x43 { return "flac" } // fLaC
        if o.count >= 4, o[0] == 0x52, o[1] == 0x49, o[2] == 0x46, o[3] == 0x46 { return "wav" }  // RIFF
        if o.count >= 4, o[0] == 0x46, o[1] == 0x4F, o[2] == 0x52, o[3] == 0x4D { return "aiff" } // FORM
        return "mp3"
    }

    nonisolated static func telecharger(_ id: String) async throws -> URL {
        if let u = fichierEnCache(id) { return u }
        let data = try await API.requete("/api/musique/\(API.segment(id))/audio", delai: 600)
        let u = dossier.appendingPathComponent(id).appendingPathExtension(extensionPour(data))
        try data.write(to: u)
        return u
    }

    private func charger() {
        guard let m = courant else { return }
        tacheChargement?.cancel()
        player.pause()
        position = 0
        duree = m.duree
        erreur = nil
        pochette = nil
        chargement = true
        enLecture = true
        majInfos()
        tacheChargement = Task {
            if m.pochette, let img = await API.image("/api/musique/\(API.segment(m.id))/pochette") {
                if courant?.id == m.id { pochette = img; majInfos() }
            }
        }
        Task {
            do {
                let url = try await Self.telecharger(m.id)
                guard courant?.id == m.id else { return }
                let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
                let item = AVPlayerItem(asset: asset)
                player.replaceCurrentItem(with: item)
                chargement = false
                reprendre()
            } catch {
                chargement = false
                enLecture = false
                self.erreur = error.localizedDescription
            }
        }
        // Précharge le suivant en arrière-plan.
        if index + 1 < file.count {
            let id = file[index + 1].id
            Task.detached(priority: .background) {
                _ = try? await Lecteur.telecharger(id)
            }
        }
    }

    // MARK: - Écran verrouillé

    private func configurerTelecommande() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.reprendre() }; return .success }
        c.pauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.pause() }; return .success }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.basculer() }; return .success }
        c.nextTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.suivant() }; return .success }
        c.previousTrackCommand.addTarget { [weak self] _ in MainActor.assumeIsolated { self?.precedent() }; return .success }
        c.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.avancer(e.positionTime - self.position)
            }
            return .success
        }
    }

    private func majInfos() {
        guard let m = courant else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var infos: [String: Any] = [
            MPMediaItemPropertyTitle: m.titre,
            MPMediaItemPropertyPlaybackDuration: duree,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: enLecture ? 1.0 : 0.0,
        ]
        if let a = m.artiste { infos[MPMediaItemPropertyArtist] = a }
        if let img = pochette {
            infos[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = infos
    }
}
