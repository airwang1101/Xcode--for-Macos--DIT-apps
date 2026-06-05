import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: AppViewModel?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard viewModel?.hasActiveTransfers == true else {
            return .terminateNow
        }
        viewModel?.importError = "仍有导入或校验任务正在执行。请先取消并等待报告生成完成后再退出。"
        return .terminateCancel
    }
}

@main
struct AirwangDITForMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(minWidth: 980, minHeight: 720)
                .onAppear {
                    appDelegate.viewModel = viewModel
                }
        }
        .defaultSize(width: 1460, height: 920)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
