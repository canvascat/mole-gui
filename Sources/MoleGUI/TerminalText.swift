import Foundation

enum TerminalText {
    static func stripANSI(_ input: String) -> String {
        var result = ""
        var index = input.startIndex
        while index < input.endIndex {
            if input[index] == "\u{1B}" {
                let next = input.index(after: index)
                if next < input.endIndex, input[next] == "[" {
                    var cursor = input.index(after: next)
                    while cursor < input.endIndex {
                        let character = input[cursor]
                        cursor = input.index(after: cursor)
                        if character.isLetter { break }
                    }
                    index = cursor
                    continue
                }
                if next < input.endIndex, input[next] == "]" {
                    var cursor = input.index(after: next)
                    while cursor < input.endIndex {
                        let character = input[cursor]
                        cursor = input.index(after: cursor)
                        if character == "\u{7}" { break }
                        if character == "\u{1B}", cursor < input.endIndex, input[cursor] == "\\" {
                            cursor = input.index(after: cursor)
                            break
                        }
                    }
                    index = cursor
                    continue
                }
            }
            result.append(input[index])
            index = input.index(after: index)
        }
        return result
    }
}

struct TerminalBuffer {
    private(set) var lines: [String] = [""]
    private let limit: Int

    init(limit: Int = 2000) {
        self.limit = limit
    }

    mutating func ingest(_ raw: String) {
        let text = TerminalText.stripANSI(raw).unicodeScalars
        var index = text.startIndex
        while index < text.endIndex {
            let scalar = text[index]
            if scalar == "\r" {
                let next = text.index(after: index)
                if next < text.endIndex, text[next] == "\n" {
                    appendLine()
                    index = text.index(after: next)
                    continue
                }
                if lines.isEmpty { lines = [""] }
                lines[lines.count - 1] = ""
            } else if scalar == "\n" {
                appendLine()
            } else if scalar == "\u{8}" {
                if var last = lines.last, !last.isEmpty {
                    last.removeLast()
                    lines[lines.count - 1] = last
                }
            } else if scalar.value >= 32 {
                if lines.isEmpty { lines = [""] }
                lines[lines.count - 1].unicodeScalars.append(scalar)
            }
            index = text.index(after: index)
        }
        if lines.count > limit {
            lines.removeFirst(lines.count - limit)
        }
    }

    private mutating func appendLine() {
        lines.append("")
    }

    var text: String { lines.joined(separator: "\n") }
}

enum UninstallLog {
    static func awaitsConfirm(_ raw: String) -> Bool {
        let plain = TerminalText.stripANSI(raw).lowercased()
        return plain.contains("enter confirm") && plain.contains("esc") && plain.contains("cancel")
    }

    static func visible(_ raw: String) -> String {
        var buffer = TerminalBuffer()
        buffer.ingest(raw)
        return buffer.lines
            .filter { !isPromptLine($0) }
            .joined(separator: "\n")
    }

    static func isPromptLine(_ line: String) -> Bool {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty { return false }
        if text.contains("enter confirm") && text.contains("esc") { return true }
        if text.contains("choose personal data") { return true }
        if text.contains("press enter to return") { return true }
        return false
    }
}
