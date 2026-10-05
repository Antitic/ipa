import Foundation

/// Données fictives (calquées sur le vrai Homelab) pour voir l'interface vivre
/// sans connexion, ou tant qu'aucun jeton n'est saisi.
final class DemoGenerator {
    private let boot = Date().addingTimeInterval(-669_354)
    private var restarted: [String: Date] = [:]

    private func wave(_ period: Double, _ phase: Double = 0) -> Double {
        sin(Date().timeIntervalSince1970 / period * 2 * .pi + phase)
    }

    private func jitter(_ amount: Double) -> Double { Double.random(in: -amount...amount) }

    func overview() -> Overview {
        let cpu = min(max(22 + 14 * wave(40) + 8 * wave(7, 1) + jitter(4), 3), 97)
        let cores = (0..<4).map { i in min(max(cpu + 18 * wave(9 + Double(i) * 3, Double(i)) + jitter(6), 1), 100) }
        let total = 3_993_358_336
        let memPct = 58 + 4 * wave(120) + jitter(0.6)
        let used = Int(Double(total) * memPct / 100)
        let rx = Int(max(60_000 + 900_000 * max(wave(25), 0) + jitter(30_000), 2_000))
        let tx = Int(max(200_000 + 2_400_000 * max(wave(31, 2), 0) + jitter(80_000), 5_000))
        let vpnFixed = restarted["vpn-fastest-exit"] != nil
        let running = vpnFixed ? 43 : 42
        return Overview(
            hostname: "Homelab",
            os: "Debian GNU/Linux 13 (trixie)",
            kernel: "6.12.74+deb13+1-amd64",
            agentVersion: "démo",
            time: Int(Date().timeIntervalSince1970),
            uptime: Int(Date().timeIntervalSince(boot)),
            cpu: CPUInfo(percent: cpu, cores: cores, count: 4,
                         load: [0.8 + cpu / 60, 0.88 + cpu / 90, 1.14], frequency: 1600 + 600 * max(wave(13), 0)),
            memory: MemoryInfo(total: total, used: used, available: total - used, cached: 1_873_747_968, percent: memPct),
            swap: SwapInfo(total: 4_174_376_960, used: 1_364_168_704, percent: 32.7),
            disks: [DiskInfo(mount: "/", device: "/dev/sda1", fs: "ext4", total: 979_241_365_504,
                             used: 824_820_719_616, free: 104_602_488_832, percent: 88.7)],
            diskIO: DiskIO(read: Int(max(2_000_000 * wave(17), 0)), write: Int(max(600_000 * wave(23, 1), 0))),
            network: NetworkInfo(rx: rx, tx: tx, addresses: [
                NetAddress(iface: "enp3s0f1", ip: "192.168.1.120"),
                NetAddress(iface: "wlp2s0", ip: "192.168.1.176"),
                NetAddress(iface: "tailscale0", ip: "100.100.226.91"),
            ]),
            temperature: 47 + 6 * wave(50) + jitter(0.5),
            sensors: [],
            fans: [FanInfo(label: "cpu_fan", rpm: cpu > 40 ? 2100 : 0)],
            battery: BatteryInfo(percent: 0, plugged: true),
            processes: 312,
            topCPU: [
                ProcessInfoItem(pid: 855, name: "qbittorrent-nox", user: "antistic", cpu: cpu * 0.6, memory: 663_556_096),
                ProcessInfoItem(pid: 1026, name: "jellyfin", user: "jellyfin", cpu: cpu * 0.3, memory: 330_772_480),
                ProcessInfoItem(pid: 880, name: "cross-seed", user: "antistic", cpu: 4.1, memory: 149_446_656),
                ProcessInfoItem(pid: 1031, name: "node", user: "antistic", cpu: 2.3, memory: 138_432_512),
                ProcessInfoItem(pid: 875, name: "tailscaled", user: "root", cpu: 1.2, memory: 101_376_000),
            ],
            topMemory: [
                ProcessInfoItem(pid: 855, name: "qbittorrent-nox", user: "antistic", cpu: nil, memory: 663_556_096),
                ProcessInfoItem(pid: 1026, name: "jellyfin", user: "jellyfin", cpu: nil, memory: 330_772_480),
                ProcessInfoItem(pid: 74227, name: "claude", user: "antistic", cpu: nil, memory: 284_196_864),
                ProcessInfoItem(pid: 1437, name: "python3", user: "antistic", cpu: nil, memory: 175_529_984),
                ProcessInfoItem(pid: 880, name: "cross-seed", user: "antistic", cpu: nil, memory: 149_446_656),
            ],
            services: ServiceCounts(total: 48, running: running, failed: vpnFixed ? 0 : 1),
            alerts: AlertCounts(errors: 64, warnings: 59)
        )
    }

    func history() -> [HistoryPoint] {
        let now = Int(Date().timeIntervalSince1970)
        return (0..<240).map { i in
            let t = now - (239 - i) * 15
            let x = Double(t)
            let cpu = 22 + 14 * sin(x / 600) + 9 * sin(x / 97) + Double.random(in: -3...3)
            let mem = 57 + 3 * sin(x / 1400) + Double.random(in: -0.4...0.4)
            let rx = Int(max(80_000 + 700_000 * sin(x / 300), 1_000))
            let tx = Int(max(300_000 + 1_800_000 * sin(x / 420 + 1), 2_000))
            let temp = 47 + 5 * sin(x / 800) + Double.random(in: -0.3...0.3)
            return HistoryPoint(t: t, cpu: max(cpu, 2), mem: mem, rx: rx, tx: tx, temp: temp)
        }
    }

    // (nom, titre, sous-titre, catégorie, ports, mémoire, état)
    private let catalog: [(String, String, String, String, [Int], Int?, String)] = [
        ("vpn-fastest-exit", "Épingle la sortie Tor", "la plus rapide hors UE pour vpn.dipherant.xyz", "reseau", [], nil, "failed"),
        ("dipherant-landing", "Dipherant landing page", "Node/Express", "web", [8100], 36_409_344, "running"),
        ("kloz", "Kloz", "la vitrine des vêtements (kloz.dipherant.xyz)", "web", [8250], 42_225_664, "running"),
        ("kru", "Kru", "la réponse sans détour — chat.dipherant.xyz", "web", [8200], 8_986_624, "running"),
        ("lyst", "lyst", "listes partagées (list.dipherant.xyz)", "web", [8340], 11_898_880, "running"),
        ("calendrier-dipherant", "Calendrier Dipherant", "agenda, tâches et flux .ics", "web", [8320], 18_014_208, "running"),
        ("searxng", "SearXNG", "métamoteur natif", "web", [8105], 62_177_280, "running"),
        ("brandix", "Brandix", "revue de stratégie marketing par IA", "web", [8130], 11_296_768, "running"),
        ("boucan-menu", "BOUCAN", "menu street food (Node/Express)", "web", [8140], 9_400_320, "running"),
        ("kontakt", "Kontakt", "messagerie WhatsApp + fiches contacts", "web", [8160], 12_570_624, "running"),
        ("storia", "Storia", "réviser les synthèses d'histoire ESABAC", "web", [8330], 13_860_864, "running"),
        ("pin", "Pin", "un iPod pour l'écosystème dipherant", "web", [8210], 8_007_680, "running"),
        ("phriend", "Phriend", "un compagnon-créature", "web", [8240], 6_144_000, "running"),
        ("shell-terminal", "Dipherant web shell", "shell.dipherant.xyz", "web", [8110], 10_231_808, "running"),
        ("apache2", "The Apache HTTP Server", "", "web", [80], 30_367_744, "running"),
        ("jellyfin", "Jellyfin Media Server", "", "media", [8090], 330_772_480, "running"),
        ("qbittorrent-nox", "qBittorrent-nox", "", "media", [8080, 63790], 1_072_889_856, "running"),
        ("prowlarr", "Prowlarr", "", "media", [9696], 156_319_744, "running"),
        ("cross-seed", "cross-seed daemon", "", "media", [2468], 149_446_656, "running"),
        ("stream-dipherant", "Strym", "films (torrent éphémère) + TV en direct", "media", [8280], 138_432_512, "running"),
        ("dl-dipherant", "Cabine", "recherche de films et envoi vers qBittorrent", "media", [8150], 25_214_976, "running"),
        ("cam-dipherant", "Caméras", "cam.dipherant.xyz", "media", [8310], 5_804_032, "running"),
        ("films-dipherant", "TLU Studios", "Grande Première site", "media", [], nil, "stopped"),
        ("tailscaled", "Tailscale node agent", "", "reseau", [41980], 101_376_000, "running"),
        ("cloudflared", "cloudflared", "", "reseau", [20241], 26_681_344, "running"),
        ("v2ray", "V2Ray Service", "", "reseau", [8230], 11_321_344, "running"),
        ("kru-tor", "Tor dédié à Kru", "sortie et rotation d'identité", "reseau", [9250, 9251], 1_908_736, "running"),
        ("ssh", "OpenBSD Secure Shell server", "", "reseau", [22], 696_320, "running"),
        ("maddy", "maddy mail server", "", "mail", [143, 465, 587, 993], 22_958_080, "running"),
        ("dipherant-mail", "Dipherant webmail", "interface + pont vers maddy", "mail", [8120], 6_184_960, "running"),
        ("valkey-server", "Advanced key-value store", "", "donnees", [6379], 3_395_584, "running"),
        ("bot", "homelab-shell", "serveur MCP (bot.dipherant.xyz)", "bot", [8350], 175_529_984, "running"),
        ("crise-homelab", "Console de crise Homelab", "crise.dipherant.xyz", "bot", [8170], 8_609_792, "running"),
        ("mlab-agent", "Mlab Agent", "l'API de supervision pour l'app iPhone", "systeme", [8787], 17_596_416, "running"),
        ("cron", "Regular background program processing daemon", "", "systeme", [], 1_568_768, "running"),
        ("qos", "QoS Network", "Priorité web sur qBittorrent", "systeme", [], nil, "done"),
    ]

    func markRestarted(_ name: String) { restarted[name] = Date() }

    func services() -> [Service] {
        let order = ["failed": 0, "starting": 1, "running": 2, "done": 3, "stopped": 4]
        let list = catalog.map { item -> Service in
            let (name, title, subtitle, cat, ports, mem, baseState) = item
            let restartedAt = restarted[name]
            let state = restartedAt != nil ? "running" : baseState
            let uptime: Int? = state == "running"
                ? Int(Date().timeIntervalSince(restartedAt ?? boot.addingTimeInterval(Double(abs(name.hashValue % 90_000)))))
                : nil
            return Service(
                id: name + ".service", name: name, title: title, subtitle: subtitle,
                description: subtitle.isEmpty ? title : "\(title) — \(subtitle)",
                state: state, activeState: state == "running" ? "active" : (state == "failed" ? "failed" : "inactive"),
                subState: state == "running" ? "running" : (state == "failed" ? "failed" : "dead"),
                enabled: true, uptime: uptime,
                memory: state == "running" ? (mem ?? 4_000_000) : nil,
                memoryMax: name == "kloz" ? 209_715_200 : nil,
                cpuSeconds: state == "running" ? Double(abs(name.hashValue % 4000)) : nil,
                restarts: name == "vpn-fastest-exit" ? 24 : 0,
                pid: state == "running" ? 800 + abs(name.hashValue % 9000) : nil,
                ports: ports, category: cat, custom: true,
                canRestart: !["tailscaled", "ssh", "mlab-agent"].contains(name)
            )
        }
        return list.sorted { (order[$0.state] ?? 9, $0.title.lowercased()) < (order[$1.state] ?? 9, $1.title.lowercased()) }
    }

    func logs(level: String, hours: Int) -> LogResponse {
        let now = Int(Date().timeIntervalSince1970)
        // (minutes écoulées, unité, titre, niveau, message, occurrences)
        let raw: [(Int, String, String, String, String, Int)] = [
            (2, "vpn-fastest-exit", "Épingle la sortie Tor", "error", "Échec : le programme s'est arrêté en erreur", 24),
            (2, "vpn-fastest-exit", "Épingle la sortie Tor", "error", "N'a pas réussi à démarrer", 24),
            (4, "kloz", "Kloz", "info", "catalogue relu (minuterie) — 6 pièce(s), 2 collection(s)", 6),
            (9, "ssh", "SSH", "info", "Connexion SSH de antistic depuis 100.64.12.4", 1),
            (14, "mail-natpmp-renew", "Renouvellement NAT-PMP", "warning", "Config bizarre dans mail-natpmp-renew.service (ligne 5) : « After » ignoré", 12),
            (18, "stream-dipherant", "Strym", "info", "[iptv] test : 187/252 chaînes visibles (252 sondées)", 2),
            (26, "dl-dipherant", "Cabine", "warning", "[robot] passe en échec : Prowlarr 429", 1),
            (33, "cross-seed", "cross-seed daemon", "info", "[rss] RSS scan complete - checked 42 new candidates", 1),
            (41, "ssh", "SSH", "warning", "Utilisateur SSH inconnu « admin » depuis 45.148.10.7", 7),
            (55, "fwupd", "fwupd", "error", "FuEngine failed to add device /sys/devices/pci0000:00/ata2", 2),
            (63, "mlab-agent", "Mlab Agent", "info", "Démarré", 1),
            (95, "jellyfin", "Jellyfin Media Server", "info", "Bibliothèque Films analysée : 3 nouveaux éléments", 1),
            (140, "kernel", "Noyau", "warning", "Le processeur chauffe trop", 1),
            (220, "qbittorrent-nox", "qBittorrent-nox", "info", "Torrent terminé : 2 fichiers", 3),
            (310, "plexmediaserver", "plexmediaserver", "info", "Arrêté", 1),
            (420, "anacron", "anacron", "info", "Normal exit (0 jobs run)", 1),
            (700, "bot", "homelab-shell", "error", "antistic : a password is required ; COMMAND=/usr/bin/true", 1),
            (1300, "phpsessionclean", "phpsessionclean", "info", "S'est terminé proprement", 1),
        ]
        let rank = ["error": 0, "warning": 1, "info": 2]
        let maxRank = level == "error" ? 0 : (level == "warning" ? 1 : 2)
        let entries = raw.enumerated().compactMap { pair -> LogEntry? in
            let (i, e) = pair
            guard e.0 * 60 <= hours * 3600, (rank[e.3] ?? 2) <= maxRank else { return nil }
            let t = now - e.0 * 60
            return LogEntry(id: "demo-\(i)", time: t, firstTime: t - e.5 * 300, unit: e.1, title: e.2,
                            level: e.3, message: e.4, raw: e.4, count: e.5)
        }
        var counts = ["error": 0, "warning": 0, "info": 0]
        for e in entries { counts[e.level, default: 0] += e.count }
        return LogResponse(hours: hours, counts: counts, entries: entries)
    }
}
