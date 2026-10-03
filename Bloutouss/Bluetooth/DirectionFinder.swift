import CoreMotion
import Foundation

/// Estime la direction d'un appareil en associant chaque mesure de RSSI à l'orientation
/// du téléphone pendant que l'utilisateur tourne sur lui-même : le corps bloque une partie
/// du signal, qui est donc plus fort quand on fait face à l'appareil.
final class DirectionFinder: ObservableObject {
    static let binCount = 24

    /// Angle de la flèche à l'écran, en radians (positif = vers la droite). Continu pour
    /// éviter que l'animation fasse un tour complet en passant de -180° à 180°.
    @Published private(set) var arrowAngle: Double = 0
    /// Angle de la cible par rapport à l'avant du téléphone, entre -π et π (positif = à droite).
    @Published private(set) var relativeAngle: Double = 0
    @Published private(set) var hasDirection = false
    @Published private(set) var confidence: Double = 0
    @Published private(set) var coverage: Double = 0
    let isAvailable: Bool

    private let motion = CMMotionManager()
    /// Cap relatif intégré depuis le gyroscope, en radians, sens trigonométrique (gauche = positif).
    private var heading: Double = 0
    private var lastTimestamp: TimeInterval?
    private var values: [Double?] = Array(repeating: nil, count: binCount)
    private var dates: [Date?] = Array(repeating: nil, count: binCount)
    private var targetHeading: Double?
    private var lastSampleDate: Date?
    private var wasAligned = false
    private let maxAge: TimeInterval = 25

    init() {
        isAvailable = motion.isDeviceMotionAvailable
    }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.integrate(data)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        lastTimestamp = nil
    }

    func reset() {
        values = Array(repeating: nil, count: Self.binCount)
        dates = Array(repeating: nil, count: Self.binCount)
        targetHeading = nil
        hasDirection = false
        confidence = 0
        coverage = 0
        wasAligned = false
    }

    /// Ajoute les mesures reçues depuis le dernier appel, associées au cap actuel.
    func ingest(_ samples: [RSSISample]) {
        guard let lastSampleDate else {
            // Les mesures plus anciennes n'ont pas d'orientation connue.
            self.lastSampleDate = samples.last?.date
            return
        }
        let fresh = samples.filter { $0.date > lastSampleDate }
        guard let newest = fresh.last else { return }
        self.lastSampleDate = newest.date

        let now = Date()
        let bin = Self.bin(for: heading)
        for sample in fresh {
            let value = Double(sample.rssi)
            if let current = values[bin], let date = dates[bin], now.timeIntervalSince(date) < maxAge {
                values[bin] = current * 0.6 + value * 0.4
            } else {
                values[bin] = value
            }
            dates[bin] = now
        }
        recompute(now: now)
    }

    // MARK: - Interne

    private func integrate(_ data: CMDeviceMotion) {
        let gravity = data.gravity
        let norm = sqrt(gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z)
        if let last = lastTimestamp, norm > 0.1 {
            let dt = data.timestamp - last
            if dt > 0, dt < 0.5 {
                let rate = data.rotationRate
                // Vitesse de rotation autour de la verticale (axe « haut » = opposé de la gravité),
                // quelle que soit la façon dont le téléphone est tenu.
                let vertical = -(rate.x * gravity.x + rate.y * gravity.y + rate.z * gravity.z) / norm
                heading += vertical * dt
            }
        }
        lastTimestamp = data.timestamp
        updateArrow()
    }

    private func recompute(now: Date) {
        let count = Self.binCount
        var valid = [Double?](repeating: nil, count: count)
        for index in 0..<count {
            if let value = values[index], let date = dates[index], now.timeIntervalSince(date) < maxAge {
                valid[index] = value
            }
        }
        let present = valid.compactMap { $0 }
        coverage = Double(present.count) / Double(count)

        guard present.count >= 6, let maxValue = present.max(), let minValue = present.min() else {
            hasDirection = false
            confidence = 0
            return
        }

        var bestIndex = 0
        var bestScore = -Double.infinity
        for index in 0..<count {
            guard let value = valid[index] else { continue }
            let left = valid[(index - 1 + count) % count] ?? value
            let right = valid[(index + 1) % count] ?? value
            let score = 0.5 * value + 0.25 * left + 0.25 * right
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }

        let spread = maxValue - minValue
        confidence = min(max((spread - 3) / 8, 0), 1) * min(coverage / 0.6, 1)
        targetHeading = (Double(bestIndex) + 0.5) / Double(count) * 2 * .pi
        hasDirection = confidence > 0.15
        updateArrow()
    }

    private func updateArrow() {
        guard let targetHeading else { return }
        // Écart positif quand la cible est à gauche (sens trigonométrique)…
        let delta = Self.wrap(targetHeading - Self.normalize(heading))
        // … alors qu'à l'écran une rotation positive tourne la flèche vers la droite.
        let screenAngle = -delta
        relativeAngle = screenAngle
        arrowAngle += Self.wrap(screenAngle - arrowAngle)

        let aligned = hasDirection && abs(screenAngle) < .pi / 12
        if aligned && !wasAligned {
            Haptics.impact(intensity: 1)
        }
        wasAligned = aligned
    }

    private static func normalize(_ angle: Double) -> Double {
        let remainder = angle.truncatingRemainder(dividingBy: 2 * .pi)
        return remainder < 0 ? remainder + 2 * .pi : remainder
    }

    private static func wrap(_ angle: Double) -> Double {
        atan2(sin(angle), cos(angle))
    }

    private static func bin(for heading: Double) -> Int {
        min(Int(normalize(heading) / (2 * .pi) * Double(binCount)), binCount - 1)
    }
}
