import SwiftUI

final class OptimizeUI: ObservableObject {
    @Published var confirm = false
    @Published var collapsed: Set<String> = [OptimizeOutcome.unchanged.rawValue]
}

struct OptimizeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var job: CommandJob
    @StateObject private var ui = OptimizeUI()

    private var report: OptimizeReport { OptimizePlan.parse(job.stdout) }
    private var runningDry: Bool { job.commandLine.contains("--dry-run") }

    var body: some View {
        PageShell(
            model: model,
            title: "维护",
            subtitle: "检查系统并运行 mo 内置的维护任务。先预览，确认后再执行。"
        ) {
            FillColumn(spacing: 12) {
                WarningNote(text: "维护会改系统状态。需要管理员权限时，CLI 会自己请求一次。本程序不保存密码，也不用 sudo 启动 mo。")
                HStack {
                    Button(job.running && runningDry ? "正在预览…" : "预览") { model.previewOptimize() }
                        .disabled(model.moPath == nil || job.running)
                    Button(job.running && !runningDry ? "正在维护…" : "开始维护") { ui.confirm = true }
                        .disabled(model.moPath == nil || job.running || !job.acceptsExecute)
                    if job.running {
                        Button("停止") { job.stop() }
                    }
                    Spacer()
                }
                .buttonStyle(.bordered)
                if let error = job.error {
                    Text(error).foregroundStyle(Theme.danger)
                }
                content
            }
        }
        .alert("开始维护？", isPresented: $ui.confirm) {
            Button("取消", role: .cancel) {}
            Button("开始维护", role: .destructive) { model.executeOptimize() }
        } message: {
            Text("将执行 mo optimize，按预览里的任务逐项处理。部分任务会改系统状态。管理员密码框如果出现，是 CLI 自己请求的。")
        }
    }

    @ViewBuilder
    private var content: some View {
        let report = report
        if job.running {
            progress(report)
                .fillsRemainder()
        } else if job.exitCode == nil {
            InfoNote(text: "点预览后，这里会列出每个维护任务会做什么。预览成功后「开始维护」才会亮。")
                .fillsRemainder()
        } else if report.tasks.isEmpty {
            failureNote
                .fillsRemainder()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let code = job.exitCode, code != 0, !job.stopped {
                        Text("mo 退出码 \(code)。下面是它已经输出的部分。")
                            .font(.caption)
                            .foregroundStyle(Theme.danger)
                    }
                    summaryStrip(report)
                    if let system = report.system {
                        systemStrip(system)
                    }
                    if !report.diagnosis.isEmpty {
                        diagnosisCard(report.diagnosis)
                    }
                    ForEach(groups(report), id: \.outcome) { group in
                        groupCard(group.outcome, tasks: group.tasks, dryRun: report.dryRun)
                    }
                    if report.inferred {
                        Text("个别任务的状态是按输出文字推断的，汇总数字以 mo 为准。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .fillsRemainder()
        }
    }

    private var failureNote: some View {
        let hint = job.stderr
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 6) {
            Text(job.stopped ? "已停止。" : "mo 没有给出任何维护任务。")
                .foregroundStyle(.secondary)
            if let code = job.exitCode, code != 0, !job.stopped {
                Text("退出码 \(code)\(hint.map { "：\($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(Theme.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func progress(_ report: OptimizeReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(runningDry ? "正在预览维护任务" : "正在执行维护")
                    .font(.headline)
                Spacer()
                if !report.tasks.isEmpty {
                    Text("已到第 \(report.tasks.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if report.tasks.isEmpty {
                        Text("正在收集系统信息。")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                    ForEach(Array(report.tasks.enumerated()), id: \.element.id) { index, task in
                        let active = index == report.tasks.count - 1
                        HStack(alignment: .center, spacing: 8) {
                            if active {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 16)
                            } else {
                                Image(systemName: symbol(task.outcome))
                                    .foregroundStyle(tint(task.outcome))
                                    .frame(width: 16)
                            }
                            Text(task.displayTitle)
                            Spacer(minLength: 8)
                            Text(active ? "进行中" : label(task.outcome, dryRun: report.dryRun))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    private func summaryStrip(_ report: OptimizeReport) -> some View {
        let counts = report.summary
        func number(_ outcome: OptimizeOutcome) -> Int {
            counts?.value(outcome) ?? report.tasks(outcome).count
        }
        let items: [(OptimizeOutcome, String)] = [
            (.applied, report.dryRun ? "将应用" : "已应用"),
            (.unchanged, "无需处理"),
            (.skipped, "跳过"),
            (.unavailable, "不可用"),
            (.attention, "需要注意"),
            (.failed, "失败"),
        ]
        return HStack(spacing: 10) {
            ForEach(items, id: \.0) { outcome, title in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(number(outcome))")
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(number(outcome) > 0 ? tint(outcome) : Color.secondary)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func systemStrip(_ system: OptimizeSystem) -> some View {
        HStack(spacing: 16) {
            Label("内存 \(system.ramUsed)/\(system.ramTotal) GB", systemImage: "memorychip")
            Label("磁盘 \(system.diskUsed)/\(system.diskTotal) GB", systemImage: "internaldrive")
            Label("已运行 \(system.uptimeDays) 天", systemImage: "clock")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func diagnosisCard(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("性能诊断")
                .font(.headline)
            ForEach(Array(lines.prefix(12).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func groups(_ report: OptimizeReport) -> [(outcome: OptimizeOutcome, tasks: [OptimizeTask])] {
        let order: [OptimizeOutcome] = [.attention, .failed, .applied, .skipped, .unavailable, .unchanged, .unknown]
        return order.compactMap { outcome in
            let rows = report.tasks(outcome)
            return rows.isEmpty ? nil : (outcome, rows)
        }
    }

    private func groupCard(_ outcome: OptimizeOutcome, tasks: [OptimizeTask], dryRun: Bool) -> some View {
        let open = !ui.collapsed.contains(outcome.rawValue)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if open {
                    ui.collapsed.insert(outcome.rawValue)
                } else {
                    ui.collapsed.remove(outcome.rawValue)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbol(outcome))
                        .foregroundStyle(tint(outcome))
                    Text(groupTitle(outcome, dryRun: dryRun))
                        .font(.headline)
                    Spacer()
                    Text("\(tasks.count)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Image(systemName: open ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                Divider()
                ForEach(tasks) { task in
                    taskRow(task)
                    if task.id != tasks.last?.id {
                        Divider().padding(.leading, 12)
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func taskRow(_ task: OptimizeTask) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(task.displayTitle)
            ForEach(Array(task.lines.prefix(4).enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func groupTitle(_ outcome: OptimizeOutcome, dryRun: Bool) -> String {
        switch outcome {
        case .attention: return "需要注意"
        case .failed: return "失败"
        case .applied: return dryRun ? "将应用" : "已应用"
        case .skipped: return "已跳过"
        case .unavailable: return "不可用"
        case .unchanged: return "无需处理"
        case .unknown: return "其他"
        }
    }

    private func label(_ outcome: OptimizeOutcome, dryRun: Bool) -> String {
        switch outcome {
        case .applied: return dryRun ? "将应用" : "已应用"
        case .unchanged: return "无需处理"
        case .skipped: return "已跳过"
        case .unavailable: return "不可用"
        case .attention: return "需要注意"
        case .failed: return "失败"
        case .unknown: return "已检查"
        }
    }

    private func symbol(_ outcome: OptimizeOutcome) -> String {
        switch outcome {
        case .attention: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .applied: return "checkmark.circle.fill"
        case .skipped: return "forward.circle"
        case .unavailable: return "minus.circle"
        case .unchanged: return "checkmark.circle"
        case .unknown: return "circle"
        }
    }

    private func tint(_ outcome: OptimizeOutcome) -> Color {
        switch outcome {
        case .attention: return .orange
        case .failed: return Theme.danger
        case .applied: return Color(red: 0.18, green: 0.70, blue: 0.42)
        default: return .secondary
        }
    }
}
