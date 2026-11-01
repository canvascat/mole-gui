import Foundation

/// `mo purge --dry-run` 逐行列出的一个项目产物，例如 `✓ [DRY RUN] ~/app/node_modules, 1.4GB`。
struct PurgeItem: Equatable, Identifiable, Sendable {
    var path: String
    var sizeBytes: Int64?
    var cloud: Bool

    var id: String { path }

    var name: String {
        let component = URL(fileURLWithPath: path).lastPathComponent
        return component.isEmpty ? path : component
    }

    var projectPath: String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    /// 云同步目录里的项目产物由 mo 自己要求确认，这个窗口不动它们。
    var deletable: Bool { !cloud && CleanPlan.deletable(path) }

    var sizeLabel: String {
        guard let sizeBytes else { return "大小未知" }
        return CleanPlan.decimalLabel(sizeBytes)
    }
}

struct PurgeProject: Equatable, Identifiable {
    var path: String
    var items: [PurgeItem]

    var id: String { path }

    var name: String {
        let component = URL(fileURLWithPath: path).lastPathComponent
        return component.isEmpty ? path : component
    }

    var totalBytes: Int64 { items.reduce(0) { $0 + ($1.sizeBytes ?? 0) } }
    var hasUnknownSize: Bool { items.contains { $0.sizeBytes == nil } }
}

enum PurgePlan {
    private static let marker = "[DRY RUN] "
    private static let cloudPrefix = "[cloud] "

    static func parse(_ raw: String) -> [PurgeItem] {
        var buffer = TerminalBuffer()
        buffer.ingest(raw)
        var seen = Set<String>()
        var items: [PurgeItem] = []
        for line in buffer.lines {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let range = text.range(of: marker) else { continue }
            var rest = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            var cloud = false
            if rest.hasPrefix(cloudPrefix) {
                cloud = true
                rest = String(rest.dropFirst(cloudPrefix.count)).trimmingCharacters(in: .whitespaces)
            }
            guard let comma = rest.range(of: ", ", options: .backwards) else { continue }
            let rawPath = String(rest[..<comma.lowerBound]).trimmingCharacters(in: .whitespaces)
            let sizeToken = String(rest[comma.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard let path = absolute(rawPath), seen.insert(path).inserted else { continue }
            items.append(PurgeItem(path: path, sizeBytes: CleanPlan.parseSize(sizeToken), cloud: cloud))
        }
        return items
    }

    static func projects(_ items: [PurgeItem]) -> [PurgeProject] {
        var grouped: [String: [PurgeItem]] = [:]
        for item in items {
            grouped[item.projectPath, default: []].append(item)
        }
        return grouped.map { path, rows in
            PurgeProject(path: path, items: rows.sorted(by: largerFirst))
        }.sorted { lhs, rhs in
            if lhs.totalBytes == rhs.totalBytes {
                return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }
            return lhs.totalBytes > rhs.totalBytes
        }
    }

    static func totalBytes(_ items: [PurgeItem]) -> (bytes: Int64, partial: Bool) {
        var bytes: Int64 = 0
        var partial = false
        for item in items {
            if let size = item.sizeBytes { bytes += size } else { partial = true }
        }
        return (bytes, partial)
    }

    private static func absolute(_ path: String) -> String? {
        var text = path
        if text == "~" || text.hasPrefix("~/") {
            text = NSHomeDirectory() + text.dropFirst()
        }
        guard text.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: text).standardizedFileURL.path
    }

    private static func largerFirst(_ lhs: PurgeItem, _ rhs: PurgeItem) -> Bool {
        let left = lhs.sizeBytes ?? -1
        let right = rhs.sizeBytes ?? -1
        if left == right { return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending }
        return left > right
    }
}
