import Foundation
import CoreLocation

/// Position et boussole de l'appareil.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var heading: Double?
    @Published var status: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        status = manager.authorizationStatus
    }

    func start() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let last = locations.last { location = last }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        heading = h
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

@MainActor
final class SatelliteStore: ObservableObject {
    @Published var satellites: [Satellite] = []
    @Published var positions: [SatPosition] = []
    @Published var issPasses: [Pass] = []
    @Published var loading = false
    @Published var error: String?
    @Published var dataDate: Date?

    private let maxAge: TimeInterval = 6 * 3600
    private var lastPassObserver: CLLocation?

    private func cacheURL(_ c: Constellation) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("celestrak-\(c.rawValue).json")
    }

    func load(force: Bool = false) async {
        guard !loading else { return }
        loading = true
        error = nil
        var all: [Satellite] = []
        var failures: [String] = []
        var oldest: Date?

        for c in Constellation.allCases {
            let file = cacheURL(c)
            var data: Data?
            var fileDate: Date?
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let mod = attrs[.modificationDate] as? Date {
                fileDate = mod
                if !force && Date().timeIntervalSince(mod) < maxAge {
                    data = try? Data(contentsOf: file)
                }
            }
            if data == nil {
                do {
                    let url = URL(string: "https://celestrak.org/NORAD/elements/gp.php?\(c.query)&FORMAT=json")!
                    var req = URLRequest(url: url, timeoutInterval: 20)
                    req.setValue("Wave-iOS/1.0", forHTTPHeaderField: "User-Agent")
                    let (d, resp) = try await URLSession.shared.data(for: req)
                    if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                        throw URLError(.badServerResponse)
                    }
                    _ = try JSONDecoder().decode([OMM].self, from: d)
                    try? d.write(to: file)
                    data = d
                    fileDate = Date()
                } catch {
                    // Repli sur le cache, même ancien.
                    data = try? Data(contentsOf: file)
                    if data == nil { failures.append(c.rawValue) }
                }
            }
            if let data, let omms = try? JSONDecoder().decode([OMM].self, from: data) {
                all += omms.compactMap { Satellite(omm: $0, constellation: c) }
                if let fd = fileDate { oldest = min(oldest ?? fd, fd) }
            }
        }

        satellites = all
        dataDate = oldest
        if !failures.isEmpty {
            error = "Téléchargement impossible : \(failures.joined(separator: ", "))"
        }
        loading = false
        lastPassObserver = nil
    }

    func recompute(for location: CLLocation, at date: Date = Date()) {
        let obs = Observer(location: location)
        positions = satellites.map { sat in
            let p = sat.ecef(at: date)
            let look = obs.look(at: p)
            let r = (p.x * p.x + p.y * p.y + p.z * p.z).squareRoot()
            return SatPosition(sat: sat, az: look.az, el: look.el, range: look.range, altitude: r - Satellite.re)
        }

        let needsPasses = lastPassObserver.map { $0.distance(from: location) > 20_000 } ?? true
        if needsPasses, let iss = satellites.first(where: { $0.constellation == .iss }) {
            lastPassObserver = location
            Task.detached(priority: .utility) {
                let passes = SatelliteStore.computePasses(sat: iss, observer: obs, from: date)
                await MainActor.run { self.issPasses = passes }
            }
        }
    }

    nonisolated static func computePasses(sat: Satellite, observer: Observer, from start: Date) -> [Pass] {
        var passes: [Pass] = []
        let step: TimeInterval = 20
        let minEl = 10.0
        var t = start
        let end = start.addingTimeInterval(36 * 3600)
        var current: (start: Date, startAz: Double, peak: Date, maxEl: Double, lastAz: Double)?

        while t < end && passes.count < 6 {
            let look = observer.look(at: sat.ecef(at: t))
            if look.el >= minEl {
                if current == nil {
                    current = (t, look.az, t, look.el, look.az)
                } else if look.el > current!.maxEl {
                    current!.maxEl = look.el
                    current!.peak = t
                }
                current!.lastAz = look.az
            } else if let c = current {
                passes.append(Pass(start: c.start, peak: c.peak, end: t, maxEl: c.maxEl,
                                   startAz: c.startAz, endAz: c.lastAz))
                current = nil
            }
            t = t.addingTimeInterval(step)
        }
        return passes
    }
}
