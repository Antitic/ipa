import SwiftUI
import UIKit

struct MessageListView: View {
    let box: String
    @Binding var compose: Draft?

    @EnvironmentObject var store: MailStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MailRow]?
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var confirmDelete: MailRow?

    private var mailbox: Mailbox? { store.boxes.first { $0.path == box } }
    private var shown: [MailRow] { results ?? store.rows[box] ?? [] }
    private var isSearch: Bool { results != nil }

    var body: some View {
        VStack(spacing: 0) {
            LeatherHeader(title: Mailbox.label(for: box), subtitle: subtitle, leading: {
                LeatherButton(symbol: "chevron.left", label: "Casiers") { dismiss() }
            }, trailing: {
                LeatherButton(symbol: "square.and.pencil") { compose = Draft() }
            })

            searchSlip
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 4)

            List {
                if shown.isEmpty {
                    emptyState
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(shown) { row in
                    // Lien invisible par-dessus l'enveloppe : pas de chevron de liste.
                    EnvelopeRow(row: row, showBox: isSearch)
                        .overlay(NavigationLink(value: Route.message(row)) { EmptyView() }.opacity(0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) { trailingActions(row) }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            Task { await store.setSeen(row, !row.seen) }
                        } label: {
                            Label(row.seen ? "Non lu" : "Lu", systemImage: row.seen ? "envelope.badge" : "envelope.open")
                        }
                        .tint(Ink.blueInk)
                    }
                    .contextMenu { menu(row) }
                    .onAppear {
                        if !isSearch, row.id == store.rows[box]?.last?.id {
                            Task { await store.loadMore(box) }
                        }
                    }
                }
                if !isSearch, store.more[box] == true {
                    HStack {
                        Spacer()
                        ProgressView().tint(Ink.stitch)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                if isSearch { await runSearch(query) } else { await store.load(box) }
            }
        }
        .background(WalnutBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if store.rows[box] == nil { await store.load(box) }
        }
        .confirmationDialog("Détruire définitivement cette lettre ?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Détruire", role: .destructive) {
                if let r = confirmDelete { Task { await store.move(r, to: "delete") } }
                confirmDelete = nil
            }
            Button("Annuler", role: .cancel) { confirmDelete = nil }
        }
    }

    private var subtitle: String? {
        if isSearch { return "\(shown.count) résultat\(shown.count > 1 ? "s" : "")" }
        guard let m = mailbox, let t = m.total else { return nil }
        let u = m.unseen ?? 0
        return u > 0 ? "\(u) non lue\(u > 1 ? "s" : "") · \(t) en tout" : "\(t) lettre\(t > 1 ? "s" : "")"
    }

    // MARK: Recherche

    private var searchSlip: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Ink.inkSoft)
            TextField("Chercher dans tout le courrier", text: $query)
                .font(Typo.typewriter(15))
                .foregroundStyle(Ink.ink)
                .tint(Ink.redInk)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { Task { await runSearch(query) } }
            if searching {
                ProgressView().tint(Ink.inkSoft).scaleEffect(0.8)
            } else if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Ink.inkSoft)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(PaperSheet(corner: 18))
        .onChange(of: query) { _, q in
            searchTask?.cancel()
            let t = q.trimmingCharacters(in: .whitespaces)
            if t.count < 2 {
                results = nil
                searching = false
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                if Task.isCancelled { return }
                await runSearch(t)
            }
        }
    }

    private func runSearch(_ q: String) async {
        let t = q.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2 else { return }
        searching = true
        defer { searching = false }
        do {
            let r = try await store.search(t)
            if !Task.isCancelled && query.trimmingCharacters(in: .whitespaces) == t { results = r }
        } catch {
            store.report(error)
        }
    }

    // MARK: Actions

    @ViewBuilder private func trailingActions(_ row: MailRow) -> some View {
        if row.box == "Trash" {
            Button(role: .destructive) {
                confirmDelete = row
            } label: { Label("Détruire", systemImage: "flame") }
            .tint(Ink.redInk)
            Button {
                Task { await store.move(row, to: "INBOX") }
            } label: { Label("Remettre", systemImage: "tray.and.arrow.up") }
            .tint(Ink.brassDeep)
        } else {
            Button(role: .destructive) {
                Task { await store.move(row, to: "Trash") }
            } label: { Label("Corbeille", systemImage: "trash") }
            .tint(Ink.redInk)
            if row.box != "Archive" {
                Button {
                    Task { await store.move(row, to: "Archive") }
                } label: { Label("Archiver", systemImage: "archivebox") }
                .tint(Ink.brassDeep)
            }
        }
    }

    @ViewBuilder private func menu(_ row: MailRow) -> some View {
        Button {
            Task { await store.setSeen(row, !row.seen) }
        } label: {
            Label(row.seen ? "Marquer non lu" : "Marquer lu", systemImage: row.seen ? "envelope.badge" : "envelope.open")
        }
        if row.box != "Archive" && row.box != "Trash" {
            Button { Task { await store.move(row, to: "Archive") } } label: { Label("Archiver", systemImage: "archivebox") }
        }
        if row.box != "INBOX" && row.box != "Sent" {
            Button { Task { await store.move(row, to: "INBOX") } } label: { Label("Remettre en réception", systemImage: "tray.and.arrow.down") }
        }
        if row.box == "Trash" {
            Button(role: .destructive) { confirmDelete = row } label: { Label("Détruire", systemImage: "flame") }
        } else {
            Button(role: .destructive) { Task { await store.move(row, to: "Trash") } } label: { Label("Corbeille", systemImage: "trash") }
        }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: isSearch ? "magnifyingglass" : "tray")
                .font(.system(size: 34, weight: .light))
            Text(store.loading.contains(box) ? "Le facteur trie le courrier…"
                 : isSearch ? "Rien trouvé." : "Ce casier est vide.")
                .font(Typo.typewriter(15))
        }
        .foregroundStyle(Ink.stitch.opacity(0.75))
        .embossed(light: .clear, dark: .black.opacity(0.6))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Une lettre dans la pile : enveloppe crème

struct EnvelopeRow: View {
    let row: MailRow
    var showBox = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack {
                if row.seen {
                    Circle().fill(Color.clear).frame(width: 12, height: 12)
                } else {
                    WaxDot()
                }
            }
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.box == "Sent" ? "À : " + row.name : row.name)
                        .font(Typo.serif(17, bold: !row.seen))
                        .foregroundStyle(Ink.ink)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    if row.att {
                        Image(systemName: "paperclip")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Ink.inkSoft)
                            .rotationEffect(.degrees(-20))
                    }
                    Text(Fmt.list(row.date))
                        .font(Typo.typewriter(12))
                        .foregroundStyle(row.seen ? Ink.inkSoft : Ink.redInk)
                }
                Text(row.subject)
                    .font(Typo.typewriter(14, bold: !row.seen))
                    .foregroundStyle(row.seen ? Ink.inkSoft : Ink.ink)
                    .lineLimit(2)
                if showBox {
                    Text(Mailbox.label(for: row.box).uppercased())
                        .font(Typo.engraved(9))
                        .foregroundStyle(Ink.blueInk.opacity(0.75))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Ink.blueInk.opacity(0.5), lineWidth: 1))
                        .rotationEffect(.degrees(-2))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            ZStack {
                PaperSheet(corner: 4, tint: Ink.envelope)
                // rabat de l'enveloppe, à peine marqué
                EnvelopeFlap()
                    .stroke(Ink.paperShade.opacity(0.9), lineWidth: 1)
                    .padding(1)
                // liseré « par avion » sur le bord gauche des non-lues
                if !row.seen {
                    AirmailEdge()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
        )
    }
}

struct EnvelopeFlap: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 4, y: r.minY + 2))
        p.addLine(to: CGPoint(x: r.midX, y: r.minY + min(r.height * 0.42, 30)))
        p.addLine(to: CGPoint(x: r.maxX - 4, y: r.minY + 2))
        return p
    }
}

struct AirmailEdge: View {
    var body: some View {
        HStack(spacing: 0) {
            Canvas { ctx, size in
                var y: CGFloat = -10
                var i = 0
                while y < size.height + 10 {
                    var p = Path()
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y - 6))
                    p.addLine(to: CGPoint(x: size.width, y: y + 1))
                    p.addLine(to: CGPoint(x: 0, y: y + 7))
                    p.closeSubpath()
                    ctx.fill(p, with: .color(i % 2 == 0 ? Ink.redInk.opacity(0.85) : Ink.blueInk.opacity(0.85)))
                    y += 14
                    i += 1
                }
            }
            .frame(width: 5)
            Spacer()
        }
        .allowsHitTesting(false)
    }
}
