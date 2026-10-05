import SwiftUI
import AVFoundation

@main
struct FluxApp: App {
    @StateObject private var library = Library()

    init() {
        // Lecture en arrière-plan + Picture in Picture
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        // Aucun cookie, jamais
        HTTPCookieStorage.shared.cookieAcceptPolicy = .never
        // Cache des miniatures (servies par le proxy Piped, pas par Google)
        URLCache.shared = URLCache(memoryCapacity: 50_000_000, diskCapacity: 200_000_000)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .tint(.pink)
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Accueil", systemImage: "house") }
            SearchView()
                .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
            SubscriptionsView()
                .tabItem { Label("Abonnements", systemImage: "person.2") }
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
    }
}
