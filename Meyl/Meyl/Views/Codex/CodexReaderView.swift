import SwiftUI
import UIKit
import QuickLook

struct CodexReaderView: View {
    let row: MailRow
    @Binding var compose: Draft?

    @EnvironmentObject var store: MailStore
    @Environment(\.dismiss) private var dismiss

    @State private var message: MailMessage?
    @State private var html: String?
    @State private var remote = false
    @State private var failed: String?
    @State private var preview: URL?
    @State private var fetching: Int?
    @State private var showDetails = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            topBar

            if let failed {
                Spacer()
                VStack(spacing: 14) {
                    Dither(cell: 4, color: CX.ink3, field: Fields.envelope).frame(width: 120, height: 90)
                    Text(failed).font(CX.serif(19, italic: true)).foregroundStyle(CX.ink2).multilineTextAlignment(.center)
                    Button("Réessayer") { Task { await load() } }
                        .font(CX.serif(18, .semibold))
                        .foregroundStyle(CX.teal)
                }
                .padding(30)
                Spacer()
            } else {
                headerBlock
                    .padding(.horizontal, 22)
                    .padding(.bottom, 8)
                Rectangle().fill(CX.hairline).frame(height: 1)
                ZStack {
                    if let html {
                        MailWebView(html: html, allowRemote: remote, codex: true)
                    } else {
                        VStack(spacing: 12) {
                            PixelLoader(width: 120, height: 28, cell: 4)
                            Text("Ouverture…").font(CX.serif(18, italic: true)).foregroundStyle(CX.ink2)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            actionBar
        }
        .background(CX.paper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .quickLookPreview($preview)
        .confirmationDialog("Supprimer définitivement ce message ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { Task { await moveAndLeave("delete") } }
            Button("Annuler", role: .cancel) {}
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            CXIconButton(symbol: "chevron.left", label: Mailbox.label(for: row.box)) { dismiss() }
            Spacer()
            if row.box != "Archive" && row.box != "Trash" {
                CXIconButton(symbol: "archivebox") { Task { await moveAndLeave("Archive") } }
            }
            CXIconButton(symbol: row.box == "Trash" ? "trash.slash" : "trash") {
                if row.box == "Trash" { confirmDelete = true } else { Task { await moveAndLeave("Trash") } }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(message?.subject ?? row.subject)
                .font(CX.display(31))
                .tracking(-0.6)
                .foregroundStyle(CX.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack(alignment: .center, spacing: 12) {
                PixelMonogram(name: message?.fromName ?? row.name, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(message?.fromName ?? row.name)
                        .font(CX.serif(19, .semibold))
                        .foregroundStyle(CX.ink)
                        .lineLimit(1)
                    if let m = message, !m.fromAddress.isEmpty, m.fromAddress != m.fromName {
                        Text(m.fromAddress)
                            .font(CX.serif(15, italic: true))
                            .foregroundStyle(CX.ink2)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12))
                    .foregroundStyle(CX.ink3)
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() } }

            Text(Fmt.pixelStamp(message?.date ?? row.date)).pixelLabel(9)

            if showDetails, let m = message {
                VStack(alignment: .leading, spacing: 6) {
                    detail("À", m.to)
                    if !m.cc.isEmpty { detail("Cc", m.cc) }
                    if !m.replyTo.isEmpty { detail("Réponse", m.replyTo) }
                }
                .transition(.opacity)
            }

            if let atts = message?.attachments, !atts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(atts) { a in
                            Button { Task { await open(a) } } label: { CodexAttachmentChip(att: a, busy: fetching == a.index) }
                                .buttonStyle(CXPress())
                        }
                    }
                }
            }

            if message?.remoteImages == true && !remote {
                Button {
                    remote = true
                    Task { await loadBody() }
                } label: {
                    HStack(spacing: 8) {
                        PixelDot(color: CX.teal, size: 6)
                        Text("Images distantes masquées — les afficher")
                            .font(CX.serif(16, italic: true))
                            .foregroundStyle(CX.teal)
                    }
                }
            }
        }
    }

    private func detail(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(k).pixelLabel(8).frame(width: 64, alignment: .leading)
            Text(v).font(CX.serif(16)).foregroundStyle(CX.ink).textSelection(.enabled)
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            barButton("arrowshape.turn.up.left", "Répondre") { reply(all: false) }
            barButton("arrowshape.turn.up.left.2", "À tous") { reply(all: true) }
            barButton("arrowshape.turn.up.right", "Transférer") {
                if let m = message { compose = Draft.forward(m) }
            }
            barButton("envelope.badge", "Non lu") {
                Task {
                    var r = row
                    r.seen = true
                    await store.setSeen(r, false)
                    dismiss()
                }
            }
        }
        .padding(.top, 6)
        .background(CX.paper.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(CX.hairline).frame(height: 1) }
    }

    private func barButton(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 18))
                Text(title).font(CX.serif(14))
            }
            .foregroundStyle(CX.ink)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(CXPress())
        .disabled(message == nil)
        .opacity(message == nil ? 0.4 : 1)
    }

    // MARK: Chargement & actions

    private func load() async {
        failed = nil
        do {
            message = try await store.message(for: row)
            await loadBody()
        } catch is CancellationError {
        } catch {
            failed = error.localizedDescription
        }
    }

    private func loadBody() async {
        do {
            html = try await store.body(for: row, remoteImages: remote)
        } catch is CancellationError {
        } catch {
            html = "<p>Corps du message illisible.</p>"
        }
    }

    private func reply(all: Bool) {
        guard let m = message else { return }
        compose = Draft.reply(to: m, all: all, me: store.user)
    }

    private func open(_ a: Attachment) async {
        fetching = a.index
        defer { fetching = nil }
        do { preview = try await store.attachmentFile(row, a) } catch { store.report(error) }
    }

    private func moveAndLeave(_ to: String) async {
        var r = row
        if let current = store.rows[row.box]?.first(where: { $0.uid == row.uid }) { r = current }
        if await store.move(r, to: to) { dismiss() }
    }
}

struct CodexAttachmentChip: View {
    let att: Attachment
    var busy = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Rectangle().fill(CX.tealWash)
                if busy {
                    PixelLoader(width: 30, height: 30, cell: 2)
                } else {
                    Image(systemName: att.symbol).font(.system(size: 13)).foregroundStyle(CX.teal)
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(att.name).font(CX.serif(15, .medium)).foregroundStyle(CX.ink).lineLimit(1)
                Text(att.sizeText).pixelLabel(7)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: 210, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CX.hairline, lineWidth: 1))
    }
}
