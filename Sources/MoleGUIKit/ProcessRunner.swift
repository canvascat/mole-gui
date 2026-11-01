import Combine
import Darwin
import Foundation

enum RunnerError: Error, LocalizedError {
    case busy(String)
    case launch(String)

    var errorDescription: String? {
        switch self {
        case .busy(let title):
            if title.isEmpty {
                return "已经有一条 mo 在运行。侧栏底部可以停止它。"
            }
            return "已经有一条 mo 在运行：\(title)。侧栏底部可以停止它。"
        case .launch(let message):
            return message
        }
    }

    static func busyNow() -> RunnerError {
        let snap = CommandBoard.shared.current()
        return .busy(snap.running ? snap.title : "")
    }
}

final class RunLock: @unchecked Sendable {
    static let shared = RunLock()
    private let lock = NSLock()
    private var held = false

    func tryAcquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if held { return false }
        held = true
        return true
    }

    func release() {
        lock.lock()
        held = false
        lock.unlock()
    }
}

final class ProcessTracker: @unchecked Sendable {
    static let shared = ProcessTracker()
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    func add(_ process: Process) {
        lock.lock()
        processes[ObjectIdentifier(process)] = process
        lock.unlock()
    }

    func remove(_ process: Process) {
        lock.lock()
        processes.removeValue(forKey: ObjectIdentifier(process))
        lock.unlock()
    }

    func stopAll() {
        let snapshot: [Process]
        lock.lock()
        snapshot = Array(processes.values)
        lock.unlock()
        for process in snapshot where process.isRunning {
            process.terminate()
        }
        let deadline = Date().addingTimeInterval(0.4)
        while Date() < deadline {
            if snapshot.allSatisfy({ !$0.isRunning }) { break }
            Thread.sleep(forTimeInterval: 0.05)
        }
        for process in snapshot where process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}

struct CommandSnapshot: Sendable {
    var stdout: String
    var stderr: String
    var running: Bool
    var exitCode: Int32?
    var stopped: Bool
}

final class LiveRun: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = ""
    private var stderr = ""
    private var process: Process?
    private var stopped = false
    private var exitCode: Int32?
    private var finished = false
    private var didSignal = false
    private var acquired = false
    private var streamsOpen = 2
    private var keepStdout: Bool
    private let done = DispatchSemaphore(value: 0)
    private var onChange: (@Sendable () -> Void)?
    private var onDelta: (@Sendable (String, Bool) -> Void)?
    private var lastPublish = Date.distantPast
    private let cap = 400_000
    private var retainedHandles: [FileHandle] = []
    private var pipes: [Pipe] = []
    private var activityToken = 0

    init(keepStdout: Bool = true) {
        self.keepStdout = keepStdout
    }

    func setChangeHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        onChange = handler
        lock.unlock()
    }

    func setDeltaHandler(_ handler: @escaping @Sendable (String, Bool) -> Void) {
        lock.lock()
        onDelta = handler
        lock.unlock()
    }

    func snapshot() -> CommandSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let complete = finished && streamsOpen <= 0
        return CommandSnapshot(
            stdout: stdout,
            stderr: stderr,
            running: !complete && process != nil,
            exitCode: complete ? exitCode : nil,
            stopped: stopped
        )
    }

    func start(executable: String, arguments: [String], environment: [String: String]) throws {
        try CommandPolicy.validate(executable: executable, arguments: arguments, pseudoTerminal: false)
        guard RunLock.shared.tryAcquire() else { throw RunnerError.busyNow() }
        acquired = true
        let token = CommandBoard.shared.begin(
            title: RunningCommandTitle.make(arguments),
            commandLine: DisplayCommand.string(executable: executable, arguments: arguments),
            stop: { self.stop() }
        )
        lock.lock()
        activityToken = token
        lock.unlock()
        var ready = false
        defer {
            if !ready { CommandBoard.shared.end(token: token) }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice
        retainedHandles = [outPipe.fileHandleForReading, errPipe.fileHandleForReading]
        pipes = [outPipe, errPipe]
        self.process = process

        let outFD = outPipe.fileHandleForReading.fileDescriptor
        let errFD = errPipe.fileHandleForReading.fileDescriptor
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readLoop(fd: outFD, stderr: false, activity: token)
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readLoop(fd: errFD, stderr: true, activity: token)
        }
        process.terminationHandler = { [weak self] proc in
            ProcessTracker.shared.remove(proc)
            self?.noteExit(proc.terminationStatus)
        }
        ProcessTracker.shared.add(process)
        do {
            try process.run()
        } catch {
            ProcessTracker.shared.remove(process)
            releaseLock()
            throw RunnerError.launch(error.localizedDescription)
        }
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()
        ready = true
    }

    func stop() {
        lock.lock()
        stopped = true
        let proc = process
        lock.unlock()
        guard let proc, proc.isRunning else {
            // 进程已经没了，但界面和锁可能还停在“正在运行”。这里把收尾补上。
            signalDone()
            return
        }
        proc.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
        }
    }

    func wait() {
        done.wait()
    }

    deinit {
        if let proc = process, proc.isRunning {
            proc.terminate()
            kill(proc.processIdentifier, SIGKILL)
        }
        releaseLock()
        CommandBoard.shared.end(token: activityToken)
    }

    private func readLoop(fd: Int32, stderr: Bool, activity: Int) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                append(Data(buffer[0..<count]), stderr: stderr, activity: activity)
            } else {
                break
            }
        }
        markStreamEnded()
    }

    private func append(_ data: Data, stderr: Bool, activity: Int) {
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        if stderr {
            self.stderr = capped(self.stderr, text)
        } else if keepStdout {
            self.stdout = capped(self.stdout, text)
        }
        let delta = onDelta
        let change = onChange
        let now = Date()
        let publish = now.timeIntervalSince(lastPublish) > 0.08
        if publish { lastPublish = now }
        lock.unlock()
        CommandBoard.shared.note(token: activity, chunk: text)
        delta?(text, stderr)
        if publish { change?() }
    }

    private func capped(_ existing: String, _ text: String) -> String {
        var next = existing + text
        if next.count > cap {
            next = "…前文已截断…\n" + String(next.suffix(cap))
        }
        return next
    }

    private func markStreamEnded() {
        lock.lock()
        streamsOpen -= 1
        let ready = streamsOpen <= 0 && finished && !didSignal
        lock.unlock()
        if ready { signalDone() }
    }

    private func noteExit(_ code: Int32) {
        lock.lock()
        exitCode = code
        finished = true
        let ready = streamsOpen <= 0 && !didSignal
        lock.unlock()
        if ready { signalDone() }
    }

    private func signalDone() {
        lock.lock()
        if didSignal {
            lock.unlock()
            return
        }
        didSignal = true
        let change = onChange
        let token = activityToken
        lock.unlock()
        change?()
        releaseLock()
        done.signal()
        CommandBoard.shared.end(token: token)
    }

    private func releaseLock() {
        lock.lock()
        let should = acquired
        acquired = false
        lock.unlock()
        if should { RunLock.shared.release() }
    }
}

final class PTYRun: @unchecked Sendable {
    private let lock = NSLock()
    private var master: Int32 = -1
    private var process: Process?
    private var stdout = ""
    private var stderr = ""
    private var tty = ""
    private var stopped = false
    private var exitCode: Int32?
    private var finished = false
    private var didSignal = false
    private var acquired = false
    private var streamsOpen = 2
    private let cap = 400_000
    private let done = DispatchSemaphore(value: 0)
    private var onChange: (@Sendable () -> Void)?
    private var handles: [FileHandle] = []
    private var pipes: [Pipe] = []
    private var activityToken = 0

    func setChangeHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        onChange = handler
        lock.unlock()
    }

    func snapshot() -> CommandSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let complete = finished && streamsOpen <= 0
        return CommandSnapshot(
            stdout: stdout,
            stderr: stderr,
            running: !complete && process != nil,
            exitCode: complete ? exitCode : nil,
            stopped: stopped
        )
    }

    func controlText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return stdout + "\n" + stderr + "\n" + tty
    }

    func start(executable: String, arguments: [String], environment: [String: String]) throws {
        try CommandPolicy.validate(executable: executable, arguments: arguments, pseudoTerminal: true)
        guard RunLock.shared.tryAcquire() else { throw RunnerError.busyNow() }
        acquired = true
        let token = CommandBoard.shared.begin(
            title: RunningCommandTitle.make(arguments),
            commandLine: DisplayCommand.string(executable: executable, arguments: arguments),
            stop: { self.stop() }
        )
        lock.lock()
        activityToken = token
        lock.unlock()
        var ready = false
        defer {
            if !ready { CommandBoard.shared.end(token: token) }
        }

        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1
        var size = winsize()
        size.ws_row = 32
        size.ws_col = 120
        size.ws_xpixel = 0
        size.ws_ypixel = 0
        if openpty(&masterFD, &slaveFD, nil, nil, &size) != 0 {
            releaseLock()
            throw RunnerError.launch("打不开伪终端。")
        }
        var term = termios()
        if tcgetattr(slaveFD, &term) == 0 {
            term.c_iflag |= tcflag_t(ICRNL)
            term.c_lflag |= tcflag_t(ECHO | ECHOE | ECHOK | ICANON | ISIG)
            term.c_oflag |= tcflag_t(OPOST | ONLCR)
            _ = tcsetattr(slaveFD, TCSANOW, &term)
        }
        master = masterFD

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var env = environment
        env["TERM"] = "xterm-256color"
        process.environment = env
        let inputFD = dup(slaveFD)
        let input = FileHandle(fileDescriptor: inputFD, closeOnDealloc: false)
        let outPipe = Pipe()
        let errPipe = Pipe()
        handles = [input, outPipe.fileHandleForReading, errPipe.fileHandleForReading]
        pipes = [outPipe, errPipe]
        process.standardInput = input
        process.standardOutput = outPipe
        process.standardError = errPipe
        self.process = process
        let outFD = outPipe.fileHandleForReading.fileDescriptor
        let errFD = errPipe.fileHandleForReading.fileDescriptor
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readPipe(fd: outFD, stderr: false, activity: token)
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readPipe(fd: errFD, stderr: true, activity: token)
        }
        let masterCopy = masterFD
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.readMaster(masterCopy, activity: token)
        }
        process.terminationHandler = { [weak self] proc in
            ProcessTracker.shared.remove(proc)
            self?.noteExit(proc.terminationStatus)
        }
        ProcessTracker.shared.add(process)
        do {
            try process.run()
        } catch {
            Darwin.close(slaveFD)
            Darwin.close(inputFD)
            Darwin.close(masterFD)
            master = -1
            ProcessTracker.shared.remove(process)
            releaseLock()
            throw RunnerError.launch(error.localizedDescription)
        }
        Darwin.close(slaveFD)
        Darwin.close(inputFD)
        try? outPipe.fileHandleForWriting.close()
        try? errPipe.fileHandleForWriting.close()
        ready = true
    }

    func send(_ text: String) {
        lock.lock()
        let fd = master
        lock.unlock()
        guard fd >= 0 else { return }
        let bytes = Array(text.utf8)
        bytes.withUnsafeBytes { buffer in
            _ = Darwin.write(fd, buffer.baseAddress, buffer.count)
        }
    }

    func stop() {
        lock.lock()
        stopped = true
        let proc = process
        lock.unlock()
        guard let proc, proc.isRunning else {
            signalDone()
            return
        }
        proc.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) {
            if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
        }
    }

    func wait() { done.wait() }

    deinit {
        if let proc = process, proc.isRunning {
            proc.terminate()
            kill(proc.processIdentifier, SIGKILL)
        }
        if master >= 0 {
            Darwin.close(master)
            master = -1
        }
        releaseLock()
        CommandBoard.shared.end(token: activityToken)
    }

    private func readPipe(fd: Int32, stderr: Bool, activity: Int) {
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                append(Data(buffer[0..<count]), stderr: stderr, activity: activity)
            } else {
                break
            }
        }
        markStreamEnded()
    }

    private func append(_ data: Data, stderr: Bool, activity: Int) {
        let text = String(decoding: data, as: UTF8.self)
        lock.lock()
        if stderr {
            self.stderr = capped(self.stderr, text)
        } else {
            self.stdout = capped(self.stdout, text)
        }
        let change = onChange
        lock.unlock()
        CommandBoard.shared.note(token: activity, chunk: text)
        change?()
    }

    private func capped(_ existing: String, _ text: String) -> String {
        var next = existing + text
        if next.count > cap {
            next = "…前文已截断…\n" + String(next.suffix(cap))
        }
        return next
    }

    private func readMaster(_ fd: Int32, activity: Int) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count > 0 {
                let text = String(decoding: Data(buffer[0..<count]), as: UTF8.self)
                lock.lock()
                tty = capped(tty, text)
                let change = onChange
                lock.unlock()
                CommandBoard.shared.note(token: activity, chunk: text)
                change?()
            } else {
                break
            }
        }
    }

    private func markStreamEnded() {
        lock.lock()
        streamsOpen -= 1
        let ready = streamsOpen <= 0 && finished && !didSignal
        let change = onChange
        lock.unlock()
        change?()
        if ready { signalDone() }
    }

    private func noteExit(_ code: Int32) {
        lock.lock()
        exitCode = code
        finished = true
        let ready = streamsOpen <= 0 && !didSignal
        let change = onChange
        lock.unlock()
        change?()
        if ready { signalDone() }
    }

    private func signalDone() {
        lock.lock()
        if didSignal {
            lock.unlock()
            return
        }
        didSignal = true
        let fd = master
        master = -1
        let change = onChange
        let token = activityToken
        lock.unlock()
        if fd >= 0 { Darwin.close(fd) }
        change?()
        releaseLock()
        done.signal()
        CommandBoard.shared.end(token: token)
    }

    private func releaseLock() {
        lock.lock()
        let should = acquired
        acquired = false
        lock.unlock()
        if should { RunLock.shared.release() }
    }
}

enum RunKind {
    case query
    case preview
    case execute(phrase: String?)
}

@MainActor
final class CommandJob: ObservableObject {
    @Published var stdout = ""
    @Published var stderr = ""
    @Published var exitCode: Int32?
    @Published var running = false
    @Published var stopped = false
    @Published var error: String?
    @Published var acceptsExecute = false
    @Published var commandLine = ""

    var onFinish: (() -> Void)?
    private var live: LiveRun?
    private var finishNotified = false

    func start(moPath: String?, action: MoleSubcommand, kind: RunKind) {
        error = nil
        if running {
            error = "上一条命令还在运行。"
            return
        }
        guard let moPath else {
            error = "还没有找到 mo。"
            return
        }
        switch kind {
        case .preview:
            guard CommandPolicy.isPreview(action) else {
                error = "预览只能跑带 --dry-run 的命令。"
                return
            }
            acceptsExecute = false
        case .execute(let phrase):
            if let message = ExecutionGate.refuse(acceptsExecute: acceptsExecute, phrase: phrase, action: action) {
                error = message
                return
            }
            acceptsExecute = false
        case .query:
            if CommandPolicy.isExecute(action) || CommandPolicy.isPreview(action) {
                error = "查询不能用来执行清理。"
                return
            }
        }

        let arguments: [String]
        do {
            arguments = try CommandPolicy.plan(executable: moPath, action: action, pseudoTerminal: false)
        } catch {
            self.error = error.localizedDescription
            return
        }

        let run = LiveRun()
        live = run
        commandLine = DisplayCommand.string(executable: moPath, arguments: arguments)
        stdout = ""
        stderr = ""
        exitCode = nil
        stopped = false
        running = true
        finishNotified = false
        let armPreview: Bool
        if case .preview = kind { armPreview = true } else { armPreview = false }
        run.setChangeHandler { [weak self, weak run] in
            DispatchQueue.main.async {
                guard let self, let run else { return }
                self.pull(run, armPreview: armPreview)
            }
        }
        do {
            try run.start(
                executable: moPath,
                arguments: arguments,
                environment: MoleEnvironment.make(moPath: moPath)
            )
        } catch {
            running = false
            self.error = error.localizedDescription
            live = nil
        }
    }

    func stop() {
        live?.stop()
        stopped = true
    }

    private func pull(_ run: LiveRun, armPreview: Bool) {
        let snap = run.snapshot()
        stdout = snap.stdout
        stderr = snap.stderr
        stopped = snap.stopped || stopped
        if let code = snap.exitCode {
            exitCode = code
            running = false
            if armPreview, code == 0, !snap.stopped {
                acceptsExecute = true
            }
            if !finishNotified {
                finishNotified = true
                onFinish?()
            }
        } else {
            running = snap.running
        }
    }
}

@MainActor
final class PTYJob: ObservableObject {
    @Published var stdout = ""
    @Published var stderr = ""
    @Published var running = false
    @Published var exitCode: Int32?
    @Published var error: String?
    @Published var commandLine = ""
    @Published var stopped = false

    var onFinish: (() -> Void)?
    private var live: PTYRun?
    private var confirmArmed = false
    private var finishNotified = false

    func start(moPath: String?, names: [String]) {
        error = nil
        guard let moPath else {
            error = "还没有找到 mo。"
            return
        }
        if running {
            error = "卸载还在进行。"
            return
        }
        let arguments: [String]
        do {
            arguments = try CommandPolicy.plan(
                executable: moPath,
                action: .uninstallLive(names: names),
                pseudoTerminal: true
            )
        } catch {
            self.error = error.localizedDescription
            return
        }
        let run = PTYRun()
        live = run
        confirmArmed = false
        finishNotified = false
        stdout = ""
        stderr = ""
        exitCode = nil
        stopped = false
        running = true
        commandLine = DisplayCommand.string(executable: moPath, arguments: arguments)
        run.setChangeHandler { [weak self, weak run] in
            DispatchQueue.main.async {
                guard let self, let run else { return }
                self.pull(run)
            }
        }
        do {
            try run.start(
                executable: moPath,
                arguments: arguments,
                environment: MoleEnvironment.make(moPath: moPath)
            )
        } catch {
            running = false
            self.error = error.localizedDescription
            live = nil
        }
    }

    func stop() {
        stopped = true
        live?.stop()
    }

    private func pull(_ run: PTYRun) {
        let snap = run.snapshot()
        stdout = UninstallLog.visible(snap.stdout)
        stderr = UninstallLog.visible(snap.stderr)
        stopped = snap.stopped || stopped
        if !confirmArmed, UninstallLog.awaitsConfirm(run.controlText()) {
            confirmArmed = true
            // CLI 先清掉已经排队的按键，再读确认。等这次清空结束再回车。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.running else { return }
                self.live?.send("\r")
            }
        }
        if let code = snap.exitCode {
            exitCode = code
            running = false
            if !finishNotified {
                finishNotified = true
                onFinish?()
            }
        } else {
            running = snap.running
        }
    }
}
