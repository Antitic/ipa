import SwiftUI

struct ChannelView: View {
    let channelID: String

    @State private var channel: ChannelPage?
    @State private var items: [PipedItem] = []
    @State private var nextpage: String?
    @State private var loadingMore = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            if let channel {
                header(channel)
                if items.isEmpty {
                    MessageView(icon: "film", title: "Aucune vidéo (hors Shorts)")
                } else {
                    ItemList(items: items, onReachEnd: loadMore).padding(.vertical)
                    if loadingMore { ProgressView().padding() }
                }
            } else if let error {
                MessageView(icon: "exclamationmark.triangle", title: "Erreur", message: error, retry: load)
            } else {
                ProgressView().padding(.top, 120)
            }
        }
        .navigationTitle(channel?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task { if channel == nil { await load() } }
    }

    private func header(_ c: ChannelPage) -> some View {
        VStack(spacing: 0) {
            if let banner = c.bannerUrl {
                Color.clear
                    .frame(height: 100)
                    .overlay(RemoteImage(url: banner))
                    .clipped()
            }
            HStack(spacing: 14) {
                Avatar(url: c.avatarUrl, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.name ?? "").font(.title3.bold()).lineLimit(2)
                    if let subs = Fmt.count(c.subscriberCount) {
                        Text("\(subs) abonnés").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                SubscribeButton(ref: ChannelRef(id: channelID, name: c.name ?? channelID, avatar: c.avatarUrl))
            }
            .padding()
            Divider()
        }
    }

    private func load() async {
        error = nil
        do {
            let c = try await PipedAPI.shared.channel(channelID)
            items = (c.relatedStreams ?? []).cleaned
            nextpage = c.nextpage
            channel = c
        } catch let e {
            if !isCancellation(e) { error = e.localizedDescription }
        }
    }

    private func loadMore() async {
        guard let page = nextpage, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        if let next = try? await PipedAPI.shared.channelNext(channelID, page: page) {
            items = (items + (next.relatedStreams ?? [])).cleaned
            nextpage = next.nextpage
        }
    }
}
