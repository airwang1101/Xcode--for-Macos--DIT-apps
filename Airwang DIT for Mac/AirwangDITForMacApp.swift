import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var viewModel: AppViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        presentMainWindowForUITesting()
        #endif
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        #if DEBUG
        presentMainWindowForUITesting()
        #endif
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard viewModel?.hasActiveFileOperations == true || viewModel?.isExportingDiagnostics == true else {
            return .terminateNow
        }
        if viewModel?.isExportingPDFReport == true {
            viewModel?.importError = viewModel?.localized("PDF 报告正在导出。请先取消并等待导出收尾后再退出。")
        } else {
            viewModel?.importError = viewModel?.localized("仍有导入、校验、规整或诊断导出正在执行。请先取消并等待文件操作收尾后再退出。")
        }
        return .terminateCancel
    }

    #if DEBUG
    private func presentMainWindowForUITesting() {
        guard ProcessInfo.processInfo.environment["AIRWANG_DIT_UI_TESTING"] == "1" else { return }

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.isVisible && !window.isMiniaturized {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
    }
    #endif
}

@main
struct AirwangDITForMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .frame(
                    minWidth: MainWindowLayoutPolicy.minimumWidth,
                    minHeight: MainWindowLayoutPolicy.minimumHeight
                )
                .background(
                    MainWindowConfigurator(
                        minSize: NSSize(
                            width: MainWindowLayoutPolicy.minimumWidth,
                            height: MainWindowLayoutPolicy.minimumHeight
                        )
                    )
                )
                .overlay(alignment: .top) {
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: 78)
                            .allowsHitTesting(false)
                        MainWindowDragRegion()
                        Color.clear
                            .frame(width: 220)
                            .allowsHitTesting(false)
                    }
                    .frame(height: 28)
                    .accessibilityHidden(true)
                }
                .onAppear {
                    appDelegate.viewModel = viewModel
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .help) {
                Button(viewModel.localized("新手教程")) { viewModel.reopenGettingStarted() }
                    .disabled(!viewModel.canPresentGettingStarted)
                Button(viewModel.localized("导出诊断")) {
                    viewModel.exportDiagnostics()
                }
                .disabled(viewModel.isExportingDiagnostics || viewModel.isChoosingDiagnosticsDestination)
                Button(viewModel.localized("取消 PDF 导出")) {
                    viewModel.cancelPDFReportExport()
                }
                .disabled(!viewModel.isExportingPDFReport)
            }
        }

        Settings {
            AppSettingsView()
                .environmentObject(viewModel)
        }
    }
}

private struct MainWindowConfigurator: NSViewRepresentable {
    let minSize: NSSize

    final class Coordinator {
        weak var configuredWindow: NSWindow?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // updateNSView 随每次 SwiftUI 渲染被调用(窗口缩放期间是每帧),
        // 窗口属性只需设置一次:同一窗口重复配置直接跳过。
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            guard coordinator.configuredWindow !== window else { return }
            coordinator.configuredWindow = window
            window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable])
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.minSize = minSize
            window.contentMinSize = minSize
            window.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            window.title = "Airwang DIT for Mac"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.zoomButton)?.isEnabled = true
            window.standardWindowButton(.zoomButton)?.isHidden = false
        }
    }
}

private struct MainWindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        NativeWindowDragView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class NativeWindowDragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            if event.clickCount == 2 {
                window.performZoom(nil)
            } else {
                window.performDrag(with: event)
            }
        }
    }
}

private struct AppSettingsView: View {
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        Form {
            Section(viewModel.localized("界面设置")) {
                Picker(viewModel.localized("界面外观"), selection: Binding(
                    get: { viewModel.interfaceStyle },
                    set: { viewModel.setInterfaceStyle($0) }
                )) {
                    ForEach(InterfaceStyle.allCases) { style in
                        Text(viewModel.localized(style.title)).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                Picker(viewModel.localized("主题"), selection: Binding(
                    get: { viewModel.selectedTheme },
                    set: { viewModel.setTheme($0) }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(viewModel.localizedThemeTitle(theme)).tag(theme)
                    }
                }
                .pickerStyle(.segmented)

                Picker(viewModel.localized("语言"), selection: Binding(
                    get: { viewModel.selectedLanguage },
                    set: { viewModel.setLanguage($0) }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(viewModel.localized("自动执行")) {
                Toggle(
                    viewModel.localized("新建任务默认 5 分钟后自动执行"),
                    isOn: Binding(
                        get: { viewModel.autoStartQueuedProjects },
                        set: { viewModel.setAutoStartQueuedProjects($0) }
                    )
                )
                Text(viewModel.localized("关闭后，新建项目只加入队列，需要手动执行。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(viewModel.localized("支持与诊断")) {
                Button(viewModel.localized("新手教程")) { viewModel.reopenGettingStarted() }
                    .disabled(!viewModel.canPresentGettingStarted)
                    .accessibilityIdentifier("settings-getting-started")
                Text(viewModel.localized("导出版本、系统环境和任务状态。诊断不包含素材、文件名、路径或原始错误文本。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button(viewModel.localized("导出诊断")) {
                        viewModel.exportDiagnostics()
                    }
                    .disabled(viewModel.isExportingDiagnostics || viewModel.isChoosingDiagnosticsDestination)
                    .accessibilityIdentifier("settings-export-diagnostics")
                    if viewModel.isExportingDiagnostics {
                        ProgressView().controlSize(.small)
                        Button(viewModel.localized("取消导出")) { viewModel.cancelDiagnosticsExport() }
                    }
                }
                if let status = viewModel.diagnosticsExportStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .fontDesign(viewModel.interfaceStyle == .paper ? .default : .serif)
        .padding(24)
        .frame(width: 460)
        .preferredColorScheme(viewModel.selectedTheme == .night ? .dark : .light)
    }
}
