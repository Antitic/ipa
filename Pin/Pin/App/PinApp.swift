import SwiftUI
import AVFoundation

@main
struct PinApp: App {
    @StateObject private var nav = Navigateur()
    @StateObject private var compte = Compte()
    @StateObject private var lecteur = Lecteur()
    @StateObject private var whatsapp = WhatsAppStore()
    @StateObject private var clavier = Clavier()
    @Environment(\.scenePhase) private var phase

    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        UIDevice.current.isBatteryMonitoringEnabled = true
        UserDefaults.standard.register(defaults: ["haptique": true, "clics": true])
    }

    var body: some Scene {
        WindowGroup {
            Coque()
                .environmentObject(nav)
                .environmentObject(compte)
                .environmentObject(lecteur)
                .environmentObject(whatsapp)
                .environmentObject(clavier)
                .preferredColorScheme(.light)
                .statusBarHidden(true)
                .task { await compte.verifier() }
                .task {
                    ClaudeWeb.partage.clavier = clavier
                    ClaudeWeb.partage.demarrer()
                }
                .onChange(of: compte.connecte) { _, connecte in
                    if connecte { whatsapp.demarrer() } else { whatsapp.arreter() }
                }
                .onChange(of: phase) { _, p in
                    if p == .active, compte.connecte { whatsapp.demarrer() }
                }
        }
    }
}
