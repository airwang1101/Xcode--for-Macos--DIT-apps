import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @EnvironmentObject var viewModel: AppViewModel
    @State private var isWindowResizing = false
    @State private var resizeSettlingTask: Task<Void, Never>?
    @State private var measuredHeaderHeight: CGFloat = 0

    @State var paperCopyTab: PaperCopyTab = .create
    @State var paperSelectedVolumeID: String?
    @State var paperShowsSources = false
    init(paperCopyTab: PaperCopyTab = .create) {
        _paperCopyTab = State(initialValue: paperCopyTab)
    }
    var usesPaperAppearance: Bool { viewModel.interfaceStyle == .paper }
    var paperPalette: PaperPalette { PaperPalette(theme: viewModel.selectedTheme) }

    var body: some View {
        ZStack {
            Group {
                if usesPaperAppearance {
                    paperRoot
                } else {
                    classicRoot
                }
            }
            .disabled(viewModel.isShowingGettingStarted)
            .allowsHitTesting(!viewModel.isShowingGettingStarted)
            .accessibilityHidden(viewModel.isShowingGettingStarted)
            if viewModel.isShowingGettingStarted {
                Color.black.opacity(0.22).ignoresSafeArea()
                    .accessibilityHidden(true)
                GettingStartedView()
                    .padding(.horizontal, 16)
                    .padding(.top, 36)
                    .padding(.bottom, 16)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .environment(\.ditPaperAppearance, usesPaperAppearance)
        .fontDesign(usesPaperAppearance ? .default : .serif)
        .preferredColorScheme(viewModel.selectedTheme == .night ? .dark : .light)
        .sheet(item: Binding(
            get: { viewModel.isShowingGettingStarted ? nil : viewModel.pendingImportVolume },
            set: { if !viewModel.isShowingGettingStarted { viewModel.pendingImportVolume = $0 } }
        )) { volume in
            ImportSheet(volume: volume)
                .environmentObject(viewModel)
                .environment(\.ditPaperAppearance, usesPaperAppearance)
        }
        .sheet(item: Binding(
            get: { viewModel.isShowingGettingStarted ? nil : viewModel.activeFolderPicker },
            set: { if !viewModel.isShowingGettingStarted { viewModel.activeFolderPicker = $0 } }
        )) { purpose in
            FolderPickerSheet(purpose: purpose)
                .environmentObject(viewModel)
                .environment(\.ditPaperAppearance, usesPaperAppearance)
        }
        .alert(viewModel.localized("提示"), isPresented: Binding(
            get: { !viewModel.isShowingGettingStarted && viewModel.importError != nil },
            set: { if !$0 { viewModel.importError = nil } }
        )) {
            Button(viewModel.localized("知道了"), role: .cancel) {}
        } message: { Text(viewModel.importError ?? "") }
        .task { viewModel.presentGettingStartedIfNeeded() }
        .onChange(of: viewModel.canPresentGettingStarted) { _, canPresent in
            if canPresent { viewModel.presentGettingStartedIfNeeded() }
        }
    }

    var classicRoot: some View {
        ZStack(alignment: .top) {
            musicBackdrop
                .ignoresSafeArea()

            ambientAurora
                .ignoresSafeArea()

            if viewModel.isConfigured {
                mainDashboard
            } else {
                onboardingView
            }
        }
        .fontDesign(.serif)
        .preferredColorScheme(viewModel.selectedTheme == .night ? .dark : .light)
        .transaction { transaction in
            if reduceMotionEffects || isWindowResizing {
                transaction.animation = nil
            }
        }
        .onDisappear {
            resizeSettlingTask?.cancel()
        }
    }

    var onboardingView: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 920
            let contentPadding: CGFloat = compact ? 16 : 34

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: compact ? 20 : 28) {
                    Text("Airwang DIT for Mac")
                        .font(.system(size: compact ? 32 : 38, weight: .semibold, design: .serif))
                        .minimumScaleFactor(0.82)
                        .lineLimit(1)
                        .foregroundStyle(primaryTextColor)
                    Text("先在软件内设置默认导入目标。完成后，插入新卡或 SSD 时会直接弹出导入任务，不再通过访达跳转。")
                        .font(compact ? .body : .title3)
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(viewModel.localized("新手教程")) { viewModel.reopenGettingStarted() }
                        .disabled(!viewModel.canPresentGettingStarted)
                        .accessibilityIdentifier("setup-getting-started")

                    onboardingDestinationSection(stacked: compact)
                    onboardingFeatureSection(stacked: compact)
                }
                .padding(compact ? 22 : 34)
                .frame(maxWidth: 1140, alignment: .leading)
                .background(glassSurface(cornerRadius: compact ? 24 : 30))
                .padding(contentPadding)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
            .onChange(of: proxy.size) { _, _ in
                markWindowResizing()
            }
        }
        .accessibilityIdentifier("onboarding-view")
    }

    @ViewBuilder
    func onboardingDestinationSection(stacked: Bool) -> some View {
        let targetCard = destinationCard(
            badge: "主目标盘",
            title: viewModel.preferences.targetPath == nil ? "尚未设置默认主目标位置" : "默认写入位置",
            path: viewModel.preferences.targetPath,
            actionTitle: "在软件内选择主目标盘",
            action: { viewModel.openFolderPicker(for: .target) }
        )

        let backupControls = VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("同时备份")
                    .font(.headline)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { viewModel.preferences.backupEnabled },
                    set: { viewModel.setBackupEnabled($0) }
                ))
                .labelsHidden()
            }

            destinationCard(
                badge: "备份盘",
                title: viewModel.preferences.backupEnabled ? "同步写入备份位置" : "当前未启用备份",
                path: viewModel.preferences.backupPath,
                actionTitle: "在软件内选择备份盘",
                action: { viewModel.openFolderPicker(for: .backup) }
            )
            .disabled(!viewModel.preferences.backupEnabled)
        }

        if stacked {
            VStack(alignment: .leading, spacing: 16) {
                targetCard
                backupControls
            }
        } else {
            HStack(alignment: .top, spacing: 18) {
                targetCard
                backupControls
            }
        }
    }

    @ViewBuilder
    func onboardingFeatureSection(stacked: Bool) -> some View {
        if stacked {
            VStack(spacing: 12) {
                onboardingFeature(label: "应用内目录浏览", detail: "直接选文件夹并查看剩余容量")
                onboardingFeature(label: "自动设备发现", detail: "检测新介质后快速开始导入")
                onboardingFeature(label: "拷贝后校验", detail: "导入完成即执行完整性确认")
            }
        } else {
            HStack(spacing: 18) {
                onboardingFeature(label: "应用内目录浏览", detail: "直接选文件夹并查看剩余容量")
                onboardingFeature(label: "自动设备发现", detail: "检测新介质后快速开始导入")
                onboardingFeature(label: "拷贝后校验", detail: "导入完成即执行完整性确认")
            }
        }
    }

    var mainDashboard: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 1180
            let heightCompact = proxy.size.height < 760
            let portraitOptimized = MainWindowLayoutPolicy.usesPortraitLayout(
                width: proxy.size.width,
                height: proxy.size.height
            )
            let contentPadding: CGFloat = portraitOptimized ? 12 : (compact ? 16 : 26)
            let contentSpacing: CGFloat = portraitOptimized ? 12 : (compact ? 14 : 18)
            let availableWidth = max(0, proxy.size.width - contentPadding * 2)
            let topInset = max(proxy.safeAreaInsets.top, heightCompact ? 8 : (compact ? 10 : 16))
            let headerHeight = measuredHeaderHeight > 0
                ? measuredHeaderHeight
                : workspaceHeaderHeight(availableWidth: availableWidth)
            let headerReserve = headerHeight
                + topInset
                + (heightCompact ? 10 : contentSpacing)
            let bottomInset = max(proxy.safeAreaInsets.bottom, heightCompact ? 8 : (compact ? 10 : 16))
            let bottomReserve = bottomTabBarHeight(availableWidth: availableWidth, heightCompact: heightCompact)
                + bottomInset
                + (heightCompact ? 12 : contentSpacing)
            let workspaceHeight = max(360, proxy.size.height - headerReserve - bottomReserve)

            Color.clear
                .overlay(alignment: .top) {
                    dashboardContent(
                        availableWidth: availableWidth,
                        availableHeight: workspaceHeight,
                        contentSpacing: contentSpacing,
                        portraitOptimized: portraitOptimized
                    )
                        .padding(.horizontal, contentPadding)
                        .padding(.top, headerReserve)
                        .padding(.bottom, bottomReserve)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                        .animation(stableLayoutAnimation, value: compact)
                        .animation(stableLayoutAnimation, value: heightCompact)
                        .animation(stableLayoutAnimation, value: portraitOptimized)
                }
                .overlay(alignment: .top) {
                    floatingWorkspaceHeader(availableWidth: availableWidth)
                        .background(
                            // 实测头部真实高度回填给 headerReserve:硬编码常量
                            // 无法跟随文字换行/字号变化,错位时会遮住首行内容。
                            GeometryReader { headerProxy in
                                Color.clear.preference(
                                    key: WorkspaceHeaderHeightKey.self,
                                    value: headerProxy.size.height
                                )
                            }
                        )
                        .padding(.horizontal, contentPadding)
                        .padding(.top, topInset)
                        .zIndex(3)
                        .animation(stableLayoutAnimation, value: compact)
                        .animation(stableLayoutAnimation, value: heightCompact)
                        .animation(stableLayoutAnimation, value: portraitOptimized)
                }
                .overlay(alignment: .bottom) {
                    bottomTabBar(availableWidth: availableWidth, heightCompact: heightCompact)
                        .padding(.horizontal, contentPadding)
                        .padding(.bottom, bottomInset)
                        .zIndex(2)
                        .animation(stableLayoutAnimation, value: compact)
                        .animation(stableLayoutAnimation, value: heightCompact)
                        .animation(stableLayoutAnimation, value: portraitOptimized)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .onChange(of: proxy.size) { _, _ in
                    markWindowResizing()
                }
        }
        .onPreferenceChange(WorkspaceHeaderHeightKey.self) { height in
            if abs(measuredHeaderHeight - height) > 0.5 {
                measuredHeaderHeight = height
            }
        }
        .accessibilityIdentifier("main-dashboard")
    }

    func dashboardContent(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        contentSpacing: CGFloat,
        portraitOptimized: Bool
    ) -> some View {
        ScrollView(.vertical) {
            Group {
                switch viewModel.selectedSection {
                case .copy:
                    copyWorkspace(availableWidth: availableWidth, portraitOptimized: portraitOptimized)
                case .dashboard:
                    dashboardWorkspace(availableWidth: availableWidth, portraitOptimized: portraitOptimized)
                case .backup:
                    backupWorkspace(portraitOptimized: portraitOptimized)
                case .organize:
                    organizeWorkspace(availableWidth: availableWidth)
                case .statistics:
                    statisticsWorkspace(availableWidth: availableWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .frame(minHeight: availableHeight, alignment: .top)
            .transition(responsiveLayoutTransition)
            .animation(sectionSwitchAnimation, value: viewModel.selectedSection)
            .accessibilityIdentifier("workspace-\(viewModel.selectedSection.rawValue)")
        }
        .scrollIndicators(.visible)
    }

    func floatingWorkspaceHeader(availableWidth: CGFloat) -> some View {
        let tightHeader = availableWidth < 620

        return floatingChromeSurface(
            cornerRadius: tightHeader ? 24 : 28,
            horizontalPadding: tightHeader ? 18 : 22,
            verticalPadding: tightHeader ? 16 : 18
        ) {
            workspaceHeader(availableWidth: availableWidth)
        }
        .accessibilityIdentifier("floating-workspace-header")
    }

    /// 首帧兜底值:PreferenceKey 实测高度尚未回填时使用,之后以实测为准。
    /// 数值按实测渲染高度校准(宽 ~101pt / 窄 ~148pt),把回填瞬间的
    /// 一次性内容位移压到不可感知。
    func workspaceHeaderHeight(availableWidth: CGFloat) -> CGFloat {
        availableWidth < 620 ? 148 : 101
    }

    @ViewBuilder
    func floatingChromeSurface<Content: View>(
        cornerRadius: CGFloat,
        horizontalPadding: CGFloat,
        verticalPadding: CGFloat,
        surfaceElevation: AirwangGlassElevation = .floating,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        // 分支只看 OS 版本(进程内恒定),不再掺入 reduceGlassEffects:
        // 运行时条件会让整块 chrome 在窗口缩放的起止各换一次树。
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                content()
                    .padding(.horizontal, horizontalPadding)
                    .padding(.vertical, verticalPadding)
                    .glassEffect(.regular.interactive(), in: shape)
            }
            .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.18, elevation: .floating, enabled: !reduceVisualEffects)
        } else {
            content()
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
                .background(glassSurface(cornerRadius: cornerRadius, elevation: surfaceElevation))
                .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.18, elevation: .floating, enabled: !reduceVisualEffects)
        }
    }

    func workspaceHeader(availableWidth: CGFloat) -> some View {
        let tightHeader = availableWidth < 620

        return Group {
            if tightHeader {
                VStack(alignment: .leading, spacing: 14) {
                    headerTitle(compact: true)
                    headerControls
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    headerTitle(compact: false)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)
                    headerControls
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .transition(responsiveLayoutTransition)
        .animation(stableLayoutAnimation, value: tightHeader)
    }

    func headerTitle(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Airwang DIT for Mac")
                .font(.system(size: compact ? 28 : 34, weight: .semibold, design: .serif))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
                .foregroundStyle(primaryTextColor)
            Text("多项目拷贝队列、主盘校验、串行备份与可追溯报告")
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var headerControls: some View {
        HStack(spacing: 8) {
            headerIconButton(
                systemImage: "globe",
                helpText: viewModel.selectedLanguage == .chinese ? "Switch to English" : "切换到中文"
            ) {
                withResponsiveAnimation {
                    viewModel.setLanguage(viewModel.selectedLanguage == .chinese ? .english : .chinese)
                }
            }

            headerIconButton(
                systemImage: "externaldrive.fill",
                helpText: viewModel.localized("选择主目标盘")
            ) {
                viewModel.openFolderPicker(for: .target)
            }

            headerIconButton(
                systemImage: "arrow.clockwise",
                helpText: viewModel.localized("刷新设备")
            ) {
                viewModel.refreshVolumes()
            }

            headerIconButton(
                systemImage: viewModel.selectedTheme == .night ? "sun.max.fill" : "moon.fill",
                helpText: viewModel.selectedTheme == .night ? viewModel.localized("白天") : viewModel.localized("夜晚"),
                isActive: viewModel.selectedTheme == .night
            ) {
                withResponsiveAnimation {
                    viewModel.setTheme(viewModel.selectedTheme == .night ? .day : .night)
                }
            }
        }
        .frame(width: 200, alignment: .trailing)
    }

    func headerIconButton(
        systemImage: String,
        helpText: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActive ? Color.white : primaryTextColor)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isActive ? accentColor : Color.white.opacity(viewModel.selectedTheme == .night ? 0.10 : 0.30))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(viewModel.selectedTheme == .night ? 0.16 : 0.58), lineWidth: 0.8)
                )
                .airwangSoftShadow(
                    theme: viewModel.selectedTheme,
                    tint: isActive ? accentColor : .clear,
                    tintStrength: isActive ? 0.8 : 0,
                    elevation: isActive ? .selected : .tile,
                    enabled: !reduceVisualEffects
                )
                .scaleEffect(isActive ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(Text(helpText))
        .animation(controlAnimation, value: isActive)
        .animation(controlAnimation, value: systemImage)
    }

    @ViewBuilder
    func bottomTabBar(availableWidth: CGFloat, heightCompact: Bool) -> some View {
        let compact = availableWidth < 680 || heightCompact
        let sectionCount = CGFloat(MainSection.allCases.count)
        let horizontalPadding: CGFloat = compact ? 16 : 20
        let totalSpacing = max(sectionCount - 1, 0) * (compact ? 7 : 10)
        let fittedButtonWidth = max(54, (availableWidth - horizontalPadding - totalSpacing) / max(sectionCount, 1))
        let buttonWidth = compact ? min(96, fittedButtonWidth) : 112
        let dashboardWidth = compact ? buttonWidth : 128
        let buttonHeight: CGFloat = compact ? 48 : 58
        let cornerRadius: CGFloat = compact ? 22 : 30
        let verticalPadding: CGFloat = compact ? 7 : 10

        floatingChromeSurface(
            cornerRadius: cornerRadius,
            horizontalPadding: compact ? 8 : 10,
            verticalPadding: verticalPadding,
            // 与重构前的 tab 栏背景保持一致(旧代码用默认 .panel 海拔),
            // .floating 的内层阴影会和外层悬浮影叠加得过重。
            surfaceElevation: .panel
        ) {
            HStack(spacing: compact ? 7 : 10) {
                ForEach(MainSection.allCases) { section in
                    bottomTabButton(
                        section,
                        compact: compact,
                        buttonWidth: section == .dashboard ? dashboardWidth : buttonWidth,
                        buttonHeight: buttonHeight
                    )
                }
            }
        }
        .frame(height: buttonHeight + verticalPadding * 2)
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(stableLayoutAnimation, value: compact)
        .animation(sectionSwitchAnimation, value: viewModel.selectedSection)
        .accessibilityIdentifier("bottom-tab-bar")
    }

    @ViewBuilder
    func bottomTabButton(
        _ section: MainSection,
        compact: Bool,
        buttonWidth: CGFloat,
        buttonHeight: CGFloat
    ) -> some View {
        let isSelected = viewModel.selectedSection == section

        if #available(macOS 26.0, *) {
            if isSelected {
                Button {
                    withResponsiveAnimation {
                        viewModel.selectedSection = section
                    }
                } label: {
                    bottomTabLabel(section, compact: compact, selected: true)
                        .frame(width: buttonWidth, height: buttonHeight)
                }
                .buttonStyle(.glassProminent)
                .tint(accentColor)
                .accessibilityLabel(Text(viewModel.localized(section.title)))
                .accessibilityIdentifier("bottom-tab-\(section.rawValue)")
            } else {
                Button {
                    withResponsiveAnimation {
                        viewModel.selectedSection = section
                    }
                } label: {
                    bottomTabLabel(section, compact: compact, selected: false)
                        .frame(width: buttonWidth, height: buttonHeight)
                }
                .buttonStyle(.glass)
                .tint(accentColor)
                .accessibilityLabel(Text(viewModel.localized(section.title)))
                .accessibilityIdentifier("bottom-tab-\(section.rawValue)")
            }
        } else {
            Button {
                withResponsiveAnimation {
                    viewModel.selectedSection = section
                }
            } label: {
                bottomTabLabel(section, compact: compact, selected: isSelected)
                    .frame(width: buttonWidth, height: buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous)
                            .fill(isSelected ? accentColor : Color.white.opacity(viewModel.selectedTheme == .night ? 0.09 : 0.34))
                    )
                    .scaleEffect(isSelected ? 1.015 : 1)
                    .airwangSoftShadow(
                        theme: viewModel.selectedTheme,
                        tint: isSelected ? accentColor : .clear,
                        tintStrength: isSelected ? 1 : 0,
                        elevation: isSelected ? .selected : .tile,
                        enabled: !reduceVisualEffects
                    )
                    .accessibilityIdentifier("bottom-tab-label-\(section.rawValue)")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(viewModel.localized(section.title)))
            .accessibilityIdentifier("bottom-tab-\(section.rawValue)")
        }
    }

    func bottomTabLabel(_ section: MainSection, compact: Bool, selected: Bool) -> some View {
        VStack(spacing: compact ? 4 : 5) {
            Image(systemName: section.systemImage)
                .font(.system(size: compact ? 18 : (section == .dashboard ? 22 : 20), weight: .semibold))
            Text(viewModel.localized(section.title))
                .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .foregroundStyle(selected ? Color.white : secondaryTextColor)
        .accessibilityIdentifier("bottom-tab-label-\(section.rawValue)")
    }

    func bottomTabBarHeight(availableWidth: CGFloat, heightCompact: Bool) -> CGFloat {
        let compact = availableWidth < 680 || heightCompact
        let buttonHeight: CGFloat = compact ? 48 : 58
        let verticalPadding: CGFloat = compact ? 7 : 10
        return buttonHeight + verticalPadding * 2
    }

    func destinationCard(badge: String, title: String, path: String?, actionTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(badge.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            Text(title)
                .font(.headline)
                .foregroundStyle(primaryTextColor)
            Text(path ?? "尚未选择目录")
                .font(.body.weight(.medium))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(2)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
        }
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .padding(22)
        .background(glassSurface(cornerRadius: 24, tint: accentColor, elevation: .card))
    }

    func detailRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(primaryTextColor)
        }
    }

    func progressTrack(title: String, detail: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                Spacer()
                Text("\(Int((value * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }

            ProgressView(value: value)
                .tint(tint)

            Text(detail)
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
        }
        .padding(14)
        .background(glassSurface(cornerRadius: 16))
    }

    func glassSurface(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        elevation: AirwangGlassElevation = .panel
    ) -> some View {
        AirwangGlassSurface(
            cornerRadius: cornerRadius,
            theme: viewModel.selectedTheme,
            tint: tint ?? accentColor,
            tintStrength: tint == nil ? 0.0 : 1.0,
            elevation: elevation,
            reduceEffects: reduceGlassEffects
        )
    }

    func etaText(_ value: TimeInterval?) -> String {
        guard let value else { return "--" }
        let formatter = value > 3600 ? CachedDateFormatters.etaHoursMinutes : CachedDateFormatters.etaMinutesSeconds
        return formatter.string(from: value) ?? "--"
    }

    func stopwatchText(_ value: TimeInterval) -> String {
        let totalSeconds = max(Int(value.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func preciseDateTimeText(_ value: Date) -> String {
        CachedDateFormatters
            .formatter(localeIdentifier: "zh_CN", fixedFormat: "yyyy年M月d日 HH:mm:ss")
            .string(from: value)
    }

    func onboardingFeature(label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(glassSurface(cornerRadius: 18, elevation: .tile))
    }

    func emptyState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "externaldrive.badge.questionmark")
                .font(.headline)
                .foregroundStyle(primaryTextColor)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(glassSurface(cornerRadius: 18, elevation: .tile))
    }

    func compactInfo(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            Text(value)
                .font(.headline)
                .foregroundStyle(primaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(glassSurface(cornerRadius: 16, elevation: .tile))
    }

    var musicBackdrop: some View {
        Group {
            if viewModel.selectedTheme == .night {
                LinearGradient(
                    colors: [
                        Color(red: 0.014, green: 0.015, blue: 0.020),
                        Color(red: 0.032, green: 0.023, blue: 0.032),
                        Color(red: 0.052, green: 0.027, blue: 0.044),
                        Color(red: 0.020, green: 0.026, blue: 0.036)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 1.000, green: 0.978, blue: 0.965),
                        Color(red: 0.982, green: 0.944, blue: 0.930),
                        Color(red: 0.945, green: 0.922, blue: 0.938),
                        Color(red: 0.918, green: 0.930, blue: 0.958)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    var ambientAurora: some View {
        // 大半径模糊圆是固定尺寸的静态图层,CoreAnimation 会缓存其渲染结果,
        // 窗口缩放期间保留它们几乎零成本;此前 reduceGlassEffects 在 Color.clear
        // 与整组光晕之间换树,缩放起止各触发一次三个 120-150pt 模糊的重建,
        // 恰好制造两次卡顿尖峰。现在树恒定,只有材质条用透明度降级。
        ZStack {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(viewModel.selectedTheme == .night ? 0.18 : 0.12))
                    .frame(width: 620, height: 620)
                    .blur(radius: 120)
                    .offset(x: -390, y: -210)

                Circle()
                    .fill(secondaryAccentColor.opacity(viewModel.selectedTheme == .night ? 0.11 : 0.10))
                    .frame(width: 740, height: 740)
                    .blur(radius: 145)
                    .offset(x: 430, y: -250)

                Circle()
                    .fill(Color(red: 0.30, green: 0.56, blue: 1.00).opacity(viewModel.selectedTheme == .night ? 0.07 : 0.08))
                    .frame(width: 560, height: 560)
                    .blur(radius: 150)
                    .offset(x: 230, y: 500)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if viewModel.selectedTheme == .night {
                RoundedRectangle(cornerRadius: 80, style: .continuous)
                    .fill(accentColor.opacity(0.035))
                    .frame(height: 280)
                    .blur(radius: 78)
                    .offset(y: -180)
                    .opacity(0.55)
            } else {
                // material 依赖实时背景采样,不能进 drawingGroup,单独保留;
                // 它的宽度跟随窗口,缩放期间用透明度归零跳过背景采样。
                RoundedRectangle(cornerRadius: 60, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.50))
                    .frame(height: 340)
                    .blur(radius: 34)
                    .offset(y: -170)
                    .opacity(reduceGlassEffects ? 0 : 0.88)
            }
        }
        .allowsHitTesting(false)
    }

    var responsiveLayoutAnimation: Animation {
        .easeOut(duration: 0.16)
    }

    var stableLayoutAnimation: Animation? {
        isWindowResizing || reduceMotionEffects ? nil : responsiveLayoutAnimation
    }

    var sectionSwitchAnimation: Animation? {
        isWindowResizing || reduceMotionEffects ? nil : .easeInOut(duration: 0.14)
    }

    var controlAnimation: Animation? {
        reduceMotionEffects ? nil : .easeOut(duration: 0.12)
    }

    var responsiveLayoutTransition: AnyTransition {
        .opacity
    }

    func withResponsiveAnimation(_ action: () -> Void) {
        if accessibilityReduceMotion || isWindowResizing {
            action()
        } else {
            withAnimation(responsiveLayoutAnimation) {
                action()
            }
        }
    }

    // 只在窗口缩放时降级视觉效果。此前滚动也会触发降级(isScrolling),
    // 导致滚动开始/结束时所有玻璃面板在两棵不同视图树之间整体切换。
    var reduceVisualEffects: Bool {
        isWindowResizing
    }

    var reduceGlassEffects: Bool {
        isWindowResizing
    }

    var reduceMotionEffects: Bool {
        accessibilityReduceMotion
    }

    func markWindowResizing() {
        if !isWindowResizing {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                isWindowResizing = true
            }
        }

        resizeSettlingTask?.cancel()
        resizeSettlingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                isWindowResizing = false
            }
        }
    }

    // 颜色全部委托给 `AppTheme` 扩展(Views/Theme/AirwangPalette.swift),避免再次出现
    // 三套独立定义(见 TEST_REPORT.md #45/#46/#47)。
    var primaryTextColor: Color { usesPaperAppearance ? paperPalette.ink : viewModel.selectedTheme.primaryTextColor }
    var secondaryTextColor: Color { usesPaperAppearance ? paperPalette.secondary : viewModel.selectedTheme.secondaryTextColor }
    var accentColor: Color { usesPaperAppearance ? paperPalette.accent : viewModel.selectedTheme.accentColor }
    var secondaryAccentColor: Color { usesPaperAppearance ? paperPalette.secondaryAccent : viewModel.selectedTheme.secondaryAccentColor }

}
