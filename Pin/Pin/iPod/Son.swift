import Foundation
import AudioToolbox

/// Les clics de Pin. Joués comme des sons système : iOS les coupe tout seul
/// quand l'iPhone est en mode silencieux, et ils ne coupent pas la musique.
enum Son {
    private static var idTic: SystemSoundID = 0

    private static var actif: Bool {
        UserDefaults.standard.object(forKey: "clics") as? Bool ?? true
    }

    /// Le « tic » de la molette, synthétisé une fois : un souffle très court
    /// et aigu qui retombe, proche du clic d'un iPod classic.
    private static func preparer() {
        guard idTic == 0 else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pin-tic.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? wav().write(to: url)
        }
        AudioServicesCreateSystemSoundID(url as CFURL, &idTic)
    }

    private static func wav() -> Data {
        let frequence = 44_100
        let echantillons = Int(Double(frequence) * 0.006)
        var pcm = [Int16]()
        pcm.reserveCapacity(echantillons)
        var graine: UInt32 = 0x9E37_79B9
        for i in 0..<echantillons {
            let t = Double(i) / Double(frequence)
            let enveloppe = exp(-t * 900)
            graine = graine &* 1_664_525 &+ 1_013_904_223
            let bruit = Double(Int32(bitPattern: graine)) / Double(Int32.max)
            let ton = sin(2 * .pi * 3_800 * t)
            let v = (0.55 * ton + 0.45 * bruit) * enveloppe * 0.5
            pcm.append(Int16(max(-1, min(1, v)) * Double(Int16.max)))
        }
        var d = Data()
        func ajoute<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let taille = pcm.count * 2
        d.append(contentsOf: Array("RIFF".utf8)); ajoute(UInt32(36 + taille))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); ajoute(UInt32(16)); ajoute(UInt16(1)); ajoute(UInt16(1))
        ajoute(UInt32(frequence)); ajoute(UInt32(frequence * 2)); ajoute(UInt16(2)); ajoute(UInt16(16))
        d.append(contentsOf: Array("data".utf8)); ajoute(UInt32(taille))
        for s in pcm { ajoute(s) }
        return d
    }

    /// Un cran de molette.
    static func tic() {
        guard actif else { return }
        preparer()
        AudioServicesPlaySystemSound(idTic)
    }

    /// Les sons du clavier d'iOS (lettre, effacement, touche spéciale).
    static func touche() { if actif { AudioServicesPlaySystemSound(1104) } }
    static func effacement() { if actif { AudioServicesPlaySystemSound(1155) } }
    static func modificateur() { if actif { AudioServicesPlaySystemSound(1156) } }
}
