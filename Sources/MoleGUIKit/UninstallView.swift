import AppKit
import SwiftUI

final class UninstallUI: ObservableObject {
    @Published var selection = Set<String>()
    @Published var query = ""
    @Published var confirm = false
    @Published var pendingApps: [UninstallApp] = []
    @Published var sort: UninstallSort = .recent
    @Published var ascending = true
    @Published var details: [String: AppSpotlight] = [:]
    @Published var hovered: String?
}

struct UninstallView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var listJob: CommandJob
    @ObservedObject var terminal: PTYJob
    @ObservedObject private var activity = CommandActivity.shared
    @StateObject private var ui = UninstallUI()

    private var filtered: [UninstallApp] {
        let text = ui.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matched: [UninstallApp]
        if text.isEmpty {
            matched = model.uninstallApps
        } else {
            matched = model.uninstallApps.filter { app in
                app.name.localizedStandardContains(text)
                    || app.uninstallName.localizedStandardContains(text)
                    || app.bundleId.localizedStandardContains(text)
            }
        }
        return UninstallOrder.sorted(matched, by: ui.sort, ascending: ui.ascending, details: ui.details)
    }

    private var summary: String {
        let count = model.uninstallApps.count
        if count == 0 {
            return listJob.running ? "正在读取已安装的应用" : "还没有读到已安装的应用"
        }
        let bytes = UninstallSizing.sum(model.uninstallApps.map(\.size))
        return "已安装 App \(count) 个 · \(UninstallSizing.totalLabel(bytes))"
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
        selectedApps.map(\.launchName)
    }

    private var selectedLabels: [String] {
        selectedApps.map { app in
            app.name.isEmpty ? app.uninstallName : app.name
        }
    }

    var body: some View {
        PageShell(model: model, title: "卸载", subtitle: summary) {
            FillColumn(spacing: 12) {
                toolbar
                if let note = statusNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                appList
                    .fillsRemainder()
                if !selectedApps.isEmpty || terminal.running {
                    selectionBar
                }
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
        .onChange(of: activity.snapshot.running) { running in
            guard !running,
                  model.uninstallApps.isEmpty,
                  !listJob.running,
                  let error = listJob.error,
                  error.hasPrefix("已经有一条 mo 在运行")
            else { return }
            model.loadUninstallList()
        }
        .onChange(of: model.uninstallApps) { apps in
            let ids = Set(apps.map(\.id))
            ui.selection = ui.selection.intersection(ids)
        }
        .task(id: model.uninstallApps.map(\.path).joined(separator: "\n")) {
            let paths = model.uninstallApps.map(\.path)
            let loaded = await Task.detached(priority: .utility) {
                var details: [String: AppSpotlight] = [:]
                for path in paths where details[path] == nil {
                    details[path] = AppSpotlight.read(path: path)
                }
                return details
            }.value
            ui.details = loaded
        }
        .alert("确认卸载？", isPresented: $ui.confirm) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                model.startUninstall(apps: ui.pendingApps)
            }
        } message: {
            Text("将移除 \(pendingLabels.joined(separator: "、"))。应用文件会放进废纸篓。完成后如果还有相关文件，可以再选择是否清理。")
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

    private var statusNote: String? {
        if let error = listJob.error { return error }
        if listJob.exitCode == 0, model.uninstallApps.isEmpty, !listJob.stdout.isEmpty {
            return "没能解析应用列表。"
        }
        if let error = terminal.error { return error }
        if let code = terminal.exitCode, code != 0, !terminal.stopped {
            guard let reason = UninstallLog.failureReason(terminal.stdout) else { return "卸载没有完成。" }
            return "卸载没有完成：\(reason)"
        }
        return nil
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Spacer(minLength: 0)
            ForEach(UninstallSort.allCases) { key in
                Button {
                    if ui.sort == key {
                        ui.ascending.toggle()
                    } else {
                        ui.sort = key
                        ui.ascending = key != .size
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(key.title)
                        if ui.sort == key {
                            Image(systemName: ui.ascending ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(ui.sort == key ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索", text: $ui.query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
            .frame(width: 168)
            Button {
                model.loadUninstallList()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(model.moPath == nil || listJob.running)
            .help(listJob.running ? "正在列出" : "刷新列表")
        }
    }

    private var appList: some View {
        Group {
            if model.uninstallApps.isEmpty, listJob.running {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("正在读取已安装的应用")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                Text(ui.query.isEmpty ? "没有可卸载的应用。" : "没有匹配的应用。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { app in
                    Button {
                        toggle(app.id)
                    } label: {
                        appRow(app)
                    }
                    .buttonStyle(.plain)
                    .disabled(terminal.running)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 12))
                    .listRowBackground(rowBackground(app))
                    .onHover { inside in
                        if inside {
                            ui.hovered = app.id
                        } else if ui.hovered == app.id {
                            ui.hovered = nil
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func appRow(_ app: UninstallApp) -> some View {
        let selected = ui.selection.contains(app.id)
        let name = app.name.isEmpty ? app.uninstallName : app.name
        let caption = ui.details[app.path]?.caption(size: app.size) ?? app.size
        return HStack(spacing: 12) {
            Image(nsImage: AppBundleIcon.image(forPath: app.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !caption.isEmpty {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if selected, !app.size.isEmpty {
                Text("移除 \(app.size)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: selected ? "checkmark.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(selected ? Theme.accent : Color.secondary.opacity(0.7))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func rowBackground(_ app: UninstallApp) -> Color {
        if ui.selection.contains(app.id) {
            return Theme.accent.opacity(0.14)
        }
        if ui.hovered == app.id {
            return Color.primary.opacity(0.05)
        }
        return Color.clear
    }

    private var selectionBar: some View {
        let bytes = UninstallSizing.sum(selectedApps.map(\.size))
        return HStack(spacing: 12) {
            HStack(spacing: -8) {
                ForEach(selectedApps.prefix(4)) { app in
                    Image(nsImage: AppBundleIcon.image(forPath: app.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1))
                }
            }
            Text(selectionSummary(bytes: bytes))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button("取消选择") { ui.selection = [] }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .disabled(terminal.running || ui.selection.isEmpty)
            Spacer(minLength: 8)
            if terminal.running {
                Button("停止") { terminal.stop() }
                    .buttonStyle(.bordered)
            }
            Button(terminal.running ? "正在移除…" : "移除 \(selectedApps.count) 项") {
                ui.pendingApps = selectedApps
                ui.confirm = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(terminal.running || !UninstallLaunch.canStart(
                moFound: model.moPath != nil,
                terminalRunning: terminal.running,
                names: selectedNames
            ))
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private func selectionSummary(bytes: Double) -> String {
        let names = selectedLabels.joined(separator: "、")
        if bytes > 0 {
            return "\(names) · \(UninstallSizing.totalLabel(bytes))"
        }
        return names
    }

    private func toggle(_ id: String) {
        if ui.selection.contains(id) {
            ui.selection.remove(id)
        } else {
            ui.selection.insert(id)
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
