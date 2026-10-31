import SwiftUI

final class UninstallUI: ObservableObject {
    @Published var selection = Set<String>()
    @Published var query = ""
    @Published var draft = ""
}

struct UninstallView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var listJob: CommandJob
    @ObservedObject var preview: CommandJob
    @ObservedObject var terminal: PTYJob
    @StateObject private var ui = UninstallUI()

    private var filtered: [UninstallApp] {
        let text = ui.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return model.uninstallApps }
        return model.uninstallApps.filter { app in
            app.name.localizedStandardContains(text)
                || app.uninstallName.localizedStandardContains(text)
                || app.bundleId.localizedStandardContains(text)
        }
    }

    private var selectedNames: [String] {
        var seen = Set<String>()
        return model.uninstallApps.compactMap { app -> String? in
            guard ui.selection.contains(app.id) else { return nil }
            let name = app.uninstallName
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
    }

    var body: some View {
        PageShell(
            model: model,
            title: "卸载",
            subtitle: "列表来自 mo uninstall --list。真正卸载在伪终端里执行，让 CLI 自己的确认继续生效。不传 --with-data，也不传 --permanent。"
        ) {
            WarningNote(text: "窗口里的选择不能代替 CLI 的确认。默认保留个人数据。文件默认进废纸篓。应用已经不在时，应改用清理去找残留。")
            HStack {
                Button(listJob.running ? "正在列出…" : "刷新列表") { model.loadUninstallList() }
                    .disabled(model.moPath == nil || listJob.running)
                Button("预览") { model.previewUninstall(names: selectedNames) }
                    .disabled(model.moPath == nil || preview.running || selectedNames.isEmpty)
                Button("在伪终端中卸载") { model.startUninstall(names: selectedNames) }
                    .disabled(model.moPath == nil || terminal.running || !preview.acceptsExecute || selectedNames.isEmpty)
                    .tint(Theme.danger)
                if terminal.running {
                    Button("停止") { terminal.stop() }
                }
                Spacer()
            }
            .buttonStyle(.bordered)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("搜索名称或 bundle id", text: $ui.query)
                        .textFieldStyle(.roundedBorder)
                    List(filtered, selection: $ui.selection) { app in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name.isEmpty ? app.uninstallName : app.name)
                            Text("\(app.source) · \(app.size)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(app.id)
                    }
                    .frame(minWidth: 280, maxWidth: 360, maxHeight: .infinity)
                }
                VStack(alignment: .leading, spacing: 8) {
                    if selectedNames.isEmpty {
                        Text("先选一个或多个应用。后续参数用 uninstall_name，不用显示名猜测。")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("将使用的名字：\(selectedNames.joined(separator: "，"))")
                            .textSelection(.enabled)
                    }
                    if let error = listJob.error {
                        Text(error).foregroundStyle(Theme.danger)
                    }
                    if listJob.exitCode == 0, model.uninstallApps.isEmpty, !listJob.stdout.isEmpty {
                        Text("没能解析应用列表 JSON。")
                            .foregroundStyle(Theme.danger)
                    }
                    if !listJob.stderr.isEmpty {
                        Text(listJob.stderr)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    StreamPanes(job: preview)
                    terminalPane
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .task {
            if model.uninstallApps.isEmpty, !listJob.running, model.moPath != nil {
                model.loadUninstallList()
            }
        }
        .onChange(of: model.moPath) { path in
            if path != nil, model.uninstallApps.isEmpty, !listJob.running {
                model.loadUninstallList()
            }
        }
        .onChange(of: ui.selection) { _ in
            preview.acceptsExecute = false
        }
    }

    private var terminalPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("伪终端")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("标准输出和标准错误在这里合在一起。请在下面完成 CLI 自己的确认。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !terminal.commandLine.isEmpty {
                Text(terminal.commandLine)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            if let error = terminal.error {
                Text(error).foregroundStyle(Theme.danger)
            }
            ScrollView {
                Text(terminal.transcript.isEmpty ? "卸载开始后，CLI 的预览会出现在这里。" : terminal.transcript)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color(red: 0.93, green: 0.95, blue: 0.90))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 140, maxHeight: .infinity)
            .background(Color(red: 0.12, green: 0.13, blue: 0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            HStack {
                TextField("发送到 CLI", text: $ui.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { sendDraft() }
                Button("发送") { sendDraft() }
                    .disabled(!terminal.running)
                Button("回车") { terminal.sendEnter() }
                    .disabled(!terminal.running)
                Button("中断") { terminal.sendInterrupt() }
                    .disabled(!terminal.running)
            }
            if let code = terminal.exitCode {
                Text(terminal.stopped ? "已停止，退出码 \(code)。" : "退出码 \(code)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sendDraft() {
        terminal.sendLine(ui.draft)
        ui.draft = ""
    }
}
