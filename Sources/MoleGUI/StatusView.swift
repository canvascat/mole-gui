import SwiftUI

final class StatusUI: ObservableObject {
    @Published var fast = false
}

struct StatusView: View {
    @ObservedObject var model: AppModel
    @StateObject private var ui = StatusUI()

    var body: some View {
        PageShell(
            model: model,
            title: "状态",
            subtitle: "定时执行 mo status --json。进程表只展示，不能结束进程。僵尸进程不改变健康分。"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Toggle("更快刷新（2 秒）", isOn: $ui.fast)
                        .toggleStyle(.switch)
                    Button("立即刷新") {
                        Task { await model.refreshStatus() }
                    }
                    .disabled(model.moPath == nil)
                    if model.statusRunning {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    if let updated = model.statusUpdatedAt {
                        Text(updated.formatted(date: .omitted, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = model.statusError {
                    WarningNote(text: error)
                }

                BoundedScroll(minHeight: 200) {
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            cpuCard
                            memoryCard
                        }
                        diskCard
                        processCard
                        if !model.statusStderr.isEmpty {
                            LogBox(title: "标准错误", text: model.statusStderr, minHeight: 80, maxHeight: 160)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task(id: ui.fast) {
            await model.runStatusLoop(fast: ui.fast)
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 24) {
            scoreRing
            VStack(alignment: .leading, spacing: 6) {
                Text(model.statusReport?.host ?? "等待 mo status")
                    .font(.title3.weight(.semibold))
                if let hardware = model.statusReport?.hardware {
                    Text([hardware.model, hardware.cpuModel, hardware.osVersion].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                }
                Text("开机时间 \(model.statusReport?.uptime ?? "—")")
                if let message = model.statusReport?.healthScoreMessage, !message.isEmpty {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var scoreRing: some View {
        let score = model.statusReport?.healthScore
        let fraction = CGFloat(min(max(score ?? 0, 0), 100)) / 100
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.15), lineWidth: 12)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(healthColor(score), style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(score.map(String.init) ?? "—")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text("健康分")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 120, height: 120)
    }

    private var cpuCard: some View {
        MetricCard(title: "CPU") {
            let cpu = model.statusReport?.cpu
            Text(cpu?.usage.map { Format.percent($0, digits: 1) } ?? "—")
                .font(.title2.weight(.semibold).monospacedDigit())
            Text(loadLine(cpu))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var memoryCard: some View {
        MetricCard(title: "内存") {
            let memory = model.statusReport?.memory
            Text(memory?.usedPercent.map { Format.percent($0, digits: 0) } ?? "—")
                .font(.title2.weight(.semibold).monospacedDigit())
            Text(memoryLine(memory))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var diskCard: some View {
        MetricCard(title: "磁盘") {
            let disks = model.statusReport?.disks ?? []
            if disks.isEmpty {
                Text("还没有磁盘数据")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(disks) { disk in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(disk.mount ?? "磁盘")
                            if disk.external == true {
                                Text("外置")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                            }
                            Spacer()
                            Text(disk.usedPercent.map { Format.percent($0, digits: 0) } ?? "—")
                                .monospacedDigit()
                        }
                        ProgressView(value: min(max((disk.usedPercent ?? 0) / 100, 0), 1))
                        Text(diskCaption(disk))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var processCard: some View {
        MetricCard(title: "进程") {
            Text("只展示。没有结束进程的按钮。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.statusReport?.processStale == true {
                Text("进程采样已过期，数字仍只是展示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            let processes = model.statusReport?.topProcesses ?? []
            if processes.isEmpty {
                Text("还没有进程数据")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(processes.prefix(12)) { row in
                    HStack {
                        Text(row.name ?? "进程")
                            .lineLimit(1)
                        Spacer()
                        Text(row.cpu.map { Format.percent($0, digits: 1) } ?? "—")
                            .monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
                        Text(row.memoryBytes.map { Format.bytes($0) } ?? "—")
                            .monospacedDigit()
                            .frame(width: 88, alignment: .trailing)
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            if let alerts = model.statusReport?.processAlerts, !alerts.isEmpty {
                Text("持续高 CPU：\(alerts.map { "\($0.name ?? "进程") \($0.cpu.map { Format.percent($0, digits: 0) } ?? "")" }.joined(separator: "，"))")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let zombies = model.statusReport?.zombieCount, zombies > 0 {
                Text("僵尸进程 \(zombies) 个。这里不结束它们，健康分也不因此改变。")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func healthColor(_ score: Int?) -> Color {
        guard let score else { return Color.secondary }
        if score >= 80 { return Color(red: 0.18, green: 0.55, blue: 0.34) }
        if score >= 50 { return Color(red: 0.76, green: 0.48, blue: 0.12) }
        return Theme.danger
    }

    private func loadLine(_ cpu: StatusReport.CPUStatus?) -> String {
        let one = cpu?.load1.map(Format.load) ?? "—"
        let five = cpu?.load5.map(Format.load) ?? "—"
        let fifteen = cpu?.load15.map(Format.load) ?? "—"
        let cores = cpu?.logicalCPU ?? cpu?.coreCount
        let coreText = cores.map { "\($0) 个逻辑核心" } ?? "核心数未知"
        return "负载 \(one) / \(five) / \(fifteen) · \(coreText)"
    }

    private func memoryLine(_ memory: StatusReport.MemoryStatus?) -> String {
        let used = memory?.used.map { Format.bytes($0) } ?? "—"
        let total = memory?.total.map { Format.bytes($0) } ?? "—"
        return "\(used) / \(total) · 压力 \(Format.memoryPressure(memory?.pressure))"
    }

    private func diskCaption(_ disk: StatusReport.DiskStatus) -> String {
        let used = disk.used.map { Format.bytes($0) } ?? "—"
        let total = disk.total.map { Format.bytes($0) } ?? "—"
        let smart = disk.smartStatus?.isEmpty == false ? disk.smartStatus! : "SMART 未知"
        return "\(used) / \(total) · \(smart)"
    }
}
