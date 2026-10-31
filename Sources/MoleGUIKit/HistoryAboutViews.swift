import SwiftUI

struct HistoryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var job: CommandJob

    var body: some View {
        PageShell(
            model: model,
            title: "记录",
            subtitle: "mo history --json --limit 50。只展示最近做了什么，不能撤销。"
        ) {
            FillColumn(spacing: 16) {
                InfoNote(text: "日志里记着删过的路径，这一页会再显示一遍。ended_at 为空表示没有记下结束。归属不确定的记录不要当成同一次操作。")
                HStack {
                    Button(job.running ? "正在读取…" : "刷新") { model.loadHistory() }
                        .disabled(model.moPath == nil || job.running)
                    Spacer()
                }
                .buttonStyle(.bordered)
                if let error = job.error {
                    Text(error).foregroundStyle(Theme.danger)
                }
                if let parseError = model.historyParseError {
                    Text(parseError).foregroundStyle(Theme.danger)
                }
                if !job.stderr.isEmpty {
                    LogPane(title: "标准错误", text: job.stderr)
                        .frame(height: 120)
                }
                PaneScroll {
                    VStack(alignment: .leading, spacing: 16) {
                        sessions
                        deletions
                    }
                }
                .fillsRemainder()
            }
        }
        .task {
            if model.historyReport == nil, !job.running, model.moPath != nil {
                model.loadHistory()
            }
        }
        .onChange(of: model.moPath) { path in
            if path != nil, model.historyReport == nil, !job.running {
                model.loadHistory()
            }
        }
    }

    @ViewBuilder
    private var sessions: some View {
        let sessions = model.historyReport?.sessions ?? []
        MetricCard(title: "会话") {
            if sessions.isEmpty {
                Text("还没有会话记录")
                    .foregroundStyle(.secondary)
            }
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.command ?? "未知命令")
                            .font(.body.weight(.semibold))
                        Text(Format.attribution(session.attribution))
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                        Spacer()
                        Text(session.size ?? "")
                            .foregroundStyle(.secondary)
                    }
                    Text("开始 \(session.startedAt ?? "—") · 结束 \(Format.ended(session.endedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let run = session.runId, !run.isEmpty {
                        Text("run \(run)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    if let actions = session.actions {
                        Text("移除 \(actions.removed ?? 0) · 废纸篓 \(actions.trashed ?? 0) · 跳过 \(actions.skipped ?? 0) · 失败 \(actions.failed ?? 0)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    @ViewBuilder
    private var deletions: some View {
        let deletions = model.historyReport?.deletions ?? []
        MetricCard(title: "删除记录") {
            if deletions.isEmpty {
                Text("还没有删除记录")
                    .foregroundStyle(.secondary)
            }
            ForEach(deletions) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.path ?? "未知路径")
                        .textSelection(.enabled)
                        .lineLimit(2)
                    Text("\(item.timestamp ?? "—") · \(item.mode ?? "") · \(item.status ?? "")\(item.sizeKb.map { " · \($0) KB" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }
}

final class AboutUI: ObservableObject {
    @Published var terminalError: String?
}

struct AboutView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ui = AboutUI()

    var body: some View {
        PaneScroll {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 14) {
                    Image(nsImage: AppIconFactory.image(side: 128))
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("mole-gui")
                            .font(.title2.weight(.semibold))
                        Text(model.versionText.isEmpty ? "尚未读到 mo 的版本" : "mo \(model.versionText)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                }
                Text("这个窗口调用本机的 Mole CLI（mo），不是官方的 Mole for Mac。")
                    .fixedSize(horizontal: false, vertical: true)
                Link("github.com/tw93/Mole", destination: URL(string: "https://github.com/tw93/Mole")!)
                Link("官方图形应用是另一套产品：mole.fit", destination: URL(string: "https://mole.fit/")!)
                Text("界面不使用 Mole 的标志。清理仍然是整批执行。卸载完成后，相关文件会单独列出来。不提供登录项、风扇、菜单栏或 AI 清理。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let path = model.moPath {
                    Text(path)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                } else {
                    MissingMoCard()
                }
                Text("扫资源库深处时，把完全磁盘访问权限授给 mole-gui。它才是启动 mo 的程序。权限不够时会显示 CLI 的原文，不会反复执行删除。")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("高级")
                    .font(.headline)
                Text("安装包、瘦身和更新不在这个窗口里执行。下面只会在终端里打开，确认由你在终端里完成。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                advancedRow(
                    title: "安装包",
                    detail: "mo installer 会永久删除选中的安装包。第一版不在窗口里执行删除。",
                    arguments: ["installer"]
                )
                advancedRow(
                    title: "瘦身",
                    detail: "mo slim 会替换通用应用里的 Intel 代码。请在终端里自己确认。",
                    arguments: ["slim"]
                )
                advancedRow(
                    title: "更新 CLI",
                    detail: "mo update 会覆盖安装。这个窗口不代为更新。",
                    arguments: ["update"]
                )
                if let terminalError = ui.terminalError {
                    Text(terminalError).foregroundStyle(Theme.danger)
                }
                Text("第一版也不调用 touchid、completion、remove，不裸跑 mo，不用 sudo，不传 --permanent 或 --with-data。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("关闭") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(24)
        }
        .frame(width: 560, height: 640)
    }

    private func advancedRow(title: String, detail: String, arguments: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.body.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("在终端中打开") {
                ui.terminalError = model.openTerminal(arguments: arguments)
            }
            .disabled(model.moPath == nil)
            .buttonStyle(.bordered)
        }
    }
}
