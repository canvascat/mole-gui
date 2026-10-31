import Foundation

enum MoleLocator {
    static func accept(path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.last == "mo", !parts.contains("sudo") else { return false }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue && FileManager.default.isExecutableFile(atPath: path)
    }

    static func fixedCandidates() -> [String] {
        let home = NSHomeDirectory()
        return [
            "/opt/homebrew/bin/mo",
            "/usr/local/bin/mo",
            home + "/.local/bin/mo",
        ]
    }

    static func locate() -> String? {
        for path in fixedCandidates() where accept(path: path) {
            return path
        }
        for path in pathFileCandidates() where accept(path: path) {
            return path
        }
        if let shell = locateViaLoginShell(), accept(path: shell) {
            return shell
        }
        return nil
    }

    static func pathFileCandidates() -> [String] {
        var directories: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            directories.append(contentsOf: path.split(separator: ":").map(String.init))
        }
        if let paths = try? String(contentsOfFile: "/etc/paths", encoding: .utf8) {
            directories.append(contentsOf: paths.split(whereSeparator: \.isNewline).map(String.init))
        }
        if let items = try? FileManager.default.contentsOfDirectory(atPath: "/etc/paths.d") {
            for item in items.sorted() {
                let file = "/etc/paths.d/" + item
                if let text = try? String(contentsOfFile: file, encoding: .utf8) {
                    directories.append(contentsOf: text.split(whereSeparator: \.isNewline).map(String.init))
                }
            }
        }
        var seen = Set<String>()
        var candidates: [String] = []
        for directory in directories where !directory.isEmpty && seen.insert(directory).inserted {
            candidates.append((directory as NSString).appendingPathComponent("mo"))
        }
        return candidates
    }

    static func locateViaLoginShell() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "command -v mo"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in semaphore.signal() }
        if semaphore.wait(timeout: .now() + 3) == .timedOut {
            if process.isRunning { process.terminate() }
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text.hasPrefix("/"), !text.contains("\n"), !text.contains("\r") else { return nil }
        return text
    }
}

enum MoleEnvironment {
    static func make(moPath: String) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let directory = (moPath as NSString).deletingLastPathComponent
        var directories = [directory, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        if let current = environment["PATH"] {
            directories.append(contentsOf: current.split(separator: ":").map(String.init))
        }
        var seen = Set<String>()
        let merged = directories.filter { !$0.isEmpty && seen.insert($0).inserted }
        environment["PATH"] = merged.joined(separator: ":")
        if environment["LANG"] == nil { environment["LANG"] = "zh_CN.UTF-8" }
        return environment
    }
}

enum TerminalLauncher {
    static func open(shellCommand: String) -> String? {
        if shellCommand.contains("\n") || shellCommand.contains("\r") || shellCommand.contains("\0") {
            return "命令里有换行，没有打开终端。"
        }
        let source = "tell application \"Terminal\" to do script \(appleScriptString(shellCommand))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return "打不开终端：\(error.localizedDescription)"
        }
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = (process.standardError as? Pipe)?.fileHandleForReading.readDataToEndOfFile() ?? Data()
            let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? "终端没有打开这条命令。" : text
        }
        return nil
    }

    static func appleScriptString(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
