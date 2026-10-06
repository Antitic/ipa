import SwiftUI
import Observation

enum LinkState: Equatable {
    case connecting, online, offline, demo
}

enum ConsoleTab: Int, CaseIterable, Identifiable {
    case dashboard, services, journal, settings

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Tableau"
        case .services: return "Services"
        case .journal: return "Journal"
        case .settings: return "Réglages"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .services: return "server.rack"
        case .journal: return "printer.dotmatrix"
        case .settings: return "slider.vertical.3"
        }
    }
}

@MainActor
@Observable
final class Store {
    // Navigation
    var tab: ConsoleTab = .dashboard

    // Données
    var overview: Overview?
    var history: [HistoryPoint] = []
    var services: [Service] = []
    var logs: LogResponse?
    var logsLoading = false

    // Filtres du journal (positions des boutons rotatifs)
    var logLevelIndex = 0
    var logHoursIndex = 2

    // Liaison
    var link: LinkState = .connecting
    var errorMessage: String?
    var lastUpdate: Date?
    var didSelfTest = false

    // Réglages
    var baseURL: String
    var token: String
    var demoMode: Bool
    var intervalIndex: Int

    static let intervals: [Double] = [2, 5, 10, 30]
    static let intervalLabels = ["2 s", "5 s", "10 s", "30 s"]
    static let logHours = [1, 6, 24, 168]
    static let logHourLabels = ["1 h", "6 h", "24 h", "7 j"]
    static let logLevels = ["all", "warning", "error"]
    static let logLevelLabels = ["Tout", "Alertes", "Erreurs"]
    static let defaultURL = "https://mlab.dipherant.xyz"
    static let oldDefaultURL = "http://100.100.226.91:8787"

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    private let demo = DemoGenerator()

    init() {
        let d = UserDefaults.standard
        let saved = d.string(forKey: "baseURL")
        baseURL = (saved == nil || saved == Store.oldDefaultURL) ? Store.defaultURL : saved!
        token = Keychain.get("token")
        demoMode = d.object(forKey: "demoMode") as? Bool ?? false
        intervalIndex = d.object(forKey: "intervalIndex") as? Int ?? 0
        // Arguments de lancement (captures automatiques) : -forceDemo YES -startTab 2
        if d.bool(forKey: "forceDemo") { demoMode = true }
        if let t = d.string(forKey: "startTab").flatMap(Int.init), let tab = ConsoleTab(rawValue: t) {
            self.tab = tab
        }
    }

    var isDemo: Bool { demoMode || token.trimmingCharacters(in: .whitespaces).isEmpty }

    private var api: API? { API(baseURL: baseURL, token: token) }

    var logHours: Int { Store.logHours[clamped(logHoursIndex, Store.logHours.count)] }
    var logLevel: String { Store.logLevels[clamped(logLevelIndex, Store.logLevels.count)] }

    private func clamped(_ i: Int, _ count: Int) -> Int { min(max(i, 0), count - 1) }

    // MARK: Réglages

    func saveSettings() {
        let d = UserDefaults.standard
        d.set(baseURL, forKey: "baseURL")
        d.set(demoMode, forKey: "demoMode")
        d.set(intervalIndex, forKey: "intervalIndex")
        Keychain.set(token.trimmingCharacters(in: .whitespacesAndNewlines), for: "token")
        overview = nil
        history = []
        services = []
        logs = nil
        errorMessage = nil
        link = isDemo ? .demo : .connecting
        start()
    }

    /// Changer la cadence ne doit pas effacer les mesures déjà affichées.
    func saveInterval() {
        UserDefaults.standard.set(intervalIndex, forKey: "intervalIndex")
        start()
    }

    func testConnection() async -> (ok: Bool, message: String) {
        guard let api else { return (false, "Adresse invalide") }
        do {
            let ping: PingResponse = try await api.get("api/ping")
            return (true, "\(ping.hostname) répond · agent \(ping.version)")
        } catch {
            return (false, Store.describe(error))
        }
    }

    // MARK: Relève périodique

    func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.loop()
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func loop() async {
        var tick = 0
        while !Task.isCancelled {
            await refreshOverview()
            if tick % 5 == 0 {
                await refreshHistory()
                await refreshServices()
            }
            tick += 1
            let seconds = Store.intervals[clamped(intervalIndex, Store.intervals.count)]
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    func refreshAll() async {
        await refreshOverview()
        await refreshHistory()
        await refreshServices()
    }

    func refreshOverview() async {
        if isDemo {
            overview = demo.overview()
            link = .demo
            errorMessage = nil
            lastUpdate = Date()
            return
        }
        guard let api else { fail(APIError.badURL); return }
        if overview == nil { link = .connecting }
        do {
            let o: Overview = try await api.get("api/overview")
            overview = o
            link = .online
            errorMessage = nil
            lastUpdate = Date()
        } catch {
            fail(error)
        }
    }

    func refreshHistory() async {
        if isDemo { history = demo.history(); return }
        guard let api else { return }
        if let h: HistoryResponse = try? await api.get("api/history") {
            history = h.points
        }
    }

    func refreshServices() async {
        if isDemo { services = demo.services(); return }
        guard let api else { return }
        do {
            let r: ServicesResponse = try await api.get("api/services")
            services = r.services
        } catch {
            fail(error)
        }
    }

    func refreshLogs() async {
        logsLoading = true
        defer { logsLoading = false }
        if isDemo {
            try? await Task.sleep(for: .milliseconds(450))
            logs = demo.logs(level: logLevel, hours: logHours)
            return
        }
        guard let api else { return }
        do {
            let r: LogResponse = try await api.get("api/logs", query: [
                URLQueryItem(name: "hours", value: String(logHours)),
                URLQueryItem(name: "level", value: logLevel),
            ])
            logs = r
        } catch {
            fail(error)
        }
    }

    /// Journal d'un seul service (fiche détaillée). nil = échec.
    func fetchLogs(unit: String) async -> [LogEntry]? {
        if isDemo {
            try? await Task.sleep(for: .milliseconds(350))
            return demo.logs(level: "all", hours: 48).entries.filter { $0.unit == unit }
        }
        guard let api else { return nil }
        let r: LogResponse? = try? await api.get("api/logs", query: [
            URLQueryItem(name: "hours", value: "48"),
            URLQueryItem(name: "level", value: "all"),
            URLQueryItem(name: "unit", value: unit),
        ])
        return r?.entries
    }

    /// Redémarre un service. Renvoie un message d'erreur, ou nil si tout va bien.
    func restart(_ service: Service) async -> String? {
        if isDemo {
            try? await Task.sleep(for: .seconds(1.4))
            demo.markRestarted(service.name)
            services = demo.services()
            return nil
        }
        guard let api else { return APIError.badURL.errorDescription }
        do {
            try await api.post("api/services/\(service.name)/restart")
            try? await Task.sleep(for: .seconds(1))
            await refreshServices()
            return nil
        } catch {
            return Store.describe(error)
        }
    }

    private func fail(_ error: Error) {
        errorMessage = Store.describe(error)
        link = .offline
    }

    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
