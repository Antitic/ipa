import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var library: Library
    @State private var items: [PipedItem] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if !items.isEmpty {
                    ItemList(items: items).padding(.vertical)
                } else if loading {
                    ProgressView().padding(.top, 120)
                } else if let error {
                    MessageView(icon: "wifi.exclamationmark", title: "Impossible de charger",
                                message: error, retry: load)
                } else {
                    MessageView(icon: "sparkles.tv", title: "Rien à afficher",
                                message: "Cherche des chaînes et abonne-toi pour remplir ton fil.")
                }
            }
            .navigationTitle(library.subscriptions.isEmpty ? "Tendances" : "Accueil")
            .refreshable { await load() }
            .task(id: library.subscriptionIDs) { await load() }
            .fluxDestinations()
        }
    }

    private func load() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            if library.subscriptions.isEmpty {
                items = try await PipedAPI.shared.trending().cleaned
            } else {
                items = try await PipedAPI.shared.feed(library.subscriptionIDs)
                    .cleaned
                    .sorted { ($0.uploaded ?? 0) > ($1.uploaded ?? 0) }
            }
        } catch let e {
            if !isCancellation(e) { error = e.localizedDescription }
        }
    }
}
