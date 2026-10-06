import SwiftUI

@main
struct MeylApp: App {
    @StateObject private var store = MailStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
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
    @AppStorage("theme") private var themeRaw = AppTheme.codex.rawValue
    @State private var path = NavigationPath()
    @State private var compose: Draft?
    @State private var didApplyLaunchArgs = false

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .codex }

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if store.account == nil {
                    switch theme {
                    case .codex: CodexLoginView()
                    case .ecritoire: LoginView()
                    }
                } else {
                    NavigationStack(path: $path) {
                        Group {
                            switch theme {
                            case .codex: CodexHomeView(compose: $compose)
                            case .ecritoire: HomeView(compose: $compose)
                            }
                        }
                        .navigationDestination(for: Route.self) { route in
                            switch (route, theme) {
                            case (.box(let box), .ecritoire):
                                MessageListView(box: box, compose: $compose)
                            case (.box, .codex):
                                CodexHomeView(compose: $compose)
                            case (.message(let row), .codex):
                                CodexReaderView(row: row, compose: $compose)
                            case (.message(let row), .ecritoire):
                                ReaderView(row: row, compose: $compose)
                            }
                        }
                    }
                    .sheet(item: $compose) { draft in
                        Group {
                            switch theme {
                            case .codex: CodexComposeView(draft: draft).preferredColorScheme(.light)
                            case .ecritoire: ComposeView(draft: draft).preferredColorScheme(.dark)
                            }
                        }
                        .environmentObject(store)
                    }
                }
            }
            .id(theme) // changer de thème reconstruit proprement l'interface
            .transition(.opacity)

            if let t = store.toast {
                Group {
                    switch theme {
                    case .codex: CXToast(toast: t).padding(.top, 58)
                    case .ecritoire: TelegramToast(toast: t).padding(.top, 70)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
                .onTapGesture { withAnimation { store.toast = nil } }
            }
        }
        .preferredColorScheme(theme == .codex ? .light : .dark)
        .animation(.easeInOut(duration: 0.35), value: store.account == nil)
        .animation(.easeInOut(duration: 0.3), value: themeRaw)
        .sheet(isPresented: $store.showSettings) {
            SettingsView()
                .environmentObject(store)
                .preferredColorScheme(.light)
        }
        .onChange(of: themeRaw) { _, _ in
            path = NavigationPath()
        }
        .onChange(of: phase) { _, p in
            if p == .active { store.startPolling() } else { store.stopPolling() }
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
        if theme == .ecritoire, let box = d.string(forKey: "openBox") {
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
        if d.bool(forKey: "openSettings") {
            store.showSettings = true
        }
    }
}
