import SwiftUI

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var texte: String
    var modifiee: Date

    var titre: String {
        let l = texte.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return l.isEmpty ? "Nouvelle note" : l
    }
}

/// Les notes, gardées sur l'iPhone.
@MainActor
final class CarnetNotes: ObservableObject {
    static let partage = CarnetNotes()
    @Published private(set) var notes: [Note] = []
    private let cle = "notes"

    private init() {
        if let d = UserDefaults.standard.data(forKey: cle), let n = try? JSONDecoder().decode([Note].self, from: d) { notes = n }
    }

    private func sauver() {
        if let d = try? JSONEncoder().encode(notes) { UserDefaults.standard.set(d, forKey: cle) }
    }

    func creer() -> UUID {
        let n = Note(texte: "", modifiee: Date())
        notes.insert(n, at: 0)
        sauver()
        return n.id
    }

    func texte(_ id: UUID) -> String { notes.first { $0.id == id }?.texte ?? "" }

    func modifier(_ id: UUID, _ texte: String) {
        guard let i = notes.firstIndex(where: { $0.id == id }), notes[i].texte != texte else { return }
        notes[i].texte = texte
        notes[i].modifiee = Date()
        let n = notes.remove(at: i)
        notes.insert(n, at: 0)
        sauver()
    }

    func supprimer(_ id: UUID) {
        notes.removeAll { $0.id == id }
        sauver()
    }

    /// Une note laissée vide en sortant disparaît.
    func nettoyer(_ id: UUID) {
        if texte(id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { supprimer(id) }
    }
}

struct EcranNotes: View {
    @EnvironmentObject var nav: Navigateur
    @ObservedObject private var carnet = CarnetNotes.partage

    var body: some View {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .short
        let elements = [ElementListe(id: "__nouvelle", titre: "Nouvelle note")] + carnet.notes.map {
            ElementListe(id: $0.id.uuidString, titre: $0.titre, detail: f.localizedString(for: $0.modifiee, relativeTo: Date()))
        }
        return EcranListe(cle: .notes, elements: elements) { e in
            if e.id == "__nouvelle" {
                nav.ouvrir(.note(id: carnet.creer()))
            } else if let id = UUID(uuidString: e.id) {
                nav.ouvrir(.note(id: id))
            }
        }
    }
}

/// Une note : toucher le texte (ou le centre) ouvre le clavier, ⏮ dicte,
/// la molette fait défiler. Enregistrée à chaque lettre.
struct EcranNote: View {
    let id: UUID
    @EnvironmentObject var nav: Navigateur
    @EnvironmentObject var clavier: Clavier
    @ObservedObject private var carnet = CarnetNotes.partage
    @StateObject private var dictee = Dictee()
    @StateObject private var defilement = DefilementMolette()
    @State private var texte = ""
    @State private var idChamp = UUID()
    @State private var confirmer = false

    private var actif: Bool { clavier.actif && clavier.champ == idChamp }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    TexteAvecCurseur(texte: texte, titre: "Écris ou dicte ta note…", actif: actif, lignes: 10_000,
                                     depuisFin: actif ? clavier.depuisFin : 0)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                        .id("texte")
                        .background(AncreDefilement(defilement: defilement).frame(width: 0, height: 0), alignment: .top)
                }
                .onChange(of: texte) { _, _ in if clavier.depuisFin == 0 { proxy.scrollTo("texte", anchor: .bottom) } }
            }
            .contentShape(Rectangle())
            .onTapGesture { ouvrirClavier() }
            HStack(spacing: 8) {
                Button { basculerDictee() } label: {
                    Label(dictee.actif ? "Stop" : "Dicter", systemImage: dictee.actif ? "waveform.circle.fill" : "mic.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(dictee.actif ? .red : Color(white: 0.3))
                }
                Spacer()
                Text("\(texte.count) car.").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) { confirmer = true } label: {
                    Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color(white: 0.93))
        }
        .background(Color(red: 1, green: 0.99, blue: 0.9))
        .confirmationDialog("Supprimer cette note ?", isPresented: $confirmer, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { carnet.supprimer(id); nav.retour() }
        }
        .onAppear { texte = carnet.texte(id) }
        .onChange(of: texte) { _, t in carnet.modifier(id, t) }
        .onDisappear {
            dictee.arreter()
            clavier.liberer(idChamp)
            carnet.nettoyer(id)
        }
        .roue { g in
            let d = defilement
            g.tour = { s in d.cran(s) }
            g.centre = { ouvrirClavier() }
            g.precedent = { basculerDictee() }
        }
    }

    private func ouvrirClavier() {
        clavier.ouvrir(champ: idChamp, texte: $texte, type: .texte, libelleRetour: "retour", retour: nil)
    }

    private func basculerDictee() {
        if dictee.actif { dictee.arreter(); return }
        let base = texte
        dictee.demarrer { t in texte = base.isEmpty ? t : base + (base.hasSuffix("\n") ? "" : " ") + t }
    }
}
