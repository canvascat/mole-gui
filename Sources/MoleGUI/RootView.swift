import SwiftUI

final class SidebarState: ObservableObject {
    @Published var section: AppSection = .status
}

struct RootView: View {
    @ObservedObject var model: AppModel
    @StateObject private var sidebar = SidebarState()

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
                UninstallView(model: model, listJob: model.uninstallListJob, preview: model.uninstallPreview, terminal: model.uninstallLive)
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
        .sheet(isPresented: $model.showAbout) {
            AboutView(model: model)
        }
        .task { await model.locate() }
    }
}
