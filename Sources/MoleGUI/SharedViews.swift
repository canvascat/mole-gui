import AppKit
import SwiftUI

enum Theme {
    static let accent = Color(red: 0.12, green: 0.42, blue: 0.40)
    static let danger = Color(red: 0.66, green: 0.22, blue: 0.18)
}

enum AppSection: String, CaseIterable, Identifiable {
    case status, clean, uninstall, disk, purge, optimize, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .status: return "状态"
        case .clean: return "清理"
        case .uninstall: return "卸载"
        case .disk: return "磁盘"
        case .purge: return "项目产物"
        case .optimize: return "维护"
        case .history: return "记录"
        }
    }

    var symbol: String {
        switch self {
        case .status: return "speedometer"
        case .clean: return "sparkles"
        case .uninstall: return "minus.square"
        case .disk: return "internaldrive"
        case .purge: return "archivebox"
        case .optimize: return "wrench.and.screwdriver"
        case .history: return "clock"
        }
    }
}

struct PageShell<Content: View>: View {
    @ObservedObject var model: AppModel
    var title: String
    var subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.moPath == nil, !model.locating {
                MissingMoCard()
            }
            content()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MissingMoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("没有在 PATH 里找到 mo")
                .font(.headline)
            Text("请先自己安装 Mole CLI，再回到这个窗口。这里不会替你执行安装脚本，也不会用 sudo。")
                .fixedSize(horizontal: false, vertical: true)
            CopyLine(text: "brew install mole")
            CopyLine(text: "curl -fsSL https://raw.githubusercontent.com/tw93/mole/main/install.sh | bash")
            Text("也可以装到 ~/.local/bin，或看 /opt/homebrew/bin/mo、/usr/local/bin/mo 是否已经存在。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

final class CopyUI: ObservableObject {
    @Published var copied = false
}

struct CopyLine: View {
    var text: String
    @StateObject private var ui = CopyUI()

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button(ui.copied ? "已复制" : "复制") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                ui.copied = true
            }
            .buttonStyle(.bordered)
        }
    }
}

struct WarningNote: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct InfoNote: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct StreamPanes: View {
    @ObservedObject var job: CommandJob
    var destructive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !job.commandLine.isEmpty {
                Text(job.commandLine)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            if let error = job.error {
                Text(error)
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            streamBox("标准输出", job.stdout)
            streamBox("标准错误", job.stderr)
            if let code = job.exitCode {
                Text(stopCaption(code))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stopCaption(_ code: Int32) -> String {
        if job.stopped, destructive {
            return "已停止，退出码 \(code)。已经删掉的文件不会因此回来。"
        }
        if job.stopped {
            return "已停止，退出码 \(code)。"
        }
        return "退出码 \(code)"
    }

    private func streamBox(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(text.isEmpty ? "尚无输出" : text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08))
            )
        }
        .frame(minHeight: 120, maxHeight: .infinity)
    }
}

struct MetricCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
