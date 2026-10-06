import UIKit

/// La barre de navigation système est masquée (barres en cuir maison) : on garde
/// quand même le geste « glisser depuis le bord gauche » pour revenir en arrière.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
