import Foundation

struct ActivitySnapshot: Equatable, Sendable {
    var running = false
    var title = ""
    var commandLine = ""
    var detail = ""
    var token = 0
}

enum RunningCommandTitle {
    static func make(_ arguments: [String]) -> String {
        switch arguments.first {
        case "version":
            return "正在确认 Mole 版本"
        case "status":
            return "正在读取本机状态"
        case "clean":
            return arguments.contains("--dry-run") ? "正在扫描可清理的文件" : "正在清理"
        case "uninstall":
            if arguments.contains("--list") { return "正在列出可卸载的应用" }
            if arguments.contains("--dry-run") { return "正在预览卸载" }
            return "正在卸载"
        case "analyze":
            return "正在分析磁盘占用"
        case "purge":
            return arguments.contains("--dry-run") ? "正在预览项目产物" : "正在清理项目产物"
        case "optimize":
            return arguments.contains("--dry-run") ? "正在预览维护项" : "正在执行维护"
        case "history":
            return "正在读取操作记录"
        default:
            if let name = arguments.first, !name.isEmpty {
                return "正在运行 \(name)"
            }
            return "正在运行 mo"
        }
    }

    /// 最近一条给人看的输出。JSON 和空行跳过，避免状态监视把整段数据铺进侧栏。
    static func detail(in lines: [String]) -> String {
        for line in lines.reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            let first = trimmed.first
            if first == "{" || first == "[" || first == "}" || first == "]" || first == "\"" { continue }
            if trimmed.count > 180 { continue }
            return trimmed
        }
        return ""
    }
}

/// 同一时间只有一条 mo。这里记下它的名字、命令行和最近一行输出，停止按钮调用启动时留下的闭包。
final class CommandBoard: @unchecked Sendable {
    static let shared = CommandBoard()

    private let lock = NSLock()
    private var state = ActivitySnapshot()
    private var onStop: (@Sendable () -> Void)?
    private var buffer = TerminalBuffer(limit: 40)
    private var lastNote = Date.distantPast
    var listener: (@Sendable (ActivitySnapshot) -> Void)?

    func current() -> ActivitySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return state
    }

    @discardableResult
    func begin(title: String, commandLine: String, stop: @escaping @Sendable () -> Void) -> Int {
        lock.lock()
        let issued = max(state.token &+ 1, 1)
        state = ActivitySnapshot(
            running: true,
            title: title,
            commandLine: commandLine,
            detail: "",
            token: issued
        )
        onStop = stop
        buffer = TerminalBuffer(limit: 40)
        lastNote = .distantPast
        lock.unlock()
        publish()
        return issued
    }

    func note(token: Int, chunk: String) {
        lock.lock()
        guard token != 0, state.running, state.token == token else {
            lock.unlock()
            return
        }
        buffer.ingest(chunk)
        let line = RunningCommandTitle.detail(in: buffer.lines)
        var shouldPublish = false
        if !line.isEmpty, line != state.detail {
            state.detail = line
            let now = Date()
            if now.timeIntervalSince(lastNote) > 0.1 {
                lastNote = now
                shouldPublish = true
            }
        }
        lock.unlock()
        if shouldPublish { publish() }
    }

    func end(token: Int) {
        lock.lock()
        guard token != 0, state.running, state.token == token else {
            lock.unlock()
            return
        }
        state.running = false
        state.detail = ""
        let stop = onStop
        onStop = nil
        lock.unlock()
        publish()
        // 闭包可能是这条命令最后的引用。先放开锁再释放，避免它的析构回头再抢这把锁。
        withExtendedLifetime(stop) {}
    }

    func requestStop() {
        lock.lock()
        let stop = onStop
        lock.unlock()
        stop?()
    }

    private func publish() {
        let deliver = {
            self.lock.lock()
            let snapshot = self.state
            let listener = self.listener
            self.lock.unlock()
            listener?(snapshot)
        }
        if Thread.isMainThread {
            deliver()
        } else {
            DispatchQueue.main.async(execute: deliver)
        }
    }
}

final class CommandActivity: ObservableObject {
    static let shared = CommandActivity()

    @Published private(set) var snapshot = ActivitySnapshot()

    private init() {
        CommandBoard.shared.listener = { [weak self] snapshot in
            self?.snapshot = snapshot
        }
    }

    func stop() {
        CommandBoard.shared.requestStop()
    }
}
