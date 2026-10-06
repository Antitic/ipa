import SwiftUI
import UIKit

struct CodexHomeView: View {
    @EnvironmentObject var store: MailStore
    @Binding var compose: Draft?

    @State private var box = UserDefaults.standard.string(forKey: "openBox") ?? "INBOX"
    @State private var query = ""
    @State private var results: [MailRow]?
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var confirmDelete: MailRow?
    @FocusState private var searchFocused: Bool

    private var mailbox: Mailbox? { store.boxes.first { $0.path == box } }
    private var isSearch: Bool { results != nil }
    private var shown: [MailRow] { results ?? store.rows[box] ?? [] }

    var body: some View {
        List {
            header
                .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
                .listRowSeparator(.hidden)

            if shown.isEmpty {
                emptyState
                    .listRowSeparator(.hidden)
            }

            ForEach(shown) { row in
                CodexRow(row: row, showBox: isSearch)
                    .overlay(NavigationLink(value: Route.message(row)) { EmptyView() }.opacity(0))
                    .listRowInsets(EdgeInsets(top: 0, leading: 22, bottom: 0, trailing: 22))
                    .listRowSeparatorTint(CX.hairline)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) { trailingActions(row) }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            Task { await store.setSeen(row, !row.seen) }
                        } label: {
                            Label(row.seen ? "Non lu" : "Lu", systemImage: row.seen ? "envelope.badge" : "envelope.open")
                        }
                        .tint(CX.teal)
                    }
                    .contextMenu { menu(row) }
                    .onAppear {
                        if !isSearch, row.id == store.rows[box]?.last?.id {
                            Task { await store.loadMore(box) }
                        }
                    }
            }

            if !isSearch, store.more[box] == true {
                PixelLoader()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(CX.paper)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            if isSearch { await runSearch(query) } else { await store.load(box) }
        }
        .safeAreaInset(edge: .top, spacing: 0) { topBar }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: box) {
            if store.rows[box] == nil { await store.load(box) }
        }
        .confirmationDialog("Supprimer définitivement ce message ?", isPresented: Binding(
            get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) {
                if let r = confirmDelete { Task { await store.move(r, to: "delete") } }
                confirmDelete = nil
            }
            Button("Annuler", role: .cancel) { confirmDelete = nil }
        }
    }

    // MARK: Barre du haut

    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Dither(cell: 2, color: CX.teal, field: Fields.orb)
                    .frame(width: 22, height: 22)
                Text("Meyl")
                    .font(CX.display(24))
                    .tracking(-0.6)
                    .foregroundStyle(CX.ink)
                if store.isDemo {
                    Text("démo").pixelLabel(8, color: CX.teal)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .overlay(Rectangle().strokeBorder(CX.teal, lineWidth: 1))
                }
            }
            Spacer()
            if store.loading.contains(box) && !shown.isEmpty {
                PixelLoader(width: 36, height: 12, cell: 3)
            }
            CXIconButton(symbol: "gearshape") { store.showSettings = true }
            CXIconButton(symbol: "square.and.pencil") { compose = Draft() }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 8)
        .background(CX.paper.opacity(0.97))
    }

    // MARK: En-tête : titre, recherche, dossiers

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isSearch ? "Recherche" : Mailbox.label(for: box))
                .font(CX.display(46))
                .tracking(-1.2)
                .foregroundStyle(CX.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 10)
            Text(subtitle)
                .pixelLabel(9)
                .padding(.top, 2)

            searchPill
                .padding(.top, 18)

            if !isSearch {
                tabs
                    .padding(.top, 18)
            }
        }
        .padding(.bottom, 10)
    }

    private var subtitle: String {
        if isSearch { return searching ? "Recherche…" : "\(shown.count) résultat\(shown.count > 1 ? "s" : "") pour « \(query) »" }
        guard let m = mailbox, let t = m.total else { return " " }
        let u = m.unseen ?? 0
        if t == 0 { return "Vide" }
        return u > 0 ? "\(u) non lu\(u > 1 ? "s" : "") · \(t) au total" : "\(t) message\(t > 1 ? "s" : "")"
    }

    private var searchPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16))
                .foregroundStyle(CX.ink2)
            TextField("", text: $query, prompt: Text("Chercher dans ton courrier…").font(CX.serif(19, italic: true)).foregroundStyle(CX.ink3))
                .font(CX.serif(19))
                .foregroundStyle(CX.ink)
                .tint(CX.teal)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { Task { await runSearch(query) } }
            if searching {
                PixelLoader(width: 28, height: 12, cell: 2)
            } else if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .medium)).foregroundStyle(CX.ink2)
                }
            } else {
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(CX.teal.opacity(0.35)))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CX.wash)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(searchFocused ? CX.teal.opacity(0.6) : CX.hairline, lineWidth: 1))
        )
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

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .bottom, spacing: 22) {
                ForEach(store.boxes) { b in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeInOut(duration: 0.2)) { box = b.path }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 3) {
                                Text(b.label)
                                    .font(CX.serif(19, box == b.path ? .semibold : .regular))
                                    .foregroundStyle(box == b.path ? CX.ink : CX.ink2)
                                if let u = b.unseen, u > 0 {
                                    Text(String(u)).pixelLabel(8, color: CX.teal)
                                        .offset(y: 1)
                                }
                            }
                            Group {
                                if box == b.path {
                                    Dither(cell: 2, color: CX.teal, field: Fields.ramp)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(height: 4)
                        }
                        .fixedSize()
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Recherche

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
            Button(role: .destructive) { confirmDelete = row } label: { Label("Supprimer", systemImage: "trash.slash") }
                .tint(CX.red)
            Button { Task { await store.move(row, to: "INBOX") } } label: { Label("Remettre", systemImage: "tray.and.arrow.up") }
                .tint(CX.ink2)
        } else {
            Button(role: .destructive) { Task { await store.move(row, to: "Trash") } } label: { Label("Corbeille", systemImage: "trash") }
                .tint(CX.red)
            if row.box != "Archive" {
                Button { Task { await store.move(row, to: "Archive") } } label: { Label("Archiver", systemImage: "archivebox") }
                    .tint(CX.ink)
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
            Button(role: .destructive) { confirmDelete = row } label: { Label("Supprimer", systemImage: "trash.slash") }
        } else {
            Button(role: .destructive) { Task { await store.move(row, to: "Trash") } } label: { Label("Corbeille", systemImage: "trash") }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            if store.loading.contains(box) {
                PixelLoader(width: 120, height: 28, cell: 4)
                Text("Le courrier arrive…").font(CX.serif(19, italic: true)).foregroundStyle(CX.ink2)
            } else {
                Dither(cell: 4, color: CX.ink3, field: isSearch ? Fields.orb : Fields.tray)
                    .frame(width: 120, height: 90)
                Text(isSearch ? "Rien trouvé." : "Rien ici.")
                    .font(CX.serif(22, italic: true))
                    .foregroundStyle(CX.ink2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Ligne de la liste

struct CodexRow: View {
    let row: MailRow
    var showBox = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if row.seen { Color.clear } else { PixelDot() }
            }
            .frame(width: 7, height: 7)
            .padding(.top, 9)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.box == "Sent" ? "À " + row.name : row.name)
                        .font(CX.serif(19, row.seen ? .regular : .semibold))
                        .foregroundStyle(CX.ink)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if row.att {
                        Image(systemName: "paperclip")
                            .font(.system(size: 11))
                            .foregroundStyle(CX.ink3)
                    }
                    Text(Fmt.pixelList(row.date))
                        .pixelLabel(8, color: row.seen ? CX.ink3 : CX.teal)
                }
                Text(row.subject)
                    .font(CX.serif(17))
                    .foregroundStyle(row.seen ? CX.ink2 : CX.ink)
                    .lineLimit(2)
                if showBox {
                    Text(Mailbox.label(for: row.box)).pixelLabel(8, color: CX.teal)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}
