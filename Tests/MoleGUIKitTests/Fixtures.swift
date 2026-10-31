import Darwin
import Foundation

final class Fixtures {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mole-gui-tests-\(getpid())-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func makeMo(named name: String = "mo", directory: String, body: String) throws -> String {
        let dir = root.appendingPathComponent(directory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let path = dir.appendingPathComponent(name).path
        try body.write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    func echo() throws -> String {
        try makeMo(directory: "echo", body: """
        #!/bin/sh
        echo "stdout:$*"
        echo "stderr:$*" >&2
        exit 0
        """)
    }
}
