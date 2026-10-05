import SwiftUI
import UniformTypeIdentifiers

struct SubscriptionsView: View {
    @EnvironmentObject private var library: Library
    @State private var importing = false
    @State private var alert: String?

    var body: some View {
        NavigationStack {
            Group {
                if library.subscriptions.isEmpty {
                    ScrollView {
                        MessageView(icon: "person.2", title: "Aucun abonnement",
                                    message: "Abonne-toi depuis une chaîne, ou importe ton export Google Takeout (subscriptions.csv) ou NewPipe (.json).")
                    }
                } else {
                    List {
                        ForEach(library.subscriptions) { ch in
                            NavigationLink(value: Route.channel(ch.id)) {
                                HStack(spacing: 12) {
                                    Avatar(url: ch.avatar, size: 40)
                                    Text(ch.name)
                                }
                            }
                        }
                        .onDelete { library.remove(at: $0) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Abonnements")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }
                }
            }
            .fileImporter(isPresented: $importing,
                          allowedContentTypes: [.commaSeparatedText, .json, .plainText]) { result in
                switch result {
                case .success(let url):
                    do {
                        let n = try library.importFile(url)
                        alert = "\(n) chaîne(s) importée(s)."
                    } catch {
                        alert = "Import impossible : \(error.localizedDescription)"
                    }
                case .failure(let error):
                    alert = error.localizedDescription
                }
            }
            .alert(alert ?? "", isPresented: Binding(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .fluxDestinations()
        }
    }
}
