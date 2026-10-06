import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var store: MailStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("theme") private var themeRaw = AppTheme.codex.rawValue
    @State private var confirmLogout = false

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .codex }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Réglages")
                        .font(CX.display(42))
                        .tracking(-1)
                        .foregroundStyle(CX.ink)
                    Spacer()
                    CXIconButton(symbol: "xmark") { dismiss() }
                }
                .padding(.top, 22)

                section("Thème")
                HStack(spacing: 14) {
                    ForEach(AppTheme.allCases) { t in
                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeInOut(duration: 0.3)) { themeRaw = t.rawValue }
                        } label: {
                            ThemeCard(theme: t, selected: theme == t)
                        }
                        .buttonStyle(CXPress())
                    }
                }

                section("Compte")
                row("Adresse", store.user)
                row("Serveur", store.account?.server.host ?? "—")
                Button {
                    Task {
                        await store.load("INBOX")
                        store.show("Courrier relevé.")
                    }
                } label: {
                    actionRow("Relever le courrier", symbol: "arrow.clockwise", color: CX.ink)
                }
                .buttonStyle(.plain)
                Button { confirmLogout = true } label: {
                    actionRow(store.isDemo ? "Quitter la démo" : "Se déconnecter", symbol: "rectangle.portrait.and.arrow.right", color: CX.red)
                }
                .buttonStyle(.plain)

                section("À propos")
                row("Version", Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                row("Polices", "EB Garamond, Silkscreen (OFL)")
                Text("Relève automatique toutes les 30 secondes tant que l'app est ouverte.")
                    .font(CX.serif(16, italic: true))
                    .foregroundStyle(CX.ink2)
                    .padding(.top, 14)

                Dither(cell: 3, color: CX.teal.opacity(0.8), field: Fields.ramp)
                    .frame(height: 6)
                    .padding(.top, 40)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, 22)
        }
        .background(CX.paper.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .confirmationDialog("Se déconnecter de \(store.user) ?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) {
                dismiss()
                store.logout()
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    private func section(_ title: String) -> some View {
        Text(title).pixelLabel(9, color: CX.teal)
            .padding(.top, 34)
            .padding(.bottom, 12)
    }

    private func row(_ k: String, _ v: String) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(k).font(CX.serif(19)).foregroundStyle(CX.ink2)
                Spacer(minLength: 12)
                Text(v).font(CX.serif(19, .medium)).foregroundStyle(CX.ink).lineLimit(1).truncationMode(.middle)
            }
            .padding(.vertical, 12)
            Rectangle().fill(CX.hairline).frame(height: 1)
        }
    }

    private func actionRow(_ title: String, symbol: String, color: Color) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(CX.serif(19)).foregroundStyle(color)
                Spacer()
                Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(color)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            Rectangle().fill(CX.hairline).frame(height: 1)
        }
    }
}

// MARK: - Aperçu d'un thème

struct ThemeCard: View {
    let theme: AppTheme
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            preview
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? CX.teal : CX.hairline, lineWidth: selected ? 2 : 1))
            HStack(spacing: 6) {
                if selected { PixelDot(size: 6) }
                Text(theme.name).font(CX.serif(19, .semibold)).foregroundStyle(CX.ink)
            }
            Text(theme.blurb).font(CX.serif(15, italic: true)).foregroundStyle(CX.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var preview: some View {
        switch theme {
        case .codex:
            ZStack(alignment: .topLeading) {
                CX.paper
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Dither(cell: 2, color: CX.teal, field: Fields.orb).frame(width: 14, height: 14)
                        Text("Meyl").font(CX.display(15)).foregroundStyle(CX.ink)
                    }
                    Text("Réception").font(CX.display(24)).tracking(-0.6).foregroundStyle(CX.ink)
                    RoundedRectangle(cornerRadius: 6).fill(CX.wash).frame(height: 16)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(CX.hairline, lineWidth: 0.5))
                    ForEach(0..<3, id: \.self) { i in
                        HStack(spacing: 5) {
                            PixelDot(color: i == 0 ? CX.teal : .clear, size: 4)
                            RoundedRectangle(cornerRadius: 1).fill(CX.ink.opacity(i == 0 ? 0.8 : 0.35)).frame(width: 52 - CGFloat(i * 8), height: 4)
                            Spacer()
                            RoundedRectangle(cornerRadius: 1).fill(CX.ink3.opacity(0.6)).frame(width: 12, height: 3)
                        }
                    }
                }
                .padding(12)
                Dither(cell: 3, color: CX.teal.opacity(0.85), field: Fields.orb)
                    .frame(width: 46, height: 46)
                    .offset(x: 92, y: 8)
            }
        case .ecritoire:
            ZStack {
                LinearGradient(colors: [Ink.walnutLight, Ink.walnut, Ink.walnutDark], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 8) {
                    Text("Courrier").font(Typo.serif(15, bold: true)).foregroundStyle(Ink.stitch)
                    HStack(spacing: 6) {
                        ForEach(0..<2, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 5).fill(Ink.brassGradient).frame(height: 44)
                                .overlay(RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.75)).frame(height: 16).padding(.horizontal, 7).offset(y: -5))
                        }
                    }
                    RoundedRectangle(cornerRadius: 3).fill(Ink.envelope).frame(height: 34)
                        .overlay(alignment: .leading) {
                            Circle().fill(Ink.wax).frame(width: 8, height: 8).padding(.leading, 8)
                        }
                }
                .padding(12)
            }
        }
    }
}
