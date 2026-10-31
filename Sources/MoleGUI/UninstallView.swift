import AppKit
import SwiftUI

final class UninstallUI: ObservableObject {
    @Published var selection = Set<String>()
    @Published var query = ""
    @Published var confirm = false
    @Published var pendingNames: [String] = []
    @Published var pendingLabels: [String] = []
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

    private var selectedApps: [UninstallApp] {
        var seen = Set<String>()
        return model.uninstallApps.filter { app in
            guard ui.selection.contains(app.id) else { return false }
            let name = app.uninstallName
            guard !name.isEmpty, seen.insert(name).inserted else { return false }
            return true
        }
    }

    private var selectedNames: [String] {
        selectedApps.map(\.uninstallName)
    }

    private var selectedLabels: [String] {
        selectedApps.map { app in
            app.name.isEmpty ? app.uninstallName : app.name
        }
    }

    var body: some View {
        PageShell(
            model: model,
            title: "卸载",
            subtitle: "列表来自 mo uninstall --list。确认后执行 mo uninstall，不用在命令行里输入。文件进废纸篓，个人数据保留。不传 --with-data，也不传 --permanent。"
        ) {
            FillColumn(spacing: 16) {
                WarningNote(text: "点卸载后，窗口会再确认一次。确认后直接执行。应用文件放进废纸篓，个人数据保留。应用已经不在时，应改用清理去找残留。")
                HStack {
                    Button(listJob.running ? "正在列出…" : "刷新列表") { model.loadUninstallList() }
                        .disabled(model.moPath == nil || listJob.running)
                    Button("预览") { model.previewUninstall(names: selectedNames) }
                        .disabled(model.moPath == nil || preview.running || selectedNames.isEmpty)
                    Button("在伪终端中卸载") {
                        ui.pendingNames = selectedNames
                        ui.pendingLabels = selectedLabels
                        ui.confirm = true
                    }
                        .disabled(!UninstallLaunch.canStart(
                            moFound: model.moPath != nil,
                            terminalRunning: terminal.running,
                            names: selectedNames
                        ))
                        .tint(Theme.danger)
                    if terminal.running {
                        Button("停止") { terminal.stop() }
                    }
                    Spacer()
                }
                .buttonStyle(.bordered)

                HStack(alignment: .top, spacing: 16) {
                    FillColumn(spacing: 8) {
                        TextField("搜索名称或 bundle id", text: $ui.query)
                            .textFieldStyle(.roundedBorder)
                        List(filtered, selection: $ui.selection) { app in
                            HStack(alignment: .center, spacing: 8) {
                                Image(nsImage: AppBundleIcon.image(forPath: app.path))
                                    .resizable()
                                    .interpolation(.high)
                                    .frame(width: 28, height: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name.isEmpty ? app.uninstallName : app.name)
                                    Text("\(app.source) · \(app.size)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(app.id)
                        }
                        .fillsRemainder()
                    }
                    .frame(minWidth: 280, maxWidth: 360, maxHeight: .infinity)
                    FillColumn(spacing: 8) {
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
                            LogPane(title: "标准错误", text: listJob.stderr)
                                .frame(height: 96)
                        }
                        GeometryReader { proxy in
                            let gap: CGFloat = 8
                            let previewHeight = max((proxy.size.height - gap) * 0.55, 0)
                            let terminalHeight = max(proxy.size.height - gap - previewHeight, 0)
                            VStack(spacing: gap) {
                                StreamPanes(job: preview)
                                    .frame(height: previewHeight)
                                liveLog
                                    .frame(height: terminalHeight)
                            }
                        }
                        .fillsRemainder()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .fillsRemainder()
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
        .alert("确认卸载？", isPresented: $ui.confirm) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                model.startUninstall(names: ui.pendingNames)
            }
        } message: {
            Text("将卸载 \(ui.pendingLabels.joined(separator: "，"))。相关文件会放进废纸篓。个人数据会保留。")
        }
    }

    private var liveLog: some View {
        FillColumn(spacing: 8) {
            if !terminal.commandLine.isEmpty {
                Text(terminal.commandLine)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
            if let error = terminal.error {
                Text(error).foregroundStyle(Theme.danger)
            }
            GeometryReader { proxy in
                let gap: CGFloat = 8
                let height = max((proxy.size.height - gap) / 2, 0)
                VStack(spacing: gap) {
                    LogPane(
                        title: "标准输出",
                        text: terminal.stdout,
                        empty: "确认后，卸载输出会显示在这里。"
                    )
                    .frame(height: height)
                    LogPane(title: "标准错误", text: terminal.stderr)
                        .frame(height: height)
                }
            }
            .fillsRemainder()
            if let code = terminal.exitCode {
                Text(terminal.stopped ? "已停止，退出码 \(code)。" : "退出码 \(code)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

enum AppBundleIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(forPath path: String) -> NSImage {
        if let cached = cache[path] { return cached }
        let image = load(path)
        cache[path] = image
        return image
    }

    private static func load(_ path: String) -> NSImage {
        let placeholder = NSWorkspace.shared.icon(for: .application)
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) else {
            return placeholder
        }
        let icon = NSWorkspace.shared.icon(forFile: trimmed)
        guard icon.isValid else { return placeholder }
        return icon
    }
}
