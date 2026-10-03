import Foundation

/// Compte les octets reçus et envoyés par plusieurs requêtes en parallèle.
/// Appelé depuis la file du `URLSession`, lu depuis le fil principal.
private final class ByteCounter: NSObject, URLSessionDataDelegate {
    private let lock = NSLock()
    private var received: Int64 = 0
    private var sent: Int64 = 0
    private var sentPerTask: [Int: Int64] = [:]

    var totals: (received: Int64, sent: Int64) {
        lock.lock(); defer { lock.unlock() }
        return (received, sent)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock(); received += Int64(data.count); lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        lock.lock()
        let previous = sentPerTask[task.taskIdentifier] ?? 0
        sentPerTask[task.taskIdentifier] = totalBytesSent
        sent += totalBytesSent - previous
        lock.unlock()
    }
}

struct SpeedSample: Identifiable {
    let id = UUID()
    let time: Double      // secondes depuis le début de la phase
    let mbps: Double
}

/// Test de débit mesuré en continu (5 fois par seconde) vers Cloudflare.
@MainActor
final class SpeedTest: ObservableObject {
    enum Phase: String {
        case idle = "Prêt"
        case latency = "Latence"
        case download = "Réception"
        case upload = "Envoi"
        case done = "Terminé"
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var live: Double = 0                 // Mb/s instantané
    @Published private(set) var phaseProgress: Double = 0        // 0…1
    @Published private(set) var downloadSamples: [SpeedSample] = []
    @Published private(set) var uploadSamples: [SpeedSample] = []
    @Published private(set) var download: Double?
    @Published private(set) var upload: Double?
    @Published private(set) var pings: [Double] = []
    @Published private(set) var dataUsed: Int64 = 0
    @Published private(set) var error: String?

    var running: Bool { phase == .latency || phase == .download || phase == .upload }

    var latency: Double? {
        guard !pings.isEmpty else { return nil }
        return pings.sorted()[pings.count / 2]
    }

    var jitter: Double? {
        guard pings.count > 1 else { return nil }
        var sum = 0.0
        for i in 1..<pings.count { sum += abs(pings[i] - pings[i - 1]) }
        return sum / Double(pings.count - 1)
    }

    private var task: Task<Void, Never>?
    private let phaseDuration: Double = 10
    private let maxBytesPerPhase: Int64 = 250_000_000
    private let streams = 4

    func start() {
        guard !running else { return }
        task?.cancel()
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
    }

    private func run() async {
        error = nil
        download = nil
        upload = nil
        pings = []
        downloadSamples = []
        uploadSamples = []
        dataUsed = 0
        live = 0

        // 1. Latence : petites requêtes HTTP successives vers Cloudflare.
        //    (Le probe TCP brut vers 1.1.1.1 est bloqué pour les apps installées par sideload.)
        phase = .latency
        let pingConfig = URLSessionConfiguration.ephemeral
        pingConfig.timeoutIntervalForRequest = 3
        pingConfig.requestCachePolicy = .reloadIgnoringLocalCacheData
        let pingSession = URLSession(configuration: pingConfig)
        var pingURL = URLComponents(string: "https://speed.cloudflare.com/__down")!
        pingURL.queryItems = [URLQueryItem(name: "bytes", value: "0")]
        for i in 0..<10 {
            if Task.isCancelled { break }
            var req = URLRequest(url: pingURL.url!)
            req.httpMethod = "GET"
            let start = Date()
            if (try? await pingSession.data(for: req)) != nil {
                pings.append(Date().timeIntervalSince(start) * 1000)
            }
            phaseProgress = Double(i + 1) / 10
        }
        pingSession.invalidateAndCancel()

        // 2. Réception puis 3. envoi, chacun pendant 10 s maximum.
        //    On continue même si la latence a échoué : ces phases disent si Internet répond.
        if !Task.isCancelled {
            download = await measure(.download)
        }
        if !Task.isCancelled {
            upload = await measure(.upload)
        }
        if download == nil && upload == nil && !Task.isCancelled {
            error = "Serveur de test injoignable. Vérifie ta connexion Internet."
        }
        finish()
    }

    private func finish() {
        phase = .done
        live = 0
        phaseProgress = 1
    }

    private func measure(_ kind: Phase) async -> Double? {
        phase = kind
        phaseProgress = 0
        live = 0

        let counter = ByteCounter()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = streams
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: counter, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var tasks: [URLSessionTask] = []
        for _ in 0..<streams {
            if kind == .download {
                let url = URL(string: "https://speed.cloudflare.com/__down?bytes=100000000")!
                tasks.append(session.dataTask(with: url))
            } else {
                var req = URLRequest(url: URL(string: "https://speed.cloudflare.com/__up")!)
                req.httpMethod = "POST"
                req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
                tasks.append(session.uploadTask(with: req, from: Data(count: 50_000_000)))
            }
        }
        tasks.forEach { $0.resume() }

        let start = Date()
        var lastTime = 0.0
        var lastBytes: Int64 = 0
        var smoothed = 0.0
        var samples: [SpeedSample] = []
        let baseUsage = dataUsed

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 200_000_000)
            let t = Date().timeIntervalSince(start)
            let totals = counter.totals
            let bytes = kind == .download ? totals.received : totals.sent
            let dt = t - lastTime
            if dt > 0 {
                let instant = Double(bytes - lastBytes) * 8 / dt / 1_000_000
                smoothed = smoothed == 0 ? instant : smoothed * 0.6 + instant * 0.4
                lastTime = t
                lastBytes = bytes
                samples.append(SpeedSample(time: t, mbps: smoothed))
                live = smoothed
                if kind == .download { downloadSamples = samples } else { uploadSamples = samples }
                dataUsed = baseUsage + bytes
                phaseProgress = min(1, t / phaseDuration)
            }
            let allDone = tasks.allSatisfy { $0.state == .completed }
            if t >= phaseDuration || bytes >= maxBytesPerPhase || allDone { break }
        }
        tasks.forEach { $0.cancel() }

        // Débit retenu : moyenne en ignorant la première seconde (montée en charge TCP).
        let steady = samples.filter { $0.time > 1 }
        let values = (steady.isEmpty ? samples : steady).map(\.mbps)
        guard !values.isEmpty, lastBytes > 0 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
