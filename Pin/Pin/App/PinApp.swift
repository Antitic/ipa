import SwiftUI
import AVFoundation

@main
struct PinApp: App {
    @StateObject private var nav = Navigateur()
    @StateObject private var compte = Compte()
    @StateObject private var lecteur = Lecteur()
    @StateObject private var whatsapp = WhatsAppStore()
    @Environment(\.scenePhase) private var phase

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        UIDevice.current.isBatteryMonitoringEnabled = true
        UserDefaults.standard.register(defaults: ["haptique": true])
    }

    var body: some Scene {
        WindowGroup {
            Coque()
                .environmentObject(nav)
                .environmentObject(compte)
                .environmentObject(lecteur)
                .environmentObject(whatsapp)
                .preferredColorScheme(.light)
                .statusBarHidden(true)
                .task { await compte.verifier() }
                .onChange(of: compte.connecte) { _, connecte in
                    if connecte { whatsapp.demarrer() } else { whatsapp.arreter() }
                }
                .onChange(of: phase) { _, p in
                    if p == .active, compte.connecte { whatsapp.demarrer() }
                }
        }
    }
}
