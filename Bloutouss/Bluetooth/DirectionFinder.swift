import CoreMotion
import Foundation

/// Estime la direction d'un appareil pendant que l'utilisateur tourne sur lui-même :
/// le corps masque une partie du signal, qui est donc plus fort quand on fait face à l'appareil.
///
/// Méthode :
/// 1. Le cap du téléphone est intégré à partir du gyroscope (corrigé par le magnétomètre),
///    quelle que soit la façon dont le téléphone est tenu, et enregistré dans un historique.
/// 2. Chaque mesure RSSI est associée au cap exact à l'instant où elle a été reçue
///    (interpolation dans l'historique), et non au cap au moment de l'affichage.
/// 3. Le RSSI est ajusté par moindres carrés pondérés sur le modèle
///    `rssi ≈ a + b·cos(cap) + c·sin(cap)` : le maximum de la courbe donne la direction
///    avec une précision bien meilleure que la taille d'un secteur, et les résidus donnent
///    la marge d'erreur.
final class DirectionFinder: ObservableObject {
    /// Angle de la flèche à l'écran, en radians (positif = vers la droite). Continu pour
    /// éviter que l'animation fasse un tour complet en passant de -180° à 180°.
    @Published private(set) var arrowAngle: Double = 0
    /// Angle de la cible par rapport à l'avant du téléphone, entre -π et π (positif = à droite).
    @Published private(set) var relativeAngle: Double = 0
    @Published private(set) var hasDirection = false
    @Published private(set) var confidence: Double = 0
    /// Part du tour complet déjà couverte par des mesures récentes (0…1).
    @Published private(set) var coverage: Double = 0
    /// Marge d'erreur estimée, en degrés.
    @Published private(set) var accuracy: Double?
    let isAvailable: Bool

    private struct Sample {
        let time: TimeInterval
        let heading: Double
        let rssi: Double
    }

    private let motion = CMMotionManager()
    /// Cap intégré (radians, sens trigonométrique, non borné).
    private var heading: Double = 0
    private var lastTimestamp: TimeInterval?
    /// Historique (horloge `Date`, cap) pour retrouver le cap au moment de chaque mesure.
    private var headingLog: [(time: TimeInterval, heading: Double)] = []
    private var samples: [Sample] = []
    private var lastSampleDate: Date?
    private var targetHeading: Double?
    private var wasAligned = false

    private let window: TimeInterval = 30       // mesures conservées
    private let halfLife: TimeInterval = 12     // poids divisé par 2 toutes les 12 s
    private let coverageBins = 36

    init() {
        isAvailable = CMMotionManager().isDeviceMotionAvailable
    }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60
        // Référentiel corrigé par le magnétomètre : le biais du gyroscope est compensé,
        // la dérive reste négligeable pendant une recherche.
        motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.integrate(data)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        lastTimestamp = nil
    }

    func reset() {
        samples.removeAll()
        targetHeading = nil
        hasDirection = false
        confidence = 0
        coverage = 0
        accuracy = nil
        wasAligned = false
    }

    /// Ajoute les mesures reçues depuis le dernier appel.
    func ingest(_ history: [RSSISample]) {
        guard let lastSampleDate else {
            // Mesures antérieures au démarrage : orientation inconnue.
            self.lastSampleDate = history.last?.date
            return
        }
        let fresh = history.filter { $0.date > lastSampleDate }
        guard let newest = fresh.last else { return }
        self.lastSampleDate = newest.date

        for s in fresh {
            let t = s.date.timeIntervalSinceReferenceDate
            guard let h = heading(at: t) else { continue }
            samples.append(Sample(time: t, heading: h, rssi: Double(s.rssi)))
        }
        let cutoff = Date().timeIntervalSinceReferenceDate - window
        samples.removeAll { $0.time < cutoff }
        recompute()
    }

    // MARK: - Orientation

    private func integrate(_ data: CMDeviceMotion) {
        let g = data.gravity
        let norm = sqrt(g.x * g.x + g.y * g.y + g.z * g.z)
        if let last = lastTimestamp, norm > 0.1 {
            let dt = data.timestamp - last
            if dt > 0, dt < 0.5 {
                let r = data.rotationRate
                // Rotation autour de la verticale (opposé de la gravité), quelle que soit la
                // façon dont le téléphone est tenu.
                heading += -(r.x * g.x + r.y * g.y + r.z * g.z) / norm * dt
            }
        }
        lastTimestamp = data.timestamp

        let now = Date().timeIntervalSinceReferenceDate
        headingLog.append((now, heading))
        if let first = headingLog.first, now - first.time > window + 5 {
            headingLog.removeFirst(min(60, headingLog.count))
        }
        updateArrow()
    }

    /// Cap interpolé à l'instant `t` (nil si hors de l'historique).
    private func heading(at t: TimeInterval) -> Double? {
        guard let first = headingLog.first, let last = headingLog.last, t >= first.time - 0.05 else { return nil }
        if t >= last.time { return last.heading }
        // Recherche dichotomique.
        var lo = 0
        var hi = headingLog.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if headingLog[mid].time <= t { lo = mid } else { hi = mid }
        }
        let a = headingLog[lo], b = headingLog[hi]
        let span = b.time - a.time
        guard span > 0 else { return a.heading }
        return a.heading + (b.heading - a.heading) * (t - a.time) / span
    }

    // MARK: - Estimation

    private func recompute() {
        let now = Date().timeIntervalSinceReferenceDate
        guard samples.count >= 8 else {
            coverage = 0
            hasDirection = false
            return
        }

        // Couverture du tour (secteurs de 10°).
        var bins = Set<Int>()
        for s in samples {
            bins.insert(Int(Self.normalize(s.heading) / (2 * .pi) * Double(coverageBins)) % coverageBins)
        }
        coverage = Double(bins.count) / Double(coverageBins)

        // Moindres carrés pondérés : rssi = a + b·cos(h) + c·sin(h).
        var m = [[Double]](repeating: [Double](repeating: 0, count: 3), count: 3)
        var v = [Double](repeating: 0, count: 3)
        var totalWeight = 0.0
        var weightSq = 0.0
        for s in samples {
            let w = pow(0.5, (now - s.time) / halfLife)
            let f = [1, cos(s.heading), sin(s.heading)]
            for i in 0..<3 {
                v[i] += w * f[i] * s.rssi
                for j in 0..<3 { m[i][j] += w * f[i] * f[j] }
            }
            totalWeight += w
            weightSq += w * w
        }
        guard let coef = Self.solve3(m, v) else {
            hasDirection = false
            return
        }
        let (a, b, c) = (coef[0], coef[1], coef[2])
        let amplitude = sqrt(b * b + c * c)

        var residual = 0.0
        for s in samples {
            let w = pow(0.5, (now - s.time) / halfLife)
            let fit = a + b * cos(s.heading) + c * sin(s.heading)
            residual += w * (s.rssi - fit) * (s.rssi - fit)
        }
        let sigma = sqrt(residual / max(totalWeight, 1e-6))
        let effectiveCount = totalWeight * totalWeight / max(weightSq, 1e-6)

        // Incertitude angulaire ≈ σ / (A·√(N/2)) radians.
        let angularError = sigma / max(amplitude * sqrt(max(effectiveCount, 1) / 2), 1e-6)
        let errorDegrees = min(90, max(3, angularError * 180 / .pi))
        accuracy = errorDegrees

        let coverageScore = min(coverage / 0.6, 1)
        let amplitudeScore = min(max((amplitude - 1.0) / 4, 0), 1)
        let precisionScore = min(max((60 - errorDegrees) / 50, 0), 1)
        confidence = coverageScore * amplitudeScore * precisionScore

        let estimate = atan2(c, b)
        // Lissage circulaire de la direction pour une flèche stable.
        if let previous = targetHeading {
            let delta = Self.wrap(estimate - previous)
            targetHeading = previous + delta * (0.25 + 0.5 * confidence)
        } else {
            targetHeading = estimate
        }
        hasDirection = coverage >= 0.45 && amplitude >= 1.5 && errorDegrees < 60
        updateArrow()
    }

    private func updateArrow() {
        guard let targetHeading else { return }
        // Écart positif quand la cible est à gauche (sens trigonométrique)…
        let delta = Self.wrap(targetHeading - heading)
        // … alors qu'à l'écran une rotation positive tourne la flèche vers la droite.
        let screenAngle = -delta
        relativeAngle = screenAngle
        arrowAngle += Self.wrap(screenAngle - arrowAngle)

        let tolerance = max(.pi / 18, (accuracy ?? 30) * .pi / 180)
        let aligned = hasDirection && abs(screenAngle) < tolerance
        if aligned && !wasAligned {
            Haptics.impact(intensity: 1)
        }
        wasAligned = aligned
    }

    // MARK: - Outils

    /// Résout un système 3×3 (élimination de Gauss avec pivot partiel).
    private static func solve3(_ matrix: [[Double]], _ vector: [Double]) -> [Double]? {
        var a = matrix
        var b = vector
        for col in 0..<3 {
            var pivot = col
            for row in col + 1..<3 where abs(a[row][col]) > abs(a[pivot][col]) { pivot = row }
            guard abs(a[pivot][col]) > 1e-9 else { return nil }
            a.swapAt(col, pivot)
            b.swapAt(col, pivot)
            for row in col + 1..<3 {
                let factor = a[row][col] / a[col][col]
                for k in col..<3 { a[row][k] -= factor * a[col][k] }
                b[row] -= factor * b[col]
            }
        }
        var x = [0.0, 0.0, 0.0]
        for row in stride(from: 2, through: 0, by: -1) {
            var sum = b[row]
            for k in row + 1..<3 { sum -= a[row][k] * x[k] }
            x[row] = sum / a[row][row]
        }
        return x
    }

    private static func normalize(_ angle: Double) -> Double {
        let r = angle.truncatingRemainder(dividingBy: 2 * .pi)
        return r < 0 ? r + 2 * .pi : r
    }

    private static func wrap(_ angle: Double) -> Double {
        atan2(sin(angle), cos(angle))
    }
}
