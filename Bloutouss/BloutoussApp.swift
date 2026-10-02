import SwiftUI

@main
struct BloutoussApp: App {
    @StateObject private var scanner = BluetoothScanner()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scanner)
        }
    }
}
