import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store
    @State private var testing = false
    @State private var testResult: (ok: Bool, message: String)?
    @State private var revealToken = false
    @FocusState private var focused: Field?

    private enum Field { case url, token }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(spacing: 18) {
                Plate(title: "Liaison avec le serveur") {
                    slot(label: "Adresse de l'agent") {
                        TextField("http://100.100.226.91:8787", text: $store.baseURL)
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .focused($focused, equals: .url)
                            .submitLabel(.next)
                            .onSubmit { focused = .token }
                    }
                    slot(label: "Jeton d'accès") {
                        HStack {
                            Group {
                                if revealToken {
                                    TextField("colle le jeton ici", text: $store.token)
                                } else {
                                    SecureField("colle le jeton ici", text: $store.token)
                                }
                            }
                            .focused($focused, equals: .token)
                            .submitLabel(.done)
                            .onSubmit { apply() }
                            Button {
                                revealToken.toggle()
                            } label: {
                                Image(systemName: revealToken ? "eye.slash" : "eye")
                                    .foregroundStyle(Palette.phosphor.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 12) {
                        Button("Appliquer") { apply() }
                            .buttonStyle(KeyButtonStyle())
                        Button(testing ? "Essai…" : "Tester") { test() }
                            .buttonStyle(KeyButtonStyle())
                            .disabled(testing)
                        Spacer(minLength: 0)
                        LED(color: testResult.map { $0.ok ? Palette.ledGreen : Palette.ledRed } ?? Palette.ledAmber,
                            on: testing || testResult != nil, size: 10, blinking: testing)
                    }
                    if let r = testResult {
                        Text(r.message)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(r.ok ? Color(hex: 0x14532D) : Color(hex: 0x8B1A12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Plate(title: "Mode démonstration") {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Données fictives qui bougent, pour admirer le tableau de bord sans être connecté.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(hex: 0x2C2F33, opacity: 0.85))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(store.token.isEmpty ? "Actif tant qu'aucun jeton n'est saisi." : " ")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color(hex: 0x2C2F33, opacity: 0.6))
                        }
                        Spacer(minLength: 0)
                        VStack(spacing: 2) {
                            Engraved(text: "Marche", size: 8)
                            ToggleSwitch(isOn: $store.demoMode)
                            Engraved(text: "Arrêt", size: 8)
                        }
                    }
                }
                .onChange(of: store.demoMode) { _, _ in store.saveSettings() }

                Plate(title: "Cadence de relève") {
                    HStack {
                        RotaryKnob(options: Store.intervalLabels, selection: $store.intervalIndex, knobSize: 56)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Engraved(text: "Toutes les", size: 9)
                            HStack(spacing: 6) {
                                SegmentWindow(text: String(format: "%.0f", Store.intervals[min(max(store.intervalIndex, 0), 3)]),
                                              color: Palette.segRed, height: 22)
                                Engraved(text: "s", size: 10)
                            }
                            Text("Plus rapide = aiguilles plus vivantes,\nmais un peu plus de batterie.")
                                .font(.system(size: 10, weight: .medium))
                                .multilineTextAlignment(.trailing)
                                .foregroundStyle(Color(hex: 0x2C2F33, opacity: 0.7))
                        }
                    }
                }
                .onChange(of: store.intervalIndex) { _, _ in store.saveInterval() }

                Plate(title: "Mode d'emploi", style: .brass) {
                    VStack(alignment: .leading, spacing: 8) {
                        note("1", "Active Tailscale sur l'iPhone : l'agent n'écoute que le réseau privé.")
                        note("2", "Adresse : http://100.100.226.91:8787 (ou l'IP locale chez toi).")
                        note("3", "Jeton : sudo cat /etc/mlab-agent/token sur le Homelab.")
                        note("4", "Tire vers le bas sur n'importe quel écran pour forcer une relève.")
                    }
                }

                Plate(title: "Identification", style: .anodized, spacing: 8) {
                    info("Appareil", "Mohamlab · iOS")
                    info("Version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    info("Agent", store.overview?.agentVersion ?? "—")
                    info("Dernier relevé", Fmt.ago(store.lastUpdate))
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .onDisappear { focused = nil }
    }

    private func apply() {
        focused = nil
        Haptics.thunk()
        store.saveSettings()
    }

    private func test() {
        focused = nil
        testing = true
        testResult = nil
        store.saveSettings()
        Task {
            let r = await store.testConnection()
            testing = false
            testResult = r
            if r.ok { Haptics.success() } else { Haptics.error() }
        }
    }

    private func slot<C: View>(label: String, @ViewBuilder field: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Engraved(text: label, size: 9)
            field()
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.phosphor)
                .tint(Palette.phosphor)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(
                    LinearGradient(colors: [Color(hex: 0x07140B), Color(hex: 0x0E2216)], startPoint: .top, endPoint: .bottom)
                )
                .recessed(radius: 8)
        }
    }

    private func note(_ n: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(n)
                .font(.custom("Copperplate-Bold", size: 13))
                .foregroundStyle(Color(hex: 0x3A2808, opacity: 0.85))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(hex: 0x3A2808, opacity: 0.85))
                .shadow(color: Color(hex: 0xFFF2C4, opacity: 0.5), radius: 0, x: 0, y: 1)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack {
            Engraved(text: label, size: 9, style: .anodized)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Palette.ledAmber.opacity(0.85))
        }
    }
}
