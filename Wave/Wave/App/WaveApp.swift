import SwiftUI

@main
struct WaveApp: App {
    init() {
        // Titres en SF Pro Rounded, comme Santé et Forme ; le reste suit le style système.
        let navBar = UINavigationBar.appearance()
        navBar.largeTitleTextAttributes = [.font: Self.roundedFont(size: 34, weight: .bold)]
        navBar.titleTextAttributes = [.font: Self.roundedFont(size: 17, weight: .semibold)]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }

    private static func roundedFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { DetectorHome() }
                .tabItem { Label("Détecteur", systemImage: "viewfinder") }
            NavigationStack { SatellitesView() }
                .tabItem { Label("Satellites", systemImage: "globe.europe.africa.fill") }
            NavigationStack { NetworkInfoView() }
                .tabItem { Label("Réseau", systemImage: "network") }
            NavigationStack { MagnetView() }
                .tabItem { Label("Magnéto", systemImage: "location.north.circle.fill") }
        }
        .tint(Theme.accent)
    }
}
