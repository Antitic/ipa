import Foundation

/// Élément générique renvoyé par Piped (vidéo, chaîne ou playlist).
struct PipedItem: Codable, Hashable, Identifiable {
    let url: String
    let type: String?
    let title: String?
    let name: String?
    let thumbnail: String?
    let uploaderName: String?
    let uploaderUrl: String?
    let uploaderAvatar: String?
    let uploadedDate: String?
    let duration: Int?
    let views: Int?
    let uploaded: Int64?
    let isShort: Bool?
    let subscribers: Int?

    var id: String { url }

    enum Kind { case video, channel, playlist }

    var kind: Kind {
        if type == "channel" || url.hasPrefix("/channel/") { return .channel }
        if type == "playlist" || url.hasPrefix("/playlist") { return .playlist }
        return .video
    }

    var displayTitle: String { title ?? name ?? "" }

    var videoID: String? {
        if url.hasPrefix("/shorts/") { return String(url.dropFirst("/shorts/".count)) }
        guard let comps = URLComponents(string: "https://piped.local" + url) else { return nil }
        return comps.queryItems?.first(where: { $0.name == "v" })?.value
    }

    var channelID: String? {
        Self.channelID(from: kind == .channel ? url : uploaderUrl)
    }

    static func channelID(from url: String?) -> String? {
        guard let url, url.contains("/channel/") else { return nil }
        return url.components(separatedBy: "/channel/").last?
            .components(separatedBy: "?").first
    }

    /// Détection des Shorts : flag Piped, URL /shorts/, durée ≤ 60 s ou #shorts dans le titre.
    var isShortForm: Bool {
        if isShort == true { return true }
        if url.contains("/shorts/") { return true }
        if let d = duration, d > 0, d <= 60 { return true }
        if displayTitle.lowercased().contains("#shorts") { return true }
        return false
    }
}

extension Array where Element == PipedItem {
    /// Retire les Shorts, les playlists et les doublons.
    var cleaned: [PipedItem] {
        var seen = Set<String>()
        return filter { item in
            guard item.kind != .playlist, !item.isShortForm else { return false }
            return seen.insert(item.id).inserted
        }
    }
}

struct SearchPage: Codable {
    let items: [PipedItem]
    let nextpage: String?
}

struct ChannelPage: Codable {
    let id: String?
    let name: String?
    let avatarUrl: String?
    let bannerUrl: String?
    let description: String?
    let subscriberCount: Int?
    let relatedStreams: [PipedItem]?
    let nextpage: String?
}

struct ChannelNextPage: Codable {
    let relatedStreams: [PipedItem]?
    let nextpage: String?
}

struct MediaStream: Codable, Hashable {
    let url: String
    let format: String?
    let quality: String?
    let mimeType: String?
    let codec: String?
    let videoOnly: Bool?
    let height: Int?
    let bitrate: Int?
}

struct StreamDetail: Codable {
    let title: String
    let description: String?
    let uploader: String?
    let uploaderUrl: String?
    let uploaderAvatar: String?
    let uploaderSubscriberCount: Int?
    let thumbnailUrl: String?
    let hls: String?
    let duration: Int?
    let views: Int?
    let likes: Int?
    let uploadDate: String?
    let livestream: Bool?
    let videoStreams: [MediaStream]?
    let audioStreams: [MediaStream]?
    let relatedStreams: [PipedItem]?
}

struct ChannelRef: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let avatar: String?
}
