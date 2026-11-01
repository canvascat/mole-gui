import Foundation

struct StatusReport: Decodable, Equatable {
    var collectedAt: String?
    var host: String?
    var uptime: String?
    var healthScore: Int?
    var healthScoreMessage: String?
    var cpu: CPUStatus?
    var memory: MemoryStatus?
    var disks: [DiskStatus]
    var topProcesses: [ProcessRow]
    var processStale: Bool?
    var zombieCount: Int?
    var zombieParents: [ZombieParent]
    var processAlerts: [ProcessAlert]
    var hardware: HardwareInfo?
    var procs: Int?
    var uptimeSeconds: Int?
    var gpu: [GPUStatus]
    var diskIO: DiskIO?
    var network: [NetworkIface]
    var networkHistory: NetworkHistory?
    var thermal: Thermal?

    struct CPUStatus: Decodable, Equatable {
        var usage: Double?
        var perCore: [Double]?
        var load1: Double?
        var load5: Double?
        var load15: Double?
        var coreCount: Int?
        var logicalCPU: Int?
        var pCoreCount: Int?
        var eCoreCount: Int?
    }

    struct GPUStatus: Decodable, Equatable, Identifiable {
        var name: String?
        var usage: Double?
        var coreCount: Int?
        var id: String { name ?? "gpu" }
    }

    struct DiskIO: Decodable, Equatable {
        var readRate: Double?
        var writeRate: Double?
    }

    struct NetworkIface: Decodable, Equatable, Identifiable {
        var name: String?
        var rxRateMBs: Double?
        var txRateMBs: Double?
        var ip: String?
        var id: String { name ?? ip ?? "net" }
    }

    struct NetworkHistory: Decodable, Equatable {
        var rxHistory: [Double]
        var txHistory: [Double]
    }

    struct Thermal: Decodable, Equatable {
        var cpuTemp: Double?
        var gpuTemp: Double?
    }

    struct MemoryStatus: Decodable, Equatable {
        var used: UInt64?
        var total: UInt64?
        var usedPercent: Double?
        var pressure: String?
        var swapUsed: UInt64?
        var swapTotal: UInt64?
    }

    struct DiskStatus: Decodable, Equatable, Identifiable {
        var mount: String?
        var used: UInt64?
        var total: UInt64?
        var usedPercent: Double?
        var external: Bool?
        var smartStatus: String?
        var fstype: String?
        var id: String { (mount ?? "") + "|" + (fstype ?? "") + "|" + String(total ?? 0) }
    }

    struct ProcessRow: Decodable, Equatable, Identifiable {
        var pid: Int?
        var name: String?
        var command: String?
        var cpu: Double?
        var memoryBytes: UInt64?
        var id: String { "\(pid ?? -1)-\(name ?? "")" }
    }

    struct ZombieParent: Decodable, Equatable, Identifiable {
        var pid: Int?
        var name: String?
        var count: Int?
        var id: String { "\(pid ?? -1)-\(name ?? "")" }
    }

    struct ProcessAlert: Decodable, Equatable, Identifiable {
        var pid: Int?
        var name: String?
        var cpu: Double?
        var status: String?
        var id: String { "\(pid ?? -1)-\(name ?? "")" }
    }

    struct HardwareInfo: Decodable, Equatable {
        var model: String?
        var cpuModel: String?
        var totalRAM: String?
        var osVersion: String?
    }

    static func parse(_ text: String) -> StatusReport? {
        guard let data = JSONExtract.objectData(text) else { return nil }
        return try? JSONDecoder().decode(StatusReport.self, from: data)
    }
}

struct AnalyzeReport: Decodable, Equatable {
    var scanStatus: String?
    var path: String?
    var overview: Bool?
    var entries: [Entry]
    var largeFiles: [FileEntry]
    var totalSize: Int64?
    var totalFiles: Int64?

    struct Entry: Decodable, Equatable, Identifiable {
        var scanStatus: String?
        var name: String?
        var path: String?
        var size: Int64?
        var isDir: Bool?
        var id: String { (path ?? "") + "\n" + (name ?? "") }
    }

    struct FileEntry: Decodable, Equatable, Identifiable {
        var name: String?
        var path: String?
        var size: Int64?
        var id: String { path ?? name ?? "" }
    }

    static func parse(_ text: String) -> AnalyzeReport? {
        guard let data = JSONExtract.objectData(text) else { return nil }
        return try? JSONDecoder().decode(AnalyzeReport.self, from: data)
    }
}

struct UninstallApp: Decodable, Equatable, Identifiable {
    var name: String
    var bundleId: String
    var source: String
    var uninstallName: String
    var path: String
    var size: String
    var id: String { path + "\n" + uninstallName }

    /// 传给 `mo uninstall` 的名字。mo 只按显示名和 .app 目录名匹配，
    /// 而 Homebrew cask 的 uninstall_name 是 cask 名（如 mole-app），传过去会找不到应用。
    var launchName: String {
        let directory = URL(fileURLWithPath: path).lastPathComponent
        if directory.lowercased().hasSuffix(".app") {
            let base = String(directory.dropLast(4))
            if !base.isEmpty { return base }
        }
        return name.isEmpty ? uninstallName : name
    }

    static func parse(_ text: String) -> [UninstallApp]? {
        guard let data = JSONExtract.arrayData(text) else { return nil }
        return try? JSONDecoder().decode([UninstallApp].self, from: data)
    }
}

struct HistoryReport: Decodable, Equatable {
    var limit: Int?
    var sessions: [Session]
    var deletions: [Deletion]

    struct Session: Decodable, Equatable, Identifiable {
        var command: String?
        var runId: String?
        var attribution: String?
        var startedAt: String?
        var endedAt: String?
        var items: Int?
        var size: String?
        var operationCount: Int?
        var failedTasks: Int?
        var actions: Actions?
        var id: String { (runId ?? "") + "|" + (startedAt ?? "") + "|" + (command ?? "") }
    }

    struct Actions: Decodable, Equatable {
        var removed: Int?
        var trashed: Int?
        var skipped: Int?
        var failed: Int?
        var rebuilt: Int?
        var other: Int?
    }

    struct Deletion: Decodable, Equatable, Identifiable {
        var timestamp: String?
        var mode: String?
        var status: String?
        var sizeKb: Int?
        var path: String?
        var id: String { (timestamp ?? "") + "|" + (path ?? "") }
    }

    static func parse(_ text: String) -> HistoryReport? {
        guard let data = JSONExtract.objectData(text) else { return nil }
        return try? JSONDecoder().decode(HistoryReport.self, from: data)
    }
}

enum JSONExtract {
    static func objectData(_ text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        return Data(text[start...end].utf8)
    }

    static func arrayData(_ text: String) -> Data? {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]") else { return nil }
        return Data(text[start...end].utf8)
    }
}

extension StatusReport {
    enum CodingKeys: String, CodingKey {
        case collectedAt = "collected_at"
        case host
        case uptime
        case healthScore = "health_score"
        case healthScoreMessage = "health_score_msg"
        case cpu, memory, disks
        case topProcesses = "top_processes"
        case processStale = "process_stale"
        case zombieCount = "zombie_count"
        case zombieParents = "zombie_parents"
        case processAlerts = "process_alerts"
        case hardware, procs
        case uptimeSeconds = "uptime_seconds"
        case gpu
        case diskIO = "disk_io"
        case network
        case networkHistory = "network_history"
        case thermal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        collectedAt = try container.decodeIfPresent(String.self, forKey: .collectedAt)
        host = try container.decodeIfPresent(String.self, forKey: .host)
        uptime = try container.decodeIfPresent(String.self, forKey: .uptime)
        healthScore = try container.decodeIfPresent(Int.self, forKey: .healthScore)
        healthScoreMessage = try container.decodeIfPresent(String.self, forKey: .healthScoreMessage)
        cpu = try container.decodeIfPresent(CPUStatus.self, forKey: .cpu)
        memory = try container.decodeIfPresent(MemoryStatus.self, forKey: .memory)
        disks = try container.decodeIfPresent([DiskStatus].self, forKey: .disks) ?? []
        topProcesses = try container.decodeIfPresent([ProcessRow].self, forKey: .topProcesses) ?? []
        processStale = try container.decodeIfPresent(Bool.self, forKey: .processStale)
        zombieCount = try container.decodeIfPresent(Int.self, forKey: .zombieCount)
        zombieParents = try container.decodeIfPresent([ZombieParent].self, forKey: .zombieParents) ?? []
        processAlerts = try container.decodeIfPresent([ProcessAlert].self, forKey: .processAlerts) ?? []
        hardware = try container.decodeIfPresent(HardwareInfo.self, forKey: .hardware)
        procs = try container.decodeIfPresent(Int.self, forKey: .procs)
        uptimeSeconds = try container.decodeIfPresent(Int.self, forKey: .uptimeSeconds)
        gpu = try container.decodeIfPresent([GPUStatus].self, forKey: .gpu) ?? []
        diskIO = try container.decodeIfPresent(DiskIO.self, forKey: .diskIO)
        network = try container.decodeIfPresent([NetworkIface].self, forKey: .network) ?? []
        networkHistory = try container.decodeIfPresent(NetworkHistory.self, forKey: .networkHistory)
        thermal = try container.decodeIfPresent(Thermal.self, forKey: .thermal)
    }
}

extension StatusReport.CPUStatus {
    enum CodingKeys: String, CodingKey {
        case usage, load1, load5, load15
        case perCore = "per_core"
        case coreCount = "core_count"
        case logicalCPU = "logical_cpu"
        case pCoreCount = "p_core_count"
        case eCoreCount = "e_core_count"
    }
}

extension StatusReport.GPUStatus {
    enum CodingKeys: String, CodingKey {
        case name, usage
        case coreCount = "core_count"
    }
}

extension StatusReport.DiskIO {
    enum CodingKeys: String, CodingKey {
        case readRate = "read_rate"
        case writeRate = "write_rate"
    }
}

extension StatusReport.NetworkIface {
    enum CodingKeys: String, CodingKey {
        case name, ip
        case rxRateMBs = "rx_rate_mbs"
        case txRateMBs = "tx_rate_mbs"
    }
}

extension StatusReport.NetworkHistory {
    enum CodingKeys: String, CodingKey {
        case rxHistory = "rx_history"
        case txHistory = "tx_history"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rxHistory = try container.decodeIfPresent([Double].self, forKey: .rxHistory) ?? []
        txHistory = try container.decodeIfPresent([Double].self, forKey: .txHistory) ?? []
    }
}

extension StatusReport.MemoryStatus {
    enum CodingKeys: String, CodingKey {
        case used, total, pressure
        case usedPercent = "used_percent"
        case swapUsed = "swap_used"
        case swapTotal = "swap_total"
    }
}

extension StatusReport.DiskStatus {
    enum CodingKeys: String, CodingKey {
        case mount, used, total, external, fstype
        case usedPercent = "used_percent"
        case smartStatus = "smart_status"
    }
}

extension StatusReport.ProcessRow {
    enum CodingKeys: String, CodingKey {
        case pid, name, command, cpu
        case memoryBytes = "memory_bytes"
    }
}

extension StatusReport.Thermal {
    enum CodingKeys: String, CodingKey {
        case cpuTemp = "cpu_temp"
        case gpuTemp = "gpu_temp"
    }
}

extension StatusReport.HardwareInfo {
    enum CodingKeys: String, CodingKey {
        case model
        case cpuModel = "cpu_model"
        case totalRAM = "total_ram"
        case osVersion = "os_version"
    }
}

extension AnalyzeReport {
    enum CodingKeys: String, CodingKey {
        case scanStatus = "scan_status"
        case path, overview, entries
        case largeFiles = "large_files"
        case totalSize = "total_size"
        case totalFiles = "total_files"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scanStatus = try container.decodeIfPresent(String.self, forKey: .scanStatus)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        overview = try container.decodeIfPresent(Bool.self, forKey: .overview)
        entries = try container.decodeIfPresent([Entry].self, forKey: .entries) ?? []
        largeFiles = try container.decodeIfPresent([FileEntry].self, forKey: .largeFiles) ?? []
        totalSize = try container.decodeIfPresent(Int64.self, forKey: .totalSize)
        totalFiles = try container.decodeIfPresent(Int64.self, forKey: .totalFiles)
    }
}

extension AnalyzeReport.Entry {
    enum CodingKeys: String, CodingKey {
        case scanStatus = "scan_status"
        case name, path, size
        case isDir = "is_dir"
    }
}

extension UninstallApp {
    enum CodingKeys: String, CodingKey {
        case name
        case bundleId = "bundle_id"
        case source
        case uninstallName = "uninstall_name"
        case path, size
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId) ?? ""
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? ""
        uninstallName = try container.decodeIfPresent(String.self, forKey: .uninstallName) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        size = try container.decodeIfPresent(String.self, forKey: .size) ?? ""
    }
}

extension HistoryReport {
    enum CodingKeys: String, CodingKey {
        case limit, sessions, deletions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit)
        sessions = try container.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        deletions = try container.decodeIfPresent([Deletion].self, forKey: .deletions) ?? []
    }
}

extension HistoryReport.Session {
    enum CodingKeys: String, CodingKey {
        case command
        case runId = "run_id"
        case attribution
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case items, size
        case operationCount = "operation_count"
        case failedTasks = "failed_tasks"
        case actions
    }
}

extension HistoryReport.Deletion {
    enum CodingKeys: String, CodingKey {
        case timestamp, mode, status, path
        case sizeKb = "size_kb"
    }
}
