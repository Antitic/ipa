import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CodexComposeView: View {
    @EnvironmentObject var store: MailStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Draft
    @State private var showCc: Bool
    @State private var sending = false
    @State private var error: String?
    @State private var importing = false
    @State private var confirmDiscard = false
    @FocusState private var focus: Field?

    enum Field { case to, cc, subject, body }

    init(draft: Draft) {
        _draft = State(initialValue: draft)
        _showCc = State(initialValue: !draft.cc.isEmpty)
    }

    private var isEmpty: Bool {
        draft.to.isEmpty && draft.subject.isEmpty && draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Annuler") {
                    if isEmpty { dismiss() } else { confirmDiscard = true }
                }
                .font(CX.serif(18))
                .foregroundStyle(CX.ink2)
                Spacer()
                Text(draft.inReplyTo.isEmpty ? "Nouveau message" : "Réponse")
                    .font(CX.serif(19, .semibold))
                    .foregroundStyle(CX.ink)
                Spacer()
                Button { importing = true } label: {
                    Image(systemName: "paperclip").font(.system(size: 17)).foregroundStyle(CX.ink)
                }
                .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    line("À", $draft.to, .to, keyboard: .emailAddress) {
                        if !showCc {
                            Button("Cc") { withAnimation { showCc = true } }
                                .font(CX.serif(16, italic: true))
                                .foregroundStyle(CX.teal)
                        }
                    }
                    if showCc { line("Cc", $draft.cc, .cc, keyboard: .emailAddress) { EmptyView() } }
                    line("Objet", $draft.subject, .subject) { EmptyView() }

                    if !draft.files.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(draft.files) { f in
                                    HStack(spacing: 4) {
                                        CodexAttachmentChip(att: Attachment(index: 0, name: f.name, size: f.data.count, contentType: f.mime))
                                        Button { draft.files.removeAll { $0.id == f.id } } label: {
                                            Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(CX.ink3)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        if draft.body.isEmpty {
                            Text("Écris ici…")
                                .font(CX.serif(20, italic: true))
                                .foregroundStyle(CX.ink3)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $draft.body)
                            .font(CX.serif(20))
                            .foregroundStyle(CX.ink)
                            .tint(CX.teal)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 340)
                            .focused($focus, equals: .body)
                    }
                    .padding(.top, 14)

                    if let error {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            PixelDot(color: CX.red, size: 6)
                            Text(error).font(CX.serif(17)).foregroundStyle(CX.red)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(CX.paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            CXPrimaryButton(title: sending ? "Envoi…" : "Envoyer", symbol: sending ? nil : "paperplane", busy: sending) {
                Task { await send() }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
            .background(LinearGradient(colors: [CX.paper.opacity(0), CX.paper], startPoint: .top, endPoint: .center))
        }
        .interactiveDismissDisabled(!isEmpty || sending)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): attach(urls)
            case .failure(let e): error = e.localizedDescription
            }
        }
        .confirmationDialog("Abandonner ce message ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Supprimer le brouillon", role: .destructive) { dismiss() }
            Button("Continuer d'écrire", role: .cancel) {}
        }
        .onAppear {
            if draft.to.isEmpty { focus = .to } else if !draft.inReplyTo.isEmpty { focus = .body }
        }
    }

    private func line<Trailing: View>(_ label: String, _ text: Binding<String>, _ field: Field,
                                      keyboard: UIKeyboardType = .default,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).pixelLabel(9, color: focus == field ? CX.teal : CX.ink3)
                    .frame(width: 46, alignment: .leading)
                TextField("", text: text)
                    .font(CX.serif(19, field == .subject ? .medium : .regular))
                    .foregroundStyle(CX.ink)
                    .tint(CX.teal)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(field == .subject ? .sentences : .never)
                    .autocorrectionDisabled(field != .subject)
                    .focused($focus, equals: field)
                trailing()
            }
            .padding(.vertical, 12)
            Rectangle().fill(focus == field ? CX.teal : CX.hairline).frame(height: 1)
        }
    }

    private func attach(_ urls: [URL]) {
        var total = draft.files.reduce(0) { $0 + $1.data.count }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                error = "Impossible de lire \(url.lastPathComponent)."
                continue
            }
            if data.count > 15 * 1024 * 1024 { error = "\(url.lastPathComponent) dépasse 15 Mo."; continue }
            if draft.files.count >= 10 { error = "10 pièces jointes maximum."; break }
            total += data.count
            if total > 25 * 1024 * 1024 { error = "L'ensemble dépasse 25 Mo."; break }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            draft.files.append(DraftFile(name: url.lastPathComponent, mime: mime, data: data))
        }
    }

    private func send() async {
        guard !sending else { return }
        focus = nil
        error = nil
        if draft.to.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "Ajoute au moins un destinataire."
            return
        }
        sending = true
        defer { sending = false }
        do {
            let delivered = try await store.send(draft)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            store.show(delivered ? "Message envoyé." : "En file d'attente : il partira dès que le relais répondra.")
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            self.error = error.localizedDescription
        }
    }
}
