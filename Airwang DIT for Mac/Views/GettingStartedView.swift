import SwiftUI

/// A setup assistant over the existing workspace. All examples are view-local;
/// guide progress, language and explicit destination choices are persisted.
struct GettingStartedView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var exampleVerification: VerificationMode = .sha256
    @State private var exampleStage = 0
    @AccessibilityFocusState private var focusesTitle: Bool

    private var step: GettingStartedStep { viewModel.gettingStartedProgress.step }
    private var palette: PaperPalette { PaperPalette(theme: viewModel.selectedTheme) }
    private func text(_ chinese: String, _ english: String) -> String {
        viewModel.selectedLanguage == .english ? english : chinese
    }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 720 || geometry.size.height < 640
            VStack(spacing: 0) {
                HStack {
                    Text(text("Airwang DIT · 使用助理", "Airwang DIT · Getting Started"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.secondary)
                    Spacer()
                    Picker(text("语言", "Language"), selection: Binding(
                        get: { viewModel.selectedLanguage }, set: { viewModel.setLanguage($0) }
                    )) {
                        Text("简体中文").tag(AppLanguage.chinese)
                        Text("English").tag(AppLanguage.english)
                    }
                    .labelsHidden()
                    .frame(width: 130)
                    .accessibilityIdentifier("guide-language")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

                ScrollViewReader { scroll in
                    ScrollView {
                        VStack(spacing: compact ? 18 : 24) {
                            VStack(spacing: 14) {
                                Image(systemName: step.symbol)
                                    .font(.system(size: compact ? 44 : 60, weight: .light))
                                    .foregroundStyle(palette.accent)
                                    .frame(height: compact ? 58 : 80)
                                    .accessibilityHidden(true)
                                Text(step == .welcome ? text("欢迎使用 Airwang DIT", "Welcome to Airwang DIT") : step.title(language: viewModel.selectedLanguage))
                                    .font(.system(size: compact ? 26 : 32, weight: .semibold))
                                    .multilineTextAlignment(.center)
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityIdentifier("guide-title")
                                    .accessibilityFocused($focusesTitle)
                                Text(subtitle)
                                    .font(.system(size: 14))
                                    .foregroundStyle(palette.secondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: 510)
                            }
                            .id("guide-top")

                            lessonContent
                                .frame(maxWidth: 560)

                            if let error = viewModel.importError {
                                Label(error, systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundStyle(palette.error)
                                    .accessibilityIdentifier("guide-save-error")
                            }
                        }
                        .padding(.horizontal, compact ? 24 : 44)
                        .padding(.top, compact ? 8 : 20)
                        .padding(.bottom, 24)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: step) { _, _ in
                        // Keep the title visible when moving on from a long lesson.
                        scroll.scrollTo("guide-top", anchor: .top)
                        exampleStage = 0
                        focusesTitle = true
                    }
                }

                Rectangle().fill(palette.divider).frame(height: 1)
                footer
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
            }
            .foregroundStyle(palette.ink)
            .tint(palette.accent)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.divider, lineWidth: 1))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: step)
        }
        .frame(maxWidth: 880, maxHeight: 680)
        .fontDesign(viewModel.interfaceStyle == .paper ? .default : .serif)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("getting-started-assistant")
        .onAppear { focusesTitle = true }
    }

    private var subtitle: String {
        switch step {
        case .welcome:
            text("从素材卡到可追溯的报告，一步一步了解第一次拷贝。你可以随时跳过，之后在帮助菜单重新打开。",
                 "Follow your media from card to report. You can skip this guide and reopen it from Help at any time.")
        case .destinations:
            text("主目标盘保存工作副本。备份盘保存另一份副本，建议使用独立的存储设备。",
                 "Your primary destination holds the working copy. A separate device is recommended for the backup copy.")
        case .source:
            text("连接素材卡或 SSD，选择需要的文件，再确认这次任务。",
                 "Connect a card or SSD, select the files you need, then confirm the project.")
        case .verification:
            text("校验决定软件怎样检查拷贝结果。点击下面的选项，看看它们分别能确认什么。",
                 "Verification controls how the copy is checked. Select an option below to see what it can confirm.")
        case .queue:
            text("任务先加入队列，再由你执行。下面可以体验一项任务的四个阶段。",
                 "Projects enter the queue before you run them. Explore the four transfer stages below.")
        case .recovery:
            text("遇到中断，保留素材和已有副本。重新连接设备后，可以手动重试。",
                 "After an interruption, keep your media and existing copies. Reconnect the devices, then retry manually.")
        case .history:
            text("任务结束后，在报告中确认结果。拷贝记录与应用分开保存在这台 Mac 上。",
                 "Review the result in Reports. Copy history is stored separately from the app on this Mac.")
        case .ready:
            text("准备几份测试素材，完成一项小任务，熟悉流程后再处理正式素材。",
                 "Start with a few test files and a small project before working with production media.")
        }
    }

    @ViewBuilder private var lessonContent: some View {
        switch step {
        case .welcome:
            VStack(spacing: 18) {
                flowDiagram
                tip("rectangle.split.3x1", "拷贝工作台", "Copy workspace",
                    "上方切换新建任务、设备、队列和报告。底部保留全部五个工作区。",
                    "Use the top tabs for New Project, Devices, Queue and Reports. All five workspaces remain in the bottom navigation.")
                detail("按你的习惯使用", "Make it yours") {
                    Text(text("设置中可以切换经典界面、白天或夜晚主题，以及中英文。规整、统计、备份和工具入口均保留。",
                              "Settings let you switch to Classic, change the day or night theme, and choose Chinese or English. Organize, Statistics, Backup and Tools remain available."))
                }
            }
        case .destinations:
            VStack(spacing: 14) {
                destinationSetup
                detail("设备与空间检查", "Device and space checks") {
                    Text(text("选择可写且空间充足的文件夹。两个文件夹在同一设备上仍有共同的硬件风险。软件会检查路径重叠、存储卷、写入权限和剩余空间。保留源素材，直到需要的副本与校验完成。",
                              "Choose writable folders with enough free space. Two folders on one device share its hardware risk. The app checks paths, volumes, access and space. Keep the source until your copies and verification finish."))
                }
            }
        case .source:
            VStack(spacing: 14) {
                exampleLabel
                HStack(spacing: 14) {
                    Image(systemName: "sdcard.fill").font(.system(size: 36)).foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(text("素材卡 · 3 个文件", "Media card · 3 files")).font(.headline)
                        Text("clip.mov    photo.arw    photo.xmp").font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.secondary)
                    }
                    Spacer(minLength: 0)
                }.padding(16).background(palette.background, in: RoundedRectangle(cornerRadius: 10))
                tip("calendar", "按时间选择，或自由多选", "Select by time or choose freely",
                    "时间模式按拍摄日期分组；自由模式方便逐个挑选。图标、列表、分栏和画廊视图都可使用。",
                    "Time mode groups media by date. Free mode lets you select individual files. Icon, List, Column and Gallery views are available.")
                tip("checklist", "确认选中的素材", "Review the selection",
                    "检查关联边车文件、任务名称、目标与备份位置，然后加入队列。也可以通过新建任务选择已有文件夹。",
                    "Review related sidecars, the project name and destinations before adding to the queue. New Project also lets you choose an existing folder.")
            }
        case .verification:
            VStack(spacing: 12) {
                exampleLabel
                ForEach(VerificationMode.allCases) { mode in
                    Button { exampleVerification = mode } label: {
                        HStack(spacing: 12) {
                            Image(systemName: exampleVerification == mode ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(exampleVerification == mode ? palette.accent : palette.secondary)
                            Text(verificationTitle(mode)).font(.system(size: 14, weight: .medium))
                            if mode == .sha256 {
                                Text(text("首次使用建议", "Recommended")).font(.caption).foregroundStyle(palette.accent)
                            }
                            Spacer(minLength: 0)
                        }.padding(12).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(exampleVerification == mode ? palette.accent.opacity(0.08) : palette.background,
                                in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel(verificationTitle(mode))
                    .accessibilityAddTraits(exampleVerification == mode ? .isSelected : [])
                    .accessibilityIdentifier("guide-verification-\(mode.rawValue)")
                }
                Label(verificationExplanation, systemImage: exampleVerification == .sha256 ? "checkmark.shield" : "info.circle")
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(palette.secondary)
                Text(text("这里的选择仅用于演示。实际任务的校验方式在新建任务时选择。",
                          "This selection is only an example. Choose the actual verification mode when creating a project."))
                    .font(.caption).foregroundStyle(palette.secondary)
            }
        case .queue:
            VStack(spacing: 16) {
                exampleLabel
                VStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { index in
                        HStack {
                            Image(systemName: exampleStage > index ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(exampleStage > index ? palette.success : palette.secondary)
                            Text(stageTitle(index)).font(.system(size: 14))
                            Spacer()
                            Text(exampleStage > index ? text("完成", "Done") : text("等待", "Waiting"))
                                .font(.caption).foregroundStyle(palette.secondary)
                        }
                    }
                    Button(exampleStage == 4 ? text("重新演示", "Restart example") : text("演示下一阶段", "Show next stage")) {
                        exampleStage = exampleStage == 4 ? 0 : exampleStage + 1
                    }
                    .accessibilityIdentifier("guide-demo-advance")
                }.padding(18).background(palette.background, in: RoundedRectangle(cornerRadius: 10))
                tip("play.circle", "在队列中开始执行", "Start from the queue",
                    "默认需要手动执行。设置中可启用新任务 5 分钟后自动执行；队列支持顺序与并行。未配置备份的任务只执行主盘阶段。",
                    "Manual start is the default. Settings can enable a five-minute auto-start delay. Sequential and parallel queues are available. Without backup, only the primary stages run.")
            }
        case .recovery:
            VStack(spacing: 14) {
                tip("cable.connector", "先重新连接设备", "Reconnect your devices",
                    "接回原素材设备与目标盘，在队列中找到异常或取消的任务，选择重试。",
                    "Reconnect the original media and destination, then find the failed or cancelled project in Queue and retry.")
                tip("checkmark.shield", "重试会检查已有文件", "Existing files are checked",
                    "已有文件通过完整 SHA-256 比对后才复用。缺少的文件继续拷贝；内容冲突会保留并报告。",
                    "Existing files are reused only after full SHA-256 comparison. Missing files are copied; conflicting files are preserved and reported.")
                tip("externaldrive.badge.checkmark", "主盘完成后可单独重试备份", "Retry the backup independently",
                    "主盘完成记录有效时，可以只重试备份。请先检查报告，再决定何时清理原素材。",
                    "With a valid completed primary record, you can retry just the backup. Review the report before deciding when to clear the source media.")
            }
        case .history:
            VStack(spacing: 14) {
                tip("doc.text", "打开 TXT 或导出 PDF", "Open TXT or export PDF",
                    "在拷贝工作台的“报告”中查看结果、打开 TXT、导出 PDF，也可以在访达定位文件。统计工作区显示汇总。",
                    "Reports in the copy workspace shows results, opens TXT, exports PDF and reveals files in Finder. Statistics shows the summary.")
                tip("internaldrive", "记录保存在这台 Mac", "History stays on this Mac",
                    "只删除应用本体后重装，同一用户的数据目录保留时，兼容的历史记录会自动读取。",
                    "After replacing or deleting just the app, compatible history loads again when the same user's data folder is retained.")
                detail("保存位置与备份", "Storage and backups") {
                    Text("~/Library/Application Support/\(AppStorageScope.bundleIdentifier)/")
                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    Text(text("Data 保存队列、历史和设置，Reports 保存本地 TXT。清理软件删除整个目录会同时删除记录；当前没有云端恢复，也不会仅靠 TXT 重建历史。升级前可备份整个目录。",
                              "Data holds the queue, history and settings; Reports holds local TXT files. Removing this folder also removes the records. Cloud recovery and rebuilding history from TXT are unavailable. Back up the whole folder before upgrading."))
                }
            }
        case .ready:
            VStack(spacing: 14) {
                tip("1.circle", "选择目标位置", "Choose a destination",
                    viewModel.isConfigured ? "你已设置主目标位置，接下来可以进入拷贝工作台。" : "点击下方按钮，在目录选择器中设置主目标位置。需要备份时，再启用并选择备份盘。",
                    viewModel.isConfigured ? "Your primary destination is already configured. Continue to the copy workspace." : "Use the button below to set the primary destination in the folder picker. Enable backup and select a backup device when needed.")
                tip("2.circle", "用小任务走完流程", "Try one small project",
                    "选择几份测试素材，使用 SHA-256，加入队列并执行。完成后查看报告。",
                    "Select a few test files, choose SHA-256, add the project to Queue and run it. Review the report when it finishes.")
                Text(text("以后可以从帮助菜单、设置或首次配置页面重新打开新手教程。",
                          "Reopen Getting Started from Help, Settings or the initial setup page whenever you need it."))
                    .font(.caption).foregroundStyle(palette.secondary).multilineTextAlignment(.center)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button(text("以后再看", "Not now")) { viewModel.dismissGettingStarted() }
                .buttonStyle(.plain).foregroundStyle(palette.secondary)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("guide-skip")
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                ForEach(GettingStartedStep.allCases) { item in
                    Button { viewModel.visitGettingStartedStep(item) } label: {
                        Circle().fill(item == step ? palette.accent : palette.divider)
                            .frame(width: 6, height: 6).padding(4).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.rawValue + 1) / \(GettingStartedStep.allCases.count): \(item.title(language: viewModel.selectedLanguage))")
                    .accessibilityAddTraits(item == step ? .isSelected : [])
                }
            }
            .accessibilityIdentifier("guide-progress")
            Spacer(minLength: 8)
            Button(text("返回", "Back")) {
                if let previous = GettingStartedStep(rawValue: step.rawValue - 1) {
                    viewModel.visitGettingStartedStep(previous)
                }
            }
            .disabled(step == .welcome)
            .accessibilityIdentifier("guide-back")
            Button(step == .ready ? (viewModel.isConfigured ? text("进入工作台", "Open workspace") : text("开始设置", "Set up")) : text("继续", "Continue")) {
                if step == .ready {
                    viewModel.dismissGettingStarted()
                    viewModel.selectedSection = .copy
                    if !viewModel.isConfigured { viewModel.openFolderPicker(for: .target) }
                } else if let next = GettingStartedStep(rawValue: step.rawValue + 1) {
                    viewModel.visitGettingStartedStep(next)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("guide-continue")
        }
    }

    private var destinationSetup: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(text("主目标位置", "Primary destination")).font(.system(size: 14, weight: .semibold))
                    Text(viewModel.preferences.targetPath ?? text("选择工作副本的保存位置", "Choose where your working copy will be saved"))
                        .font(.caption).foregroundStyle(palette.secondary).lineLimit(2).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Button(text("选择…", "Choose…")) { viewModel.chooseGettingStartedDestination(backup: false) }
                    .accessibilityIdentifier("guide-choose-primary")
            }
            Divider()
            Toggle(text("同时备份", "Create a backup copy"), isOn: Binding(
                get: { viewModel.preferences.backupEnabled }, set: { viewModel.setBackupEnabled($0) }
            ))
            .accessibilityIdentifier("guide-backup-toggle")
            if viewModel.preferences.backupEnabled {
                HStack {
                    Text(viewModel.preferences.backupPath ?? text("选择独立设备上的备份位置", "Choose a destination on a separate device"))
                        .font(.caption).foregroundStyle(palette.secondary).lineLimit(2).truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button(text("选择…", "Choose…")) { viewModel.chooseGettingStartedDestination(backup: true) }
                        .accessibilityIdentifier("guide-choose-backup")
                }
            }
            Text(text("选择后会回到这一页。也可以继续阅读，稍后再设置。",
                      "You will return here after choosing a folder. You can also continue and configure it later."))
                .font(.caption).foregroundStyle(palette.secondary)
        }
        .padding(16).background(palette.background, in: RoundedRectangle(cornerRadius: 10))
    }

    private var exampleLabel: some View {
        Label(text("操作演示 · 不会读写你的素材", "Example · your media is untouched"), systemImage: "play.rectangle")
            .font(.caption).foregroundStyle(palette.secondary)
    }

    private var flowDiagram: some View {
        HStack(spacing: 10) {
            diagramItem("sdcard", text("素材", "Source"))
            Image(systemName: "chevron.right").foregroundStyle(palette.divider)
            diagramItem("externaldrive", text("主目标", "Primary"))
            Image(systemName: "chevron.right").foregroundStyle(palette.divider)
            diagramItem("externaldrive.badge.checkmark", text("备份", "Backup"))
        }
        .padding(18).frame(maxWidth: .infinity)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 12))
    }

    private func diagramItem(_ symbol: String, _ label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text(label).font(.system(size: 12, weight: .medium))
        }.frame(maxWidth: .infinity)
    }

    private func tip(_ symbol: String, _ titleZH: String, _ titleEN: String, _ bodyZH: String, _ bodyEN: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(palette.accent)
                .frame(width: 30).padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(text(titleZH, titleEN)).font(.system(size: 14, weight: .semibold))
                Text(text(bodyZH, bodyEN)).font(.system(size: 13)).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func detail<Content: View>(_ titleZH: String, _ titleEN: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup(text(titleZH, titleEN)) {
            VStack(alignment: .leading, spacing: 8) { content() }
                .font(.system(size: 12)).foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
        }.font(.system(size: 13)).padding(14)
            .background(palette.background, in: RoundedRectangle(cornerRadius: 10))
    }

    private func stageTitle(_ index: Int) -> String {
        let titles = [text("拷贝到主目标", "Copy to primary"), text("校验主目标", "Verify primary"),
                      text("从主目标拷贝到备份", "Copy primary to backup"), text("校验备份", "Verify backup")]
        return titles[index]
    }

    private var verificationExplanation: String {
        switch exampleVerification {
        case .sha256: text("完整读取文件并比对 SHA-256，适合首次任务和正式素材。", "Reads complete files and compares SHA-256. A good choice for your first project and production media.")
        case .fastFingerprint: text("比对大小并抽样读取头部、中部和尾部，无法保证发现所有内容变化。", "Compares size and samples the beginning, middle and end. It cannot detect every content change.")
        case .sizeOnly: text("确认文件存在且大小一致，内容是否相同仍未确认。", "Checks that files exist and sizes match. Matching contents are still unconfirmed.")
        case .skipped: text("报告会标记校验已跳过。素材完整性仍未确认，实际操作保留原有跳过确认流程。", "The report marks verification as skipped. Integrity remains unconfirmed; actual transfers retain the existing skip confirmation.")
        }
    }

    private func verificationTitle(_ mode: VerificationMode) -> String {
        switch mode {
        case .sha256: text("SHA-256 全量校验", "Full SHA-256")
        case .fastFingerprint: text("快速指纹校验", "Fast fingerprint")
        case .sizeOnly: text("大小校验", "Size only")
        case .skipped: text("跳过校验", "Skip verification")
        }
    }
}
