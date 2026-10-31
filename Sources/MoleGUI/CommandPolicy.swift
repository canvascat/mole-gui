import Foundation

enum PolicyError: Error, Equatable, LocalizedError {
    case notMo
    case sudo
    case empty
    case forbiddenFlag(String)
    case unsupported
    case needsTerminal
    case invalidName
    case invalidPath

    var errorDescription: String? {
        switch self {
        case .notMo:
            return "只能执行名为 mo 的程序。"
        case .sudo:
            return "不会用 sudo 启动 mo。"
        case .empty:
            return "必须带具体子命令，不能裸跑 mo。"
        case .forbiddenFlag(let flag):
            return "第一版不会传递 \(flag)。"
        case .unsupported:
            return "第一版不会执行这条命令。"
        case .needsTerminal:
            return "真正的卸载只能在伪终端里跑，好让 CLI 自己的确认留下。"
        case .invalidName:
            return "卸载名字无效。请用列表里的 uninstall_name，不要把开关当成名字。"
        case .invalidPath:
            return "磁盘路径无效。请选择一个存在的目录。"
        }
    }
}

enum MoleSubcommand: Equatable {
    case version
    case statusJSON
    case statusWatch
    case cleanDryRun
    case clean
    case uninstallList
    case uninstallDryRun(names: [String])
    case uninstallLive(names: [String])
    case analyze(path: String)
    case purgeDryRun
    case purgeYes
    case optimizeDryRun
    case optimize
    case history
}

enum CommandPolicy {
    static let purgeConfirmation = "永久删除"
    static let historyLimit = "50"
    static let watchInterval = "2s"

    static func isPreview(_ action: MoleSubcommand) -> Bool {
        switch action {
        case .cleanDryRun, .optimizeDryRun, .purgeDryRun, .uninstallDryRun:
            return true
        default:
            return false
        }
    }

    static func isExecute(_ action: MoleSubcommand) -> Bool {
        switch action {
        case .clean, .optimize, .purgeYes:
            return true
        default:
            return false
        }
    }

    static func arguments(for action: MoleSubcommand) throws -> [String] {
        switch action {
        case .version:
            return ["version"]
        case .statusJSON:
            return ["status", "--json"]
        case .statusWatch:
            return ["status", "--watch", "--interval", watchInterval]
        case .cleanDryRun:
            return ["clean", "--dry-run"]
        case .clean:
            return ["clean"]
        case .uninstallList:
            return ["uninstall", "--list"]
        case .uninstallDryRun(let names):
            return ["uninstall", "--dry-run"] + (try validateNames(names))
        case .uninstallLive(let names):
            return ["uninstall"] + (try validateNames(names))
        case .analyze(let path):
            try validateAnalyzePath(path)
            return ["analyze", "--json", path]
        case .purgeDryRun:
            return ["purge", "--dry-run"]
        case .purgeYes:
            return ["purge", "--yes"]
        case .optimizeDryRun:
            return ["optimize", "--dry-run"]
        case .optimize:
            return ["optimize"]
        case .history:
            return ["history", "--json", "--limit", historyLimit]
        }
    }

    static func plan(executable: String, action: MoleSubcommand, pseudoTerminal: Bool) throws -> [String] {
        let args = try arguments(for: action)
        try validate(executable: executable, arguments: args, pseudoTerminal: pseudoTerminal)
        return args
    }

    static func validate(executable: String, arguments: [String], pseudoTerminal: Bool) throws {
        if arguments.isEmpty {
            throw PolicyError.empty
        }
        for argument in arguments {
            if argument == "sudo" || argument == "--permanent" || argument == "--with-data" {
                throw PolicyError.forbiddenFlag(argument)
            }
            if argument.contains("\0") || argument.contains("\n") || argument.contains("\r") {
                throw PolicyError.invalidName
            }
        }
        try validateExecutable(executable)

        switch arguments[0] {
        case "version":
            guard arguments == ["version"], !pseudoTerminal else { throw PolicyError.unsupported }
        case "status":
            let allowed = arguments == ["status", "--json"]
                || arguments == ["status", "--watch", "--interval", watchInterval]
            guard allowed, !pseudoTerminal else { throw PolicyError.unsupported }
        case "clean":
            guard arguments == ["clean"] || arguments == ["clean", "--dry-run"], !pseudoTerminal else {
                throw PolicyError.unsupported
            }
        case "optimize":
            guard arguments == ["optimize"] || arguments == ["optimize", "--dry-run"], !pseudoTerminal else {
                throw PolicyError.unsupported
            }
        case "purge":
            guard arguments == ["purge", "--dry-run"] || arguments == ["purge", "--yes"], !pseudoTerminal else {
                throw PolicyError.unsupported
            }
        case "history":
            guard arguments == ["history", "--json", "--limit", historyLimit], !pseudoTerminal else {
                throw PolicyError.unsupported
            }
        case "analyze":
            guard arguments.count == 3, arguments[1] == "--json", !pseudoTerminal else {
                throw PolicyError.unsupported
            }
            try validateAnalyzePath(arguments[2])
        case "uninstall":
            if arguments == ["uninstall", "--list"] {
                guard !pseudoTerminal else { throw PolicyError.unsupported }
                return
            }
            if arguments.count >= 3, arguments[1] == "--dry-run" {
                guard !pseudoTerminal else { throw PolicyError.unsupported }
                _ = try validateNames(Array(arguments.dropFirst(2)))
                return
            }
            if arguments.count >= 2, !arguments[1].hasPrefix("-") {
                guard pseudoTerminal else { throw PolicyError.needsTerminal }
                _ = try validateNames(Array(arguments.dropFirst(1)))
                return
            }
            throw PolicyError.unsupported
        default:
            throw PolicyError.unsupported
        }
    }

    static func validateExecutable(_ executable: String) throws {
        let parts = executable.split(separator: "/").map(String.init)
        if parts.contains("sudo") || executable == "sudo" {
            throw PolicyError.sudo
        }
        guard parts.last == "mo" else { throw PolicyError.notMo }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: executable, isDirectory: &isDirectory)
        guard exists, !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: executable) else {
            throw PolicyError.notMo
        }
    }

    @discardableResult
    static func validateNames(_ names: [String]) throws -> [String] {
        if names.isEmpty { throw PolicyError.invalidName }
        for name in names {
            if name.isEmpty || name.count > 240 { throw PolicyError.invalidName }
            if name.hasPrefix("-") { throw PolicyError.invalidName }
            if name.contains("\0") || name.contains("\n") || name.contains("\r") {
                throw PolicyError.invalidName
            }
        }
        return names
    }

    static func validateAnalyzePath(_ path: String) throws {
        if path.isEmpty || !path.hasPrefix("/") || path.hasPrefix("-") || path.contains("\0") {
            throw PolicyError.invalidPath
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PolicyError.invalidPath
        }
    }
}

enum ExecutionGate {
    static func refuse(acceptsExecute: Bool, phrase: String?, action: MoleSubcommand) -> String? {
        if !CommandPolicy.isExecute(action) {
            return "这条命令不能从确认按钮执行。"
        }
        if !acceptsExecute {
            return "请先完成预览，再确认执行。"
        }
        if case .purgeYes = action, phrase != CommandPolicy.purgeConfirmation {
            return "确认语不正确，没有执行。"
        }
        return nil
    }
}

enum DisplayCommand {
    static func string(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(quote).joined(separator: " ")
    }

    static func quote(_ value: String) -> String {
        let safe = value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || "/._+-:@".unicodeScalars.contains(scalar)
        }
        if safe && !value.isEmpty { return value }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
