import SwiftUI

struct ElementListe: Identifiable, Equatable {
    let id: String
    var titre: String
    var detail: String? = nil
    var badge: String? = nil
    var chevron: Bool = true
}

/// Sélection d'une liste, gardée dans une classe pour que la molette (qui
/// garde des fermetures) lise toujours les valeurs à jour.
@MainActor
final class ModeleListe: ObservableObject {
    @Published var index = 0
    @Published var elements: [ElementListe] = []
    var choisir: ((ElementListe) -> Void)?
    var cle: Ecran?
    weak var nav: Navigateur?

    func deplacer(_ sens: Int) {
        guard !elements.isEmpty else { return }
        let n = min(max(index + sens, 0), elements.count - 1)
        if n != index {
            index = n
            if let cle { nav?.selections[cle] = n }
        }
    }

    func valider() {
        guard elements.indices.contains(index) else { return }
        choisir?(elements[index])
    }

    func toucher(_ i: Int) {
        index = i
        if let cle { nav?.selections[cle] = i }
        valider()
    }
}

/// Une ligne façon iPod : sélection en dégradé bleu, chevron à droite.
struct LigneIPod: View {
    let element: ElementListe
    let selectionne: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(element.titre)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if let d = element.detail {
                    Text(d)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .opacity(0.75)
                }
            }
            Spacer(minLength: 4)
            if let b = element.badge {
                Text(b)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(selectionne ? Color.white.opacity(0.3) : Color(red: 0.2, green: 0.6, blue: 0.3)))
                    .foregroundStyle(.white)
            }
            if element.chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: element.detail == nil ? 28 : 38)
        .foregroundStyle(selectionne ? Color.white : Color.black)
        .background {
            if selectionne {
                LinearGradient(colors: [Color(red: 0.42, green: 0.66, blue: 0.95), Color(red: 0.16, green: 0.44, blue: 0.86)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                Color.white
            }
        }
        .contentShape(Rectangle())
    }
}

/// Un écran-liste complet : molette, centre, tap, sélection mémorisée.
struct EcranListe: View {
    let cle: Ecran
    let elements: [ElementListe]
    var vide: String = "Rien ici pour l'instant."
    let choisir: (ElementListe) -> Void
    var configurer: ((GestionnaireRoue, ModeleListe) -> Void)? = nil

    @EnvironmentObject var nav: Navigateur
    @StateObject private var modele = ModeleListe()

    var body: some View {
        Group {
            if elements.isEmpty {
                Text(vide)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(modele.elements.enumerated()), id: \.element.id) { i, e in
                                LigneIPod(element: e, selectionne: i == modele.index)
                                    .id(i)
                                    .onTapGesture { modele.toucher(i) }
                            }
                        }
                    }
                    .onChange(of: modele.index) { _, n in
                        withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(n) }
                    }
                    .onAppear { proxy.scrollTo(modele.index) }
                }
            }
        }
        .onAppear {
            modele.nav = nav
            modele.cle = cle
            modele.choisir = choisir
            modele.elements = elements
            modele.index = min(nav.selections[cle] ?? 0, max(elements.count - 1, 0))
        }
        .onChange(of: elements) { _, nouveaux in
            modele.elements = nouveaux
            if modele.index >= nouveaux.count { modele.index = max(nouveaux.count - 1, 0) }
        }
        .roue { g in
            let m = modele
            g.tour = { [weak m] s in m?.deplacer(s) }
            g.centre = { [weak m] in m?.valider() }
            configurer?(g, m)
        }
    }
}

/// Message centré pour les écrans en attente ou en erreur.
struct MessageEcran: View {
    let icone: String
    let texte: String
    var detail: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icone).font(.system(size: 30)).foregroundStyle(Color(white: 0.55))
            Text(texte).font(.system(size: 14, weight: .semibold)).multilineTextAlignment(.center)
            if let detail {
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Bouton bleu façon iPod, pour les formulaires.
struct BoutonIPod: View {
    let titre: String
    var actif = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(titre)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(colors: [Color(red: 0.42, green: 0.66, blue: 0.95), Color(red: 0.16, green: 0.44, blue: 0.86)],
                                             startPoint: .top, endPoint: .bottom))
                )
                .opacity(actif ? 1 : 0.45)
        }
        .disabled(!actif)
    }
}

/// Champ texte façon iPod.
struct ChampIPod: View {
    let titre: String
    @Binding var texte: String
    var secret = false
    var clavier: UIKeyboardType = .default

    var body: some View {
        Group {
            if secret {
                SecureField(titre, text: $texte)
            } else {
                TextField(titre, text: $texte)
                    .keyboardType(clavier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.95)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.75), lineWidth: 0.5))
    }
}
