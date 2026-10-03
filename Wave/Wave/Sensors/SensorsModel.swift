import Foundation
import CoreMotion
import CoreLocation
import UIKit

/// Lit en direct tous les capteurs accessibles de l'iPhone.
@MainActor
final class SensorsModel: NSObject, ObservableObject, CLLocationManagerDelegate {
    // Mouvement
    @Published var accel = SIMD3<Double>(0, 0, 0)        // g (accélération propre, hors gravité)
    @Published var gravity = SIMD3<Double>(0, 0, 0)       // g
    @Published var rotation = SIMD3<Double>(0, 0, 0)      // rad/s
    @Published var attitude = SIMD3<Double>(0, 0, 0)      // roll, pitch, yaw (rad)
    @Published var field: Double = 0                      // µT
    @Published var fieldCalibrated = false

    // Baromètre
    @Published var pressure: Double?                      // kPa
    @Published var relativeAltitude: Double = 0           // m

    // Localisation
    @Published var heading: Double?                       // ° vrai
    @Published var speed: Double?                         // m/s
    @Published var altitude: Double?                      // m
    @Published var horizontalAccuracy: Double?            // m
    @Published var locationDenied = false

    // Podomètre
    @Published var steps: Int?
    @Published var cadence: Double?                       // pas/min

    // Proximité, batterie, thermique
    @Published var proximityNear = false
    @Published var batteryLevel: Float = -1
    @Published var batteryState: UIDevice.BatteryState = .unknown
    @Published var thermal: ProcessInfo.ThermalState = .nominal

    // Historiques pour les courbes
    @Published var accelHistory: [Double] = []
    @Published var rotationHistory: [Double] = []
    @Published var fieldHistory: [Double] = []
    @Published var pressureHistory: [Double] = []

    private let motion = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let pedometer = CMPedometer()
    private let location = CLLocationManager()
    private var lastHistory = Date.distantPast

    var accelMagnitude: Double { sqrt((accel * accel).sum()) }
    var rotationMagnitude: Double { sqrt((rotation * rotation).sum()) }

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
    }

    func start() {
        startMotion()
        startBarometer()
        startLocation()
        startPedometer()
        startDevice()
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        pedometer.stopUpdates()
        location.stopUpdatingLocation()
        location.stopUpdatingHeading()
        UIDevice.current.isProximityMonitoringEnabled = false
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Mouvement

    private func startMotion() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.showsDeviceMovementDisplay = true
        motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            self.accel = SIMD3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z)
            self.gravity = SIMD3(m.gravity.x, m.gravity.y, m.gravity.z)
            self.rotation = SIMD3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z)
            self.attitude = SIMD3(m.attitude.roll, m.attitude.pitch, m.attitude.yaw)
            self.fieldCalibrated = m.magneticField.accuracy != .uncalibrated
            if self.fieldCalibrated {
                let f = m.magneticField.field
                self.field = sqrt(f.x * f.x + f.y * f.y + f.z * f.z)
            }
            self.pushHistory()
        }
    }

    private func pushHistory() {
        guard Date().timeIntervalSince(lastHistory) > 0.1 else { return }
        lastHistory = Date()
        append(&accelHistory, accelMagnitude)
        append(&rotationHistory, rotationMagnitude)
        if fieldCalibrated { append(&fieldHistory, field) }
        if let p = pressure { append(&pressureHistory, p) }
    }

    private func append(_ array: inout [Double], _ value: Double) {
        array.append(value)
        if array.count > 120 { array.removeFirst(array.count - 120) }
    }

    // MARK: Baromètre

    private func startBarometer() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.pressure = data.pressure.doubleValue
            self.relativeAltitude = data.relativeAltitude.doubleValue
        }
    }

    // MARK: Localisation

    private func startLocation() {
        if location.authorizationStatus == .notDetermined {
            location.requestWhenInUseAuthorization()
        }
        location.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { location.startUpdatingHeading() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            locationDenied = status == .denied || status == .restricted
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        Task { @MainActor in
            speed = max(0, l.speed)
            altitude = l.altitude
            horizontalAccuracy = l.horizontalAccuracy >= 0 ? l.horizontalAccuracy : nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        Task { @MainActor in
            heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: Podomètre

    private func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor in
                self?.steps = data.numberOfSteps.intValue
                self?.cadence = data.currentCadence.map { $0.doubleValue * 60 }
            }
        }
    }

    // MARK: Proximité, batterie, thermique

    private func startDevice() {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        device.isProximityMonitoringEnabled = true
        batteryLevel = device.batteryLevel
        batteryState = device.batteryState
        proximityNear = device.proximityState
        thermal = ProcessInfo.processInfo.thermalState

        let center = NotificationCenter.default
        center.addObserver(forName: UIDevice.proximityStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.proximityNear = UIDevice.current.proximityState }
        }
        center.addObserver(forName: UIDevice.batteryLevelDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.batteryLevel = UIDevice.current.batteryLevel }
        }
        center.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.batteryState = UIDevice.current.batteryState }
        }
        center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.thermal = ProcessInfo.processInfo.thermalState }
        }
    }

    // MARK: Libellés

    var batteryText: String {
        guard batteryLevel >= 0 else { return "—" }
        let pct = Int((batteryLevel * 100).rounded())
        switch batteryState {
        case .charging: return "\(pct) % (en charge)"
        case .full: return "\(pct) % (pleine)"
        case .unplugged: return "\(pct) %"
        default: return "\(pct) %"
        }
    }

    var thermalText: String {
        switch thermal {
        case .nominal: return "Normale"
        case .fair: return "Correcte"
        case .serious: return "Élevée"
        case .critical: return "Critique"
        @unknown default: return "—"
        }
    }

    var thermalColor: UIColor {
        switch thermal {
        case .nominal: return .systemGreen
        case .fair: return .systemYellow
        case .serious: return .systemOrange
        case .critical: return .systemRed
        @unknown default: return .systemGray
        }
    }
}
