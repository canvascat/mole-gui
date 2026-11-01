import Darwin
import Foundation
import os
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
        #expect(status?.gpu.isEmpty == true)
        #expect(status?.network.isEmpty == true)
    }

    @Test func 状态卡片字段() {
        let status = StatusReport.parse("""
        {"health_score":74,"health_score_msg":"Good: memory pressure","uptime_seconds":2847600,
         "procs":152,"hardware":{"cpu_model":"Apple M4","total_ram":"16.0 GB","os_version":"macOS 27.0.1"},
         "cpu":{"usage":34,"per_core":[10,20],"logical_cpu":10,"load1":5.2},
         "gpu":[{"name":"Apple M4","usage":-1}],
         "thermal":{"cpu_temp":0,"gpu_temp":0},
         "disk_io":{"read_rate":110,"write_rate":0.0005},
         "disks":[{"mount":"/","used":204000000000,"total":245000000000,"used_percent":83}],
         "network":[{"name":"en1","rx_rate_mbs":0.009,"tx_rate_mbs":0.001,"ip":"192.168.1.2"}],
         "network_history":{"rx_history":[0.1,0.2],"tx_history":[0.1]}}
        """)
        #expect(status?.procs == 152)
        #expect(status?.cpu?.perCore?.count == 2)
        #expect(status?.gpu.first?.usage == -1)
        #expect(status?.diskIO?.readRate == 110)
        #expect(status?.network.first?.name == "en1")
        #expect(status?.networkHistory?.rxHistory.count == 2)
        #expect(status?.thermal?.cpuTemp == 0)
        #expect(Format.healthGrade(74) == "良好")
        #expect(Format.healthNote(message: "Good: memory pressure", pressure: "warn") == "内存压力偏高")
        #expect(Format.healthNote(message: "Excellent: Restart Recommended", pressure: "") == "建议重启")
        #expect(Format.uptimeLabel(seconds: 2_847_600, raw: nil) == "已运行 32 天 23 小时")
        #expect(Format.rateMBps(110) == "110 MB/s")
        #expect(Format.rateMBps(0.0005) == "<1 KB/s")
        #expect(Format.storageBytes(245_000_000_000) == "245 GB")
        #expect(Format.chipLabel("Apple M4") == "M4")
        #expect(Format.ramLabel("16.0 GB") == "16 GB")
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

    @Test func 清理扫描过程() {
        let steps = CleanScanProgress.parse("""
        Clean Your Mac
        Dry Run Mode, Preview only, no deletions
        ➤ User essentials
          → Homebrew cache · 1.87GB dry
        \u{1B}[32m✓\u{1B}[0m Nothing to clean
        ➤ App caches
          → WeChat cache · 12.0MB dry
          → Telegram cache · 4MB dry
        """)
        #expect(steps.map(\.title) == ["用户缓存", "App 缓存"])
        #expect(steps[0].state == .done)
        #expect(steps[0].items == 1)
        #expect(steps[0].latest == "Homebrew cache")
        #expect(steps[1].state == .running)
        #expect(steps[1].items == 2)
        #expect(steps[1].latest == "Telegram cache")
    }

    @Test func 清理清单按类解析() {
        let home = NSHomeDirectory()
        let text = """
        # Mole Cleanup Preview
        === User essentials ===
        \(home)/Library/Caches/Google  # 2.44GB
        \(home)/Library/Caches/Google/Chrome  # 1.70GB, counted under \(home)/Library/Caches/Google
        === Developer tools ===
        \(home)/Library/Developer/Xcode/DerivedData/App  # 188.4MB, 2 items
        === App leftovers ===
        \(home)/Library/Application Support/OldApp  # size unknown
        === System ===
        /Library/Caches/com.apple.iconservices  # 12KB
        === Mystery ===
        \(home)/Library/Caches/Custom/Tool  # 8KB

        """
        let entries = CleanPlan.parse(text)
        #expect(entries.map(\.path) == [
            home + "/Library/Caches/Google",
            home + "/Library/Developer/Xcode/DerivedData/App",
            home + "/Library/Application Support/OldApp",
            "/Library/Caches/com.apple.iconservices",
            home + "/Library/Caches/Custom/Tool",
        ])
        #expect(entries[0].sizeBytes == 2_440_000_000)
        #expect(entries[0].recommended)
        #expect(entries[2].sizeBytes == nil)
        #expect(!entries[2].recommended)
        #expect(!entries[3].deletable)
        #expect(entries[1].deletable)
        let catalog = CleanPlan.catalog(entries)
        #expect(catalog.groups.map(\.title) == ["App 缓存与日志", "开发工具", "卸载残留", "系统数据", "其他"])
        let roots = CleanPlan.deletionRoots([
            home + "/Library/Caches/Google",
            home + "/Library/Caches/Google/Chrome",
            home + "/Library/Caches/Arc",
        ])
        #expect(roots.sorted() == [
            home + "/Library/Caches/Arc",
            home + "/Library/Caches/Google",
        ].sorted())
        #expect(!CleanPlan.deletable(home + "/Library/Caches"))
        #expect(!CleanPlan.deletable(home))
        #expect(CleanPlan.decimalLabel(0) == "0 B")
    }

    @Test func 卸载后的相关文件() {
        let home = NSHomeDirectory()
        let kept = home + "/Library/Preferences/io.tailscale.ipn.macsys.plist"
        let cache = home + "/Library/Caches/io.tailscale.ipn.macsys"
        let support = home + "/Library/Application Support/Tailscale"
        let log = """
        Files to be removed:
        ✓ Tailscale , 80.2 MB
          /Applications/Tailscale.app , 75 MB
          \(cache) , 4.7 MB
          \(support) , 90 KB
        Personal data kept:
          ⊙ ~/Library/Preferences/io.tailscale.ipn.macsys.plist
          ⊙ ~/Library/HTTPStorages/io.tailscale.ipn.macsys.binarycookies
        System: /Library/LaunchDaemons/com.tailscale.plist
        Review only: /Library/SystemExtensions/io.tailscale
        Cleaning files for Tailscale...
        \(home)/Library/Logs/should-not-appear
        """
        let paths = LeftoverPlan.paths(in: log, excludingAppPaths: ["/Applications/Tailscale.app"])
        #expect(paths == [
            cache,
            support,
            kept,
            home + "/Library/HTTPStorages/io.tailscale.ipn.macsys.binarycookies",
        ])
        let files = LeftoverPlan.collect(
            log: log,
            excludingAppPaths: ["/Applications/Tailscale.app"],
            exists: { $0 == kept || $0 == support },
            measure: { $0 == support ? 90 * 1024 : 0 }
        )
        #expect(files.map(\.path) == [support, kept])
        #expect(files[0].name == "Tailscale")
        #expect(files[0].sizeLabel == "90.0 KB")
        #expect(files[1].sizeLabel == "空")
        #expect(!LeftoverPlan.allowed("/Applications/Tailscale.app"))
        #expect(!LeftoverPlan.allowed(home + "/Library"))
        #expect(!LeftoverPlan.allowed("/private/var/folders/ab"))
        #expect(LeftoverPlan.allowed("/private/var/folders/ab/cd/T/io.tailscale.ipn.macsys"))
        #expect(!LeftoverPlan.allowed(home + "/Library/../../etc/passwd"))
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

@Suite struct RunningCommandTests {
    @Test func 命令标题() {
        #expect(RunningCommandTitle.make(["version"]) == "正在确认 Mole 版本")
        #expect(RunningCommandTitle.make(["status", "--watch", "--interval", "2s"]) == "正在读取本机状态")
        #expect(RunningCommandTitle.make(["clean", "--dry-run"]) == "正在扫描可清理的文件")
        #expect(RunningCommandTitle.make(["clean"]) == "正在清理")
        #expect(RunningCommandTitle.make(["uninstall", "--list"]) == "正在列出可卸载的应用")
        #expect(RunningCommandTitle.make(["uninstall", "--dry-run", "Demo"]) == "正在预览卸载")
        #expect(RunningCommandTitle.make(["uninstall", "Demo"]) == "正在卸载")
        #expect(RunningCommandTitle.make(["analyze", "--json", "/"]) == "正在分析磁盘占用")
        #expect(RunningCommandTitle.make(["purge", "--yes"]) == "正在清理项目产物")
        #expect(RunningCommandTitle.make(["optimize"]) == "正在执行维护")
        #expect(RunningCommandTitle.make(["history"]) == "正在读取操作记录")
        #expect(RunningCommandTitle.detail(in: ["", "➤ User essentials", "{\"health\":1}", "\"health_score\": 85", ""]) == "➤ User essentials")
        #expect(RunningCommandTitle.detail(in: ["{\"health\":1}"]) == "")
    }

    @Test func 活动板记录当前命令并停止() {
        let board = CommandBoard()
        let hits = OSAllocatedUnfairLock(initialState: 0)
        let token = board.begin(title: "正在卸载", commandLine: "mo uninstall Demo", stop: {
            hits.withLock { $0 += 1 }
        })
        #expect(board.current().running)
        #expect(board.current().title == "正在卸载")
        #expect(board.current().commandLine == "mo uninstall Demo")
        board.note(token: token, chunk: "Removing Demo\n")
        #expect(board.current().detail == "Removing Demo")
        board.note(token: token, chunk: "{\"skip\":true}\n")
        #expect(board.current().detail == "Removing Demo")
        board.requestStop()
        #expect(hits.withLock { $0 } == 1)
        board.end(token: token)
        #expect(!board.current().running)
        board.end(token: token)
        #expect(!board.current().running)
        #expect(RunnerError.busy("正在读取本机状态").errorDescription == "已经有一条 mo 在运行：正在读取本机状态。侧栏底部可以停止它。")
        #expect(RunnerError.busy("").errorDescription == "已经有一条 mo 在运行。侧栏底部可以停止它。")
    }
}
