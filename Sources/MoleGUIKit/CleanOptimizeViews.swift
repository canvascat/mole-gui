import SwiftUI

final class CleanUI: ObservableObject {
    @Published var confirm = false
    @Published var terminalError: String?
}

struct CleanView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var job: CommandJob
    @StateObject private var ui = CleanUI()

    var body: some View {
        PageShell(
            model: model,
            title: "清理",
            subtitle: "先看 mo clean --dry-run 的原文，确认后才执行 mo clean。没有逐条复选框。"
        ) {
            FillColumn(spacing: 16) {
                WarningNote(text: "这是整批用户级清理，永久删除，默认包含废纸篓，不能在窗口里取消其中几行。取消必须发生在启动之前。开始之后可以停止进程，但已经删掉的文件不会回来。系统缓存可能弹出 macOS 自己的管理员授权，本窗口不会用 sudo。")
                HStack {
                    Button("预览") { model.previewClean() }
                        .disabled(model.moPath == nil || job.running)
                    Button("开始清理") { ui.confirm = true }
                        .disabled(model.moPath == nil || job.running || !job.acceptsExecute)
                        .tint(Theme.danger)
                    if job.running {
                        Button("停止") { job.stop() }
                    }
                    Button("编辑保护名单") {
                        ui.terminalError = model.openTerminal(arguments: ["clean", "--whitelist"])
                    }
                    .disabled(model.moPath == nil)
                    Spacer()
                }
                .buttonStyle(.bordered)
                if !job.acceptsExecute, !job.running {
                    InfoNote(text: "请先预览。预览成功之后，「开始清理」才会亮。")
                }
                Text("保护名单文件：\(Format.homeAbbreviated(NSHomeDirectory() + "/.config/mole/whitelist"))。读失败时 CLI 会停，窗口不会自动重试。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let terminalError = ui.terminalError {
                    Text(terminalError).foregroundStyle(Theme.danger)
                }
                StreamPanes(job: job, destructive: true)
                    .fillsRemainder()
            }
        }
        .alert("开始整批清理？", isPresented: $ui.confirm) {
            Button("取消", role: .cancel) {}
            Button("开始清理", role: .destructive) { model.executeClean() }
        } message: {
            Text("将执行 mo clean。这是整批用户级清理，永久删除，默认包含废纸篓，不能取消其中几行。系统部分如果要管理员权限，会由 macOS 自己弹出授权。")
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

final class PurgeUI: ObservableObject {
    @Published var confirm = false
    @Published var phrase = ""
    @Published var terminalError: String?
}

struct PurgeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var job: CommandJob
    @StateObject private var ui = PurgeUI()

    var body: some View {
        PageShell(
            model: model,
            title: "项目产物",
            subtitle: "mo purge --dry-run 只展示候选。删除只有一个动作：确认后执行 mo purge --yes。"
        ) {
            FillColumn(spacing: 16) {
                WarningNote(text: "这会永久删除全部非近期、非云同步的候选，不能只删其中几项，也不会进废纸篓。node_modules、构建目录一类东西删了要重新安装。更稳的做法是在终端里自己跑 mo purge。")
                HStack {
                    Button("预览") { model.previewPurge() }
                        .disabled(model.moPath == nil || job.running)
                    Button("在终端中打开") {
                        ui.terminalError = model.openTerminal(arguments: ["purge"])
                    }
                    .disabled(model.moPath == nil)
                    Button("永久删除全部非近期、非云同步的候选，不能只删其中几项") {
                        ui.phrase = ""
                        ui.confirm = true
                    }
                    .disabled(model.moPath == nil || job.running || !job.acceptsExecute)
                    .tint(Theme.danger)
                    if job.running {
                        Button("停止") { job.stop() }
                    }
                    Spacer()
                }
                .buttonStyle(.bordered)
                if !job.acceptsExecute, !job.running {
                    InfoNote(text: "请先预览。窗口不能替你挑其中几项。")
                }
                if let terminalError = ui.terminalError {
                    Text(terminalError).foregroundStyle(Theme.danger)
                }
                StreamPanes(job: job, destructive: true)
                    .fillsRemainder()
            }
        }
        .sheet(isPresented: $ui.confirm) {
            VStack(alignment: .leading, spacing: 14) {
                Text("永久删除全部符合条件的项目产物")
                    .font(.title3.weight(.semibold))
                Text("将执行 mo purge --yes。这会永久删除全部非近期、非云同步的候选，不能只删其中几项，也不会进废纸篓。")
                    .fixedSize(horizontal: false, vertical: true)
                TextField("输入「永久删除」", text: $ui.phrase)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("取消") { ui.confirm = false }
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("执行 mo purge --yes") {
                        model.executePurge(phrase: ui.phrase)
                        ui.confirm = false
                    }
                    .disabled(ui.phrase != CommandPolicy.purgeConfirmation)
                    .keyboardShortcut(.defaultAction)
                    .tint(Theme.danger)
                }
            }
            .padding(24)
            .frame(width: 480)
        }
    }
}
