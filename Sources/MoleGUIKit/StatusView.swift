import AppKit
import SwiftUI

final class StatusUI: ObservableObject {
    @Published var diskIndex = 0

    func stepDisk(_ delta: Int, count: Int) {
        guard count > 1 else { return }
        diskIndex = (diskIndex + delta + count) % count
    }
}

struct StatusView: View {
    @ObservedObject var model: AppModel
    @StateObject private var ui = StatusUI()
    @State private var watchToken = 0

    var body: some View {
        PageShell(
            model: model,
            title: "状态",
            subtitle: "约每 2 秒读取一次 mo status。进程只展示，不能结束。"
        ) {
            FillColumn(spacing: 12) {
                HStack {
                    if model.statusReport == nil, model.statusRunning {
                        ProgressView().controlSize(.small)
                        Text("正在读取")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if model.statusPaused {
                        Text("已停止读取")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("继续") { watchToken += 1 }
                            .buttonStyle(.borderless)
                            .font(.caption)
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
                if !model.statusStderr.isEmpty {
                    Text(model.statusStderr)
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    healthCard
                    cpuCard
                    diskCard
                    networkCard
                }

                processSection
                    .fillsRemainder()
            }
        }
        .task(id: watchToken) {
            await model.runStatusLoop(fast: true)
        }
    }

    private var report: StatusReport? { model.statusReport }

    private var healthCard: some View {
        DashCard(title: "健康度", symbol: "sun.max") {
            let score = report?.healthScore
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(score.map(String.init) ?? "—")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(healthColor(score))
                if let score {
                    Text(Format.healthGrade(score))
                        .font(.title3.weight(.medium))
                }
            }
            if let note = Format.healthNote(message: report?.healthScoreMessage, pressure: report?.memory?.pressure) {
                Text(note)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text(Format.uptimeLabel(seconds: report?.uptimeSeconds, raw: report?.uptime))
                .font(.caption)
                .foregroundStyle(.secondary)
            badgeRow
        }
    }

    @ViewBuilder
    private var badgeRow: some View {
        let hardware = report?.hardware
        let badges = [
            Format.chipLabel(hardware?.cpuModel),
            Format.ramLabel(hardware?.totalRAM),
            hardware?.osVersion
        ].compactMap { $0 }
        if !badges.isEmpty {
            HStack(spacing: 6) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private var cpuCard: some View {
        let cpu = report?.cpu
        let temp = report?.thermal?.cpuTemp
        return DashCard(title: "CPU", symbol: "cpu", badge: tempText(temp)) {
            Text(cpu?.usage.map { Format.percent($0, digits: 0) } ?? "—")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
            if let cores = cpu?.perCore, !cores.isEmpty {
                CoreBars(values: cores, color: Color(red: 0.18, green: 0.62, blue: 0.55))
            }
            Text(cpuCaption(cpu))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var diskCard: some View {
        DashCard(title: "可用空间", symbol: "internaldrive", badge: selectedDisk.flatMap { $0.total.map { Format.storageBytes($0) } }) {
            if orderedDisks.count > 1 {
                diskSwitcher
            }
            if let disk = selectedDisk, let total = disk.total, let used = disk.used {
                let free = total >= used ? total - used : 0
                Text(Format.storageBytes(free))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                CapsuleMeter(fraction: min(max((disk.usedPercent ?? 0) / 100, 0), 1), color: Color(red: 0.86, green: 0.62, blue: 0.22))
                Text(diskCaption(disk))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("还没有磁盘数据")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var diskSwitcher: some View {
        HStack(spacing: 6) {
            Button {
                ui.stepDisk(-1, count: orderedDisks.count)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            Text(selectedDisk.map(diskTitle) ?? "磁盘")
                .font(.caption.weight(.medium))
                .lineLimit(1)
            if selectedDisk?.external == true {
                Text("外置")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
            Button {
                ui.stepDisk(1, count: orderedDisks.count)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            Spacer(minLength: 0)
        }
    }

    private var networkCard: some View {
        let iface = primaryNetwork
        return DashCard(title: "网络", symbol: "network", badge: iface?.name) {
            Text(iface?.rxRateMBs.map(Format.rateMBps) ?? "—")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
            if let history = report?.networkHistory?.rxHistory, history.count > 1 {
                Sparkline(values: history, color: Color(red: 0.25, green: 0.48, blue: 0.75))
            }
            Text("上传 \(iface?.txRateMBs.map(Format.rateMBps) ?? "—")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var processSection: some View {
        let processes = (report?.topProcesses ?? []).sorted { ($0.memoryBytes ?? 0) > ($1.memoryBytes ?? 0) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet")
                    .font(.caption)
                Text("名称 (\(processes.count))")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 4)
            }
            .foregroundStyle(.secondary)
            if let procs = report?.procs, procs > processes.count {
                Text("共 \(procs) 个进程")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if report?.processStale == true {
                Text("进程采样已过期，数字仍只是展示。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if processes.isEmpty {
                Text("还没有进程数据")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                HStack {
                    Spacer()
                    Text("内存")
                        .frame(width: 72, alignment: .trailing)
                    Text("% CPU")
                        .frame(width: 92, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(processes) { row in
                                HStack(spacing: 8) {
                                    processIcon(row.name)
                                    Text(row.name ?? "进程")
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(row.memoryBytes.map { Format.bytes($0) } ?? "—")
                                        .monospacedDigit()
                                        .frame(width: 72, alignment: .trailing)
                                    cpuMeter(row.cpu)
                                }
                                .font(.callout)
                            }
                            if let alerts = report?.processAlerts, !alerts.isEmpty {
                                Text("持续高 CPU：\(alerts.map { "\($0.name ?? "进程") \($0.cpu.map { Format.percent($0, digits: 0) } ?? "")" }.joined(separator: "，"))")
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let zombies = report?.zombieCount, zombies > 0 {
                                Text("僵尸进程 \(zombies) 个。这里不结束它们，健康分也不因此改变。")
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: max(proxy.size.width, 0), height: max(proxy.size.height, 0))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func processIcon(_ name: String?) -> some View {
        let image = name.flatMap { appIcon(named: $0) }
        return Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "app.dashed")
                    .font(.caption)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func cpuMeter(_ cpu: Double?) -> some View {
        let fraction = min(max((cpu ?? 0) / 100, 0), 1)
        let hot = (cpu ?? 0) >= 50
        return HStack(spacing: 6) {
            CapsuleMeter(fraction: fraction, color: hot ? Color(red: 0.86, green: 0.55, blue: 0.20) : Color.secondary.opacity(0.45))
                .frame(width: 36)
            Text(cpu.map { Format.percent($0, digits: 1) } ?? "—")
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .frame(width: 92, alignment: .trailing)
    }

    private var orderedDisks: [StatusReport.DiskStatus] {
        (report?.disks ?? []).sorted { lhs, rhs in
            diskRank(lhs) < diskRank(rhs)
        }
    }

    private var selectedDisk: StatusReport.DiskStatus? {
        let disks = orderedDisks
        guard !disks.isEmpty else { return nil }
        let index = ((ui.diskIndex % disks.count) + disks.count) % disks.count
        return disks[index]
    }

    private func diskRank(_ disk: StatusReport.DiskStatus) -> Int {
        if disk.mount == "/" { return 0 }
        if disk.external == true { return 2 }
        return 1
    }

    private func diskTitle(_ disk: StatusReport.DiskStatus) -> String {
        guard let mount = disk.mount, !mount.isEmpty else { return "磁盘" }
        if mount == "/" { return "启动盘" }
        return (mount as NSString).lastPathComponent
    }

    private var primaryNetwork: StatusReport.NetworkIface? {
        let ifaces = report?.network ?? []
        return ifaces.sorted { lhs, rhs in
            let left = (lhs.rxRateMBs ?? 0) + (lhs.txRateMBs ?? 0)
            let right = (rhs.rxRateMBs ?? 0) + (rhs.txRateMBs ?? 0)
            if left != right { return left > right }
            return !(lhs.ip ?? "").isEmpty && (rhs.ip ?? "").isEmpty
        }.first
    }

    private func cpuCaption(_ cpu: StatusReport.CPUStatus?) -> String {
        let usage = cpu?.usage ?? 0
        let state = usage < 70 ? "正常" : (usage < 90 ? "偏高" : "繁忙")
        let cores = cpu?.logicalCPU ?? cpu?.coreCount
        let coreText = cores.map { "\($0) 核" } ?? "核心数未知"
        let load = cpu?.load1.map { String(format: "%.1f", $0) } ?? "—"
        return "\(state) · \(coreText) · 平均负载 \(load)"
    }

    private func diskCaption(_ disk: StatusReport.DiskStatus) -> String {
        let read = report?.diskIO?.readRate.map(Format.rateMBps) ?? "—"
        let write = report?.diskIO?.writeRate.map(Format.rateMBps) ?? "—"
        var line = "读 \(read) · 写 \(write)"
        if let smart = disk.smartStatus, !smart.isEmpty, smart.lowercased() != "verified" {
            line += " · SMART \(smart)"
        }
        return line
    }

    private func tempText(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        return "\(Int(value.rounded()))°C"
    }

    private func healthColor(_ score: Int?) -> Color {
        guard let score else { return Color.secondary }
        if score >= 80 { return Color(red: 0.18, green: 0.55, blue: 0.34) }
        if score >= 50 { return Color(red: 0.76, green: 0.48, blue: 0.12) }
        return Theme.danger
    }

    private func appIcon(named name: String) -> NSImage? {
        let apps = NSWorkspace.shared.runningApplications
        if let exact = apps.first(where: { $0.localizedName == name }) {
            return exact.icon
        }
        return apps.compactMap { app -> (Int, NSImage)? in
            guard let title = app.localizedName, title.count >= 2, name.hasPrefix(title), let icon = app.icon else { return nil }
            return (title.count, icon)
        }
        .max { $0.0 < $1.0 }?
        .1
    }
}

private struct DashCard<Content: View>: View {
    var title: String
    var symbol: String
    var badge: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                if let badge, !badge.isEmpty {
                    Text(badge)
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct CoreBars: View {
    var values: [Double]
    var color: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 8, height: max(CGFloat(3), 26 * CGFloat(min(max(value, 0), 100) / 100)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .bottomLeading)
    }
}

private struct Sparkline: View {
    var values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let peak = max(values.max() ?? 0, 0.001)
            Path { path in
                guard values.count > 1 else { return }
                for index in values.indices {
                    let x = geo.size.width * CGFloat(index) / CGFloat(values.count - 1)
                    let y = geo.size.height * (1 - CGFloat(values[index] / peak))
                    let point = CGPoint(x: x, y: y)
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 32)
    }
}

private struct CapsuleMeter: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(4, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 6)
    }
}
