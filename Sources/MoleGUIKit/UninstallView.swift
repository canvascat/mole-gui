import AppKit
import SwiftUI

final class UninstallUI: ObservableObject {
    @Published var selection = Set<String>()
    @Published var query = ""
    @Published var confirm = false
    @Published var pendingApps: [UninstallApp] = []
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
            subtitle: "列表来自 mo uninstall --list。确认后执行 mo uninstall。卸载成功后会刷新列表，并列出还留在磁盘上的相关文件。不传 --permanent。"
        ) {
            FillColumn(spacing: 16) {
                WarningNote(text: "点卸载后，窗口会再确认一次。确认后直接执行，应用文件放进废纸篓。卸载完成后如果还有相关文件，会再列出来，可以跳过，或放进废纸篓。")
                HStack {
                    Button(listJob.running ? "正在列出…" : "刷新列表") { model.loadUninstallList() }
                        .disabled(model.moPath == nil || listJob.running)
                    Button("预览") { model.previewUninstall(names: selectedNames) }
                        .disabled(model.moPath == nil || preview.running || selectedNames.isEmpty)
                    Button("在伪终端中卸载") {
                        ui.pendingApps = selectedApps
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
        .onChange(of: model.uninstallApps) { apps in
            let ids = Set(apps.map(\.id))
            ui.selection = ui.selection.intersection(ids)
        }
        .alert("确认卸载？", isPresented: $ui.confirm) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                model.startUninstall(apps: ui.pendingApps)
            }
        } message: {
            Text("将卸载 \(pendingLabels.joined(separator: "，"))。应用文件会放进废纸篓。完成后如果还有相关文件，可以再选择是否清理。")
        }
        .sheet(item: $model.leftoverReview) { review in
            LeftoverSheet(review: review) { paths in
                model.trashLeftovers(paths)
            } onClose: {
                model.leftoverReview = nil
            }
        }
    }

    private var pendingLabels: [String] {
        ui.pendingApps.map { app in
            app.name.isEmpty ? app.uninstallName : app.name
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

private struct LeftoverSheet: View {
    let review: LeftoverReview
    var trash: ([String]) -> [String: String]
    var onClose: () -> Void

    @State private var files: [LeftoverFile]
    @State private var selected: Set<String>
    @State private var errorText = ""

    init(
        review: LeftoverReview,
        trash: @escaping ([String]) -> [String: String],
        onClose: @escaping () -> Void
    ) {
        self.review = review
        self.trash = trash
        self.onClose = onClose
        _files = State(initialValue: review.files)
        _selected = State(initialValue: Set(review.files.map(\.path)))
    }

    private var selectedFiles: [LeftoverFile] {
        files.filter { selected.contains($0.path) }
    }

    private var selectedBytes: Int64 {
        selectedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    private var allSelected: Bool {
        !files.isEmpty && selected.count == files.count
    }

    private var cleanTitle: String {
        guard !selected.isEmpty else { return "清理" }
        return "清理 \(LeftoverPlan.sizeLabel(selectedBytes))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: AppBundleIcon.image(forPath: review.apps.first?.path ?? ""))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.title)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(LeftoverPlan.sizeLabel(selectedBytes))
                        .foregroundStyle(.secondary)
                    Text("应用已经卸载。这些相关文件还在，清理会放进废纸篓。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(20)

            Divider()

            HStack {
                Text("待移除 \(selected.count)")
                    .foregroundStyle(.secondary)
                Spacer()
                Button(allSelected ? "取消全选" : "全选") {
                    selected = allSelected ? [] : Set(files.map(\.path))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(red: 0.16, green: 0.62, blue: 0.38))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(files) { file in
                        Button {
                            if selected.contains(file.path) {
                                selected.remove(file.path)
                            } else {
                                selected.insert(file.path)
                            }
                        } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: selected.contains(file.path) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(
                                        selected.contains(file.path)
                                            ? Color(red: 0.18, green: 0.70, blue: 0.42)
                                            : Color.secondary
                                    )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(file.name)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(Format.homeAbbreviated(file.path))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer(minLength: 12)
                                Text(file.sizeLabel)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            Divider()

            HStack {
                Spacer()
                Button("跳过", action: onClose)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.cancelAction)
                Button(cleanTitle) { clean() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 520, height: 560)
    }

    private func clean() {
        let paths = selectedFiles.map(\.path)
        let failed = trash(paths)
        errorText = failed.map { path, message in
            "\(Format.homeAbbreviated(path))：\(message)"
        }.sorted().joined(separator: "\n")
        let removed = Set(paths.filter { failed[$0] == nil })
        files.removeAll { removed.contains($0.path) }
        selected = selected.intersection(Set(files.map(\.path)))
        if files.isEmpty {
            onClose()
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
