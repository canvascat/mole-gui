import SwiftUI

final class CleanUI: ObservableObject {
    @Published var confirm = false
    @Published var terminalError: String?
    @Published var deleting = false
    @Published var cleanError = ""
    @Published var expanded = Set<String>()
}

struct CleanView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var job: CommandJob
    @StateObject private var ui = CleanUI()

    private var selectedEntries: [CleanEntry] {
        model.cleanPlan?.entries.filter { model.cleanSelection.contains($0.path) } ?? []
    }

    private var selectedSize: (bytes: Int64, partial: Bool) {
        CleanPlan.totalBytes(selectedEntries)
    }

    var body: some View {
        PageShell(
            model: model,
            title: "清理",
            subtitle: "先扫描 mo clean --dry-run。结果按大类展开，勾选后再永久删除。未勾选的会留下。"
        ) {
            FillColumn(spacing: 12) {
                WarningNote(text: "勾选的项目会永久删除，不进废纸篓。嵌套在已选目录里的文件会一起删除。系统路径不会用 sudo 删除。")
                HStack {
                    Button(job.running ? "正在扫描…" : "扫描") { model.previewClean() }
                        .disabled(model.moPath == nil || job.running || ui.deleting)
                    if job.running {
                        Button("停止") { job.stop() }
                    }
                    Button("编辑保护名单") {
                        ui.terminalError = model.openTerminal(arguments: ["clean", "--whitelist"])
                    }
                    .disabled(model.moPath == nil || job.running)
                    Spacer()
                }
                .buttonStyle(.bordered)
                if let terminalError = ui.terminalError {
                    Text(terminalError).foregroundStyle(Theme.danger)
                }
                if let error = model.cleanPlanError {
                    Text(error).foregroundStyle(Theme.danger)
                }
                if !ui.cleanError.isEmpty {
                    Text(ui.cleanError)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
                if ui.deleting {
                    deleteProgress
                        .fillsRemainder()
                } else if job.running {
                    scanProgress
                        .fillsRemainder()
                } else if let plan = model.cleanPlan, !plan.groups.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(plan.groups) { group in
                                cleanGroup(group)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .fillsRemainder()
                    cleanFooter
                } else if model.cleanPlan != nil {
                    Text("这次扫描没有可清理的项目。")
                        .foregroundStyle(.secondary)
                        .fillsRemainder()
                } else {
                    InfoNote(text: "点扫描之后，这里会按大类列出可清理的路径。缓存默认勾选，卸载残留、项目产物和系统数据默认不勾。")
                        .fillsRemainder()
                }
            }
        }
        .alert("永久删除已选项？", isPresented: $ui.confirm) {
            Button("取消", role: .cancel) {}
            Button("永久清理", role: .destructive) {
                ui.deleting = true
                ui.cleanError = ""
                Task {
                    let message = await model.deleteCleanSelection()
                    ui.cleanError = message ?? ""
                    ui.deleting = false
                }
            }
        } message: {
            Text("将永久删除已选的 \(selectedEntries.count) 项，约 \(cleanSize(selectedSize))。未勾选的不会动。")
        }
    }

    private var deleteProgress: some View {
        DeleteProgressPanel(progress: model.cleanDelete, title: "正在清理", doneTitle: "已清理")
    }

    private var scanProgress: some View {
        let steps = CleanScanProgress.parse(job.stdout)
        let current = steps.last(where: { $0.state == .running })
        return FillColumn(spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(current.map { "正在检查 \($0.title)" } ?? "正在启动扫描")
                    .font(.headline)
                Spacer()
                if let current, current.items > 0 {
                    Text("已发现 \(current.items) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if steps.isEmpty {
                        Text(job.stdout.isEmpty ? "正在启动 mo clean --dry-run。" : "正在读取扫描输出。")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                    ForEach(steps) { step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: scanSymbol(step.state))
                                .foregroundStyle(step.state == .running ? Theme.accent : .secondary)
                                .frame(width: 16)
                            Text(step.title)
                            Spacer(minLength: 8)
                            Text(scanDetail(step))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        if step.state == .running, !step.latest.isEmpty {
                            Text(step.latest)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.leading, 24)
                                .padding(.bottom, 4)
                        }
                    }
                    if job.running, current == nil, !steps.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(Theme.accent)
                                .frame(width: 16)
                            Text("正在继续扫描")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            if let error = job.error {
                Text(error).foregroundStyle(Theme.danger)
            }
        }
    }

    private func scanSymbol(_ state: CleanScanState) -> String {
        switch state {
        case .running: return "circle.dotted"
        case .done: return "checkmark.circle.fill"
        case .empty: return "checkmark.circle"
        }
    }

    private func scanDetail(_ step: CleanScanStep) -> String {
        switch step.state {
        case .running where step.items == 0: return "正在检查"
        case .running: return "已发现 \(step.items) 项"
        case .done: return "\(step.items) 项"
        case .empty: return "没有可清理的"
        }
    }

    private func cleanGroup(_ group: CleanGroup) -> some View {
        let open = ui.expanded.contains(group.id)
        let selectable = group.entries.filter(\.deletable)
        let chosen = selectable.filter { model.cleanSelection.contains($0.path) }
        let chosenSize = CleanPlan.totalBytes(chosen)
        let totalSize = CleanPlan.totalBytes(group.entries)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                checkButton(mark: mark(chosen: chosen.count, total: selectable.count)) {
                    let paths = Set(selectable.map(\.path))
                    if chosen.count == selectable.count {
                        model.setCleanSelection(model.cleanSelection.subtracting(paths))
                    } else {
                        model.setCleanSelection(model.cleanSelection.union(paths))
                    }
                }
                .disabled(selectable.isEmpty || ui.deleting)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.headline)
                    Text(group.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Text("\(cleanSize(chosenSize)) / \(cleanSize(totalSize))")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    if open {
                        ui.expanded.remove(group.id)
                    } else {
                        ui.expanded.insert(group.id)
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
                ForEach(group.entries) { entry in
                    cleanRow(entry)
                    if entry.id != group.entries.last?.id {
                        Divider().padding(.leading, 44)
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func cleanRow(_ entry: CleanEntry) -> some View {
        let on = model.cleanSelection.contains(entry.path)
        return HStack(alignment: .center, spacing: 10) {
            checkButton(mark: on ? .on : .off) {
                model.toggleClean(entry.path)
            }
            .disabled(!entry.deletable || ui.deleting)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .lineLimit(1)
                    if !entry.recommended {
                        Text("需确认")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if !entry.deletable {
                        Text("不删除")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(Format.homeAbbreviated(entry.path))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(entry.sizeLabel)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var cleanFooter: some View {
        HStack(spacing: 12) {
            Text("已选 \(selectedEntries.count) 项")
                .foregroundStyle(.secondary)
            Button("全选") { model.setCleanSelection(Set(model.cleanPlan?.entries.filter(\.deletable).map(\.path) ?? [])) }
                .buttonStyle(.plain)
            Button("全不选") { model.setCleanSelection([]) }
                .buttonStyle(.plain)
            Button("推荐") {
                let paths = model.cleanPlan?.entries.filter { $0.recommended && $0.deletable }.map(\.path) ?? []
                model.setCleanSelection(Set(paths))
            }
            .buttonStyle(.plain)
            Spacer()
            Button(ui.deleting ? "正在删除…" : "永久清理 \(cleanSize(selectedSize))") {
                ui.confirm = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedEntries.isEmpty || ui.deleting || job.running)
        }
    }

    private func cleanSize(_ size: (bytes: Int64, partial: Bool)) -> String {
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

enum CheckMark {
    case on, off, partial

    var symbol: String {
        switch self {
        case .on: return "checkmark.circle.fill"
        case .off: return "circle"
        case .partial: return "minus.circle.fill"
        }
    }
}

final class OptimizeUI: ObservableObject {
    @Published var confirm = false
}

struct OptimizeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var job: CommandJob
    @StateObject private var ui = OptimizeUI()

    var body: some View {
        PageShell(
            model: model,
            title: "维护",
            subtitle: "先看 mo optimize --dry-run，确认后再执行 mo optimize。"
        ) {
            FillColumn(spacing: 16) {
                WarningNote(text: "维护会改系统状态。如果需要管理员权限，CLI 会自己弹出一次密码框。本程序不保存密码，也不用 sudo 启动 mo。")
                HStack {
                    Button("预览") { model.previewOptimize() }
                        .disabled(model.moPath == nil || job.running)
                    Button("开始维护") { ui.confirm = true }
                        .disabled(model.moPath == nil || job.running || !job.acceptsExecute)
                    if job.running {
                        Button("停止") { job.stop() }
                    }
                    Spacer()
                }
                .buttonStyle(.bordered)
                if !job.acceptsExecute, !job.running {
                    InfoNote(text: "请先预览。预览成功之后，「开始维护」才会亮。")
                }
                StreamPanes(job: job, destructive: true)
                    .fillsRemainder()
            }
        }
        .alert("开始维护？", isPresented: $ui.confirm) {
            Button("取消", role: .cancel) {}
            Button("开始维护", role: .destructive) { model.executeOptimize() }
        } message: {
            Text("将执行 mo optimize。部分任务会改系统状态。管理员密码框如果出现，是 CLI 自己请求的。")
        }
    }
}
