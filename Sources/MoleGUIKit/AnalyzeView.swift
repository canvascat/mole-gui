import AppKit
import SwiftUI
import UniformTypeIdentifiers

final class AnalyzeUI: ObservableObject {
    @Published var trail: [String] = []
    @Published var picking = false
    @Published var started = false
}

struct AnalyzeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var job: CommandJob
    @StateObject private var ui = AnalyzeUI()

    var body: some View {
        PageShell(
            model: model,
            title: "磁盘",
            subtitle: "mo analyze --json 只读。这一页没有删除按钮。数字是扫描估算，不保证能腾出同样的空间。"
        ) {
            FillColumn(spacing: 16) {
                InfoNote(text: "未完成的大小后面会加 +。大小为 0 且状态是无法读取时，不代表目录是空的。扫资源库深处时，把完全磁盘访问权限授给 mole-gui，它才是启动 mo 的程序。失败时显示 CLI 原文，不会转去执行删除。")
                HStack {
                    Button("主目录") { open(NSHomeDirectory(), reset: true) }
                        .disabled(model.moPath == nil || job.running)
                    Button("选择文件夹") { ui.picking = true }
                        .disabled(model.moPath == nil || job.running)
                    Menu("选择 /Volumes") {
                        let volumes = model.volumes()
                        if volumes.isEmpty {
                            Button("没有挂载项") {}.disabled(true)
                        }
                        ForEach(volumes, id: \.self) { path in
                            Button(path) { open(path, reset: true) }
                        }
                    }
                    .disabled(model.moPath == nil || job.running)
                    if job.running {
                        Button("停止") { job.stop() }
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                .buttonStyle(.bordered)

                if !ui.trail.isEmpty {
                    HorizontalStrip(height: 32) {
                        HStack(spacing: 6) {
                            ForEach(Array(ui.trail.enumerated()), id: \.offset) { index, path in
                                Button(Format.homeAbbreviated(path)) {
                                    ui.trail = Array(ui.trail.prefix(index + 1))
                                    model.scan(path: path)
                                }
                                .buttonStyle(.borderless)
                                .disabled(job.running)
                                if index < ui.trail.count - 1 {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let error = job.error {
                    Text(error).foregroundStyle(Theme.danger)
                }
                if let parseError = model.analyzeParseError {
                    Text(parseError).foregroundStyle(Theme.danger)
                }

                scanBody
                    .fillsRemainder()
            }
        }
        .fileImporter(isPresented: $ui.picking, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                open(url.path, reset: true)
            }
        }
        .task {
            guard !ui.started else { return }
            ui.started = true
            if model.moPath != nil {
                open(NSHomeDirectory(), reset: true)
            }
        }
        .onChange(of: model.moPath) { path in
            if path != nil, ui.trail.isEmpty {
                open(NSHomeDirectory(), reset: true)
            }
        }
    }

    @ViewBuilder
    private var scanBody: some View {
        if let report = model.analyzeReport {
            FillColumn(spacing: 12) {
                summary(report)
                PaneScroll {
                    VStack(alignment: .leading, spacing: 12) {
                        entryList(report)
                        if !report.largeFiles.isEmpty {
                            largeFiles(report.largeFiles)
                        }
                    }
                }
                .fillsRemainder()
                if !job.stderr.isEmpty {
                    LogPane(title: "标准错误", text: job.stderr)
                        .frame(height: 150)
                }
            }
        } else {
            LogPane(
                title: "标准错误",
                text: job.stderr,
                empty: job.running ? "正在扫描…" : "选择目录后，扫描输出会显示在这里。"
            )
        }
    }

    private func open(_ path: String, reset: Bool) {
        if reset {
            ui.trail = [path]
        }
        model.scan(path: path)
    }

    private func summary(_ report: AnalyzeReport) -> some View {
        HStack(spacing: 16) {
            Label(Format.scanStatus(report.scanStatus), systemImage: "circle.fill")
                .font(.callout)
                .foregroundStyle(statusColor(report.scanStatus))
            Text(Format.bytes(report.totalSize, scanStatus: report.scanStatus))
                .font(.title3.weight(.semibold).monospacedDigit())
            if let files = report.totalFiles {
                Text("\(files) 个文件")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func entryList(_ report: AnalyzeReport) -> some View {
        let maxSize = report.entries.map { max($0.size ?? 0, 0) }.max() ?? 1
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(report.entries) { entry in
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        guard entry.isDir == true, let path = entry.path else { return }
                        ui.trail.append(path)
                        model.scan(path: path)
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: entry.isDir == true ? "folder" : "doc")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.name ?? entry.path ?? "未命名")
                                    .lineLimit(1)
                                Text(Format.scanStatus(entry.scanStatus))
                                    .font(.caption2)
                                    .foregroundStyle(statusColor(entry.scanStatus))
                                GeometryReader { geo in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Theme.accent.opacity(0.45))
                                        .frame(width: geo.size.width * barFraction(entry.size, maxSize: maxSize))
                                }
                                .frame(height: 6)
                            }
                            Spacer(minLength: 8)
                            Text(Format.bytes(entry.size, scanStatus: entry.scanStatus))
                                .monospacedDigit()
                            if entry.isDir == true {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(entry.isDir != true || job.running)
                    if let path = entry.path {
                        Button("在访达中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 8)
                Divider()
            }
        }
    }

    private func largeFiles(_ files: [AnalyzeReport.FileEntry]) -> some View {
        MetricCard(title: "较大的文件") {
            ForEach(files) { file in
                HStack {
                    Text(file.name ?? file.path ?? "文件")
                        .lineLimit(1)
                    Spacer()
                    Text(Format.bytes(file.size, scanStatus: "complete"))
                        .monospacedDigit()
                    if let path = file.path {
                        Button("在访达中显示") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func barFraction(_ size: Int64?, maxSize: Int64) -> CGFloat {
        guard let size, size > 0, maxSize > 0 else { return 0 }
        return CGFloat(min(Double(size) / Double(maxSize), 1))
    }

    private func statusColor(_ status: String?) -> Color {
        switch status {
        case "complete": return Color(red: 0.18, green: 0.55, blue: 0.34)
        case "partial": return Color(red: 0.76, green: 0.48, blue: 0.12)
        default: return Theme.danger
        }
    }
}
