import Foundation

struct LeftoverFile: Equatable, Identifiable, Sendable {
    var path: String
    var sizeBytes: Int64

    var id: String { path }

    var name: String {
        let component = URL(fileURLWithPath: path).lastPathComponent
        return component.isEmpty ? path : component
    }

    var sizeLabel: String {
        LeftoverPlan.sizeLabel(sizeBytes)
    }
}

struct LeftoverReview: Equatable, Identifiable {
    var id: String
    var apps: [UninstallApp]
    var files: [LeftoverFile]

    var title: String {
        let names = apps.map { app in
            app.name.isEmpty ? app.uninstallName : app.name
        }
        let text = names.filter { !$0.isEmpty }.joined(separator: "、")
        return text.isEmpty ? "已卸载的应用" : text
    }
}

enum LeftoverPlan {
    static func sizeLabel(_ bytes: Int64) -> String {
        if bytes <= 0 { return "空" }
        return Format.bytes(UInt64(bytes))
    }

    static func paths(in log: String, excludingAppPaths: Set<String>) -> [String] {
        let excluded = Set(excludingAppPaths.map(standardize))
        var section = Section.none
        var seen = Set<String>()
        var result: [String] = []
        for raw in TerminalText.stripANSI(log).components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let folded = line.lowercased()
            if folded.contains("personal data kept") {
                section = .kept
                continue
            }
            if folded.contains("files to be removed") {
                section = .removing
                continue
            }
            if folded.contains("personal data to remove") {
                section = .ignore
                continue
            }
            if isSectionEnd(folded) {
                section = .ignore
                continue
            }
            guard section == .removing || section == .kept else { continue }
            if folded.contains("system:") || folded.contains("review only:") { continue }
            guard let token = pathToken(from: line) else { continue }
            let absolute = standardize(expandHome(token))
            guard allowed(absolute), !excluded.contains(absolute) else { continue }
            if seen.insert(absolute).inserted {
                result.append(absolute)
            }
        }
        return result
    }

    static func collect(
        log: String,
        excludingAppPaths: Set<String>,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        measure: (String) -> Int64 = { PathMeasure.allocatedBytes($0) }
    ) -> [LeftoverFile] {
        paths(in: log, excludingAppPaths: excludingAppPaths).compactMap { path in
            guard exists(path), allowed(path) else { return nil }
            return LeftoverFile(path: path, sizeBytes: max(0, measure(path)))
        }
    }

    static func allowed(_ path: String) -> Bool {
        if path.contains("\0") || path.contains("\n") || path.contains("\r") { return false }
        let std = standardize(path)
        if std.isEmpty || std == "/" || std.contains("\0") { return false }
        let homeLibrary = NSHomeDirectory() + "/Library/"
        if std.hasPrefix(homeLibrary) {
            let rest = std.dropFirst(homeLibrary.count)
            return !rest.isEmpty && rest != "."
        }
        if let rest = remainder(std, prefix: "/private/var/folders/") ?? remainder(std, prefix: "/var/folders/") {
            return rest.contains("/")
        }
        return false
    }

    private enum Section {
        case none
        case removing
        case kept
        case ignore
    }

    private static func isSectionEnd(_ folded: String) -> Bool {
        let markers = [
            "enter confirm",
            "cleaning files",
            "cleaning system",
            "dry run complete",
            "no apps were removed",
            "uninstall complete",
        ]
        return markers.contains { folded.contains($0) }
    }

    private static func pathToken(from line: String) -> String? {
        guard let index = line.firstIndex(where: { $0 == "~" || $0 == "/" }) else { return nil }
        let prefix = line[..<index]
        if prefix.count > 8 { return nil }
        if prefix.contains(where: \.isLetter) || prefix.contains(where: \.isNumber) { return nil }
        var text = String(line[index...]).trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: " , ", options: .backwards) {
            let size = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if size.range(of: #"^\d+(\.\d+)?\s*[KMGT]?B$"#, options: .regularExpression) != nil {
                text = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
        }
        if text == "~" || text.hasPrefix("~/") || text.hasPrefix("/") {
            return text
        }
        return nil
    }

    private static func expandHome(_ path: String) -> String {
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") {
            return NSHomeDirectory() + String(path.dropFirst(1))
        }
        return path
    }

    private static func standardize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func remainder(_ path: String, prefix: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }
}

enum PathMeasure {
    static func allocatedBytes(_ path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isDirectory == true {
            return directoryBytes(url)
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    private static func directoryBytes(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey],
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileAllocatedSizeKey])
            if values?.isRegularFile == true {
                total += Int64(values?.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
