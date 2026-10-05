import SwiftUI

enum Route: Hashable {
    case video(String)
    case channel(String)
}

extension View {
    func fluxDestinations() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .video(let id): PlayerView(videoID: id)
            case .channel(let id): ChannelView(channelID: id)
            }
        }
    }
}

struct RemoteImage: View {
    let url: String?

    var body: some View {
        AsyncImage(url: url.flatMap { URL(string: $0) }) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Rectangle().fill(Color.secondary.opacity(0.15))
            }
        }
    }
}

struct Avatar: View {
    let url: String?
    var size: CGFloat = 36

    var body: some View {
        RemoteImage(url: url)
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}

struct VideoRow: View {
    let item: PipedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(RemoteImage(url: item.thumbnail))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomTrailing) { badge.padding(6) }

            HStack(alignment: .top, spacing: 10) {
                Avatar(url: item.uploaderAvatar)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var badge: some View {
        if item.duration == -1 {
            Text("EN DIRECT")
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
        } else if let d = Fmt.duration(item.duration) {
            Text(d)
                .font(.caption2.monospacedDigit().bold())
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
        }
    }

    private var meta: String {
        [
            item.uploaderName,
            Fmt.count(item.views).map { "\($0) vues" },
            Fmt.relative(ms: item.uploaded) ?? item.uploadedDate,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

struct ChannelRow: View {
    let item: PipedItem

    var body: some View {
        HStack(spacing: 14) {
            Avatar(url: item.thumbnail, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle).font(.headline)
                if let subs = Fmt.count(item.subscribers) {
                    Text("\(subs) abonnés").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct ItemList: View {
    let items: [PipedItem]
    var onReachEnd: (() async -> Void)? = nil

    var body: some View {
        LazyVStack(spacing: 22) {
            ForEach(items) { item in
                row(item)
                    .task {
                        if item.id == items.last?.id, let onReachEnd { await onReachEnd() }
                    }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder private func row(_ item: PipedItem) -> some View {
        switch item.kind {
        case .channel:
            if let id = item.channelID {
                NavigationLink(value: Route.channel(id)) { ChannelRow(item: item) }
                    .buttonStyle(.plain)
            }
        case .video:
            if let id = item.videoID {
                NavigationLink(value: Route.video(id)) { VideoRow(item: item) }
                    .buttonStyle(.plain)
            }
        case .playlist:
            EmptyView()
        }
    }
}

struct MessageView: View {
    let icon: String
    let title: String
    var message: String? = nil
    var retry: (() async -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let retry {
                Button("Réessayer") { Task { await retry() } }.buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

struct SubscribeButton: View {
    @EnvironmentObject private var library: Library
    let ref: ChannelRef

    var body: some View {
        let subscribed = library.isSubscribed(ref.id)
        Button {
            withAnimation { library.toggle(ref) }
        } label: {
            Text(subscribed ? "Abonné" : "S'abonner")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
        }
        .buttonStyle(.borderedProminent)
        .tint(subscribed ? Color.gray : Color.pink)
        .clipShape(Capsule())
    }
}

func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
}
