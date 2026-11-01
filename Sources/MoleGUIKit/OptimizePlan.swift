import Foundation

enum OptimizeOutcome: String, CaseIterable, Sendable {
    case attention, failed, applied, skipped, unavailable, unchanged, unknown

    fileprivate var rank: Int {
        switch self {
        case .failed: return 6
        case .attention: return 5
        case .applied: return 4
        case .unavailable: return 3
        case .skipped: return 2
        case .unchanged: return 1
        case .unknown: return 0
        }
    }
}

struct OptimizeTask: Equatable, Identifiable, Sendable {
    var title: String
    var lines: [String]
    var outcome: OptimizeOutcome

    var id: String { title }

    var displayTitle: String { OptimizePlan.titles[title] ?? title }
}

struct OptimizeCounts: Equatable, Sendable {
    var applied = 0
    var unchanged = 0
    var skipped = 0
    var unavailable = 0
    var attention = 0
    var failed = 0

    func value(_ outcome: OptimizeOutcome) -> Int {
        switch outcome {
        case .applied: return applied
        case .unchanged: return unchanged
        case .skipped: return skipped
        case .unavailable: return unavailable
        case .attention: return attention
        case .failed: return failed
        case .unknown: return 0
        }
    }
}

struct OptimizeSystem: Equatable, Sendable {
    var ramUsed: Int
    var ramTotal: Int
    var diskUsed: Int
    var diskTotal: Int
    var uptimeDays: Int
}

struct OptimizeReport: Equatable, Sendable {
    var dryRun = false
    var system: OptimizeSystem?
    var diagnosis: [String] = []
    var tasks: [OptimizeTask] = []
    var summary: OptimizeCounts?
    var finished = false
    /// 按文字推断的状态和 mo 汇总的数字对不上时为 true。
    var inferred = false

    func tasks(_ outcome: OptimizeOutcome) -> [OptimizeTask] {
        tasks.filter { $0.outcome == outcome }
    }
}

/// mo optimize 没有结构化输出。每个任务只输出一个标题和几行带图标的文字，
/// 状态（已应用、无需处理、跳过……）要按文字推断，再用结尾的汇总数字对账。
enum OptimizePlan {
    static let titles: [String: String] = [
        "Finder Cache Refresh": "Finder 缓存刷新",
        "App State Cleanup": "App 状态清理",
        "Broken Config Repair": "损坏配置修复",
        "Network Cache Refresh": "网络缓存刷新",
        "Database Optimization": "数据库优化",
        "Prevent Finder .DS_Store": "避免生成 .DS_Store",
        "Legacy Overrides": "旧版覆盖设置",
        "Network Stack Refresh": "网络栈刷新",
        "Permission Repair": "权限修复",
        "Spotlight Optimization": "Spotlight 优化",
        "Spotlight Orphan Rules": "Spotlight 失效规则",
        "Periodic Maintenance": "周期性维护",
        "Shared File Lists": "共享文件列表",
        "Disk Health": "磁盘健康",
        "Login Items": "登录项",
        "Quarantine Database Cleanup": "隔离记录清理",
        "Launch Agents Cleanup": "启动代理检查",
        "Notifications": "通知数据库",
        "Usage Data": "使用数据",
    ]

    private static let taskMarker = "\u{27A4}"

    static func parse(_ raw: String) -> OptimizeReport {
        var buffer = TerminalBuffer()
        buffer.ingest(raw)
        var report = OptimizeReport()
        var current: (title: String, lines: [(icon: Character?, text: String)])?
        var inDiagnosis = false
        var inSummary = false
        var pending: [(title: String, lines: [(icon: Character?, text: String)])] = []

        func flush() {
            if let current { pending.append(current) }
            current = nil
        }

        for line in buffer.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                inDiagnosis = false
                continue
            }
            if trimmed.hasPrefix("===") {
                flush()
                inSummary = true
                inDiagnosis = false
                continue
            }
            if inSummary {
                parseSummaryLine(trimmed, into: &report)
                continue
            }
            if trimmed.localizedCaseInsensitiveContains("DRY RUN MODE") {
                report.dryRun = true
                continue
            }
            if let system = parseSystem(trimmed) {
                report.system = system
                continue
            }
            if trimmed == "Performance diagnosis" {
                flush()
                inDiagnosis = true
                continue
            }
            if trimmed.hasPrefix(taskMarker) {
                flush()
                inDiagnosis = false
                let title = String(trimmed.dropFirst(taskMarker.count)).trimmingCharacters(in: .whitespaces)
                current = (title, [])
                continue
            }
            if inDiagnosis {
                report.diagnosis.append(trimmed)
                continue
            }
            if current != nil {
                let item = splitIcon(trimmed)
                current?.lines.append(item)
            }
        }
        flush()

        report.tasks = pending.map { task in
            OptimizeTask(
                title: task.title,
                lines: task.lines.map(\.text).filter { !$0.isEmpty },
                outcome: classify(task.lines)
            )
        }
        if report.summary != nil { report.finished = true }
        reconcile(&report)
        return report
    }

    static func classify(_ lines: [(icon: Character?, text: String)]) -> OptimizeOutcome {
        var best = OptimizeOutcome.unknown
        var sawUnknown = false
        var sawSignal = false
        for line in lines {
            guard let outcome = classify(icon: line.icon, text: line.text) else { continue }
            sawSignal = true
            if outcome == .unknown {
                sawUnknown = true
            } else if outcome.rank > best.rank {
                best = outcome
            }
        }
        if !sawSignal { return .unknown }
        // 看不出结果的行可能是已应用，也可能是无需处理；没有更确定的应用或异常时不下结论。
        if sawUnknown, best.rank < OptimizeOutcome.applied.rank { return .unknown }
        return best
    }

    static func classify(icon: Character?, text: String) -> OptimizeOutcome? {
        let t = text.lowercased()
        if icon == "\u{2139}" { return nil }
        if t.contains("failed") || t.contains("timed out") || t.contains("could not") || t.contains("time budget") {
            return .failed
        }
        if icon == "\u{25CE}" {
            if t.contains("broken") || t.contains("missing program") || t.contains("disk issues") { return .attention }
            if t.contains("incomplete") || t.contains("unavailable") || t.contains("not available") { return .unavailable }
            if t.contains("skipped") { return .skipped }
            return .attention
        }
        if icon == "-" {
            return t.contains("unavailable") || t.contains("not readable") ? .unavailable : nil
        }
        if icon == "\u{25CB}" { return .skipped }
        if t.contains("not available") || t.contains("unavailable") { return .unavailable }
        if t.contains("skipped") || t.contains("skipping") { return .skipped }
        if t.contains("already") || t.contains(" valid") || t.contains("healthy") || t.hasPrefix("no ")
            || t.contains("not found") || t.contains("verified") || t.contains("current") {
            return .unchanged
        }
        if t.range(of: #"^optimized \d+"#, options: .regularExpression) != nil { return .applied }
        let appliedWords = ["would remove", "refreshed", "rebuilt", "enabled", "removed", "repaired",
                            "cleaned", "cleared", "triggered", "started"]
        if appliedWords.contains(where: { t.contains($0) }) { return .applied }
        return .unknown
    }

    private static func reconcile(_ report: inout OptimizeReport) {
        guard let summary = report.summary else { return }
        let known = Dictionary(grouping: report.tasks, by: \.outcome).mapValues(\.count)
        let unknownIndexes = report.tasks.indices.filter { report.tasks[$0].outcome == .unknown }
        var need: [OptimizeOutcome: Int] = [:]
        var mismatch = false
        let classes: [OptimizeOutcome] = [.applied, .unchanged, .skipped, .unavailable, .attention, .failed]
        for outcome in classes {
            let gap = summary.value(outcome) - (known[outcome] ?? 0)
            if gap < 0 { mismatch = true }
            if gap > 0 { need[outcome] = gap }
        }
        let needed = need.values.reduce(0, +)
        if needed != unknownIndexes.count { mismatch = true }
        if !mismatch, need.count == 1, let only = need.keys.first {
            for index in unknownIndexes { report.tasks[index].outcome = only }
        } else if !unknownIndexes.isEmpty, need.count > 1 {
            mismatch = true
        }
        report.inferred = mismatch
    }

    private static func splitIcon(_ trimmed: String) -> (icon: Character?, text: String) {
        guard let first = trimmed.first else { return (nil, trimmed) }
        let rest = trimmed.dropFirst()
        if !first.isLetter, !first.isNumber, rest.first == " " {
            return (first, rest.trimmingCharacters(in: .whitespaces))
        }
        return (nil, trimmed)
    }

    private static func parseSystem(_ line: String) -> OptimizeSystem? {
        let pattern = #"(\d+)/(\d+) GB RAM \| (\d+)/(\d+) GB Disk \| Uptime (\d+)d"#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        let numbers = line[range].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numbers.count == 5 else { return nil }
        return OptimizeSystem(
            ramUsed: numbers[0],
            ramTotal: numbers[1],
            diskUsed: numbers[2],
            diskTotal: numbers[3],
            uptimeDays: numbers[4]
        )
    }

    private static func parseSummaryLine(_ line: String, into report: inout OptimizeReport) {
        var counts = report.summary ?? OptimizeCounts()
        var touched = false
        if let range = line.range(of: #"(?:Would apply|Applied) (\d+) optimization"#, options: .regularExpression) {
            let digits = line[range].split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
            counts.applied = digits ?? 0
            touched = true
        }
        let pairs: [(String, WritableKeyPath<OptimizeCounts, Int>)] = [
            ("unchanged", \.unchanged),
            ("skipped", \.skipped),
            ("unavailable", \.unavailable),
            ("need attention", \.attention),
            ("failed", \.failed),
        ]
        for (word, keyPath) in pairs {
            guard let range = line.range(of: #"(\d+) "# + word, options: .regularExpression) else { continue }
            let digits = line[range].split(whereSeparator: { !$0.isNumber }).first.flatMap { Int($0) }
            counts[keyPath: keyPath] = digits ?? 0
            touched = true
        }
        if touched { report.summary = counts }
    }
}
