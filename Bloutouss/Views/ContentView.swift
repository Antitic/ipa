import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var scanner: BluetoothScanner
    @AppStorage(SettingsKey.keepScreenOn) private var keepScreenOn = false

    private var activeTrackerCount: Int {
        scanner.devices.values.filter { $0.info.isTracker && !$0.isStale(now: scanner.now) }.count
    }

    var body: some View {
        TabView {
            DeviceListView()
                .tabItem { Label("Appareils", systemImage: "list.bullet") }
            RadarView()
                .tabItem { Label("Radar", systemImage: "scope") }
            TrackersView()
                .tabItem { Label("Traqueurs", systemImage: "exclamationmark.shield") }
                .badge(activeTrackerCount)
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .overlay(alignment: .top) {
            if let alert = scanner.favoriteAlert {
                FavoriteBanner(alert: alert)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { scanner.favoriteAlert = nil }
                    .task(id: alert.id) {
                        do {
                            try await Task.sleep(nanoseconds: 4_000_000_000)
                            scanner.favoriteAlert = nil
                        } catch {}
                    }
            }
        }
        .animation(.spring(), value: scanner.favoriteAlert)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepScreenOn }
        .onChange(of: keepScreenOn) { newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
    }
}
