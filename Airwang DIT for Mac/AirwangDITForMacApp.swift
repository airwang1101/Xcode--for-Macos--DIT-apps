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
        }

        Settings {
            AppSettingsView()
                .environmentObject(viewModel)
        }
    }
}

private struct MainWindowConfigurator: NSViewRepresentable {
    let minSize: NSSize

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
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
        }
        .formStyle(.grouped)
        .fontDesign(.serif)
        .padding(24)
        .frame(width: 460)
        .preferredColorScheme(viewModel.selectedTheme == .night ? .dark : .light)
    }
}
