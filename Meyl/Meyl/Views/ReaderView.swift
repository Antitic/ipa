import SwiftUI
import UIKit
import QuickLook

struct ReaderView: View {
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
            LeatherHeader(title: Mailbox.label(for: row.box), leading: {
                LeatherButton(symbol: "chevron.left", label: "Retour") { dismiss() }
            }, trailing: {
                HStack(spacing: 8) {
                    if row.box != "Archive" && row.box != "Trash" {
                        LeatherButton(symbol: "archivebox.fill") { Task { await moveAndLeave("Archive") } }
                    }
                    LeatherButton(symbol: row.box == "Trash" ? "flame.fill" : "trash.fill") {
                        if row.box == "Trash" { confirmDelete = true } else { Task { await moveAndLeave("Trash") } }
                    }
                }
            })

            if let failed {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "envelope.badge.shield.half.filled")
                        .font(.system(size: 40))
                    Text(failed).font(Typo.typewriter(15)).multilineTextAlignment(.center)
                    Button("Réessayer") { Task { await load() } }
                        .font(Typo.serif(16, bold: true))
                }
                .foregroundStyle(Ink.stitch)
                .padding(30)
                Spacer()
            } else {
                VStack(spacing: 10) {
                    letterhead
                    letterBody
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
            }

            actionBar
        }
        .background(WalnutBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .quickLookPreview($preview)
        .confirmationDialog("Détruire définitivement cette lettre ?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Détruire", role: .destructive) { Task { await moveAndLeave("delete") } }
            Button("Annuler", role: .cancel) {}
        }
    }

    // MARK: En-tête de la lettre

    private var letterhead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message?.subject ?? row.subject)
                .font(Typo.serif(21, bold: true))
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(message?.fromName ?? row.name)
                        .font(Typo.serif(16, bold: true))
                        .foregroundStyle(Ink.blueInk)
                    if let m = message, !m.fromAddress.isEmpty, m.fromAddress != m.fromName {
                        Text(m.fromAddress)
                            .font(Typo.typewriter(12))
                            .foregroundStyle(Ink.inkSoft)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                PostmarkView(date: message?.date ?? row.date)
            }

            if showDetails, let m = message {
                VStack(alignment: .leading, spacing: 3) {
                    detail("À", m.to)
                    if !m.cc.isEmpty { detail("Cc", m.cc) }
                    if let d = m.date { detail("Le", Fmt.long(d)) }
                }
                .transition(.opacity)
            }

            if let atts = message?.attachments, !atts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(atts) { a in
                            Button { Task { await open(a) } } label: { AttachmentTag(att: a, busy: fetching == a.index) }
                                .buttonStyle(PressStyle())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if message?.remoteImages == true && !remote {
                Button {
                    remote = true
                    Task { await loadBody() }
                } label: {
                    Label("Images distantes bloquées — les afficher", systemImage: "photo.badge.exclamationmark")
                        .font(Typo.typewriter(12))
                        .foregroundStyle(Ink.redInk)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaperSheet(corner: 5))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() } }
    }

    private func detail(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(k).font(Typo.serif(13, bold: true)).foregroundStyle(Ink.inkSoft).frame(width: 24, alignment: .leading)
            Text(v).font(Typo.typewriter(12)).foregroundStyle(Ink.ink).textSelection(.enabled)
        }
    }

    // MARK: Corps

    private var letterBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(red: 1.0, green: 0.995, blue: 0.975))
                .overlay(Grain(seed: 21, density: 0.0006, dark: 0.03, light: 0.0)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous)))
                .shadow(color: .black.opacity(0.45), radius: 6, x: 0, y: 4)
            if let html {
                MailWebView(html: html, allowRemote: remote)
                    .padding(.horizontal, 8)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ProgressView().tint(Ink.inkSoft)
                    Text("On décachette…").font(Typo.typewriter(13)).foregroundStyle(Ink.inkSoft)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Barre d'actions

    private var actionBar: some View {
        HStack(spacing: 0) {
            barButton("arrowshape.turn.up.left.fill", "Répondre") { reply(all: false) }
            barButton("arrowshape.turn.up.left.2.fill", "À tous") { reply(all: true) }
            barButton("arrowshape.turn.up.right.fill", "Transférer") {
                if let m = message { compose = Draft.forward(m) }
            }
            barButton("envelope.badge.fill", "Non lu") {
                Task {
                    var r = row
                    r.seen = true
                    await store.setSeen(r, false)
                    dismiss()
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
        .background(
            Leather(shape: Rectangle(), stitchInset: 4)
                .ignoresSafeArea(edges: .bottom)
                .shadow(color: .black.opacity(0.6), radius: 5, x: 0, y: -2)
        )
        .padding(.top, 10)
    }

    private func barButton(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 18, weight: .bold))
                Text(title).font(Typo.serif(12, bold: true))
            }
            .foregroundStyle(Ink.stitch)
            .embossed(light: .white.opacity(0.1), dark: .black.opacity(0.85))
            .frame(maxWidth: .infinity, minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(message == nil)
        .opacity(message == nil ? 0.5 : 1)
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
            html = "<p style=\"font-family:-apple-system;color:#77736a\">Corps du message illisible.</p>"
        }
    }

    private func reply(all: Bool) {
        guard let m = message else { return }
        compose = Draft.reply(to: m, all: all, me: store.user)
    }

    private func open(_ a: Attachment) async {
        fetching = a.index
        defer { fetching = nil }
        do {
            preview = try await store.attachmentFile(row, a)
        } catch {
            store.report(error)
        }
    }

    private func moveAndLeave(_ to: String) async {
        var r = row
        if let current = store.rows[row.box]?.first(where: { $0.uid == row.uid }) { r = current }
        if await store.move(r, to: to) { dismiss() }
    }
}

// MARK: - Cachet de la poste (date)

struct PostmarkView: View {
    let date: Date?

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Ink.blueInk.opacity(0.55), lineWidth: 1.6)
            Circle()
                .strokeBorder(Ink.blueInk.opacity(0.4), lineWidth: 0.8)
                .padding(5)
            VStack(spacing: 0) {
                Text(dayText)
                    .font(Typo.engraved(10))
                Text(timeText)
                    .font(Typo.typewriter(10, bold: true))
            }
            .foregroundStyle(Ink.blueInk.opacity(0.7))
        }
        .frame(width: 62, height: 62)
        .rotationEffect(.degrees(-14))
    }

    private var dayText: String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.locale = Fmt.fr
        f.timeZone = Fmt.paris
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: date).replacingOccurrences(of: ".", with: "").uppercased()
    }

    private var timeText: String {
        guard let date else { return "" }
        let f = DateFormatter()
        f.locale = Fmt.fr
        f.timeZone = Fmt.paris
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Étiquette de pièce jointe

struct AttachmentTag: View {
    let att: Attachment
    var busy = false

    var body: some View {
        HStack(spacing: 6) {
            if busy {
                ProgressView().scaleEffect(0.7).tint(Ink.inkSoft)
            } else {
                Image(systemName: att.symbol).font(.system(size: 13, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(att.name).font(Typo.typewriter(12, bold: true)).lineLimit(1)
                Text(att.sizeText).font(Typo.typewriter(10))
            }
        }
        .foregroundStyle(Ink.ink)
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 200, alignment: .leading)
        .background(
            TagShape()
                .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.86, blue: 0.68), Color(red: 0.84, green: 0.75, blue: 0.55)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(TagShape().stroke(Ink.brassDeep.opacity(0.5), lineWidth: 0.8))
                .overlay(alignment: .leading) {
                    Circle().fill(Ink.walnutDark.opacity(0.7)).frame(width: 5, height: 5).padding(.leading, 5)
                }
                .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 1)
        )
    }
}

struct TagShape: Shape {
    func path(in r: CGRect) -> Path {
        let notch: CGFloat = 8
        var p = Path()
        p.move(to: CGPoint(x: r.minX + notch, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 3, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + 3), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 3))
        p.addQuadCurve(to: CGPoint(x: r.maxX - 3, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + notch, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.closeSubpath()
        return p
    }
}
