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
        // Pas besoin de mises à jour fréquentes pour une carte du ciel : on évite de
        // redessiner tout l'écran à chaque micro-mouvement.
        manager.distanceFilter = 200
        manager.headingFilter = 3
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
        guard let last = locations.last, last.horizontalAccuracy >= 0 else { return }
        location = last
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
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

    private static let maxAge: TimeInterval = 6 * 3600
    private var lastPassObserver: CLLocation?
    private var lastPassDate: Date?
    private var computing = false

    private nonisolated static func cacheURL(_ c: Constellation) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("celestrak-\(c.rawValue).json")
    }

    private struct LoadResult: Sendable {
        let constellation: Constellation
        let satellites: [Satellite]
        let date: Date?
        let failed: Bool
    }

    func load(force: Bool = false) async {
        guard !loading else { return }
        loading = true
        error = nil

        // Les cinq constellations en parallèle, téléchargement et décodage hors du fil principal.
        let results = await withTaskGroup(of: LoadResult.self) { group -> [LoadResult] in
            for c in Constellation.allCases {
                group.addTask { await SatelliteStore.fetch(c, force: force) }
            }
            var all: [LoadResult] = []
            for await r in group { all.append(r) }
            return all
        }

        let ordered = Constellation.allCases.compactMap { c in results.first { $0.constellation == c } }
        satellites = ordered.flatMap(\.satellites)
        dataDate = ordered.compactMap(\.date).min()
        let failures = ordered.filter(\.failed).map(\.constellation.rawValue)
        if !failures.isEmpty {
            error = "Téléchargement impossible : \(failures.joined(separator: ", ")). Vérifie ta connexion puis réessaie."
        }
        loading = false
        lastPassObserver = nil
    }

    private nonisolated static func fetch(_ c: Constellation, force: Bool) async -> LoadResult {
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
                var req = URLRequest(url: url, timeoutInterval: 15)
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
                // Repli sur le cache, même ancien (CelesTrak limite aussi les téléchargements répétés).
                data = try? Data(contentsOf: file)
            }
        }
        guard let data, let omms = try? JSONDecoder().decode([OMM].self, from: data) else {
            return LoadResult(constellation: c, satellites: [], date: nil, failed: true)
        }
        return LoadResult(constellation: c,
                          satellites: omms.compactMap { Satellite(omm: $0, constellation: c) },
                          date: fileDate,
                          failed: false)
    }

    func recompute(for location: CLLocation, at date: Date = Date()) {
        guard !computing, !satellites.isEmpty else { return }
        computing = true
        let sats = satellites
        let obs = Observer(location: location)
        Task.detached(priority: .userInitiated) {
            let result = SatelliteStore.computePositions(sats, observer: obs, at: date)
            await MainActor.run {
                self.positions = result
                self.computing = false
            }
        }

        // Passages de l'ISS : à recalculer quand on bouge beaucoup ou toutes les 6 heures.
        let moved = lastPassObserver.map { $0.distance(from: location) > 20_000 } ?? true
        let stale = lastPassDate.map { date.timeIntervalSince($0) > 6 * 3600 } ?? true
        if moved || stale, let iss = sats.first(where: { $0.constellation == .iss }) {
            lastPassObserver = location
            lastPassDate = date
            Task.detached(priority: .utility) {
                let passes = SatelliteStore.computePasses(sat: iss, observer: obs, from: date)
                await MainActor.run { self.issPasses = passes }
            }
        }
    }

    nonisolated static func computePositions(_ sats: [Satellite], observer obs: Observer, at date: Date) -> [SatPosition] {
        sats.map { sat in
            let p = sat.ecef(at: date)
            let look = obs.look(at: p)
            let r = (p.x * p.x + p.y * p.y + p.z * p.z).squareRoot()
            return SatPosition(sat: sat, az: look.az, el: look.el, range: look.range, altitude: r - Satellite.re)
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
