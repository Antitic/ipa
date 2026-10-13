import SwiftUI
import UIKit

/// Fait défiler une ScrollView SwiftUI à la molette, au pixel près (et pas
/// d'élément en élément). On récupère la UIScrollView qui porte le contenu :
/// le doigt continue de défiler normalement.
@MainActor
final class DefilementMolette: ObservableObject {
    fileprivate weak var vue: UIScrollView?
    private var dernierCran = Date.distantPast
    private var vitesse: CGFloat = 1

    /// Un cran de molette : ~26 pt, jusqu'à ×3 quand on tourne vite.
    func cran(_ sens: Int) {
        guard let vue else { return }
        let maintenant = Date()
        let ecart = maintenant.timeIntervalSince(dernierCran)
        vitesse = ecart < 0.07 ? min(vitesse + 0.35, 3) : (ecart < 0.15 ? max(vitesse - 0.2, 1) : 1)
        dernierCran = maintenant
        defiler(vue, de: CGFloat(sens) * 26 * vitesse)
    }

    static func defiler(_ vue: UIScrollView, de dy: CGFloat) {
        let min = -vue.adjustedContentInset.top
        let max = Swift.max(min, vue.contentSize.height - vue.bounds.height + vue.adjustedContentInset.bottom)
        let y = Swift.min(Swift.max(vue.contentOffset.y + dy, min), max)
        guard y != vue.contentOffset.y else { return }
        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
            vue.contentOffset.y = y
        }
    }

    fileprivate func defiler(_ vue: UIScrollView, de dy: CGFloat) { Self.defiler(vue, de: dy) }
}

/// À poser dans le contenu d'une ScrollView : retrouve la UIScrollView parente.
struct AncreDefilement: UIViewRepresentable {
    let defilement: DefilementMolette

    func makeUIView(context: Context) -> Ancre {
        let a = Ancre()
        a.defilement = defilement
        return a
    }

    func updateUIView(_ a: Ancre, context: Context) {
        a.defilement = defilement
        a.chercher()
    }

    final class Ancre: UIView {
        weak var defilement: DefilementMolette?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            chercher()
        }

        func chercher() {
            var v = superview
            while let s = v {
                if let sv = s as? UIScrollView {
                    defilement?.vue = sv
                    return
                }
                v = s.superview
            }
        }
    }
}
