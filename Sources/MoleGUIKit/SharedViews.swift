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
        FillColumn(spacing: 16) {
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
                .fillsRemainder()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct RemainderKey: LayoutValueKey {
    static let defaultValue = false
}

extension View {
    func fillsRemainder() -> some View {
        layoutValue(key: RemainderKey.self, value: true)
    }
}

struct FillColumn: Layout {
    var spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 800, height: proposal.height ?? 640)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = bounds.width
        let flex = subviews.indices.first { subviews[$0][RemainderKey.self] } ?? subviews.indices.last!
        var fixed: CGFloat = 0
        for index in subviews.indices where index != flex {
            fixed += subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }
        let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
        let flexHeight = max(0, bounds.height - fixed - gaps)
        var y = bounds.minY
        for index in subviews.indices {
            let height = index == flex
                ? flexHeight
                : subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
            subviews[index].place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: height)
            )
            y += height + spacing
        }
    }
}

struct PaneScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(width: max(proxy.size.width, 0), height: max(proxy.size.height, 0), alignment: .topLeading)
        }
    }
}

struct HorizontalStrip<Content: View>: View {
    var height: CGFloat = 32
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: true) {
                content()
            }
            .frame(width: max(proxy.size.width, 0), height: max(proxy.size.height, 0), alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

struct LogPane: View {
    var title: String?
    var text: String
    var foreground = Color.primary
    var background = Color(nsColor: .textBackgroundColor)
    var empty = "尚无输出"

    var body: some View {
        FillColumn(spacing: 6) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            PaneScroll {
                Text(text.isEmpty ? empty : text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(foreground)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(background, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.08))
            )
            .fillsRemainder()
        }
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
        FillColumn(spacing: 10) {
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
            GeometryReader { proxy in
                let gap: CGFloat = 10
                let height = max((proxy.size.height - gap) / 2, 0)
                VStack(spacing: gap) {
                    LogPane(title: "标准输出", text: job.stdout)
                        .frame(height: height)
                    LogPane(title: "标准错误", text: job.stderr)
                        .frame(height: height)
                }
            }
            .fillsRemainder()
            if let code = job.exitCode {
                Text(stopCaption(code))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
