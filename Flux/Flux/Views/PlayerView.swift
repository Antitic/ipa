import SwiftUI
import AVKit

struct PlayerView: View {
    let videoID: String

    @State private var detail: StreamDetail?
    @State private var player: AVPlayer?
    @State private var error: String?
    @State private var fullDescription = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    Color.black
                    if let player {
                        PlayerController(player: player)
                    } else if let error {
                        Text(error).font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center).padding()
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .aspectRatio(16 / 9, contentMode: .fit)

                if let d = detail { info(d) }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder private func info(_ d: StreamDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(d.title).font(.headline)

            Text([
                Fmt.count(d.views).map { "\($0) vues" },
                d.uploadDate.map { String($0.prefix(10)) },
                Fmt.count(d.likes).map { "\($0) j'aime" },
            ].compactMap { $0 }.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if let cid = PipedItem.channelID(from: d.uploaderUrl) {
                    NavigationLink(value: Route.channel(cid)) {
                        HStack(spacing: 10) {
                            Avatar(url: d.uploaderAvatar, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(d.uploader ?? "").font(.subheadline.weight(.semibold))
                                if let subs = Fmt.count(d.uploaderSubscriberCount) {
                                    Text("\(subs) abonnés").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    SubscribeButton(ref: ChannelRef(id: cid, name: d.uploader ?? cid, avatar: d.uploaderAvatar))
                }
            }

            if let desc = d.description, !desc.isEmpty {
                Text(Fmt.stripHTML(desc))
                    .font(.footnote)
                    .lineLimit(fullDescription ? nil : 3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { withAnimation { fullDescription.toggle() } }
            }
        }
        .padding(.horizontal)

        let related = (d.relatedStreams ?? []).cleaned.filter { $0.kind == .video }
        if !related.isEmpty {
            Text("À suivre").font(.title3.bold()).padding(.horizontal).padding(.top, 8)
            ItemList(items: related).padding(.bottom)
        }
    }

    private func load() async {
        guard detail == nil else { return }
        do {
            let d = try await PipedAPI.shared.streams(videoID)
            detail = d
            let item = try await PlayerFactory.makeItem(for: d)
            let p = AVPlayer(playerItem: item)
            player = p
            p.play()
        } catch let e {
            if !isCancellation(e) { error = e.localizedDescription }
        }
    }
}

struct PlayerController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.allowsPictureInPicturePlayback = true
        vc.canStartPictureInPictureAutomaticallyFromInline = true
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.exitsFullScreenWhenPlaybackEnds = true
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}

/// Construit l'item de lecture à partir des flux proxifiés par Piped.
enum PlayerFactory {
    static func makeItem(for d: StreamDetail) async throws -> AVPlayerItem {
        // 1. HLS (adaptatif, idéal — surtout pour les directs)
        if let hls = d.hls, !hls.isEmpty, let url = URL(string: hls) {
            return AVPlayerItem(url: url)
        }

        let videos = d.videoStreams ?? []
        let byHeight: (MediaStream, MediaStream) -> Bool = { ($0.height ?? 0) < ($1.height ?? 0) }

        // 2. Flux vidéo+audio déjà multiplexé
        if let muxed = videos.filter({ $0.videoOnly == false && ($0.mimeType ?? "").contains("mp4") }).max(by: byHeight),
           let url = URL(string: muxed.url) {
            return AVPlayerItem(url: url)
        }

        // 3. Vidéo seule H.264 + audio AAC, assemblés à la volée
        let mp4Video = videos.filter { $0.videoOnly == true && ($0.mimeType ?? "").contains("mp4") && ($0.height ?? 0) <= 1080 }
        let avc = mp4Video.filter { ($0.codec ?? "").hasPrefix("avc1") }
        guard let v = (avc.isEmpty ? mp4Video : avc).max(by: byHeight),
              let a = (d.audioStreams ?? []).filter({ ($0.mimeType ?? "").contains("mp4") }).max(by: { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }),
              let vURL = URL(string: v.url), let aURL = URL(string: a.url)
        else { throw APIError.noStream }

        let vAsset = AVURLAsset(url: vURL)
        let aAsset = AVURLAsset(url: aURL)
        let vTracks = try await vAsset.loadTracks(withMediaType: .video)
        let aTracks = try await aAsset.loadTracks(withMediaType: .audio)
        guard let vTrack = vTracks.first, let aTrack = aTracks.first else { throw APIError.noStream }

        let vDuration = try await vAsset.load(.duration)
        let aDuration = try await aAsset.load(.duration)
        let range = CMTimeRange(start: .zero, duration: CMTimeMinimum(vDuration, aDuration))

        let composition = AVMutableComposition()
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: vTrack, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: aTrack, at: .zero)
        return AVPlayerItem(asset: composition)
    }
}
