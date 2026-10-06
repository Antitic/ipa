import SwiftUI
import UIKit

struct LoginView: View {
    @EnvironmentObject var store: MailStore

    @State private var user = SecretStore.get("user") ?? ""
    @State private var pass = ""
    @State private var server = UserDefaults.standard.string(forKey: "server") ?? Account.defaultServer
    @State private var showServer = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Field { case user, pass, server }

    var body: some View {
        ZStack {
            WalnutBackground()
            ScrollView {
                VStack(spacing: 26) {
                    mailboxDoor
                        .padding(.top, 36)
                    form
                    WaxSealButton(symbol: "envelope.open.fill", caption: busy ? "Ouverture…" : "Ouvrir le courrier", busy: busy) {
                        Task { await submit() }
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 22)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // La porte de boîte aux lettres en laiton
    private var mailboxDoor: some View {
        VStack(spacing: 14) {
            Text("MEYL")
                .font(Typo.display(46))
                .kerning(8)
                .engraved()
            // fente
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(LinearGradient(colors: [.black, Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                .frame(height: 16)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Ink.brassHi.opacity(0.8), lineWidth: 1).offset(y: 1))
                .overlay(
                    // la lettre qui dépasse
                    Rectangle()
                        .fill(Ink.envelope)
                        .frame(width: 70, height: 10)
                        .offset(x: 18, y: -3)
                        .rotationEffect(.degrees(-3))
                        .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                )
                .padding(.horizontal, 30)
            Text("LETTRES · DIPHERANT.XYZ")
                .font(Typo.engraved(13))
                .kerning(2)
                .engraved()
        }
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background(BrassPlate(corner: 14))
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fiche d'accès")
                .font(Typo.serif(20, bold: true))
                .foregroundStyle(Ink.ink)
                .padding(.bottom, 6)
            TypedField(label: "Adresse", text: $user, keyboard: .emailAddress, placeholder: "toi@dipherant.xyz")
                .focused($focus, equals: .user)
                .submitLabel(.next)
                .onSubmit { focus = .pass }
            TypedField(label: "Mot de passe", text: $pass, secure: true, placeholder: "••••••••")
                .focused($focus, equals: .pass)
                .submitLabel(.go)
                .onSubmit { Task { await submit() } }

            if showServer {
                TypedField(label: "Serveur", text: $server, keyboard: .URL, placeholder: Account.defaultServer)
                    .focused($focus, equals: .server)
            }
            Button {
                withAnimation { showServer.toggle() }
            } label: {
                Text(showServer ? "Masquer le bureau de poste" : "Autre bureau de poste…")
                    .font(Typo.typewriter(12))
                    .foregroundStyle(Ink.blueInk.opacity(0.8))
                    .underline()
            }
            .padding(.top, 8)

            if let error {
                Text(error)
                    .font(Typo.typewriter(13, bold: true))
                    .foregroundStyle(Ink.redInk)
                    .padding(.top, 10)
                    .rotationEffect(.degrees(-0.8))
            }
        }
        .padding(22)
        .background(PaperSheet())
        .overlay(alignment: .topTrailing) {
            // timbre
            Image(systemName: "seal.fill")
                .font(.system(size: 34))
                .foregroundStyle(Ink.redInk.opacity(0.18))
                .rotationEffect(.degrees(12))
                .padding(14)
        }
    }

    private func submit() async {
        guard !busy else { return }
        focus = nil
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
