import AppKit
import SwiftUI

final class SidebarState: ObservableObject {
    @Published var section: AppSection = .status
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @StateObject private var sidebar = SidebarState()
    @ObservedObject private var activity = CommandActivity.shared

    var body: some View {
        NavigationSplitView {
            FillColumn(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("mole-gui")
                        .font(.headline)
                    Text(model.moPath == nil ? "未找到 mo" : "本机 mo 的窗口")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !model.versionText.isEmpty {
                        Text(model.versionText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)

                List(AppSection.allCases, selection: $sidebar.section) { item in
                    Label(item.title, systemImage: item.symbol)
                        .tag(item)
                }
                .listStyle(.sidebar)
                .fillsRemainder()

                if activity.snapshot.running {
                    RunningCommandCard(snapshot: activity.snapshot) {
                        activity.stop()
                    }
                }

                Button("关于") { model.showAbout = true }
                    .buttonStyle(.borderless)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationSplitViewColumnWidth(min: 196, ideal: 220, max: 260)
        } detail: {
            switch sidebar.section {
            case .status:
                StatusView(model: model)
            case .clean:
                CleanView(model: model, job: model.clean)
            case .uninstall:
                UninstallView(model: model, listJob: model.uninstallListJob, terminal: model.uninstallLive)
            case .disk:
                AnalyzeView(model: model, job: model.analyzeJob)
            case .purge:
                PurgeView(model: model, job: model.purge)
            case .optimize:
                OptimizeView(model: model, job: model.optimize)
            case .history:
                HistoryView(model: model, job: model.historyJob)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SidebarSeamAligner())
        .sheet(isPresented: $model.showAbout) {
            AboutView(model: model)
        }
        .onChange(of: sidebar.section) { section in
            if section != .status {
                model.stopStatusWatch()
            }
        }
        .task { await model.locate() }
    }
}

private struct RunningCommandCard: View {
    var snapshot: ActivitySnapshot
    var stop: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text(snapshot.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(shownCommand)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(4)
                .textSelection(.enabled)
            if !snapshot.detail.isEmpty {
                Text(snapshot.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Button("停止", action: stop)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(nsColor: .controlBackgroundColor)))
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    /// 侧栏很窄，完整路径会在参数中间断开。这里只留可执行文件名，后面的参数原样保留。
    private var shownCommand: String {
        let line = snapshot.commandLine
        guard let space = line.firstIndex(of: " ") else {
            return (line as NSString).lastPathComponent
        }
        let head = String(line[..<space])
        guard !head.hasPrefix("'"), (head as NSString).lastPathComponent == "mo" else { return line }
        return "mo" + line[space...]
    }
}

/// 标题栏自己画的侧栏接缝比分割线靠左约 2pt，拖动分割线后系统会把接缝画回去，所以每次布局再对齐一次。
private struct SidebarSeamAligner: NSViewRepresentable {
    func makeNSView(context: Context) -> SidebarSeamAlignerView {
        SidebarSeamAlignerView()
    }

    func updateNSView(_ nsView: SidebarSeamAlignerView, context: Context) {
        nsView.schedule()
    }
}

private final class SidebarSeamAlignerView: NSView {
    private var tokens: [NSObjectProtocol] = []
    private var watching = false
    private var scheduled = false

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        watching = false
        tokens.forEach(NotificationCenter.default.removeObserver)
        tokens.removeAll()
        schedule()
    }

    override func layout() {
        super.layout()
        schedule()
    }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }

    func schedule() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduled = false
            self.align()
        }
    }

    private func align() {
        guard let window, let theme = window.contentView?.superview else { return }
        guard let split = first(window.contentView, where: { $0 is NSSplitView }) as? NSSplitView else { return }
        if !watching {
            watching = true
            for view in [split] + split.subviews {
                view.postsFrameChangedNotifications = true
                let token = NotificationCenter.default.addObserver(
                    forName: NSView.frameDidChangeNotification,
                    object: view,
                    queue: .main
                ) { [weak self] _ in
                    self?.schedule()
                }
                tokens.append(token)
            }
        }

        let panes = split.subviews.filter { view in
            let name = String(describing: type(of: view))
            return view.frame.width > 40
                && !name.contains("Divider")
                && !name.contains("Collapsed")
        }
        guard let detail = panes.max(by: { $0.frame.minX < $1.frame.minX }) else { return }
        // 分割线画在侧栏右缘外侧。标题栏接缝要跟内容区左缘对齐，竖线才落在同一个角上。
        let seam = detail.convert(CGPoint.zero, to: nil).x

        guard let titlebar = first(theme, where: { String(describing: type(of: $0)) == "NSTitlebarView" }) else { return }
        for view in titlebar.subviews + (titlebar.superview?.subviews ?? []) {
            let name = String(describing: type(of: view))
            let sidebarBackground = name.contains("TitlebarBackground") && view.frame.minX < 1 && view.frame.width > 40
            let contentBackground = name.contains("TitlebarBackground")
                && view.frame.minX > 1
                && view.frame.width > titlebar.bounds.width * 0.4
            let blocker = name.contains("Blocking")
            guard sidebarBackground || contentBackground || blocker else { continue }
            guard let host = view.superview else { continue }
            let origin = view.convert(CGPoint.zero, to: nil).x
            if sidebarBackground {
                let width = seam - origin
                guard width > 40, abs(view.frame.width - width) > 0.5 else { continue }
                var frame = view.frame
                frame.size.width = width
                view.frame = frame
                continue
            }
            let delta = seam - origin
            guard delta > 0.5, delta < 8 else { continue }
            var frame = view.frame
            frame.origin.x = host.convert(CGPoint(x: seam, y: 0), from: nil).x
            if contentBackground {
                frame.size.width -= delta
            }
            view.frame = frame
        }
    }

    private func first(_ root: NSView?, where match: (NSView) -> Bool) -> NSView? {
        guard let root else { return nil }
        if match(root) { return root }
        for child in root.subviews {
            if let found = first(child, where: match) { return found }
        }
        return nil
    }
}
