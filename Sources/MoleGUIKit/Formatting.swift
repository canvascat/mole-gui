import Foundation

enum Format {
    static func bytes(_ value: UInt64, partial: Bool = false) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var amount = Double(value)
        var index = 0
        while amount >= 1024, index < units.count - 1 {
            amount /= 1024
            index += 1
        }
        let text: String
        if index == 0 {
            text = "\(value) \(units[0])"
        } else {
            text = String(format: amount >= 100 ? "%.0f %@" : "%.1f %@", amount, units[index])
        }
        return partial ? text + "+" : text
    }

    static func bytes(_ value: Int64?, scanStatus: String?) -> String {
        guard let value else { return "未知" }
        if value < 0 { return "未知" }
        if scanStatus == "unavailable", value == 0 { return "无法读取" }
        return bytes(UInt64(value), partial: scanStatus == "partial")
    }

    static func percent(_ value: Double, digits: Int = 0) -> String {
        String(format: "%.\(digits)f%%", value)
    }

    static func load(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    static func scanStatus(_ raw: String?) -> String {
        switch raw {
        case "complete": return "已完成"
        case "partial": return "未完成"
        case "unavailable": return "无法读取"
        default: return raw?.isEmpty == false ? raw! : "未知"
        }
    }

    static func healthGrade(_ score: Int) -> String {
        switch score {
        case 85...: return "优秀"
        case 70..<85: return "良好"
        case 50..<70: return "一般"
        default: return "较差"
        }
    }

    /// 健康卡上的一句原因。压力优先，其余只翻译 mo 会写出的英文提示。
    static func healthNote(message: String?, pressure: String?) -> String? {
        switch pressure {
        case "warn": return "内存压力偏高"
        case "critical": return "内存压力很高"
        default: break
        }
        let text = message ?? ""
        if text.range(of: "restart", options: .caseInsensitive) != nil { return "建议重启" }
        if text.range(of: "smart", options: .caseInsensitive) != nil { return "磁盘 SMART 异常" }
        if text.range(of: "full", options: .caseInsensitive) != nil,
           text.range(of: "disk", options: .caseInsensitive) != nil {
            return "磁盘快满了"
        }
        if text.range(of: "cpu", options: .caseInsensitive) != nil { return "CPU 负载偏高" }
        if text.range(of: "memory pressure", options: .caseInsensitive) != nil { return "内存压力偏高" }
        return nil
    }

    static func uptimeLabel(seconds: Int?, raw: String?) -> String {
        if let seconds, seconds >= 0 {
            let days = seconds / 86_400
            let hours = (seconds % 86_400) / 3_600
            let minutes = (seconds % 3_600) / 60
            if days > 0, hours > 0 { return "已运行 \(days) 天 \(hours) 小时" }
            if days > 0 { return "已运行 \(days) 天" }
            if hours > 0, minutes > 0 { return "已运行 \(hours) 小时 \(minutes) 分钟" }
            if hours > 0 { return "已运行 \(hours) 小时" }
            return "已运行 \(minutes) 分钟"
        }
        if let raw, !raw.isEmpty { return "已运行 \(raw)" }
        return "开机时间未知"
    }

    /// 磁盘容量按十进制 GB 显示，和访达、mo 的磁盘数字一致。
    static func storageBytes(_ value: UInt64) -> String {
        let gb = Double(value) / 1_000_000_000
        if gb >= 10 { return "\(Int(gb.rounded())) GB" }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(value) / 1_000_000
        if mb >= 10 { return "\(Int(mb.rounded())) MB" }
        if mb >= 1 { return String(format: "%.1f MB", mb) }
        return bytes(value)
    }

    /// mo 的磁盘和网络速率单位是 MB/s。
    static func rateMBps(_ value: Double) -> String {
        let mb = max(value, 0)
        let kb = mb * 1024
        if kb < 1 { return kb == 0 ? "0 KB/s" : "<1 KB/s" }
        if mb < 0.1 { return String(format: "%.0f KB/s", kb) }
        if mb < 10 { return String(format: "%.1f MB/s", mb) }
        return String(format: "%.0f MB/s", mb)
    }

    static func chipLabel(_ cpuModel: String?) -> String? {
        guard var text = cpuModel?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("Apple ") { text.removeFirst("Apple ".count) }
        return text
    }

    static func ramLabel(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        return raw.replacingOccurrences(of: ".0 ", with: " ")
    }

    static func memoryPressure(_ raw: String?) -> String {
        switch raw {
        case "normal": return "正常"
        case "warn": return "偏高"
        case "critical": return "紧张"
        default: return raw?.isEmpty == false ? raw! : "未知"
        }
    }

    static func attribution(_ raw: String?) -> String {
        switch raw {
        case "run": return "同一次运行"
        case "command": return "按命令归并"
        case "ambiguous": return "归属不确定"
        default: return raw?.isEmpty == false ? raw! : "未知"
        }
    }

    static func ended(_ value: String?) -> String {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return "没有记下结束"
    }

    static func homeAbbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
