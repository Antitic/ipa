import Foundation

// Miroir exact du JSON renvoyé par mlab-agent (agent/mlab_agent.py).

struct Overview: Codable, Equatable {
    var hostname: String
    var os: String
    var kernel: String
    var agentVersion: String
    var time: Int
    var uptime: Int
    var cpu: CPUInfo
    var memory: MemoryInfo
    var swap: SwapInfo
    var disks: [DiskInfo]
    var diskIO: DiskIO
    var network: NetworkInfo
    var temperature: Double?
    var sensors: [SensorInfo]
    var fans: [FanInfo]
    var battery: BatteryInfo?
    var processes: Int
    var topCPU: [ProcessInfoItem]
    var topMemory: [ProcessInfoItem]
    var services: ServiceCounts
    var alerts: AlertCounts
}

struct CPUInfo: Codable, Equatable {
    var percent: Double
    var cores: [Double]
    var count: Int?
    var load: [Double]
    var frequency: Double?
}

struct MemoryInfo: Codable, Equatable {
    var total: Int
    var used: Int
    var available: Int
    var cached: Int
    var percent: Double
}

struct SwapInfo: Codable, Equatable {
    var total: Int
    var used: Int
    var percent: Double
}

struct DiskInfo: Codable, Equatable, Identifiable {
    var mount: String
    var device: String
    var fs: String
    var total: Int
    var used: Int
    var free: Int
    var percent: Double
    var id: String { mount }
}

struct DiskIO: Codable, Equatable {
    var read: Int
    var write: Int
}

struct NetworkInfo: Codable, Equatable {
    var rx: Int
    var tx: Int
    var addresses: [NetAddress]
}

struct NetAddress: Codable, Equatable, Identifiable {
    var iface: String
    var ip: String
    var id: String { iface + ip }
}

struct SensorInfo: Codable, Equatable {
    var chip: String
    var label: String
    var current: Double
    var high: Double?
    var critical: Double?
}

struct FanInfo: Codable, Equatable {
    var label: String
    var rpm: Double
}

struct BatteryInfo: Codable, Equatable {
    var percent: Double
    var plugged: Bool
}

struct ProcessInfoItem: Codable, Equatable, Identifiable {
    var pid: Int
    var name: String
    var user: String?
    var cpu: Double?
    var memory: Int
    var id: Int { pid }
}

struct ServiceCounts: Codable, Equatable {
    var total: Int
    var running: Int
    var failed: Int
}

struct AlertCounts: Codable, Equatable {
    var errors: Int
    var warnings: Int
}

struct HistoryResponse: Codable {
    var points: [HistoryPoint]
}

struct HistoryPoint: Codable, Equatable {
    var t: Int
    var cpu: Double
    var mem: Double
    var rx: Int
    var tx: Int
    var temp: Double?
}

struct ServicesResponse: Codable {
    var services: [Service]
}

struct Service: Codable, Equatable, Identifiable, Hashable {
    var id: String
    var name: String
    var title: String
    var subtitle: String
    var description: String
    var state: String          // running | done | failed | starting | stopped
    var activeState: String
    var subState: String
    var enabled: Bool
    var uptime: Int?
    var memory: Int?
    var memoryMax: Int?
    var cpuSeconds: Double?
    var restarts: Int
    var pid: Int?
    var ports: [Int]
    var category: String       // web | media | reseau | mail | donnees | bot | systeme
    var custom: Bool
    var canRestart: Bool
}

struct LogResponse: Codable, Equatable {
    var hours: Int
    var counts: [String: Int]
    var entries: [LogEntry]
}

struct LogEntry: Codable, Equatable, Identifiable {
    var id: String
    var time: Int
    var firstTime: Int
    var unit: String
    var title: String
    var level: String          // error | warning | info
    var message: String
    var raw: String
    var count: Int
}

struct PingResponse: Codable {
    var ok: Bool
    var hostname: String
    var version: String
}

struct OKResponse: Codable {
    var ok: Bool
}

struct ErrorResponse: Codable {
    var error: String
}

// MARK: - Petites aides de lecture

extension Service {
    var isRunning: Bool { state == "running" }
    var isFailed: Bool { state == "failed" }

    var categoryLabel: String {
        switch category {
        case "web": return "Web"
        case "media": return "Média"
        case "reseau": return "Réseau"
        case "mail": return "Courrier"
        case "donnees": return "Données"
        case "bot": return "Bots"
        default: return "Système"
        }
    }

    var stateLabel: String {
        switch state {
        case "running": return "En service"
        case "done": return "Terminé"
        case "failed": return "En panne"
        case "starting": return "Démarrage"
        default: return "À l'arrêt"
        }
    }
}

extension Overview {
    var mainDisk: DiskInfo? { disks.first { $0.mount == "/" } ?? disks.first }
    var tailscaleIP: String? { network.addresses.first { $0.iface.hasPrefix("tailscale") }?.ip }
    var lanIPs: [NetAddress] { network.addresses.filter { !$0.iface.hasPrefix("tailscale") } }
    var shortOS: String {
        // "Debian GNU/Linux 13 (trixie)" → "Debian 13"
        let parts = os.replacingOccurrences(of: "GNU/Linux ", with: "").components(separatedBy: " (")
        return parts.first ?? os
    }
}
