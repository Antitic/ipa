// Dessine l'icône de Pin (1024 × 1024) : une façade d'iPod blanche, un écran
// sombre avec le carré rose de dipherant, la molette. Lancé par la CI :
//   swift outils/icone.swift Pin/Ressources/Assets.xcassets/AppIcon.appiconset/icon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let cote = 1024
let espace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: cote, height: cote, bitsPerComponent: 8, bytesPerRow: 0,
                          space: espace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { exit(1) }

func couleur(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: espace, components: [r, g, b, a])!
}

func degrade(_ haut: CGColor, _ bas: CGColor, dans rect: CGRect, chemin: CGPath) {
    ctx.saveGState()
    ctx.addPath(chemin)
    ctx.clip()
    let d = CGGradient(colorsSpace: espace, colors: [haut, bas] as CFArray, locations: [0, 1])!
    // Repère CoreGraphics : y vers le haut.
    ctx.drawLinearGradient(d, start: CGPoint(x: rect.midX, y: rect.maxY), end: CGPoint(x: rect.midX, y: rect.minY), options: [])
    ctx.restoreGState()
}

let tout = CGRect(x: 0, y: 0, width: cote, height: cote)
degrade(couleur(0.99, 0.99, 0.99), couleur(0.88, 0.88, 0.9), dans: tout, chemin: CGPath(rect: tout, transform: nil))

// Écran
let ecran = CGRect(x: 232, y: 560, width: 560, height: 360)
degrade(couleur(0.24, 0.26, 0.3), couleur(0.08, 0.09, 0.11), dans: ecran,
        chemin: CGPath(roundedRect: ecran, cornerWidth: 44, cornerHeight: 44, transform: nil))
let vitre = ecran.insetBy(dx: 22, dy: 22)
degrade(couleur(0.97, 0.98, 1), couleur(0.84, 0.88, 0.94), dans: vitre,
        chemin: CGPath(roundedRect: vitre, cornerWidth: 22, cornerHeight: 22, transform: nil))
// Ligne sélectionnée façon iPod
let ligne = CGRect(x: vitre.minX, y: vitre.maxY - 150, width: vitre.width, height: 62)
degrade(couleur(0.42, 0.66, 0.95), couleur(0.16, 0.44, 0.86), dans: ligne, chemin: CGPath(rect: ligne, transform: nil))
for i in 0..<3 {
    ctx.setFillColor(couleur(0.75, 0.78, 0.82))
    ctx.fill(CGRect(x: vitre.minX + 36, y: vitre.maxY - 60 - CGFloat(i == 0 ? 0 : 62 + 62 * i), width: 250 - CGFloat(i) * 40, height: 18))
}
// Le carré rose de dipherant
ctx.setFillColor(couleur(1, 0.12, 0.42))
ctx.fill(CGRect(x: vitre.maxX - 92, y: vitre.minY + 34, width: 56, height: 56))

// Molette
let centreMolette = CGPoint(x: 512, y: 300)
let rayon: CGFloat = 230
let anneau = CGRect(x: centreMolette.x - rayon, y: centreMolette.y - rayon, width: rayon * 2, height: rayon * 2)
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: couleur(0, 0, 0, 0.18))
degrade(couleur(0.98, 0.98, 0.98), couleur(0.86, 0.86, 0.88), dans: anneau, chemin: CGPath(ellipseIn: anneau, transform: nil))
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setStrokeColor(couleur(0.76, 0.76, 0.78))
ctx.setLineWidth(4)
ctx.strokeEllipse(in: anneau)
let r2: CGFloat = 86
let bouton = CGRect(x: centreMolette.x - r2, y: centreMolette.y - r2, width: r2 * 2, height: r2 * 2)
degrade(couleur(0.99, 0.99, 0.99), couleur(0.88, 0.88, 0.9), dans: bouton, chemin: CGPath(ellipseIn: bouton, transform: nil))
ctx.strokeEllipse(in: bouton)
// Repères MENU / ⏮ / ⏭ / ⏯
ctx.setFillColor(couleur(0.62, 0.62, 0.64))
ctx.fill(CGRect(x: centreMolette.x - 40, y: centreMolette.y + 160, width: 80, height: 16))
for (x, sens) in [(centreMolette.x + 175, CGFloat(1)), (centreMolette.x - 175, CGFloat(-1))] {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x - 14 * sens, y: centreMolette.y + 18))
    p.addLine(to: CGPoint(x: x + 14 * sens, y: centreMolette.y))
    p.addLine(to: CGPoint(x: x - 14 * sens, y: centreMolette.y - 18))
    p.closeSubpath()
    ctx.addPath(p)
    ctx.fillPath()
}
ctx.fill(CGRect(x: centreMolette.x - 22, y: centreMolette.y - 182, width: 12, height: 32))
ctx.fill(CGRect(x: centreMolette.x + 8, y: centreMolette.y - 182, width: 12, height: 32))

guard let image = ctx.makeImage() else { exit(1) }
let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png")
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { exit(1) }
CGImageDestinationAddImage(dest, image, nil)
exit(CGImageDestinationFinalize(dest) ? 0 : 1)
