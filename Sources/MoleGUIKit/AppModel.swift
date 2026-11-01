import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published var moPath: String?
    @Published var versionText = ""
    @Published var locating = false
    @Published var showAbout = false

    let clean = CommandJob()
    let optimize = CommandJob()
    let purge = CommandJob()
    let historyJob = CommandJob()
    let analyzeJob = CommandJob()
    let uninstallListJob = CommandJob()
    let uninstallPreview = CommandJob()
    let uninstallLive = PTYJob()

    @Published var cleanPlan: CleanCatalog?
    @Published var cleanSelection = Set<String>()
    @Published var cleanPlanError: String?
    @Published var cleanDelete: CleanDeleteProgress?
    @Published var uninstallApps: [UninstallApp] = []
    @Published var leftoverReview: LeftoverReview?
    @Published var analyzeReport: AnalyzeReport?
    @Published var analyzeParseError: String?
    @Published var historyReport: HistoryReport?
    @Published var historyParseError: String?

    @Published var statusReport: StatusReport?
    @Published var statusStderr = ""
    @Published var statusError: String?
    @Published var statusUpdatedAt: Date?
    @Published var statusRunning = false

    private var watchLine = ""

    init() {
        clean.onFinish = { [weak self] in self?.ingestCleanPreview() }
        uninstallListJob.onFinish = { [weak self] in self?.ingestUninstallList() }
        uninstallLive.onFinish = { [weak self] in self?.finishUninstall() }
        analyzeJob.onFinish = { [weak self] in self?.ingestAnalyze() }
        historyJob.onFinish = { [weak self] in self?.ingestHistory() }
    }

    private var uninstallTargets: [UninstallApp] = []
    private var uninstallGeneration = 0

    func locate() async {
        locating = true
        defer { locating = false }
        let path = await Task.detached { MoleLocator.locate() }.value
        moPath = path
        versionText = ""
        clean.acceptsExecute = false
        optimize.acceptsExecute = false
        purge.acceptsExecute = false
        uninstallPreview.acceptsExecute = false
        guard let path else { return }
        let snapshot = await Task.detached { () -> CommandSnapshot? in
            let run = LiveRun()
            do {
                let arguments = try CommandPolicy.plan(executable: path, action: .version, pseudoTerminal: false)
                try run.start(
                    executable: path,
                    arguments: arguments,
                    environment: MoleEnvironment.make(moPath: path)
                )
            } catch {
                return nil
            }
            run.wait()
            return run.snapshot()
        }.value
        guard let snapshot else { return }
        let text = snapshot.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        versionText = text.isEmpty
            ? snapshot.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            : text
    }

    func runStatusLoop(fast: Bool) async {
        if fast {
            let run = LiveRun(keepStdout: false)
            watchLine = ""
            statusStderr = ""
            statusRunning = true
            run.setDeltaHandler { [weak self] delta, isStderr in
                DispatchQueue.main.async {
                    self?.consumeWatch(delta, isStderr: isStderr)
                }
            }
            defer {
                run.stop()
                statusRunning = false
            }
            do {
                guard let moPath else {
                    statusError = "还没有找到 mo。"
                    return
                }
                let arguments = try CommandPolicy.plan(executable: moPath, action: .statusWatch, pseudoTerminal: false)
                try run.start(
                    executable: moPath,
                    arguments: arguments,
                    environment: MoleEnvironment.make(moPath: moPath)
                )
            } catch {
                statusError = error.localizedDescription
                return
            }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 200_000_000)
                } catch {
                    break
                }
            }
        } else {
            while !Task.isCancelled {
                await refreshStatus()
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    break
                }
            }
        }
    }

    func refreshStatus() async {
        guard let moPath else {
            statusError = "还没有找到 mo。"
            return
        }
        let run = LiveRun()
        statusRunning = true
        defer { statusRunning = false }
        do {
            let arguments = try CommandPolicy.plan(executable: moPath, action: .statusJSON, pseudoTerminal: false)
            try run.start(
                executable: moPath,
                arguments: arguments,
                environment: MoleEnvironment.make(moPath: moPath)
            )
        } catch {
            statusError = error.localizedDescription
            return
        }
        while true {
            if Task.isCancelled {
                run.stop()
                return
            }
            let snapshot = run.snapshot()
            statusStderr = snapshot.stderr
            if let code = snapshot.exitCode {
                applyStatus(stdout: snapshot.stdout, stderr: snapshot.stderr, code: code)
                return
            }
            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch {
                run.stop()
                return
            }
        }
    }

    func previewClean() {
        cleanPlanError = nil
        cleanDelete = nil
        clean.start(moPath: moPath, action: .cleanDryRun, kind: .preview)
    }

    func toggleClean(_ path: String) {
        guard cleanPlan?.entries.contains(where: { $0.path == path && $0.deletable }) == true else { return }
        var next = cleanSelection
        if next.contains(path) {
            next.remove(path)
        } else {
            next.insert(path)
        }
        cleanSelection = next
    }

    func setCleanSelection(_ paths: Set<String>) {
        let allowed = Set(cleanPlan?.entries.filter(\.deletable).map(\.path) ?? [])
        cleanSelection = paths.intersection(allowed)
    }

    func deleteCleanSelection() async -> String? {
        guard let plan = cleanPlan else { return "还没有扫描结果。" }
        let allowed = plan.entries.filter(\.deletable)
        let allowedPaths = Set(allowed.map(\.path))
        let roots = CleanPlan.deletionRoots(cleanSelection.filter { allowedPaths.contains($0) })
        let items = roots.compactMap { path -> CleanDeleteItem? in
            guard let entry = allowed.first(where: { $0.path == path }) else { return nil }
            let group = plan.groups.first { $0.entries.contains { $0.path == path } }?.title ?? ""
            return CleanDeleteItem(path: path, name: entry.name, group: group, bytes: entry.sizeBytes)
        }.sorted { ($0.bytes ?? -1) > ($1.bytes ?? -1) }
        guard !items.isEmpty else { return "没有可以删除的项目。" }
        cleanDelete = CleanDeleteProgress(total: items.count, completed: 0, freedBytes: 0, current: nil, done: [])
        var failed: [String: String] = [:]
        for item in items {
            var progress = cleanDelete ?? CleanDeleteProgress(total: items.count, completed: 0, freedBytes: 0, current: nil, done: [])
            progress.current = item
            cleanDelete = progress
            let outcome = await Task.detached(priority: .userInitiated) { () -> String? in
                guard CleanPlan.deletable(item.path) else { return "这个路径不会从窗口里删除。" }
                do {
                    try FileManager.default.removeItem(at: URL(fileURLWithPath: item.path))
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            var next = cleanDelete ?? progress
            next.completed += 1
            next.current = nil
            if let outcome {
                failed[item.path] = outcome
                next.done.insert(CleanDeleteRow(item: item, ok: false, message: outcome), at: 0)
            } else {
                next.freedBytes += item.bytes ?? 0
                next.done.insert(CleanDeleteRow(item: item, ok: true, message: ""), at: 0)
            }
            cleanDelete = next
        }
        let removed = Set(items.map(\.path).filter { failed[$0] == nil })
        let remaining = plan.entries.filter { entry in
            if removed.contains(entry.path) { return false }
            return !removed.contains { entry.path.hasPrefix($0 + "/") }
        }
        cleanPlan = CleanPlan.catalog(remaining)
        cleanSelection = cleanSelection.intersection(Set(remaining.map(\.path)))
        guard !failed.isEmpty else { return nil }
        return failed.map { path, message in
            "\(Format.homeAbbreviated(path))：\(message)"
        }.sorted().joined(separator: "\n")
    }

    func executeClean() {
        clean.start(moPath: moPath, action: .clean, kind: .execute(phrase: nil))
    }

    func previewOptimize() {
        optimize.start(moPath: moPath, action: .optimizeDryRun, kind: .preview)
    }

    func executeOptimize() {
        optimize.start(moPath: moPath, action: .optimize, kind: .execute(phrase: nil))
    }

    func previewPurge() {
        purge.start(moPath: moPath, action: .purgeDryRun, kind: .preview)
    }

    func executePurge(phrase: String) {
        purge.start(moPath: moPath, action: .purgeYes, kind: .execute(phrase: phrase))
    }

    func loadHistory() {
        historyParseError = nil
        historyJob.start(moPath: moPath, action: .history, kind: .query)
    }

    func scan(path: String) {
        analyzeReport = nil
        analyzeParseError = nil
        analyzeJob.start(moPath: moPath, action: .analyze(path: path), kind: .query)
    }

    func loadUninstallList() {
        uninstallListJob.start(moPath: moPath, action: .uninstallList, kind: .query)
    }

    func previewUninstall(names: [String]) {
        uninstallPreview.start(moPath: moPath, action: .uninstallDryRun(names: names), kind: .preview)
    }

    func startUninstall(apps: [UninstallApp]) {
        uninstallGeneration += 1
        uninstallTargets = apps
        leftoverReview = nil
        uninstallLive.start(moPath: moPath, names: apps.map(\.uninstallName))
    }

    func trashLeftovers(_ paths: [String]) -> [String: String] {
        let offered = Set(leftoverReview?.files.map(\.path) ?? [])
        var failed: [String: String] = [:]
        for path in paths {
            guard offered.contains(path), LeftoverPlan.allowed(path) else {
                failed[path] = "这个路径不在本次卸载留下的相关文件里。"
                continue
            }
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
            } catch {
                failed[path] = error.localizedDescription
            }
        }
        return failed
    }

    private func finishUninstall() {
        guard let code = uninstallLive.exitCode else { return }
        let stopped = uninstallLive.stopped
        let generation = uninstallGeneration
        let log = uninstallLive.stdout
        let targets = uninstallTargets
        if code == 0, !stopped {
            let names = Set(targets.map(\.uninstallName))
            let paths = Set(targets.map(\.path))
            uninstallApps.removeAll { app in
                names.contains(app.uninstallName) || paths.contains(app.path)
            }
        }
        loadUninstallList()
        guard code == 0, !stopped else { return }
        let excluded = Set(targets.map(\.path))
        Task {
            let files = await Task.detached(priority: .userInitiated) {
                LeftoverPlan.collect(log: log, excludingAppPaths: excluded)
            }.value
            guard generation == self.uninstallGeneration, !files.isEmpty else { return }
            leftoverReview = LeftoverReview(id: UUID().uuidString, apps: targets, files: files)
        }
    }

    func volumes() -> [String] {
        let root = URL(fileURLWithPath: "/Volumes")
        let items = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return items
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .map(\.path)
            .sorted()
    }

    func openTerminal(arguments: [String]) -> String? {
        guard let moPath else { return "还没有找到 mo。" }
        let key = arguments.joined(separator: " ")
        let allowed: Set<String> = [
            "clean --whitelist",
            "purge",
            "installer",
            "slim",
            "update",
        ]
        guard allowed.contains(key) else { return "这条命令不会从窗口里打开。" }
        let command = DisplayCommand.string(executable: moPath, arguments: arguments)
        return TerminalLauncher.open(shellCommand: command)
    }

    private func consumeWatch(_ delta: String, isStderr: Bool) {
        if isStderr {
            statusStderr += delta
            if statusStderr.count > 80_000 {
                statusStderr = String(statusStderr.suffix(80_000))
            }
            return
        }
        watchLine += delta
        while let range = watchLine.range(of: "\n") {
            let line = String(watchLine[..<range.lowerBound])
            watchLine = String(watchLine[range.upperBound...])
            if let report = StatusReport.parse(line) {
                statusReport = report
                statusUpdatedAt = Date()
                statusError = nil
            }
        }
    }

    private func applyStatus(stdout: String, stderr: String, code: Int32) {
        statusStderr = stderr
        statusUpdatedAt = Date()
        if let report = StatusReport.parse(stdout) {
            statusReport = report
            statusError = code == 0 ? nil : "mo status 退出码 \(code)。能解析的指标仍然显示在上面。"
        } else if code == 0 {
            statusError = "没能解析 mo status 的 JSON。"
        } else {
            statusError = "mo status 退出码 \(code)。"
        }
    }

    private func ingestCleanPreview() {
        guard clean.commandLine.contains("--dry-run") else { return }
        guard clean.exitCode == 0, !clean.stopped else {
            if clean.exitCode != nil, !clean.stopped {
                cleanPlanError = "扫描没有完成。"
            }
            return
        }
        guard let text = try? String(contentsOfFile: CleanPlan.listPath, encoding: .utf8) else {
            cleanPlan = nil
            cleanSelection = []
            cleanPlanError = "没有读到 ~/.config/mole/clean-list.txt。"
            return
        }
        let catalog = CleanPlan.catalog(CleanPlan.parse(text))
        cleanPlan = catalog
        cleanPlanError = nil
        cleanSelection = Set(catalog.entries.filter { $0.recommended && $0.deletable }.map(\.path))
    }

    private func ingestUninstallList() {
        guard uninstallListJob.exitCode == 0 else {
            uninstallApps = []
            return
        }
        if let apps = UninstallApp.parse(uninstallListJob.stdout) {
            uninstallApps = apps.sorted {
                $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        } else {
            uninstallApps = []
        }
    }

    private func ingestAnalyze() {
        if let report = AnalyzeReport.parse(analyzeJob.stdout) {
            analyzeReport = report
            analyzeParseError = nil
        } else if analyzeJob.exitCode != nil {
            analyzeReport = nil
            analyzeParseError = "没能解析 mo analyze 的 JSON。"
        }
    }

    private func ingestHistory() {
        if let report = HistoryReport.parse(historyJob.stdout) {
            historyReport = report
            historyParseError = nil
        } else if historyJob.exitCode != nil {
            historyReport = nil
            historyParseError = "没能解析 mo history 的 JSON。"
        }
    }
}
