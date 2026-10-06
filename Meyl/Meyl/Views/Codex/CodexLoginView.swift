import SwiftUI
import UIKit

struct CodexLoginView: View {
    @EnvironmentObject var store: MailStore

    @State private var user = SecretStore.get("user") ?? ""
    @State private var pass = ""
    @State private var server = UserDefaults.standard.string(forKey: "server") ?? Account.defaultServer
    @State private var showServer = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Dither(cell: 5, color: CX.teal, animated: true, speed: 0.6, field: Fields.orb)
                    .frame(width: 190, height: 190)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)

                Text("Meyl")
                    .font(CX.display(64))
                    .tracking(-1.5)
                    .foregroundStyle(CX.ink)
                    .padding(.top, 28)
                Text("Lis différemment.")
                    .font(CX.serif(26, italic: true))
                    .tracking(-0.4)
                    .foregroundStyle(CX.ink2)
                    .padding(.top, -6)
                Text("Le courrier de dipherant.xyz")
                    .pixelLabel(9)
                    .padding(.top, 10)

                VStack(alignment: .leading, spacing: 24) {
                    CXField(label: "Adresse", text: $user, keyboard: .emailAddress, placeholder: "toi@dipherant.xyz")
                    CXField(label: "Mot de passe", text: $pass, secure: true, placeholder: "••••••••")
                    if showServer {
                        CXField(label: "Serveur", text: $server, keyboard: .URL, placeholder: Account.defaultServer)
                    }
                }
                .padding(.top, 40)

                Button {
                    withAnimation { showServer.toggle() }
                } label: {
                    Text(showServer ? "Masquer le serveur" : "Autre serveur…")
                        .font(CX.serif(16, italic: true))
                        .foregroundStyle(CX.teal)
                }
                .padding(.top, 14)

                if let error {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        PixelDot(color: CX.red, size: 6)
                        Text(error).font(CX.serif(17)).foregroundStyle(CX.red)
                    }
                    .padding(.top, 18)
                }

                CXPrimaryButton(title: busy ? "Ouverture…" : "Ouvrir le courrier", symbol: busy ? nil : "arrow.right", busy: busy) {
                    Task { await submit() }
                }
                .padding(.top, 32)
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CX.paper.ignoresSafeArea())
    }

    private func submit() async {
        guard !busy else { return }
        error = nil
        guard !user.trimmingCharacters(in: .whitespaces).isEmpty, !pass.isEmpty else {
            error = "Il manque l'adresse ou le mot de passe."
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await store.login(server: server, user: user, pass: pass)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            self.error = error.localizedDescription
        }
    }
}
