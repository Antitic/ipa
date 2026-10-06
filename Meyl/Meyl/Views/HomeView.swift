import SwiftUI
import UIKit

struct HomeView: View {
    @EnvironmentObject var store: MailStore
    @Binding var compose: Draft?
    @State private var askLogout = false

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        VStack(spacing: 0) {
            LeatherHeader(title: "Courrier", subtitle: store.isDemo ? "démonstration" : nil, leading: {
                LeatherButton(symbol: "gearshape.fill") { askLogout = true }
            }, trailing: {
                LeatherButton(symbol: "square.and.pencil") { compose = Draft() }
            })

            ScrollView {
                VStack(spacing: 22) {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(store.boxes) { box in
                            NavigationLink(value: Route.box(box.path)) {
                                MailboxDoor(box: box)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }

                    latest

                    DymoLabel(text: store.user)
                        .padding(.top, 4)
                        .padding(.bottom, 30)
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
            }
            .refreshable {
                await store.load("INBOX")
            }
        }
        .background(WalnutBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if store.rows["INBOX"] == nil { await store.load("INBOX") }
        }
        .confirmationDialog("Compte \(store.user)", isPresented: $askLogout, titleVisibility: .visible) {
            Button("Relever le courrier") { Task { await store.load("INBOX") } }
            Button("Se déconnecter", role: .destructive) { store.logout() }
            Button("Annuler", role: .cancel) {}
        }
    }

    @ViewBuilder private var latest: some View {
        let recent = Array((store.rows["INBOX"] ?? []).prefix(4))
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Dernières arrivées")
                    .font(Typo.serif(19, bold: true))
                    .foregroundStyle(Ink.ink)
                Spacer()
                if store.loading.contains("INBOX") {
                    ProgressView().tint(Ink.inkSoft)
                }
            }
            .padding(.bottom, 8)

            if recent.isEmpty {
                Text(store.loading.contains("INBOX") ? "Le facteur arrive…" : "Aucune lettre pour l'instant.")
                    .font(Typo.typewriter(14))
                    .foregroundStyle(Ink.inkSoft)
                    .padding(.vertical, 12)
            }
            ForEach(Array(recent.enumerated()), id: \.element.id) { i, row in
                NavigationLink(value: Route.message(row)) {
                    HStack(alignment: .top, spacing: 10) {
                        Group {
                            if row.seen { Color.clear } else { WaxDot() }
                        }
                        .frame(width: 12, height: 12)
                        .padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(row.name)
                                    .font(Typo.serif(16, bold: !row.seen))
                                    .foregroundStyle(Ink.ink)
                                    .lineLimit(1)
                                Spacer()
                                Text(Fmt.list(row.date))
                                    .font(Typo.typewriter(11))
                                    .foregroundStyle(Ink.inkSoft)
                            }
                            Text(row.subject)
                                .font(Typo.typewriter(13))
                                .foregroundStyle(Ink.inkSoft)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if i < recent.count - 1 {
                    Rectangle().fill(Ink.blueInk.opacity(0.18)).frame(height: 1)
                }
            }
        }
        .padding(18)
        .background(PaperSheet())
    }
}

// MARK: - Porte de casier en laiton

struct MailboxDoor: View {
    let box: Mailbox

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // hublot : petite fenêtre vitrée sur le casier
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.05), Ink.walnutDark], startPoint: .top, endPoint: .bottom))
                    .frame(height: 58)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [Ink.brassDeep, Ink.brassHi], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                    )
                    .overlay(
                        // reflet de la vitre
                        LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .topLeading, endPoint: .center)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    )
                // les lettres qu'on devine derrière la vitre
                if (box.total ?? 0) > 0 {
                    HStack(spacing: -10) {
                        ForEach(0..<min(4, max(1, (box.total ?? 0) / 8 + 1)), id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(i % 2 == 0 ? Ink.envelope : Color(red: 0.85, green: 0.88, blue: 0.95))
                                .frame(width: 34, height: 24)
                                .rotationEffect(.degrees(Double(i * 7 - 9)))
                                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                        }
                    }
                    .offset(y: 6)
                    .opacity(0.85)
                }
                Image(systemName: box.symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Ink.brassHi.opacity(0.95))
                    .shadow(color: .black, radius: 2, x: 0, y: 1)
                    .opacity((box.total ?? 0) > 0 ? 0 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)

            Text(box.label.uppercased())
                .font(Typo.engraved(14))
                .kerning(1.2)
                .engraved()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(countText)
                .font(Typo.typewriter(11))
                .foregroundStyle(Color(red: 0.30, green: 0.20, blue: 0.06))
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(BrassPlate(corner: 12))
        .overlay(alignment: .topTrailing) {
            if let u = box.unseen, u > 0 {
                EnamelBadge(count: u)
                    .offset(x: 8, y: -10)
            }
        }
    }

    private var countText: String {
        guard let t = box.total else { return " " }
        return t == 0 ? "vide" : (t == 1 ? "1 lettre" : "\(t) lettres")
    }
}
