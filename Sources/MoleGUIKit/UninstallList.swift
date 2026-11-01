import Foundation

enum UninstallSort: String, CaseIterable, Identifiable {
    case name, size, recent, installed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "名称"
        case .size: return "占用体积"
        case .recent: return "最近使用"
        case .installed: return "安装日期"
        }
    }
}

struct AppSpotlight: Equatable {
    var version = ""
    var intel = false
    var lastUsed: Date?
    var installed: Date?

    static func read(path: String) -> AppSpotlight {
        var spot = AppSpotlight()
        let url = URL(fileURLWithPath: path)
        if let bundle = Bundle(url: url) {
            if let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                spot.version = version.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let exe = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String, !exe.isEmpty {
                let binary = url.appendingPathComponent("Contents/MacOS").appendingPathComponent(exe).path
                spot.intel = MachImage.isIntelOnly(path: binary)
            }
        }
        let keys: Set<URLResourceKey> = [.contentAccessDateKey, .addedToDirectoryDateKey, .creationDateKey]
        if let values = try? url.resourceValues(forKeys: keys) {
            spot.lastUsed = values.contentAccessDate
            spot.installed = values.addedToDirectoryDate ?? values.creationDate
        }
        return spot
    }

    func caption(size: String, now: Date = Date()) -> String {
        var parts: [String] = []
        if !version.isEmpty { parts.append(version) }
        if !size.isEmpty { parts.append(size) }
        if intel { parts.append("Intel") }
        if let lastUsed, let label = AppActivity.phrase(since: lastUsed, now: now) {
            parts.append(label)
        }
        return parts.joined(separator: " · ")
    }
}

enum AppActivity {
    static func phrase(since date: Date, now: Date = Date()) -> String? {
        let seconds = now.timeIntervalSince(date)
        if seconds < 86_400 { return "今天有活动" }
        let days = Int(seconds / 86_400)
        if days < 7 { return "\(days)天前有活动" }
        if days < 30 { return "\(max(days / 7, 1))周前有活动" }
        if days < 365 { return "\(max(days / 30, 1))个月前有活动" }
        return "\(max(days / 365, 1))年前有活动"
    }
}

enum UninstallSizing {
    static func bytes(from label: String) -> Double? {
        let text = label.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard !text.isEmpty else { return nil }
        var number = ""
        var unit = ""
        var sawDigit = false
        for character in text {
            if character.isNumber || character == "." {
                if !unit.isEmpty { break }
                number.append(character)
                if character.isNumber { sawDigit = true }
            } else if character == " " {
                if sawDigit { continue }
            } else {
                unit.append(character)
            }
        }
        guard sawDigit, let value = Double(number), value >= 0 else { return nil }
        let scale: Double
        switch unit.uppercased() {
        case "TB", "T": scale = 1_000_000_000_000
        case "GB", "G": scale = 1_000_000_000
        case "MB", "M": scale = 1_000_000
        case "KB", "K": scale = 1_000
        case "B", "": scale = 1
        default: return nil
        }
        return value * scale
    }

    static func totalLabel(_ bytes: Double) -> String {
        if bytes >= 1_000_000_000 {
            return String(format: "%.2f GB", bytes / 1_000_000_000)
        }
        if bytes >= 1_000_000 {
            return String(format: "%.1f MB", bytes / 1_000_000)
        }
        if bytes >= 1_000 {
            return String(format: "%.0f KB", bytes / 1_000)
        }
        return "\(Int(bytes.rounded())) B"
    }

    static func sum(_ labels: [String]) -> Double {
        labels.reduce(0) { $0 + (bytes(from: $1) ?? 0) }
    }
}

enum MachImage {
    static func isIntelOnly(path: String) -> Bool {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) else {
            return false
        }
        return isIntelOnly(Data(data.prefix(512)))
    }

    static func isIntelOnly(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        guard bytes.count >= 8 else { return false }
        if bytes[0] == 0xCF && bytes[1] == 0xFA && bytes[2] == 0xED && bytes[3] == 0xFE {
            return read(bytes, 4, little: true) == 0x0100_0007
        }
        if bytes[0] == 0xFE && bytes[1] == 0xED && bytes[2] == 0xFA && bytes[3] == 0xCF {
            return read(bytes, 4, little: false) == 0x0100_0007
        }
        if bytes[0] == 0xCA && bytes[1] == 0xFE && bytes[2] == 0xBA && bytes[3] == 0xBE {
            return fatIntelOnly(bytes, little: false)
        }
        if bytes[0] == 0xBE && bytes[1] == 0xBA && bytes[2] == 0xFE && bytes[3] == 0xCA {
            return fatIntelOnly(bytes, little: true)
        }
        return false
    }

    private static func fatIntelOnly(_ bytes: [UInt8], little: Bool) -> Bool {
        let count = Int(read(bytes, 4, little: little))
        guard count > 0, count < 32 else { return false }
        var sawIntel = false
        var sawARM = false
        for index in 0..<count {
            let offset = 8 + index * 20
            guard offset + 4 <= bytes.count else { return false }
            let cpu = read(bytes, offset, little: little)
            if cpu == 0x0100_0007 { sawIntel = true }
            if cpu == 0x0100_000C { sawARM = true }
        }
        return sawIntel && !sawARM
    }

    private static func read(_ bytes: [UInt8], _ offset: Int, little: Bool) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        let raw = UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
        return little ? raw : raw.byteSwapped
    }
}

enum UninstallOrder {
    static func sorted(
        _ apps: [UninstallApp],
        by key: UninstallSort,
        ascending: Bool,
        details: [String: AppSpotlight]
    ) -> [UninstallApp] {
        apps.sorted { lhs, rhs in
            let order = compare(lhs, rhs, key: key, details: details)
            if order == .orderedSame {
                let left = displayName(lhs)
                let right = displayName(rhs)
                return left.localizedStandardCompare(right) == .orderedAscending
            }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }

    private static func displayName(_ app: UninstallApp) -> String {
        app.name.isEmpty ? app.uninstallName : app.name
    }

    private static func compare(
        _ lhs: UninstallApp,
        _ rhs: UninstallApp,
        key: UninstallSort,
        details: [String: AppSpotlight]
    ) -> ComparisonResult {
        switch key {
        case .name:
            return displayName(lhs).localizedStandardCompare(displayName(rhs))
        case .size:
            let left = UninstallSizing.bytes(from: lhs.size) ?? -1
            let right = UninstallSizing.bytes(from: rhs.size) ?? -1
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        case .recent:
            return compareDates(details[lhs.path]?.lastUsed, details[rhs.path]?.lastUsed)
        case .installed:
            return compareDates(details[lhs.path]?.installed, details[rhs.path]?.installed)
        }
    }

    /// 没有日期的排在最前，当作最久没用过。
    private static func compareDates(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (left?, right?):
            if left == right { return .orderedSame }
            return left < right ? .orderedAscending : .orderedDescending
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedAscending
        case (_?, nil):
            return .orderedDescending
        }
    }
}
