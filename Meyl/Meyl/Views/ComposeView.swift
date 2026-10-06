import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ComposeView: View {
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
            LeatherHeader(title: draft.inReplyTo.isEmpty ? "Nouvelle lettre" : "Réponse", leading: {
                LeatherButton(symbol: "xmark", label: "Fermer") {
                    if isEmpty { dismiss() } else { confirmDiscard = true }
                }
            }, trailing: {
                LeatherButton(symbol: "paperclip") { importing = true }
            })

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            TypedField(label: "À", text: $draft.to, keyboard: .emailAddress, placeholder: "adresse, adresse…")
                                .focused($focus, equals: .to)
                            if showCc {
                                TypedField(label: "Cc", text: $draft.cc, keyboard: .emailAddress)
                                    .focused($focus, equals: .cc)
                            }
                            TypedField(label: "Objet", text: $draft.subject)
                                .focused($focus, equals: .subject)
                        }
                        if !showCc {
                            Button("Cc") { withAnimation { showCc = true } }
                                .font(Typo.serif(14, bold: true))
                                .foregroundStyle(Ink.blueInk)
                                .padding(.top, 10)
                                .padding(.leading, 6)
                        }
                    }

                    if !draft.files.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(draft.files) { f in
                                    HStack(spacing: 4) {
                                        AttachmentTag(att: Attachment(index: 0, name: f.name, size: f.data.count, contentType: f.mime))
                                        Button {
                                            draft.files.removeAll { $0.id == f.id }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.inkSoft)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }

                    ZStack(alignment: .topLeading) {
                        if draft.body.isEmpty {
                            Text("Cher ami,")
                                .font(Typo.typewriter(16))
                                .foregroundStyle(Ink.inkSoft.opacity(0.5))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $draft.body)
                            .font(Typo.typewriter(16))
                            .foregroundStyle(Ink.ink)
                            .tint(Ink.redInk)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 320)
                            .focused($focus, equals: .body)
                    }
                    .padding(.top, 12)

                    if let error {
                        Text(error)
                            .font(Typo.typewriter(13, bold: true))
                            .foregroundStyle(Ink.redInk)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background(
                    PaperSheet(corner: 4)
                        .overlay(alignment: .leading) {
                            // marge rouge du papier à lettres
                            Rectangle().fill(Ink.redInk.opacity(0.35)).frame(width: 1).padding(.leading, 14)
                        }
                )
                .padding(12)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(WalnutBackground())
        .overlay(alignment: .bottomTrailing) {
            WaxSealButton(symbol: "paperplane.fill", caption: sending ? "Envoi…" : "Envoyer", busy: sending) {
                Task { await send() }
            }
            .padding(.trailing, 22)
            .padding(.bottom, 14)
        }
        .interactiveDismissDisabled(!isEmpty || sending)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): attach(urls)
            case .failure(let e): error = e.localizedDescription
            }
        }
        .confirmationDialog("Abandonner cette lettre ?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Jeter le brouillon", role: .destructive) { dismiss() }
            Button("Continuer d'écrire", role: .cancel) {}
        }
        .onAppear {
            if draft.to.isEmpty { focus = .to } else if draft.inReplyTo.isEmpty == false { focus = .body }
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
            if data.count > 15 * 1024 * 1024 {
                error = "\(url.lastPathComponent) dépasse 15 Mo."
                continue
            }
            if draft.files.count >= 10 {
                error = "10 pièces jointes maximum."
                break
            }
            total += data.count
            if total > 25 * 1024 * 1024 {
                error = "Le paquet dépasse 25 Mo."
                break
            }
            let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            draft.files.append(DraftFile(name: url.lastPathComponent, mime: mime, data: data))
        }
    }

    private func send() async {
        guard !sending else { return }
        focus = nil
        error = nil
        if draft.to.trimmingCharacters(in: .whitespaces).isEmpty {
            error = "À qui l'envoie-t-on ?"
            return
        }
        sending = true
        defer { sending = false }
        do {
            let delivered = try await store.send(draft)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            store.show(delivered ? "Lettre postée." : "Lettre en file d'attente : elle partira dès que le relais répondra.")
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            self.error = error.localizedDescription
        }
    }
}
