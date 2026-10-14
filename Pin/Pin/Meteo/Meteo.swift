import SwiftUI
import CoreLocation

/// Météo à l'endroit où tu es (Open-Meteo, sans compte ni clé).
struct PrevisionMeteo: Decodable {
    struct Actuel: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double
        let weather_code: Int
        let wind_speed_10m: Double
        let relative_humidity_2m: Double
        let is_day: Int
    }
    struct Heures: Decodable {
        let time: [String]
        let temperature_2m: [Double]
        let weather_code: [Int]
        let precipitation_probability: [Int?]
    }
    struct Jours: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let precipitation_probability_max: [Int?]
        let sunrise: [String]
        let sunset: [String]
    }
    let timezone: String?
    let current: Actuel
    let hourly: Heures
    let daily: Jours
}

enum CodeMeteo {
    static func infos(_ code: Int, jour: Bool = true) -> (icone: String, texte: String) {
        switch code {
        case 0: return (jour ? "sun.max.fill" : "moon.stars.fill", "Ciel dégagé")
        case 1: return (jour ? "sun.min.fill" : "moon.fill", "Plutôt dégagé")
        case 2: return (jour ? "cloud.sun.fill" : "cloud.moon.fill", "Partiellement nuageux")
        case 3: return ("cloud.fill", "Couvert")
        case 45, 48: return ("cloud.fog.fill", "Brouillard")
        case 51, 53, 55: return ("cloud.drizzle.fill", "Bruine")
        case 56, 57: return ("cloud.sleet.fill", "Bruine verglaçante")
        case 61: return ("cloud.rain.fill", "Pluie faible")
        case 63: return ("cloud.rain.fill", "Pluie")
        case 65: return ("cloud.heavyrain.fill", "Forte pluie")
        case 66, 67: return ("cloud.sleet.fill", "Pluie verglaçante")
        case 71, 73, 75, 77: return ("cloud.snow.fill", "Neige")
        case 80, 81: return ("cloud.sun.rain.fill", "Averses")
        case 82: return ("cloud.heavyrain.fill", "Fortes averses")
        case 85, 86: return ("cloud.snow.fill", "Averses de neige")
        case 95: return ("cloud.bolt.rain.fill", "Orage")
        case 96, 99: return ("cloud.bolt.rain.fill", "Orage avec grêle")
        default: return ("cloud.fill", "—")
        }
    }
}

/// Position de l'iPhone, une seule fois par demande.
@MainActor
final class Localisation: NSObject, CLLocationManagerDelegate {
    private let gestionnaire = CLLocationManager()
    private var attente: CheckedContinuation<CLLocation?, Never>?

    func position() async -> CLLocation? {
        gestionnaire.delegate = self
        gestionnaire.desiredAccuracy = kCLLocationAccuracyKilometer
        let statut = gestionnaire.authorizationStatus
        if statut == .denied || statut == .restricted { return nil }
        return await withCheckedContinuation { c in
            terminer(nil)
            attente = c
            if statut == .notDetermined { gestionnaire.requestWhenInUseAuthorization() } else { gestionnaire.requestLocation() }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(12))
                self.terminer(nil)
            }
        }
    }

    private func terminer(_ l: CLLocation?) {
        attente?.resume(returning: l)
        attente = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let st = manager.authorizationStatus
        Task { @MainActor in
            if st == .authorizedWhenInUse || st == .authorizedAlways {
                if self.attente != nil { manager.requestLocation() }
            } else if st == .denied || st == .restricted {
                self.terminer(nil)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let l = locations.last
        Task { @MainActor in self.terminer(l) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.terminer(nil) }
    }
}

@MainActor
final class Meteo: ObservableObject {
    static let partage = Meteo()
    @Published private(set) var prevision: PrevisionMeteo?
    @Published private(set) var erreur: String?
    @Published private(set) var ville = "Ma position"
    private var chargeeLe: Date?
    private let localisation = Localisation()

    /// Repli quand la position est refusée ou introuvable (et jamais connue).
    private static let repli = (lat: 48.7994, lon: 2.4997, nom: "Saint-Maur-des-Fossés")

    func charger(forcer: Bool = false) async {
        if !forcer, let d = chargeeLe, Date().timeIntervalSince(d) < 600, prevision != nil { return }
        let d = UserDefaults.standard
        var lat = d.object(forKey: "meteo.lat") as? Double
        var lon = d.object(forKey: "meteo.lon") as? Double
        var nom = d.string(forKey: "meteo.ville")
        if let pos = await localisation.position() {
            lat = pos.coordinate.latitude
            lon = pos.coordinate.longitude
            let lieu = try? await CLGeocoder().reverseGeocodeLocation(pos, preferredLocale: Locale(identifier: "fr_FR")).first
            nom = lieu?.locality ?? lieu?.subAdministrativeArea ?? lieu?.name ?? "Ma position"
            d.set(lat, forKey: "meteo.lat"); d.set(lon, forKey: "meteo.lon"); d.set(nom, forKey: "meteo.ville")
        }
        let (la, lo, ville) = (lat ?? Self.repli.lat, lon ?? Self.repli.lon, nom ?? Self.repli.nom)
        let adresse = "https://api.open-meteo.com/v1/forecast?latitude=\(la)&longitude=\(lo)"
            + "&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m,is_day"
            + "&hourly=temperature_2m,weather_code,precipitation_probability"
            + "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"
            + "&timezone=auto&forecast_days=7"
        do {
            let (data, _) = try await URLSession.shared.data(from: URL(string: adresse)!)
            let p = try JSONDecoder().decode(PrevisionMeteo.self, from: data)
            if let id = p.timezone, let tz = TimeZone(identifier: id) {
                formatISO.timeZone = tz
                formatJour.timeZone = tz
            }
            prevision = p
            self.ville = ville
            erreur = nil
            chargeeLe = Date()
        } catch {
            erreur = "Météo indisponible."
        }
    }
}

private let formatISO: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Europe/Paris")
    f.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return f
}()
private let formatJour: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Europe/Paris")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

/// Écran Météo : maintenant en haut, puis les 7 jours. La molette choisit un
/// jour, le centre ouvre ses heures.
struct EcranMeteo: View {
    @EnvironmentObject var nav: Navigateur
    @ObservedObject private var meteo = Meteo.partage
    @State private var index = 0

    var body: some View {
        Group {
            if let p = meteo.prevision {
                VStack(spacing: 0) {
                    entete(p)
                    Divider()
                    ScrollViewReader { proxy in
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                ForEach(p.daily.time.indices, id: \.self) { i in
                                    ligneJour(p, i).id(i)
                                        .onTapGesture { index = i; nav.ouvrir(.meteoJour(index: i)) }
                                }
                            }
                        }
                        .onChange(of: index) { _, i in withAnimation(.linear(duration: 0.1)) { proxy.scrollTo(i, anchor: .center) } }
                    }
                }
            } else if let e = meteo.erreur {
                MessageEcran(icone: "cloud.slash", texte: e, detail: "Bouton central pour réessayer.")
                    .roue { g in g.centre = { Task { await meteo.charger(forcer: true) } } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.white)
        .task { await meteo.charger() }
        .roue { g in
            g.tour = { s in
                let n = meteo.prevision?.daily.time.count ?? 0
                guard n > 0 else { return }
                index = min(max(index + s, 0), n - 1)
            }
            g.centre = { if meteo.prevision != nil { nav.ouvrir(.meteoJour(index: index)) } }
        }
    }

    private func entete(_ p: PrevisionMeteo) -> some View {
        let c = p.current
        let info = CodeMeteo.infos(c.weather_code, jour: c.is_day == 1)
        return HStack(spacing: 10) {
            Image(systemName: info.icone)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 38))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(Int(c.temperature_2m.rounded()))°").font(.system(size: 30, weight: .light))
                Text(info.texte).font(.system(size: 12, weight: .semibold))
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 2) {
                Text(meteo.ville).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                Text("Ressenti \(Int(c.apparent_temperature.rounded()))°").font(.system(size: 10))
                Text("Vent \(Int(c.wind_speed_10m.rounded())) km/h").font(.system(size: 10))
                Text("Humidité \(Int(c.relative_humidity_2m))%").font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(LinearGradient(colors: [Color(red: 0.88, green: 0.94, blue: 1), .white], startPoint: .top, endPoint: .bottom))
    }

    private func ligneJour(_ p: PrevisionMeteo, _ i: Int) -> some View {
        let d = p.daily
        let date = formatJour.date(from: d.time[i]) ?? Date()
        let nom = i == 0 ? "Aujourd'hui" : (i == 1 ? "Demain" : date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "fr_FR"))).capitalized)
        let info = CodeMeteo.infos(d.weather_code[i])
        let pluie = d.precipitation_probability_max[i] ?? 0
        let sel = i == index
        return HStack(spacing: 8) {
            Text(nom).font(.system(size: 14, weight: .semibold)).frame(width: 96, alignment: .leading)
            Image(systemName: info.icone).symbolRenderingMode(sel ? .monochrome : .multicolor).font(.system(size: 15)).frame(width: 24)
            Text(pluie >= 20 ? "\(pluie)%" : "").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(sel ? .white : Color(red: 0.2, green: 0.5, blue: 0.9)).frame(width: 30, alignment: .leading)
            Spacer(minLength: 0)
            Text("\(Int(d.temperature_2m_min[i].rounded()))°").font(.system(size: 13)).opacity(0.7)
            Text("\(Int(d.temperature_2m_max[i].rounded()))°").font(.system(size: 13, weight: .semibold)).frame(width: 30, alignment: .trailing)
        }
        .foregroundStyle(sel ? Color.white : Color.black)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(sel ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.42, green: 0.66, blue: 0.95), Color(red: 0.16, green: 0.44, blue: 0.86)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(Color.clear))
    }
}

/// Les heures d'un jour : la molette les fait défiler.
struct EcranMeteoJour: View {
    let index: Int
    @ObservedObject private var meteo = Meteo.partage
    @StateObject private var defilement = DefilementMolette()

    var body: some View {
        Group {
            if let p = meteo.prevision, p.daily.time.indices.contains(index) {
                let jour = p.daily.time[index]
                let heures = p.hourly.time.indices.filter { p.hourly.time[$0].hasPrefix(jour) }
                let maintenant = Date()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        HStack {
                            Label(String(p.daily.sunrise[index].suffix(5)), systemImage: "sunrise.fill")
                            Spacer()
                            Label(String(p.daily.sunset[index].suffix(5)), systemImage: "sunset.fill")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .symbolRenderingMode(.multicolor)
                        .padding(8)
                        ForEach(heures, id: \.self) { h in
                            let date = formatISO.date(from: p.hourly.time[h]) ?? .distantPast
                            if index > 0 || date.addingTimeInterval(3600) > maintenant {
                                let info = CodeMeteo.infos(p.hourly.weather_code[h], jour: (7...20).contains(Calendar.current.component(.hour, from: date)))
                                HStack(spacing: 10) {
                                    Text(String(p.hourly.time[h].suffix(5))).font(.system(size: 13, weight: .semibold).monospacedDigit()).frame(width: 48, alignment: .leading)
                                    Image(systemName: info.icone).symbolRenderingMode(.multicolor).font(.system(size: 15)).frame(width: 24)
                                    Text(info.texte).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer(minLength: 0)
                                    if let pr = p.hourly.precipitation_probability[h], pr >= 20 {
                                        Text("\(pr)%").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(red: 0.2, green: 0.5, blue: 0.9))
                                    }
                                    Text("\(Int(p.hourly.temperature_2m[h].rounded()))°").font(.system(size: 14, weight: .semibold)).frame(width: 34, alignment: .trailing)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                Divider().padding(.leading, 10)
                            }
                        }
                    }
                    .background(AncreDefilement(defilement: defilement).frame(width: 0, height: 0), alignment: .top)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.white)
        .roue { g in
            let d = defilement
            g.tour = { s in d.cran(s) }
        }
    }
}
