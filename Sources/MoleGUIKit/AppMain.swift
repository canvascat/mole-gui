import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = AppIconFactory.image(side: 512)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        ProcessTracker.shared.stopAll()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

public struct MoleGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(
                    minWidth: 960,
                    idealWidth: 1120,
                    maxWidth: .infinity,
                    minHeight: 680,
                    idealHeight: 760,
                    maxHeight: .infinity
                )
        }
        .defaultSize(width: 1120, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 mole-gui") {
                    model.showAbout = true
                }
            }
            CommandGroup(replacing: .newItem) {}
        }
    }
}
