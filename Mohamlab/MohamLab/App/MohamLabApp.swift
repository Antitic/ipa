import SwiftUI

@main
struct MohamLabApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var store = store
        ZStack {
            WoodBackground()
            Group {
                switch store.tab {
                case .dashboard: DashboardView()
                case .services: ServicesView()
                case .journal: JournalView()
                case .settings: SettingsView()
                }
            }
            .transition(.opacity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ConsoleTabBar(tab: $store.tab,
                          servicesAlarm: (store.overview?.services.failed ?? 0) > 0,
                          journalAlarm: (store.overview?.alerts.errors ?? 0) > 0)
        }
        .animation(.easeInOut(duration: 0.18), value: store.tab)
        .onAppear { store.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: store.start()
            case .background: store.stop()
            default: break
            }
        }
    }
}

/// La console du bas : quatre grosses touches ivoire avec leur voyant.
struct ConsoleTabBar: View {
    @Binding var tab: ConsoleTab
    var servicesAlarm: Bool
    var journalAlarm: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ConsoleTab.allCases) { t in
                let selected = t == tab
                Button {
                    guard t != tab else { return }
                    Haptics.thunk()
                    tab = t
                } label: {
                    VStack(spacing: 4) {
                        LED(color: ledColor(t), on: selected || alarm(t), size: 6, blinking: alarm(t) && !selected && t == .services)
                            .padding(.bottom, 1)
                        Image(systemName: t.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x2A2824, opacity: selected ? 0.95 : 0.7))
                            .shadow(color: .white.opacity(0.7), radius: 0, x: 0, y: 1)
                        Text(t.title.uppercased())
                            .font(.system(size: 9, weight: .heavy).width(.condensed))
                            .tracking(1)
                            .foregroundStyle(Color(hex: 0x2A2824, opacity: 0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(KeyCap(pressed: selected, radius: 8))
                    .offset(y: selected ? 2 : 0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(6)
        .padding(.bottom, 2)
        .background(Color.black.opacity(0.85))
        .recessed(radius: 12)
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            PlateBackground(style: .anodized, radius: 0, shadow: false)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
                }
                .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: tab)
    }

    private func alarm(_ t: ConsoleTab) -> Bool {
        (t == .services && servicesAlarm) || (t == .journal && journalAlarm)
    }

    private func ledColor(_ t: ConsoleTab) -> Color {
        alarm(t) && t != tab ? Palette.ledRed : Palette.ledGreen
    }
}
