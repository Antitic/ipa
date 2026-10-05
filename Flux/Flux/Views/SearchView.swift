import SwiftUI

struct SearchView: View {
    @State private var query = ""
    @State private var submitted = ""
    @State private var items: [PipedItem] = []
    @State private var nextpage: String?
    @State private var suggestions: [String] = []
    @State private var loading = false
    @State private var loadingMore = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if loading {
                    ProgressView().padding(.top, 120)
                } else if let error {
                    MessageView(icon: "exclamationmark.triangle", title: "Erreur", message: error, retry: search)
                } else if submitted.isEmpty {
                    MessageView(icon: "magnifyingglass", title: "Recherche",
                                message: "Sans Shorts, sans pubs, sans Google.")
                } else if items.isEmpty {
                    MessageView(icon: "questionmark.circle", title: "Aucun résultat")
                } else {
                    ItemList(items: items, onReachEnd: loadMore).padding(.vertical)
                    if loadingMore { ProgressView().padding() }
                }
            }
            .navigationTitle("Recherche")
            .searchable(text: $query, prompt: "Vidéos, chaînes…")
            .searchSuggestions {
                ForEach(suggestions, id: \.self) { s in
                    Text(s).searchCompletion(s)
                }
            }
            .onSubmit(of: .search) { Task { await search() } }
            .task(id: query) { await fetchSuggestions() }
            .fluxDestinations()
        }
    }

    private func fetchSuggestions() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count > 1, q != submitted else { suggestions = []; return }
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        suggestions = (try? await PipedAPI.shared.suggestions(q)) ?? []
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        submitted = q
        suggestions = []
        loading = true
        error = nil
        defer { loading = false }
        do {
            let page = try await PipedAPI.shared.search(q)
            items = page.items.cleaned
            nextpage = page.nextpage
        } catch let e {
            if !isCancellation(e) { error = e.localizedDescription }
        }
    }

    private func loadMore() async {
        guard let page = nextpage, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        if let next = try? await PipedAPI.shared.searchNext(submitted, page: page) {
            items = (items + next.items).cleaned
            nextpage = next.nextpage
        }
    }
}
