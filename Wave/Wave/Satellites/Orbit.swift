import Foundation
import CoreLocation
import SwiftUI

// MARK: - Données CelesTrak (format OMM JSON)

struct OMM: Codable {
    let OBJECT_NAME: String
    let NORAD_CAT_ID: Int
    let EPOCH: String
    let MEAN_MOTION: Double
    let ECCENTRICITY: Double
    let INCLINATION: Double
    let RA_OF_ASC_NODE: Double
    let ARG_OF_PERICENTER: Double
    let MEAN_ANOMALY: Double
}

enum Constellation: String, CaseIterable, Identifiable {
    case gps = "GPS"
    case galileo = "Galileo"
    case glonass = "GLONASS"
    case beidou = "BeiDou"
    case iss = "ISS"

    var id: String { rawValue }

    /// Groupe CelesTrak correspondant.
    var query: String {
        switch self {
        case .gps: return "GROUP=gps-ops"
        case .galileo: return "GROUP=galileo"
        case .glonass: return "GROUP=glo-ops"
        case .beidou: return "GROUP=beidou"
        case .iss: return "CATNR=25544"
        }
    }

    var color: Color {
        switch self {
        case .gps: return Theme.accent
        case .galileo: return Theme.blue
        case .glonass: return Theme.danger
        case .beidou: return Theme.warn
        case .iss: return .white
        }
    }

    var flag: String {
        switch self {
        case .gps: return "🇺🇸"
        case .galileo: return "🇪🇺"
        case .glonass: return "🇷🇺"
        case .beidou: return "🇨🇳"
        case .iss: return "🛰️"
        }
    }
}

// MARK: - Propagation orbitale (Kepler + perturbation J2 séculaire)
//
// Les éléments moyens de CelesTrak sont propagés avec un modèle simplifié :
// suffisant pour une carte du ciel (erreur < 1° pour les satellites GNSS,
// quelques dizaines de secondes sur les passages de l'ISS à 1-2 jours).

struct Satellite: Identifiable {
    let id: Int
    let name: String
    let constellation: Constellation
    let epoch: Date
    let n: Double        // mouvement moyen, rad/s
    let e: Double
    let i: Double        // rad
    let raan0: Double    // rad
    let argp0: Double    // rad
    let m0: Double       // rad
    let a: Double        // demi-grand axe, km
    let raanDot: Double  // rad/s
    let argpDot: Double  // rad/s

    static let mu = 398_600.4418
    static let re = 6378.137
    static let j2 = 1.08262668e-3

    init?(omm: OMM, constellation: Constellation) {
        guard let epoch = Satellite.parseEpoch(omm.EPOCH), omm.MEAN_MOTION > 0 else { return nil }
        id = omm.NORAD_CAT_ID
        name = omm.OBJECT_NAME
        self.constellation = constellation
        self.epoch = epoch
        let deg = Double.pi / 180
        n = omm.MEAN_MOTION * 2 * .pi / 86400
        e = omm.ECCENTRICITY
        i = omm.INCLINATION * deg
        raan0 = omm.RA_OF_ASC_NODE * deg
        argp0 = omm.ARG_OF_PERICENTER * deg
        m0 = omm.MEAN_ANOMALY * deg
        a = pow(Satellite.mu / (n * n), 1.0 / 3.0)
        let p = a * (1 - e * e)
        let k = 1.5 * n * Satellite.j2 * pow(Satellite.re / p, 2)
        raanDot = -k * cos(i)
        argpDot = 0.5 * k * (5 * cos(i) * cos(i) - 1)
    }

    /// Nom court lisible (PRN, numéro Galileo…).
    var shortName: String {
        if let open = name.firstIndex(of: "("), let close = name.firstIndex(of: ")"), open < close {
            let inner = name[name.index(after: open)..<close]
            return inner.replacingOccurrences(of: "PRN ", with: "G")
        }
        return name
    }

    /// Position ECEF (km) à la date donnée.
    func ecef(at date: Date) -> SIMD3<Double> {
        let dt = date.timeIntervalSince(epoch)
        let m = (m0 + n * dt).truncatingRemainder(dividingBy: 2 * .pi)
        let raan = raan0 + raanDot * dt
        let argp = argp0 + argpDot * dt

        var ecc = m
        for _ in 0..<8 {
            let f = ecc - e * sin(ecc) - m
            let fp = 1 - e * cos(ecc)
            ecc -= f / fp
        }
        let nu = 2 * atan2(sqrt(1 + e) * sin(ecc / 2), sqrt(1 - e) * cos(ecc / 2))
        let r = a * (1 - e * cos(ecc))
        let u = argp + nu

        let x = r * (cos(raan) * cos(u) - sin(raan) * sin(u) * cos(i))
        let y = r * (sin(raan) * cos(u) + cos(raan) * sin(u) * cos(i))
        let z = r * (sin(u) * sin(i))

        let theta = Satellite.gmst(date)
        let xe = x * cos(theta) + y * sin(theta)
        let ye = -x * sin(theta) + y * cos(theta)
        return SIMD3(xe, ye, z)
    }

    static func gmst(_ date: Date) -> Double {
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let d = jd - 2451545.0
        let t = d / 36525
        var deg = 280.46061837 + 360.98564736629 * d + 0.000387933 * t * t - t * t * t / 38_710_000
        deg = deg.truncatingRemainder(dividingBy: 360)
        if deg < 0 { deg += 360 }
        return deg * .pi / 180
    }

    /// Format CelesTrak : "2026-10-02T12:34:56.123456" (UTC).
    static func parseEpoch(_ s: String) -> Date? {
        let parts = s.split(separator: "T")
        guard parts.count == 2 else { return nil }
        let d = parts[0].split(separator: "-").compactMap { Int($0) }
        let t = parts[1].split(separator: ":")
        guard d.count == 3, t.count == 3,
              let hh = Int(t[0]), let mm = Int(t[1]), let ss = Double(t[2]) else { return nil }
        var comps = DateComponents()
        comps.year = d[0]; comps.month = d[1]; comps.day = d[2]
        comps.hour = hh; comps.minute = mm; comps.second = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let base = cal.date(from: comps) else { return nil }
        return base.addingTimeInterval(ss)
    }
}

struct Observer {
    let lat: Double   // rad
    let lon: Double   // rad
    let ecef: SIMD3<Double>

    init(location: CLLocation) {
        lat = location.coordinate.latitude * .pi / 180
        lon = location.coordinate.longitude * .pi / 180
        let h = max(location.altitude, 0) / 1000
        let a = 6378.137
        let e2 = 0.00669437999014
        let nRad = a / sqrt(1 - e2 * sin(lat) * sin(lat))
        ecef = SIMD3((nRad + h) * cos(lat) * cos(lon),
                     (nRad + h) * cos(lat) * sin(lon),
                     (nRad * (1 - e2) + h) * sin(lat))
    }

    /// Azimut (deg, depuis le nord, sens horaire), élévation (deg), distance (km).
    func look(at sat: SIMD3<Double>) -> (az: Double, el: Double, range: Double) {
        let d = sat - ecef
        let east = -sin(lon) * d.x + cos(lon) * d.y
        let north = -sin(lat) * cos(lon) * d.x - sin(lat) * sin(lon) * d.y + cos(lat) * d.z
        let up = cos(lat) * cos(lon) * d.x + cos(lat) * sin(lon) * d.y + sin(lat) * d.z
        let range = (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
        var az = atan2(east, north) * 180 / .pi
        if az < 0 { az += 360 }
        let el = asin(up / range) * 180 / .pi
        return (az, el, range)
    }
}

struct SatPosition: Identifiable {
    let sat: Satellite
    let az: Double
    let el: Double
    let range: Double
    let altitude: Double
    var id: Int { sat.id }
}

struct Pass: Identifiable {
    let start: Date
    let peak: Date
    let end: Date
    let maxEl: Double
    let startAz: Double
    let endAz: Double
    var id: Date { start }
}

func compassName(_ az: Double) -> String {
    let names = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"]
    let idx = Int(((az + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
    return names[max(0, min(7, idx))]
}
