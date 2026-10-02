import SwiftUI

@main
struct BloutoussApp: App {
    @StateObject private var store: DeviceStore
    @StateObject private var scanner: BluetoothScanner

    init() {
        AppSettings.registerDefaults()
        let store = DeviceStore()
        _store = StateObject(wrappedValue: store)
        _scanner = StateObject(wrappedValue: BluetoothScanner(store: store))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scanner)
                .environmentObject(store)
        }
    }
}
