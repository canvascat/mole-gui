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
