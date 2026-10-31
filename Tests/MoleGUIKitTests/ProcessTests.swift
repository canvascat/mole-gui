import Foundation
import Testing
@testable import MoleGUIKit

// 同一时间只允许一条 mo，所以这些测试必须串行。
@Suite(.serialized) struct ProcessTests {
    let fixtures: Fixtures

    init() throws {
        fixtures = try Fixtures()
    }

    @Test func 分开收取输出() throws {
        let echo = try fixtures.echo()
        let run = LiveRun()
        let args = try CommandPolicy.plan(executable: echo, action: .version, pseudoTerminal: false)
        try run.start(executable: echo, arguments: args, environment: MoleEnvironment.make(moPath: echo))
        run.wait()
        let snap = run.snapshot()
        #expect(snap.exitCode == 0)
        #expect(snap.stdout.contains("stdout:version"))
        #expect(snap.stderr.contains("stderr:version"))
    }

    @Test func 永久参数不会启动进程() throws {
        let marker = fixtures.root.appendingPathComponent("ran").path
        let script = try fixtures.makeMo(directory: "marker", body: """
        #!/bin/sh
        echo ran > "\(marker)"
        echo "args:$*"
        exit 0
        """)
        #expect(throws: (any Error).self) {
            try LiveRun().start(executable: script, arguments: ["clean", "--permanent"], environment: [:])
        }
        #expect(!FileManager.default.fileExists(atPath: marker))
    }

    @Test func 同时只能有一条mo() throws {
        let echo = try fixtures.echo()
        let sleeper = try fixtures.makeMo(directory: "sleep", body: """
        #!/bin/sh
        echo start
        sleep 30
        echo done
        """)
        let first = LiveRun()
        try first.start(
            executable: sleeper,
            arguments: try CommandPolicy.arguments(for: .version),
            environment: MoleEnvironment.make(moPath: sleeper)
        )
        #expect(throws: (any Error).self) {
            try LiveRun().start(executable: echo, arguments: ["version"], environment: MoleEnvironment.make(moPath: echo))
        }
        first.stop()
        first.wait()

        let third = LiveRun()
        try third.start(executable: echo, arguments: ["version"], environment: MoleEnvironment.make(moPath: echo))
        third.wait()
        #expect(third.snapshot().exitCode == 0, "上一条结束后可以再跑")
    }

    @Test func 伪终端() async throws {
        let script = try fixtures.makeMo(directory: "pty", body: """
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
        let pty = PTYRun()
        try pty.start(
            executable: script,
            arguments: try CommandPolicy.plan(executable: script, action: .uninstallLive(names: ["Demo"]), pseudoTerminal: true),
            environment: MoleEnvironment.make(moPath: script)
        )
        var sawReady = false
        for _ in 0..<40 {
            if pty.snapshot().stdout.contains("READY") {
                sawReady = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(sawReady, "伪终端被认成终端")
        pty.send("y\r")
        pty.wait()
        let snap = pty.snapshot()
        #expect(snap.stdout.contains("LINE:y"))
        #expect(!snap.stdout.contains("NO-TTY"))
    }

    @MainActor
    @Test func 确认后自动应答卸载() async throws {
        let script = try fixtures.makeMo(directory: "confirm", body: """
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
        let job = PTYJob()
        job.start(moPath: script, names: ["Demo"])
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, !job.stdout.contains("DONE"), job.exitCode == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        if job.exitCode == nil {
            job.stop()
            try await Task.sleep(for: .milliseconds(200))
        }
        let out = job.stdout
        let err = job.stderr
        #expect(out.contains("DONE"), "\(out)\(err)")
        #expect(!out.lowercased().contains("enter confirm"))
        #expect(!out.lowercased().contains("choose personal data"))
        #expect(!err.lowercased().contains("enter confirm"))
        #expect(out.contains("Files to be removed"))
        #expect(!out.contains("NO-TTY"))
    }
}
