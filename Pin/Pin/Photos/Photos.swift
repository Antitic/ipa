import SwiftUI
import Photos
import AVFoundation

/// Accès à la Pellicule de l'iPhone.
@MainActor
final class Galerie: ObservableObject {
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var autorise: Bool?

    private let gestionnaire = PHCachingImageManager()

    func charger() async {
        let statut = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        autorise = (statut == .authorized || statut == .limited)
        guard autorise == true else { return }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let resultat = PHAsset.fetchAssets(with: .image, options: options)
        var liste: [PHAsset] = []
        liste.reserveCapacity(resultat.count)
        resultat.enumerateObjects { a, _, _ in liste.append(a) }
        assets = liste
    }

    func miniature(_ a: PHAsset, cote: CGFloat) async -> UIImage? {
        await withCheckedContinuation { c in
            let o = PHImageRequestOptions()
            o.deliveryMode = .opportunistic
            o.isNetworkAccessAllowed = true
            o.resizeMode = .fast
            var repondu = false
            gestionnaire.requestImage(for: a, targetSize: CGSize(width: cote, height: cote), contentMode: .aspectFill, options: o) { img, infos in
                let degrade = (infos?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if !degrade, !repondu {
                    repondu = true
                    c.resume(returning: img)
                }
            }
        }
    }

    /// Image en pleine définition (au plus 2400 px), iCloud compris.
    static func imagePleine(_ id: String) async -> UIImage? {
        guard let a = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        return await withCheckedContinuation { c in
            let o = PHImageRequestOptions()
            o.deliveryMode = .highQualityFormat
            o.isNetworkAccessAllowed = true
            o.isSynchronous = false
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 2400, height: 2400), contentMode: .aspectFit, options: o) { img, _ in
                c.resume(returning: img)
            }
        }
    }
}

struct EcranPellicule: View {
    @EnvironmentObject var nav: Navigateur
    @StateObject private var galerie = Galerie()
    @StateObject private var sel = SelectionGrille()
    private let colonnes = 4

    var body: some View {
        Group {
            if galerie.autorise == false {
                MessageEcran(icone: "lock", texte: "Accès aux photos refusé", detail: "Réglages iPhone › Pin › Photos.")
            } else if galerie.assets.isEmpty {
                MessageEcran(icone: "photo.on.rectangle", texte: galerie.autorise == nil ? "Chargement…" : "Pellicule vide")
            } else {
                GeometryReader { g in
                    let cote = (g.size.width - CGFloat(colonnes + 1) * 2) / CGFloat(colonnes)
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(cote), spacing: 2), count: colonnes), spacing: 2) {
                                ForEach(Array(galerie.assets.enumerated()), id: \.element.localIdentifier) { i, a in
                                    Vignette(asset: a, galerie: galerie, cote: cote)
                                        .overlay(
                                            Rectangle().stroke(Color(red: 0.16, green: 0.44, blue: 0.86), lineWidth: i == sel.index ? 3 : 0)
                                        )
                                        .id(i)
                                        .onTapGesture {
                                            sel.index = i
                                            nav.selections[.pellicule] = i
                                            nav.ouvrir(.photo(index: i))
                                        }
                                }
                            }
                            .padding(2)
                        }
                        .onChange(of: sel.index) { _, i in
                            withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(i) }
                        }
                        .onAppear { proxy.scrollTo(sel.index) }
                    }
                }
            }
        }
        .task {
            sel.index = nav.selections[.pellicule] ?? 0
            await galerie.charger()
            sel.total = galerie.assets.count
        }
        .roue { g in
            g.tour = { s in
                sel.deplacer(s)
                nav.selections[.pellicule] = sel.index
            }
            g.precedent = {
                sel.deplacer(-colonnes)
                nav.selections[.pellicule] = sel.index
            }
            g.suivant = {
                sel.deplacer(colonnes)
                nav.selections[.pellicule] = sel.index
            }
            g.centre = {
                guard sel.total > 0 else { return }
                nav.ouvrir(.photo(index: sel.index))
            }
        }
    }
}

@MainActor
final class SelectionGrille: ObservableObject {
    @Published var index = 0
    var total = 0

    func deplacer(_ s: Int) {
        guard total > 0 else { return }
        index = min(max(index + s, 0), total - 1)
    }
}

struct Vignette: View {
    let asset: PHAsset
    let galerie: Galerie
    let cote: CGFloat
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(white: 0.9)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: cote, height: cote)
        .clipped()
        .task(id: asset.localIdentifier) {
            image = await galerie.miniature(asset, cote: cote * UIScreen.main.scale)
        }
    }
}

/// Une photo en plein écran : la molette passe à la suivante, le centre
/// propose de l'envoyer sur WhatsApp.
struct EcranPhoto: View {
    let indexDepart: Int
    @EnvironmentObject var nav: Navigateur
    @StateObject private var galerie = Galerie()
    @StateObject private var sel = SelectionGrille()
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().tint(.white)
            }
            if sel.total > 0 {
                Text("\(sel.index + 1) sur \(sel.total) · centre : envoyer sur WhatsApp")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(4)
                    .background(Capsule().fill(.black.opacity(0.5)))
                    .padding(6)
            }
        }
        .task {
            await galerie.charger()
            sel.total = galerie.assets.count
            sel.index = min(indexDepart, max(sel.total - 1, 0))
            await afficher()
        }
        .onChange(of: sel.index) { _, _ in Task { await afficher() } }
        .roue { g in
            g.tour = { s in sel.deplacer(s); nav.selections[.pellicule] = sel.index }
            g.suivant = { sel.deplacer(1); nav.selections[.pellicule] = sel.index }
            g.precedent = { sel.deplacer(-1); nav.selections[.pellicule] = sel.index }
            g.centre = {
                guard galerie.assets.indices.contains(sel.index) else { return }
                nav.ouvrir(.choixDiscussion(assetId: galerie.assets[sel.index].localIdentifier))
            }
        }
    }

    private func afficher() async {
        guard galerie.assets.indices.contains(sel.index) else { return }
        let a = galerie.assets[sel.index]
        let img = await galerie.miniature(a, cote: 1400)
        if galerie.assets.indices.contains(sel.index), galerie.assets[sel.index] == a { image = img }
    }
}
