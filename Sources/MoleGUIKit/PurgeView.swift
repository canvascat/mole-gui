import SwiftUI

final class PurgeUI: ObservableObject {
    @Published var confirm = false
    @Published var terminalError: String?
    @Published var deleting = false
    @Published var trashError = ""
    @Published var notice = ""
    @Published var collapsed = Set<String>()
}

struct PurgeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var job: CommandJob
    @StateObject private var ui = PurgeUI()

    private var items: [PurgeItem] { model.purgePlan ?? [] }

    private var selectedItems: [PurgeItem] {
        items.filter { model.purgeSelection.contains($0.path) }
    }

    private var selectedSize: (bytes: Int64, partial: Bool) {
        PurgePlan.totalBytes(selectedItems)
    }

    var body: some View {
        PageShell(
            model: model,
            title: "项目产物",
            subtitle: "按项目列出 node_modules、dist 等构建产物。勾选后移到废纸篓，需要时重新安装或构建即可。"
        ) {
            FillColumn(spacing: 12) {
                HStack {
                    Button(job.running ? "正在扫描…" : "扫描") {
                        ui.notice = ""
                        ui.trashError = ""
                        model.previewPurge()
                    }
                    .disabled(model.moPath == nil || job.running || ui.deleting)
                    if job.running {
                        Button("停止") { job.stop() }
                    }
                    Button("搜索目录") {
                        ui.terminalError = model.openTerminal(arguments: ["purge", "--paths"])
                    }
                    .disabled(model.moPath == nil || job.running)
                    Button("在终端中打开") {
                        ui.terminalError = model.openTerminal(arguments: ["purge"])
                    }
                    .disabled(model.moPath == nil || job.running)
                    Spacer()
                }
                .buttonStyle(.bordered)
                if let terminalError = ui.terminalError {
                    Text(terminalError).foregroundStyle(Theme.danger)
                }
                if let error = job.error ?? model.purgeError {
                    Text(error).foregroundStyle(Theme.danger)
                }
                if let note = model.purgeNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !ui.notice.isEmpty {
                    Text(ui.notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !ui.trashError.isEmpty {
                    Text(ui.trashError)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
                content
            }
        }
        .alert("移到废纸篓？", isPresented: $ui.confirm) {
            Button("取消", role: .cancel) {}
            Button("移到废纸篓", role: .destructive) { startTrash() }
        } message: {
            Text("将把已选的 \(selectedItems.count) 项（约 \(sizeText(selectedSize))）移到废纸篓。清空废纸篓之后才会释放空间。")
        }
    }

    @ViewBuilder
    private var content: some View {
        if ui.deleting {
            DeleteProgressPanel(progress: model.purgeDelete, title: "正在移到废纸篓", doneTitle: "已移走")
                .fillsRemainder()
        } else if job.running {
            scanProgress
                .fillsRemainder()
        } else if model.purgePlan == nil {
            InfoNote(text: "点扫描后，这里会按项目列出可移除的构建产物。7 天内改动过的项目不会列出。默认一项都不勾选。")
                .fillsRemainder()
        } else if items.isEmpty {
            Text("这次扫描没有可移除的项目产物。")
                .foregroundStyle(.secondary)
                .fillsRemainder()
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(PurgePlan.projects(items)) { project in
                        projectCard(project)
                    }
                }
                .padding(.vertical, 4)
            }
            .fillsRemainder()
            footer
        }
    }

    private var scanProgress: some View {
        let found = PurgePlan.parse(job.stdout).count
        return VStack(spacing: 12) {
            ProgressView()
            Text("正在扫描项目目录")
                .font(.headline)
            Text(found > 0 ? "已发现 \(found) 项" : "这一步会检查大小和最近改动，可能要一会儿。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectCard(_ project: PurgeProject) -> some View {
        let open = !ui.collapsed.contains(project.id)
        let selectable = project.items.filter(\.deletable)
        let chosen = selectable.filter { model.purgeSelection.contains($0.path) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                checkButton(mark: mark(chosen: chosen.count, total: selectable.count)) {
                    let paths = Set(selectable.map(\.path))
                    if chosen.count == selectable.count {
                        model.setPurgeSelection(model.purgeSelection.subtracting(paths))
                    } else {
                        model.setPurgeSelection(model.purgeSelection.union(paths))
                    }
                }
                .disabled(selectable.isEmpty || ui.deleting)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(Format.homeAbbreviated(project.path))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Text(CleanPlan.decimalLabel(project.totalBytes) + (project.hasUnknownSize ? "+" : ""))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    if open {
                        ui.collapsed.insert(project.id)
                    } else {
                        ui.collapsed.remove(project.id)
                    }
                } label: {
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            if open {
                Divider()
                ForEach(project.items) { item in
                    itemRow(item)
                    if item.id != project.items.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func itemRow(_ item: PurgeItem) -> some View {
        let on = model.purgeSelection.contains(item.path)
        return HStack(alignment: .center, spacing: 10) {
            checkButton(mark: on ? .on : .off) {
                model.togglePurge(item.path)
            }
            .disabled(!item.deletable || ui.deleting)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .lineLimit(1)
                    if item.cloud {
                        Text("云同步")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    } else if !item.deletable {
                        Text("不删除")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(Format.homeAbbreviated(item.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(item.sizeLabel)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("已选 \(selectedItems.count) 项")
                .foregroundStyle(.secondary)
            Button("全选") {
                model.setPurgeSelection(Set(items.filter(\.deletable).map(\.path)))
            }
            .buttonStyle(.plain)
            Button("全不选") { model.setPurgeSelection([]) }
                .buttonStyle(.plain)
            Spacer()
            Button(ui.deleting ? "正在移除…" : "移到废纸篓 \(sizeText(selectedSize))") {
                ui.confirm = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedItems.isEmpty || ui.deleting || job.running)
        }
    }

    private func startTrash() {
        let count = selectedItems.count
        let size = selectedSize
        ui.deleting = true
        ui.trashError = ""
        ui.notice = ""
        Task {
            let message = await model.trashPurgeSelection()
            ui.trashError = message ?? ""
            if message == nil {
                ui.notice = "已把 \(count) 项（约 \(sizeText(size))）移到废纸篓。清空废纸篓之后才会释放空间。"
            }
            ui.deleting = false
        }
    }

    private func sizeText(_ size: (bytes: Int64, partial: Bool)) -> String {
        CleanPlan.decimalLabel(size.bytes) + (size.partial ? "+" : "")
    }

    private func mark(chosen: Int, total: Int) -> CheckMark {
        if total == 0 || chosen == 0 { return .off }
        if chosen == total { return .on }
        return .partial
    }

    private func checkButton(mark: CheckMark, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: mark.symbol)
                .font(.title3)
                .foregroundStyle(mark == .off ? Color.secondary : Color(red: 0.18, green: 0.70, blue: 0.42))
        }
        .buttonStyle(.plain)
    }
}
