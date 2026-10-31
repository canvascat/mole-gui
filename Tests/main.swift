import Darwin
import Foundation

setvbuf(stdout, nil, _IONBF, 0)

var failures: [String] = []

func expect(_ condition: Bool, _ name: String, _ detail: String = "") {
    if condition {
        print("ok  \(name)")
    } else {
        let line = detail.isEmpty ? name : "\(name): \(detail)"
        failures.append(line)
        print("FAIL \(line)")
    }
}

func expectThrows(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
        expect(false, name, "应该失败")
    } catch {
        expect(true, name)
    }
}

let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mole-gui-tests-\(getpid())")
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }

func makeMo(named name: String = "mo", directory: String, body: String) throws -> String {
    let dir = root.appendingPathComponent(directory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let path = dir.appendingPathComponent(name).path
    try body.write(toFile: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
    return path
}

let echo = try makeMo(directory: "echo", body: """
#!/bin/sh
echo "stdout:$*"
echo "stderr:$*" >&2
exit 0
""")

let marker = root.appendingPathComponent("ran").path
let markerScript = try makeMo(directory: "marker", body: """
#!/bin/sh
echo ran > "\(marker)"
echo "args:$*"
exit 0
""")

let sleeper = try makeMo(directory: "sleep", body: """
#!/bin/sh
echo start
sleep 30
echo done
""")

let ptyScript = try makeMo(directory: "pty", body: """
#!/bin/sh
if [ -t 0 ]; then
  echo READY
  IFS= read -r line || exit 2
  echo "LINE:$line"
  exit 0
else
  echo NO-TTY
  exit 3
fi
""")

let sudoDir = try makeMo(directory: "sudo", body: "#!/bin/sh\necho no\n")
expect(!MoleLocator.accept(path: sudoDir), "拒绝路径里带 sudo 的 mo")
expect(MoleLocator.accept(path: echo), "接受可执行的 mo")
let notMo = try makeMo(named: "mole", directory: "not-mo", body: "#!/bin/sh\necho no\n")
expect(!MoleLocator.accept(path: notMo), "拒绝不叫 mo 的程序")

expect(try CommandPolicy.arguments(for: .clean) == ["clean"], "clean 参数")
expect(try CommandPolicy.arguments(for: .cleanDryRun) == ["clean", "--dry-run"], "clean 预览参数")
expect(try CommandPolicy.arguments(for: .purgeYes) == ["purge", "--yes"], "purge --yes 参数")
expect(try CommandPolicy.arguments(for: .statusWatch) == ["status", "--watch", "--interval", "2s"], "status watch 参数")
expect(try CommandPolicy.arguments(for: .history) == ["history", "--json", "--limit", "50"], "history 参数")
expect(try CommandPolicy.arguments(for: .analyze(path: "/tmp")) == ["analyze", "--json", "/tmp"], "analyze 参数")

expectThrows("拒绝 --permanent") {
    try CommandPolicy.validate(executable: echo, arguments: ["clean", "--permanent"], pseudoTerminal: false)
}
expectThrows("拒绝 --with-data") {
    try CommandPolicy.validate(executable: echo, arguments: ["uninstall", "--with-data", "Slack"], pseudoTerminal: true)
}
expectThrows("拒绝 sudo 参数") {
    try CommandPolicy.validate(executable: echo, arguments: ["sudo", "clean"], pseudoTerminal: false)
}
expectThrows("拒绝 sudo 可执行文件") {
    try CommandPolicy.validate(executable: "/usr/bin/sudo", arguments: ["clean"], pseudoTerminal: false)
}
expectThrows("拒绝裸命令") {
    try CommandPolicy.validate(executable: echo, arguments: [], pseudoTerminal: false)
}
expectThrows("拒绝 installer") {
    try CommandPolicy.validate(executable: echo, arguments: ["installer"], pseudoTerminal: false)
}
expectThrows("拒绝 slim") {
    try CommandPolicy.validate(executable: echo, arguments: ["slim"], pseudoTerminal: false)
}
expectThrows("拒绝 touchid") {
    try CommandPolicy.validate(executable: echo, arguments: ["touchid", "enable"], pseudoTerminal: false)
}
expectThrows("拒绝 update") {
    try CommandPolicy.validate(executable: echo, arguments: ["update"], pseudoTerminal: false)
}
expectThrows("拒绝 remove") {
    try CommandPolicy.validate(executable: echo, arguments: ["remove"], pseudoTerminal: false)
}
expectThrows("卸载实跑必须在伪终端") {
    try CommandPolicy.validate(executable: echo, arguments: ["uninstall", "Slack"], pseudoTerminal: false)
}
let live = try CommandPolicy.plan(executable: echo, action: .uninstallLive(names: ["My App"]), pseudoTerminal: true)
expect(live == ["uninstall", "My App"], "卸载实跑参数保留空格", live.joined(separator: "|"))
expectThrows("卸载名字不能是开关") {
    _ = try CommandPolicy.arguments(for: .uninstallDryRun(names: ["--permanent"]))
}
expectThrows("分析路径必须存在") {
    _ = try CommandPolicy.arguments(for: .analyze(path: "/tmp/mole-gui-missing-\(getpid())"))
}
expectThrows("分析路径不能是开关") {
    try CommandPolicy.validate(executable: echo, arguments: ["analyze", "--json", "-rf"], pseudoTerminal: false)
}

expect(ExecutionGate.refuse(acceptsExecute: false, phrase: nil, action: .clean) != nil, "没预览不能清理")
expect(ExecutionGate.refuse(acceptsExecute: true, phrase: nil, action: .clean) == nil, "预览后可以清理")
expect(ExecutionGate.refuse(acceptsExecute: true, phrase: "删除", action: .purgeYes) != nil, "确认语不对不能 purge")
expect(ExecutionGate.refuse(acceptsExecute: true, phrase: "永久删除", action: .purgeYes) == nil, "确认语正确可以 purge")
expect(ExecutionGate.refuse(acceptsExecute: true, phrase: nil, action: .cleanDryRun) != nil, "预览命令不能当执行")
expect(UninstallLaunch.canStart(moFound: true, terminalRunning: false, names: ["Tailscale"]), "选中后可以在伪终端中卸载")
expect(!UninstallLaunch.canStart(moFound: true, terminalRunning: false, names: []), "没选中不能卸载")
expect(!UninstallLaunch.canStart(moFound: false, terminalRunning: false, names: ["Tailscale"]), "没有 mo 不能卸载")
expect(!UninstallLaunch.canStart(moFound: true, terminalRunning: true, names: ["Tailscale"]), "卸载进行中不能再开")

expect(Format.bytes(1536, partial: true) == "1.5 KB+", "未完成大小带加号", Format.bytes(1536, partial: true))
expect(Format.bytes(0, scanStatus: "unavailable") == "无法读取", "0 且无法读取")
expect(Format.bytes(2048, scanStatus: "partial").hasSuffix("+"), "partial 带加号")
expect(Format.ended("") == "没有记下结束", "空结束时间")
expect(Format.ended(nil) == "没有记下结束", "缺少结束时间")
expect(Format.attribution("ambiguous") == "归属不确定", "归属文案")

var buffer = TerminalBuffer()
buffer.ingest("hello\r\nworld")
expect(buffer.text == "hello\nworld", "CRLF", buffer.text)
buffer = TerminalBuffer()
buffer.ingest("abc\rXYZ")
expect(buffer.text == "XYZ", "回车覆盖", buffer.text)
buffer = TerminalBuffer()
buffer.ingest("\u{1B}[31m红色\u{1B}[0m")
expect(buffer.text == "红色", "去掉 ANSI", buffer.text)

let promptSample = """
Files to be removed:
Demo
\u{1B}[90mD\u{1B}[0m choose personal data
Remove 1 app  \u{1B}[32mEnter\u{1B}[0m confirm, \u{1B}[90mESC\u{1B}[0m cancel: 
"""
expect(UninstallLog.awaitsConfirm(promptSample), "识别卸载确认提示")
expect(!UninstallLog.awaitsConfirm("Dry run complete; no apps were removed."), "预览不是确认")
let shownPrompt = UninstallLog.visible(promptSample)
expect(shownPrompt.contains("Files to be removed"), "日志保留卸载计划", shownPrompt)
expect(shownPrompt.contains("Demo"), "日志保留应用名", shownPrompt)
expect(!shownPrompt.lowercased().contains("enter confirm"), "日志不含确认提示", shownPrompt)
expect(!shownPrompt.lowercased().contains("choose personal data"), "日志不含 D 提示", shownPrompt)
expect(!UninstallLog.visible("Press Enter to return to the app list, press q to exit (5) ").lowercased().contains("press enter"), "日志不含返回列表提示")

let statusJSON = """
noise
{"health_score": 88, "health_score_msg": "良好", "host": "mbp", "uptime": "3 days",
 "cpu": {"usage": 12.5, "load1": 1.2},
 "memory": {"used": 1024, "total": 2048, "used_percent": 50, "pressure": "normal"},
 "disks": [{"mount": "/", "used": 10, "total": 20, "used_percent": 50, "external": false, "smart_status": "Verified"}],
 "top_processes": [{"pid": 1, "name": "launchd", "cpu": 0.1, "memory_bytes": 4096}],
 "zombie_count": 2}
"""
let status = StatusReport.parse(statusJSON)
expect(status?.healthScore == 88, "解析健康分")
expect(status?.cpu?.usage == 12.5, "解析 CPU")
expect(status?.memory?.pressure == "normal", "解析内存压力")
expect(status?.disks.first?.mount == "/", "解析磁盘")
expect(status?.zombieCount == 2, "解析僵尸进程")
expect(status?.topProcesses.first?.name == "launchd", "解析进程")

let analyzeJSON = """
{"scan_status":"partial","path":"/Users/me","overview":false,"total_size":30,"total_files":2,
 "entries":[
  {"name":"Code","path":"/Users/me/Code","size":20,"is_dir":true,"scan_status":"partial"},
  {"name":"Secret","path":"/Users/me/Secret","size":0,"is_dir":true,"scan_status":"unavailable"}
 ],
 "large_files":[{"name":"disk.img","path":"/Users/me/disk.img","size":10}]}
"""
let analyze = AnalyzeReport.parse(analyzeJSON)
expect(analyze?.scanStatus == "partial", "解析扫描状态")
expect(analyze?.entries.count == 2, "解析条目")
expect(analyze?.entries.last?.scanStatus == "unavailable", "解析无法读取")
expect(analyze?.largeFiles.first?.size == 10, "解析大文件")

let apps = UninstallApp.parse(#"[{"name":"Slack","bundle_id":"com.slack","source":"App","uninstall_name":"Slack","path":"/Applications/Slack.app","size":"1.2 GB"}]"#)
expect(apps?.first?.uninstallName == "Slack", "解析卸载名字")
expect(apps?.first?.source == "App", "解析来源")

let history = HistoryReport.parse(#"""
{"limit":50,"sessions":[{"command":"clean","run_id":"","attribution":"ambiguous","started_at":"t0","ended_at":"","items":1,"size":"1MB","operation_count":1,"failed_tasks":0,"actions":{"removed":1,"trashed":0,"skipped":0,"failed":0,"rebuilt":0,"other":0}}],"deletions":[{"timestamp":"t1","mode":"remove","status":"success","size_kb":null,"path":"/tmp/a"}]}
"""#)
expect(history?.sessions.first?.attribution == "ambiguous", "解析归属")
expect(history?.sessions.first?.endedAt == "", "空结束标记")
expect(history?.deletions.first?.path == "/tmp/a", "解析删除路径")
expect(history?.deletions.first?.sizeKb == nil, "空 size_kb")

let quoted = DisplayCommand.string(executable: echo, arguments: live)
expect(quoted.contains("'My App'"), "显示命令给带空格的名字加引号", quoted)

let run = LiveRun()
let args = try CommandPolicy.plan(executable: echo, action: .version, pseudoTerminal: false)
try run.start(executable: echo, arguments: args, environment: MoleEnvironment.make(moPath: echo))
run.wait()
let snap = run.snapshot()
expect(snap.exitCode == 0, "分开收取退出码", "\(snap.exitCode ?? -1)")
expect(snap.stdout.contains("stdout:version"), "标准输出", snap.stdout)
expect(snap.stderr.contains("stderr:version"), "标准错误", snap.stderr)

expectThrows("永久参数不会启动进程") {
    try LiveRun().start(executable: markerScript, arguments: ["clean", "--permanent"], environment: [:])
}
expect(!FileManager.default.fileExists(atPath: marker), "被拒绝的命令没有写标记")

let first = LiveRun()
try first.start(
    executable: sleeper,
    arguments: try CommandPolicy.arguments(for: .version),
    environment: MoleEnvironment.make(moPath: sleeper)
)
var secondError: Error?
do {
    try LiveRun().start(
        executable: echo,
        arguments: ["version"],
        environment: MoleEnvironment.make(moPath: echo)
    )
} catch {
    secondError = error
}
expect(secondError != nil, "同时只能有一条 mo")
first.stop()
first.wait()
let third = LiveRun()
try third.start(executable: echo, arguments: ["version"], environment: MoleEnvironment.make(moPath: echo))
third.wait()
expect(third.snapshot().exitCode == 0, "上一条结束后可以再跑")

let pty = PTYRun()
try pty.start(
    executable: ptyScript,
    arguments: try CommandPolicy.plan(executable: ptyScript, action: .uninstallLive(names: ["Demo"]), pseudoTerminal: true),
    environment: MoleEnvironment.make(moPath: ptyScript)
)
var sawReady = false
for _ in 0..<40 {
    if pty.snapshot().stdout.contains("READY") {
        sawReady = true
        break
    }
    Thread.sleep(forTimeInterval: 0.05)
}
expect(sawReady, "伪终端被认成终端", pty.snapshot().stdout)
pty.send("y\r")
pty.wait()
let ptySnap = pty.snapshot()
expect(ptySnap.stdout.contains("LINE:y"), "伪终端收到确认", ptySnap.stdout)
expect(!ptySnap.stdout.contains("NO-TTY"), "伪终端不是管道")

let confirmScript = try makeMo(directory: "confirm", body: """
#!/bin/sh
if [ ! -t 0 ]; then
  echo NO-TTY
  exit 3
fi
printf 'Files to be removed:\\nDemo\\n'
printf 'D choose personal data\\n'
printf 'Enter confirm, ESC cancel: '
IFS= read -r line || exit 2
printf '\\nDONE\\n'
exit 0
""")
let confirmJob = MainActor.assumeIsolated { PTYJob() }
MainActor.assumeIsolated {
    confirmJob.start(
        moPath: confirmScript,
        names: ["Demo"]
    )
}
let confirmDeadline = Date().addingTimeInterval(3)
while Date() < confirmDeadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    let finished = MainActor.assumeIsolated { confirmJob.stdout.contains("DONE") || confirmJob.exitCode != nil }
    if finished { break }
}
let confirmOut = MainActor.assumeIsolated { confirmJob.stdout }
let confirmErr = MainActor.assumeIsolated { confirmJob.stderr }
let confirmCode = MainActor.assumeIsolated { confirmJob.exitCode }
if confirmCode == nil {
    MainActor.assumeIsolated { confirmJob.stop() }
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
}
expect(confirmOut.contains("DONE"), "确认后自动应答卸载", confirmOut + confirmErr)
expect(!confirmOut.lowercased().contains("enter confirm"), "标准输出不显示确认提示", confirmOut)
expect(!confirmOut.lowercased().contains("choose personal data"), "标准输出不显示 D 提示", confirmOut)
expect(!confirmErr.lowercased().contains("enter confirm"), "标准错误不显示确认提示", confirmErr)
expect(confirmOut.contains("Files to be removed"), "标准输出保留卸载计划", confirmOut)
expect(!confirmOut.contains("NO-TTY"), "卸载输入仍是终端")

if failures.isEmpty {
    print("all tests passed")
} else {
    print("\(failures.count) failed")
    exit(1)
}
