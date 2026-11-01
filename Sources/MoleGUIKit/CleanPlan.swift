import Foundation

struct CleanEntry: Equatable, Identifiable, Sendable {
    var path: String
    var section: String
    var sizeBytes: Int64?
    var coveredBy: String?
    var recommended: Bool

    var id: String { path }

    var name: String {
        let component = URL(fileURLWithPath: path).lastPathComponent
        return component.isEmpty ? path : component
    }

    var deletable: Bool { CleanPlan.deletable(path) }

    var sizeLabel: String {
        guard let sizeBytes else { return "大小未知" }
        return CleanPlan.decimalLabel(sizeBytes)
    }
}

struct CleanGroup: Equatable, Identifiable {
    var title: String
    var detail: String
    var entries: [CleanEntry]

    var id: String { title }
}

struct CleanCatalog: Equatable {
    var groups: [CleanGroup]

    var entries: [CleanEntry] { groups.flatMap(\.entries) }
}

enum CleanPlan {
    static let listPath = NSHomeDirectory() + "/.config/mole/clean-list.txt"

    private static let buckets: [(title: String, detail: String, sections: Set<String>, recommended: Bool)] = [
        (
            "App 缓存与日志",
            "App、浏览器、云盘和常用工具的缓存与旧日志。",
            ["User essentials", "App caches", "Browsers", "Cloud & Office", "Apps & utilities", "Apple Silicon updates"],
            true
        ),
        (
            "开发工具",
            "Xcode、包管理器、虚拟机等开发工具的缓存。",
            ["Developer tools", "Virtualization"],
            true
        ),
        (
            "项目产物",
            "项目里的构建产物。默认不选，勾选后才会删除。",
            ["Project artifacts"],
            false
        ),
        (
            "卸载残留",
            "已删除 App 留下的文件，其中可能有设置或数据。",
            ["App leftovers", "Application Support"],
            false
        ),
        (
            "系统数据",
            "系统缓存、备份和大文件。系统路径不会在这个窗口里删除。",
            ["System", "Time Machine", "Device backups & firmware", "Large files", "External volume"],
            false
        ),
    ]

    static func parse(_ text: String) -> [CleanEntry] {
        var section = ""
        var seen = Set<String>()
        var entries: [CleanEntry] = []
        for raw in text.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("===") {
                section = line.trimmingCharacters(in: CharacterSet(charactersIn: "= ")).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard !section.isEmpty else { continue }
            let path: String
            let note: String
            if let range = line.range(of: "  # ", options: .backwards) {
                path = String(line[..<range.lowerBound])
                note = String(line[range.upperBound...])
            } else {
                path = line
                note = ""
            }
            let absolute = URL(fileURLWithPath: path).standardizedFileURL.path
            guard absolute.hasPrefix("/"), seen.insert(absolute).inserted else { continue }
            let parts = note.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            let sizeToken = parts.first ?? ""
            let covered = parts.first { $0.hasPrefix("counted under ") }.map { String($0.dropFirst("counted under ".count)) }
            entries.append(CleanEntry(
                path: absolute,
                section: section,
                sizeBytes: parseSize(sizeToken),
                coveredBy: covered.map { URL(fileURLWithPath: $0).standardizedFileURL.path },
                recommended: recommended(section)
            ))
        }
        return entries.filter { $0.coveredBy == nil }
    }

    static func catalog(_ entries: [CleanEntry]) -> CleanCatalog {
        var grouped: [String: [CleanEntry]] = [:]
        var extras: [CleanEntry] = []
        for entry in entries {
            if let bucket = buckets.first(where: { $0.sections.contains(entry.section) }) {
                grouped[bucket.title, default: []].append(entry)
            } else {
                extras.append(entry)
            }
        }
        var groups: [CleanGroup] = []
        for bucket in buckets {
            let rows = (grouped[bucket.title] ?? []).sorted(by: largerFirst)
            guard !rows.isEmpty else { continue }
            groups.append(CleanGroup(title: bucket.title, detail: bucket.detail, entries: rows))
        }
        if !extras.isEmpty {
            groups.append(CleanGroup(
                title: "其他",
                detail: "这次预览里没有归进上面几类的项目。",
                entries: extras.sorted(by: largerFirst)
            ))
        }
        return CleanCatalog(groups: groups)
    }

    static func recommended(_ section: String) -> Bool {
        buckets.first { $0.sections.contains(section) }?.recommended ?? false
    }

    static func deletable(_ path: String) -> Bool {
        if path.contains("\0") || path.contains("\n") || path.contains("\r") { return false }
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        if std.isEmpty || std == "/" || std.contains("..") { return false }
        let home = NSHomeDirectory()
        let blocked: Set<String> = [
            home,
            home + "/Library",
            home + "/Documents",
            home + "/Desktop",
            home + "/Pictures",
            home + "/Movies",
            home + "/Music",
            home + "/Downloads",
            home + "/Library/Caches",
            home + "/Library/Logs",
            home + "/Library/Application Support",
            home + "/Library/Containers",
            home + "/Library/Group Containers",
            home + "/Library/Preferences",
            home + "/.Trash",
        ]
        if blocked.contains(std) { return false }
        if std.hasPrefix(home + "/") {
            return std.dropFirst(home.count + 1).split(separator: "/").count >= 2
        }
        if std.hasPrefix("/private/var/folders/") {
            return std.dropFirst("/private/var/folders/".count).split(separator: "/").count >= 3
        }
        return false
    }

    static func deletionRoots(_ paths: [String]) -> [String] {
        let unique = Array(Set(paths)).sorted()
        return unique.filter { path in
            !unique.contains { other in
                other != path && path.hasPrefix(other + "/")
            }
        }
    }

    static func decimalLabel(_ bytes: Int64) -> String {
        if bytes <= 0 { return "0 B" }
        let value = Double(bytes)
        if value >= 1_000_000_000 {
            return String(format: "%.2f GB", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1f MB", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0f KB", value / 1_000)
        }
        return "\(bytes) B"
    }

    static func totalBytes(_ entries: [CleanEntry]) -> (bytes: Int64, partial: Bool) {
        var bytes: Int64 = 0
        var partial = false
        for entry in entries {
            if let size = entry.sizeBytes {
                bytes += size
            } else {
                partial = true
            }
        }
        return (bytes, partial)
    }

    private static func largerFirst(_ lhs: CleanEntry, _ rhs: CleanEntry) -> Bool {
        let left = lhs.sizeBytes ?? -1
        let right = rhs.sizeBytes ?? -1
        if left == right { return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending }
        return left > right
    }

    static func parseSize(_ token: String) -> Int64? {
        let text = token.trimmingCharacters(in: .whitespaces)
        if text.isEmpty || text == "size unknown" { return nil }
        guard let match = text.range(of: #"^(\d+(?:\.\d+)?)(GB|MB|KB|B)$"#, options: .regularExpression) else {
            return nil
        }
        let body = String(text[match])
        let split = body.firstIndex { $0.isLetter } ?? body.endIndex
        let number = body[..<split]
        let unit = body[split...]
        guard let value = Double(number) else { return nil }
        let scale: Double
        switch String(unit) {
        case "GB": scale = 1_000_000_000
        case "MB": scale = 1_000_000
        case "KB": scale = 1_000
        default: scale = 1
        }
        return Int64((value * scale).rounded())
    }
}

struct CleanDeleteItem: Equatable, Identifiable, Sendable {
    var path: String
    var name: String
    var group: String
    var bytes: Int64?

    var id: String { path }
}

struct CleanDeleteRow: Equatable, Identifiable {
    var item: CleanDeleteItem
    var ok: Bool
    var message: String

    var id: String { item.path }
}

struct CleanDeleteProgress: Equatable {
    var total: Int
    var completed: Int
    var freedBytes: Int64
    var current: CleanDeleteItem?
    var done: [CleanDeleteRow]

    var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

enum CleanScanState: Equatable {
    case running
    case done
    case empty
}

struct CleanScanStep: Equatable, Identifiable {
    var title: String
    var state: CleanScanState
    var items: Int
    var latest: String

    var id: String { title }
}

enum CleanScanProgress {
    private static let sections = [
        "Device backups & firmware",
        "Apple Silicon updates",
        "Application Support",
        "Project artifacts",
        "Developer tools",
        "Apps & utilities",
        "User essentials",
        "External volume",
        "Time Machine",
        "Virtualization",
        "Cloud & Office",
        "App leftovers",
        "Large files",
        "App caches",
        "Browsers",
        "System",
    ]

    private static let titles = [
        "User essentials": "用户缓存",
        "App caches": "App 缓存",
        "Browsers": "浏览器",
        "Cloud & Office": "云盘与办公",
        "Developer tools": "开发工具",
        "Apps & utilities": "应用工具",
        "Virtualization": "虚拟机",
        "Application Support": "应用支持文件",
        "App leftovers": "卸载残留",
        "Device backups & firmware": "设备备份",
        "Time Machine": "时间机器",
        "Large files": "大文件",
        "Project artifacts": "项目产物",
        "System": "系统",
        "External volume": "外置磁盘",
        "Apple Silicon updates": "Apple 芯片更新",
    ]

    static func parse(_ raw: String) -> [CleanScanStep] {
        var buffer = TerminalBuffer()
        buffer.ingest(raw)
        var steps: [CleanScanStep] = []
        for line in buffer.lines {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            if let section = matchSection(text) {
                finishRunning(&steps)
                steps.append(CleanScanStep(
                    title: titles[section] ?? section,
                    state: .running,
                    items: 0,
                    latest: ""
                ))
                continue
            }
            guard let index = steps.indices.last else { continue }
            if text.localizedCaseInsensitiveContains("nothing to clean"), steps[index].items == 0 {
                steps[index].state = .empty
                continue
            }
            guard looksLikeItem(text) else { continue }
            steps[index].items += 1
            steps[index].latest = itemTitle(text)
            if steps[index].state == .empty {
                steps[index].state = .running
            }
        }
        return steps
    }

    private static func finishRunning(_ steps: inout [CleanScanStep]) {
        guard let index = steps.indices.last, steps[index].state == .running else { return }
        steps[index].state = steps[index].items > 0 ? .done : .empty
    }

    private static func matchSection(_ line: String) -> String? {
        for name in sections where line == name || line.hasSuffix(" " + name) || line.hasSuffix(name) {
            let prefixCount = line.count - name.count
            let prefix = line.prefix(prefixCount)
            if prefix.allSatisfy({ !$0.isLetter && !$0.isNumber }) {
                return name
            }
        }
        return nil
    }

    private static func looksLikeItem(_ line: String) -> Bool {
        let folded = line.lowercased()
        if folded.contains("dry run") || folded.contains("potential space") { return false }
        return line.contains("·") || folded.hasSuffix(" dry") || folded.contains(" dry ")
    }

    private static func itemTitle(_ line: String) -> String {
        var text = line
        if let dot = text.firstIndex(of: "·") {
            text = String(text[..<dot])
        }
        while let first = text.first, !first.isLetter, !first.isNumber, first != "/" {
            text.removeFirst()
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
