import SwiftUI

@main
struct WaveApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { DetectorHome() }
                .tabItem { Label("Détecteur", systemImage: "viewfinder") }
            NavigationStack { SatellitesView() }
                .tabItem { Label("Satellites", systemImage: "globe.europe.africa") }
            NavigationStack { NetworkInfoView() }
                .tabItem { Label("Réseau", systemImage: "network") }
            NavigationStack { MagnetView() }
                .tabItem { Label("Magnéto", systemImage: "location.north.circle") }
        }
    }
}
