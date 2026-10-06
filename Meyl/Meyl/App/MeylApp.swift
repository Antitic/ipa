import SwiftUI

@main
struct MeylApp: App {
    @StateObject private var store = MailStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

enum Route: Hashable {
    case box(String)
    case message(MailRow)
}

struct RootView: View {
    @EnvironmentObject var store: MailStore
    @Environment(\.scenePhase) private var phase
    @State private var path = NavigationPath()
    @State private var compose: Draft?
    @State private var didApplyLaunchArgs = false

    var body: some View {
        ZStack(alignment: .top) {
            if store.account == nil {
                LoginView()
                    .transition(.opacity)
            } else {
                NavigationStack(path: $path) {
                    HomeView(compose: $compose)
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .box(let box):
                                MessageListView(box: box, compose: $compose)
                            case .message(let row):
                                ReaderView(row: row, compose: $compose)
                            }
                        }
                }
                .transition(.opacity)
                .sheet(item: $compose) { draft in
                    ComposeView(draft: draft)
                        .environmentObject(store)
                }
            }

            if let t = store.toast {
                TelegramToast(toast: t)
                    .padding(.top, 70)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                    .onTapGesture { withAnimation { store.toast = nil } }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.account == nil)
        .onChange(of: phase) { _, p in
            if p == .active {
                store.startPolling()
            } else {
                store.stopPolling()
            }
        }
        .onChange(of: store.account == nil) { _, loggedOut in
            if loggedOut {
                path = NavigationPath()
                compose = nil
            } else {
                store.startPolling()
            }
        }
        .onAppear {
            store.startPolling()
            applyLaunchArgs()
        }
    }

    /// Arguments de lancement utilisés pour les captures d'écran automatiques.
    private func applyLaunchArgs() {
        guard !didApplyLaunchArgs else { return }
        didApplyLaunchArgs = true
        let d = UserDefaults.standard
        if let box = d.string(forKey: "openBox") {
            path.append(Route.box(box))
        }
        if let uid = d.string(forKey: "openMessage").flatMap(Int.init),
           let row = store.rows["INBOX"]?.first(where: { $0.uid == uid }) {
            path.append(Route.message(row))
        }
        if d.bool(forKey: "openCompose") {
            var draft = Draft()
            draft.to = "lea@example.org"
            draft.subject = "Ce soir"
            draft.body = "Salut Léa,\n\nCarrément, on se lance une partie vers 21 h ?\n\nT."
            compose = draft
        }
    }
}
