import Darwin
import Foundation
import Testing
@testable import MoleGUIKit

@Suite struct LocatorTests {
    let fixtures: Fixtures

    init() throws {
        fixtures = try Fixtures()
    }

    @Test func 拒绝路径里带sudo的mo() throws {
        let path = try fixtures.makeMo(directory: "sudo", body: "#!/bin/sh\necho no\n")
        #expect(!MoleLocator.accept(path: path))
    }

    @Test func 接受可执行的mo() throws {
        #expect(MoleLocator.accept(path: try fixtures.echo()))
    }

    @Test func 拒绝不叫mo的程序() throws {
        let path = try fixtures.makeMo(named: "mole", directory: "not-mo", body: "#!/bin/sh\necho no\n")
        #expect(!MoleLocator.accept(path: path))
    }
}

@Suite struct CommandPolicyTests {
    let fixtures: Fixtures
    let echo: String

    init() throws {
        fixtures = try Fixtures()
        echo = try fixtures.echo()
    }

    @Test func 参数() throws {
        #expect(try CommandPolicy.arguments(for: .clean) == ["clean"])
        #expect(try CommandPolicy.arguments(for: .cleanDryRun) == ["clean", "--dry-run"])
        #expect(try CommandPolicy.arguments(for: .purgeYes) == ["purge", "--yes"])
        #expect(try CommandPolicy.arguments(for: .statusWatch) == ["status", "--watch", "--interval", "2s"])
        #expect(try CommandPolicy.arguments(for: .history) == ["history", "--json", "--limit", "50"])
        #expect(try CommandPolicy.arguments(for: .analyze(path: "/tmp")) == ["analyze", "--json", "/tmp"])
    }

    @Test(arguments: [
        ["clean", "--permanent"],
        ["sudo", "clean"],
        [],
        ["installer"],
        ["slim"],
        ["touchid", "enable"],
        ["update"],
        ["remove"],
        ["analyze", "--json", "-rf"],
    ])
    func 拒绝危险参数(arguments: [String]) {
        #expect(throws: (any Error).self) {
            try CommandPolicy.validate(executable: echo, arguments: arguments, pseudoTerminal: false)
        }
    }

    @Test func 拒绝withData() {
        #expect(throws: (any Error).self) {
            try CommandPolicy.validate(executable: echo, arguments: ["uninstall", "--with-data", "Slack"], pseudoTerminal: true)
        }
    }

    @Test func 拒绝sudo可执行文件() {
        #expect(throws: (any Error).self) {
            try CommandPolicy.validate(executable: "/usr/bin/sudo", arguments: ["clean"], pseudoTerminal: false)
        }
    }

    @Test func 卸载实跑必须在伪终端() {
        #expect(throws: (any Error).self) {
            try CommandPolicy.validate(executable: echo, arguments: ["uninstall", "Slack"], pseudoTerminal: false)
        }
    }

    @Test func 卸载实跑参数保留空格() throws {
        let live = try CommandPolicy.plan(executable: echo, action: .uninstallLive(names: ["My App"]), pseudoTerminal: true)
        #expect(live == ["uninstall", "My App"])
        #expect(DisplayCommand.string(executable: echo, arguments: live).contains("'My App'"))
    }

    @Test func 卸载名字不能是开关() {
        #expect(throws: (any Error).self) {
            _ = try CommandPolicy.arguments(for: .uninstallDryRun(names: ["--permanent"]))
        }
    }

    @Test func 分析路径必须存在() {
        #expect(throws: (any Error).self) {
            _ = try CommandPolicy.arguments(for: .analyze(path: "/tmp/mole-gui-missing-\(getpid())"))
        }
    }

    @Test func 执行门槛() {
        #expect(ExecutionGate.refuse(acceptsExecute: false, phrase: nil, action: .clean) != nil, "没预览不能清理")
        #expect(ExecutionGate.refuse(acceptsExecute: true, phrase: nil, action: .clean) == nil, "预览后可以清理")
        #expect(ExecutionGate.refuse(acceptsExecute: true, phrase: "删除", action: .purgeYes) != nil, "确认语不对不能 purge")
        #expect(ExecutionGate.refuse(acceptsExecute: true, phrase: "永久删除", action: .purgeYes) == nil, "确认语正确可以 purge")
        #expect(ExecutionGate.refuse(acceptsExecute: true, phrase: nil, action: .cleanDryRun) != nil, "预览命令不能当执行")
    }

    @Test func 卸载启动条件() {
        #expect(UninstallLaunch.canStart(moFound: true, terminalRunning: false, names: ["Tailscale"]))
        #expect(!UninstallLaunch.canStart(moFound: true, terminalRunning: false, names: []), "没选中不能卸载")
        #expect(!UninstallLaunch.canStart(moFound: false, terminalRunning: false, names: ["Tailscale"]), "没有 mo 不能卸载")
        #expect(!UninstallLaunch.canStart(moFound: true, terminalRunning: true, names: ["Tailscale"]), "卸载进行中不能再开")
    }
}

@Suite struct FormatTests {
    @Test func 大小与文案() {
        #expect(Format.bytes(1536, partial: true) == "1.5 KB+")
        #expect(Format.bytes(0, scanStatus: "unavailable") == "无法读取")
        #expect(Format.bytes(2048, scanStatus: "partial").hasSuffix("+"))
        #expect(Format.ended("") == "没有记下结束")
        #expect(Format.ended(nil) == "没有记下结束")
        #expect(Format.attribution("ambiguous") == "归属不确定")
    }
}

@Suite struct TerminalTextTests {
    @Test(arguments: [
        ("hello\r\nworld", "hello\nworld"),
        ("abc\rXYZ", "XYZ"),
        ("\u{1B}[31m红色\u{1B}[0m", "红色"),
    ])
    func 终端缓冲(input: String, expected: String) {
        var buffer = TerminalBuffer()
        buffer.ingest(input)
        #expect(buffer.text == expected)
    }

    @Test func 卸载确认提示() {
        let prompt = """
        Files to be removed:
        Demo
        \u{1B}[90mD\u{1B}[0m choose personal data
        Remove 1 app  \u{1B}[32mEnter\u{1B}[0m confirm, \u{1B}[90mESC\u{1B}[0m cancel: 
        """
        #expect(UninstallLog.awaitsConfirm(prompt))
        #expect(!UninstallLog.awaitsConfirm("Dry run complete; no apps were removed."))
        let shown = UninstallLog.visible(prompt)
        #expect(shown.contains("Files to be removed"))
        #expect(shown.contains("Demo"))
        #expect(!shown.lowercased().contains("enter confirm"))
        #expect(!shown.lowercased().contains("choose personal data"))
        #expect(!UninstallLog.visible("Press Enter to return to the app list, press q to exit (5) ").lowercased().contains("press enter"))
    }
}

@Suite struct ParsingTests {
    @Test func 状态() {
        let status = StatusReport.parse("""
        noise
        {"health_score": 88, "health_score_msg": "良好", "host": "mbp", "uptime": "3 days",
         "cpu": {"usage": 12.5, "load1": 1.2},
         "memory": {"used": 1024, "total": 2048, "used_percent": 50, "pressure": "normal"},
         "disks": [{"mount": "/", "used": 10, "total": 20, "used_percent": 50, "external": false, "smart_status": "Verified"}],
         "top_processes": [{"pid": 1, "name": "launchd", "cpu": 0.1, "memory_bytes": 4096}],
         "zombie_count": 2}
        """)
        #expect(status?.healthScore == 88)
        #expect(status?.cpu?.usage == 12.5)
        #expect(status?.memory?.pressure == "normal")
        #expect(status?.disks.first?.mount == "/")
        #expect(status?.zombieCount == 2)
        #expect(status?.topProcesses.first?.name == "launchd")
    }

    @Test func 分析() {
        let analyze = AnalyzeReport.parse("""
        {"scan_status":"partial","path":"/Users/me","overview":false,"total_size":30,"total_files":2,
         "entries":[
          {"name":"Code","path":"/Users/me/Code","size":20,"is_dir":true,"scan_status":"partial"},
          {"name":"Secret","path":"/Users/me/Secret","size":0,"is_dir":true,"scan_status":"unavailable"}
         ],
         "large_files":[{"name":"disk.img","path":"/Users/me/disk.img","size":10}]}
        """)
        #expect(analyze?.scanStatus == "partial")
        #expect(analyze?.entries.count == 2)
        #expect(analyze?.entries.last?.scanStatus == "unavailable")
        #expect(analyze?.largeFiles.first?.size == 10)
    }

    @Test func 卸载列表() {
        let apps = UninstallApp.parse(#"[{"name":"Slack","bundle_id":"com.slack","source":"App","uninstall_name":"Slack","path":"/Applications/Slack.app","size":"1.2 GB"}]"#)
        #expect(apps?.first?.uninstallName == "Slack")
        #expect(apps?.first?.source == "App")
    }

    @Test func 历史() {
        let history = HistoryReport.parse(#"""
        {"limit":50,"sessions":[{"command":"clean","run_id":"","attribution":"ambiguous","started_at":"t0","ended_at":"","items":1,"size":"1MB","operation_count":1,"failed_tasks":0,"actions":{"removed":1,"trashed":0,"skipped":0,"failed":0,"rebuilt":0,"other":0}}],"deletions":[{"timestamp":"t1","mode":"remove","status":"success","size_kb":null,"path":"/tmp/a"}]}
        """#)
        #expect(history?.sessions.first?.attribution == "ambiguous")
        #expect(history?.sessions.first?.endedAt == "")
        #expect(history?.deletions.first?.path == "/tmp/a")
        #expect(history?.deletions.first?.sizeKb == nil)
    }
}
