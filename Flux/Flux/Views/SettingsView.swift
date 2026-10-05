import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.instanceKey) private var instance = Prefs.defaultInstances[0]
    @AppStorage(Prefs.regionKey) private var region = "FR"
    @AppStorage(Prefs.fallbackKey) private var fallback = true
    @State private var custom = ""
    @State private var testResult: String?
    @State private var testing = false

    private var allInstances: [String] {
        var list = Prefs.defaultInstances
        if !list.contains(instance) { list.insert(instance, at: 0) }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Instance", selection: $instance) {
                        ForEach(allInstances, id: \.self) { Text(host($0)).tag($0) }
                    }
                    TextField("https://pipedapi.ton-domaine.xyz", text: $custom)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Utiliser cette instance") {
                        instance = Prefs.normalize(custom)
                        custom = ""
                    }
                    .disabled(custom.trimmingCharacters(in: .whitespaces).isEmpty)
                    Toggle("Basculer si l'instance tombe", isOn: $fallback)
                    Button {
                        Task { await test() }
                    } label: {
                        HStack {
                            Text("Tester l'instance")
                            Spacer()
                            if testing { ProgressView() } else if let testResult { Text(testResult).foregroundStyle(.secondary) }
                        }
                    }
                } header: {
                    Text("Instance Piped")
                } footer: {
                    Text("Toutes les requêtes (pages, miniatures, vidéos) passent par cette instance. Ton téléphone ne parle jamais à Google. Désactive la bascule si tu utilises ta propre instance et veux qu'aucune autre ne voie ton trafic.")
                }

                Section("Contenu") {
                    TextField("Région des tendances", text: $region)
                        .textInputAutocapitalization(.characters)
                    LabeledContent("Shorts", value: "Masqués partout")
                    LabeledContent("Publicités", value: "Aucune")
                    LabeledContent("Trackers", value: "Aucun")
                }

                Section {
                    LabeledContent("Version", value: "1.0")
                } footer: {
                    Text("Flux — client YouTube libre basé sur Piped. Pas de compte, pas de cookies, abonnements stockés uniquement sur cet appareil.")
                }
            }
            .navigationTitle("Réglages")
        }
    }

    private func host(_ s: String) -> String {
        URL(string: s)?.host ?? s
    }

    private func test() async {
        testing = true
        testResult = nil
        defer { testing = false }
        do {
            let ms = try await PipedAPI.shared.ping(instance)
            testResult = "OK · \(ms) ms"
        } catch {
            testResult = "Hors ligne"
        }
    }
}
