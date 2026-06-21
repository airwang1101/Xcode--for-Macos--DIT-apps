import AppKit
import QuickLookThumbnailing
import SwiftUI

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var isWindowResizing = false
    @State private var resizeSettlingTask: Task<Void, Never>?
    @State private var hoveredActivityDay: CopyActivityDay?
    @State private var selectedActivityMode: StatisticsActivityMode = .daily

    var body: some View {
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
            if reduceMotionEffects {
                transaction.animation = nil
            }
        }
        .onDisappear {
            resizeSettlingTask?.cancel()
        }
        .sheet(item: $viewModel.pendingImportVolume) { volume in
            ImportSheet(volume: volume)
                .environmentObject(viewModel)
        }
        .sheet(item: $viewModel.activeFolderPicker) { purpose in
            FolderPickerSheet(purpose: purpose)
                .environmentObject(viewModel)
        }
        .alert("提示", isPresented: Binding(
            get: { viewModel.importError != nil },
            set: { if !$0 { viewModel.importError = nil } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(viewModel.importError ?? "")
        }
    }

    private var onboardingView: some View {
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
    }

    @ViewBuilder
    private func onboardingDestinationSection(stacked: Bool) -> some View {
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
    private func onboardingFeatureSection(stacked: Bool) -> some View {
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

    private var mainDashboard: some View {
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
            let bottomInset = max(proxy.safeAreaInsets.bottom, heightCompact ? 8 : (compact ? 10 : 16))
            let bottomReserve = bottomTabBarHeight(availableWidth: availableWidth, heightCompact: heightCompact)
                + bottomInset
                + (heightCompact ? 12 : contentSpacing)

            Color.clear
                .overlay(alignment: .top) {
                    dashboardContent(
                        availableWidth: availableWidth,
                        contentSpacing: contentSpacing,
                        portraitOptimized: portraitOptimized
                    )
                        .padding(.horizontal, contentPadding)
                        .padding(.top, contentPadding)
                        .padding(.bottom, bottomReserve)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                        .animation(responsiveLayoutAnimation, value: compact)
                        .animation(responsiveLayoutAnimation, value: heightCompact)
                        .animation(responsiveLayoutAnimation, value: portraitOptimized)
                }
                .overlay(alignment: .bottom) {
                    bottomTabBar(availableWidth: availableWidth, heightCompact: heightCompact)
                        .padding(.horizontal, contentPadding)
                        .padding(.bottom, bottomInset)
                        .zIndex(2)
                        .animation(responsiveLayoutAnimation, value: compact)
                        .animation(responsiveLayoutAnimation, value: heightCompact)
                        .animation(responsiveLayoutAnimation, value: portraitOptimized)
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .onChange(of: proxy.size) { _, _ in
                    markWindowResizing()
                }
        }
    }

    private func dashboardContent(
        availableWidth: CGFloat,
        contentSpacing: CGFloat,
        portraitOptimized: Bool
    ) -> some View {
        VStack(spacing: contentSpacing) {
            workspaceHeader(availableWidth: availableWidth)

            Group {
                switch viewModel.selectedSection {
                case .copy:
                    copyWorkspace(availableWidth: availableWidth, portraitOptimized: portraitOptimized)
                case .dashboard:
                    dashboardWorkspace(availableWidth: availableWidth, portraitOptimized: portraitOptimized)
                case .backup:
                    backupWorkspace(portraitOptimized: portraitOptimized)
                case .statistics:
                    statisticsWorkspace(availableWidth: availableWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(responsiveLayoutTransition)
            .animation(responsiveLayoutAnimation, value: viewModel.selectedSection)
        }
    }

    private func workspaceHeader(availableWidth: CGFloat) -> some View {
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
        .animation(responsiveLayoutAnimation, value: tightHeader)
    }

    private func headerTitle(compact: Bool) -> some View {
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

    private var headerControls: some View {
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

    private func headerIconButton(
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
        .animation(responsiveLayoutAnimation, value: isActive)
        .animation(responsiveLayoutAnimation, value: systemImage)
    }

    @ViewBuilder
    private func copyWorkspace(availableWidth: CGFloat, portraitOptimized: Bool) -> some View {
        if portraitOptimized {
            ScrollView {
                VStack(spacing: 14) {
                    copyPresetCard(availableWidth: availableWidth)
                    volumeListCard
                        .frame(minHeight: 320)
                    projectQueueCard
                        .frame(minHeight: 420)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.visible)
            .transition(responsiveLayoutTransition)
        } else if availableWidth < 1180 {
            VStack(spacing: 14) {
                copyPresetCard(availableWidth: availableWidth)
                volumeListCard
                    .frame(maxHeight: .infinity)
                projectQueueCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            .transition(responsiveLayoutTransition)
        } else {
            let queueWidth = min(520, max(420, availableWidth * 0.36))
            let presetWidth = max(0, availableWidth - queueWidth - 18)

            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 18) {
                    copyPresetCard(availableWidth: presetWidth)
                    volumeListCard
                        .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                projectQueueCard
                    .frame(width: queueWidth)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(responsiveLayoutTransition)
        }
    }

    @ViewBuilder
    private func dashboardWorkspace(availableWidth: CGFloat, portraitOptimized: Bool) -> some View {
        if portraitOptimized {
            ScrollView {
                VStack(spacing: 14) {
                    queueControlStrip(availableWidth: availableWidth)
                    dashboardProjectList
                        .frame(minHeight: 420)
                    logCard
                        .frame(minHeight: 340)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            }
            .scrollIndicators(.visible)
            .transition(responsiveLayoutTransition)
        } else if availableWidth < 1180 {
            VStack(spacing: 14) {
                queueControlStrip(availableWidth: availableWidth)
                dashboardProjectList
                    .frame(maxHeight: .infinity)
                logCard
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            .transition(responsiveLayoutTransition)
        } else {
            let logWidth = min(420, max(360, availableWidth * 0.30))
            let listWidth = max(0, availableWidth - logWidth - 18)

            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 18) {
                    queueControlStrip(availableWidth: listWidth)
                    dashboardProjectList
                        .frame(maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                logCard
                    .frame(width: logWidth)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)
            .transition(responsiveLayoutTransition)
        }
    }

    private var dashboardProjectList: some View {
        let orderedProjects = viewModel.activeQueueProjects

        return ScrollView {
            LazyVStack(spacing: 14) {
                if orderedProjects.isEmpty {
                    emptyState(
                        title: "还没有拷贝项目",
                        detail: "去「拷贝」页选择源文件夹、目标盘和校验方式，创建项目后这里会按项目显示实时速度、ETA 和报告入口。"
                    )
                }
                ForEach(orderedProjects) { project in
                    projectDashboardCard(project)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func backupWorkspace(portraitOptimized: Bool) -> some View {
        let backupProjects = viewModel.backupProjects

        return VStack(alignment: .leading, spacing: 18) {
            Group {
                if portraitOptimized {
                    VStack(alignment: .leading, spacing: 12) {
                        backupWorkspaceTitle
                        backupWorkspaceStartButton
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                } else {
                    HStack {
                        backupWorkspaceTitle
                        Spacer()
                        backupWorkspaceStartButton
                    }
                }
            }

            ScrollView {
                LazyVStack(spacing: 14) {
                    if backupProjects.isEmpty {
                        emptyState(title: viewModel.localized("暂无备份项目"), detail: viewModel.localized("创建拷贝项目时开启备份盘后，这里会自动出现对应的备份进度。"))
                    }
                    ForEach(backupProjects) { project in
                        backupProjectCard(project)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
    }

    private var backupWorkspaceTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.localized("备份工作台"))
                .sectionTitle()
            Text(viewModel.localized("这里只显示在拷贝项目里配置了备份盘的项目，备份来源固定为主目标盘。"))
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var backupWorkspaceStartButton: some View {
        Button {
            viewModel.startQueue()
        } label: {
            Label(viewModel.localized("执行队列"), systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(accentColor)
        .disabled(!viewModel.canStartQueue)
        .help(viewModel.startQueueDisabledHelp ?? viewModel.localized("开始执行排队中的拷贝项目"))
    }

    @ViewBuilder
    private func statisticsWorkspace(availableWidth: CGFloat) -> some View {
        let summary = viewModel.copyStatistics
        let stackedInsights = availableWidth < 900
        let insightsWidth = min(500, max(360, availableWidth * 0.46))

        ScrollView {
            VStack(spacing: 16) {
                statisticsProfileCard(summary, availableWidth: availableWidth)
                activityHeatmapCard(summary, availableWidth: availableWidth)

                if stackedInsights {
                    VStack(spacing: 16) {
                        activityInsightsCard(summary)
                        commonStatisticsCard(summary)
                    }
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        activityInsightsCard(summary)
                            .frame(width: insightsWidth, alignment: .top)
                            .frame(minHeight: 304, alignment: .top)
                        commonStatisticsCard(summary)
                            .frame(maxWidth: .infinity, minHeight: 304, alignment: .top)
                    }
                }

                statisticsRecentReportsCard
                    .frame(minHeight: 260, maxHeight: 360)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
        }
        .transition(responsiveLayoutTransition)
        .animation(responsiveLayoutAnimation, value: stackedInsights)
    }

    private func statisticsProfileCard(_ summary: CopyStatisticsSummary, availableWidth: CGFloat) -> some View {
        let compact = availableWidth < 680
        let statColumns = Array(repeating: GridItem(.flexible(minimum: compact ? 116 : 138), spacing: 0), count: compact ? 2 : 5)

        return VStack(spacing: 0) {
            LazyVGrid(columns: statColumns, spacing: 0) {
                profileStatBlock(value: ByteDisplayFormatter.string(fromByteCount: summary.totalBytes), label: viewModel.localized("累计拷贝量"), compact: compact)
                profileStatBlock(value: ByteDisplayFormatter.string(fromByteCount: summary.peakDayBytes), label: viewModel.localized("峰值拷贝量"), compact: compact)
                profileStatBlock(value: stopwatchText(summary.longestReportDuration), label: viewModel.localized("最长任务"), compact: compact)
                profileStatBlock(value: "\(summary.currentStreakDays) 天", label: viewModel.localized("当前连续天数"), compact: compact)
                profileStatBlock(value: "\(summary.longestStreakDays) 天", label: viewModel.localized("最长连续天数"), compact: compact)
            }
        }
        .padding(.horizontal, compact ? 14 : 20)
        .padding(.vertical, compact ? 12 : 16)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
        .animation(responsiveLayoutAnimation, value: compact)
    }

    private func profileStatBlock(value: String, label: String, compact: Bool) -> some View {
        VStack(spacing: compact ? 3 : 5) {
            Text(value)
                .font(.system(size: compact ? 15 : 16, weight: .semibold, design: .serif).monospacedDigit())
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(label)
                .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .serif))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 48 : 54)
    }

    private func activityInsightsCard(_ summary: CopyStatisticsSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(viewModel.localized("活动洞察"))
                .sectionTitle()

            VStack(spacing: 10) {
                insightRow(viewModel.localized("备份覆盖率"), value: percentText(numerator: summary.backupReportCount, denominator: summary.totalReports))
                insightRow(viewModel.localized("成功率"), value: percentText(numerator: summary.successfulReports, denominator: summary.totalReports))
                insightRow(viewModel.localized("活跃天数"), value: "\(summary.activeDayCount)")
                insightRow(viewModel.localized("文件总数"), value: "\(summary.totalFiles)")
                insightRow(viewModel.localized("报告总数"), value: "\(summary.totalReports)")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
    }

    private func commonStatisticsCard(_ summary: CopyStatisticsSummary) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(viewModel.localized("最常用的校验"))
                .sectionTitle()

            VStack(spacing: 10) {
                if summary.verificationModeCounts.isEmpty {
                    emptyState(title: viewModel.localized("暂无统计数据"), detail: viewModel.localized("完成一次拷贝后，这里会显示每日写入热力图、最近数据量和报告数量。"))
                }

                ForEach(summary.verificationModeCounts) { item in
                    countListRow(title: item.title, count: item.count, systemImage: "checkmark.seal")
                }
            }

            Divider().opacity(0.22)

            Text(viewModel.localized("常用源设备"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryTextColor)

            VStack(spacing: 10) {
                ForEach(summary.sourceCounts) { item in
                    countListRow(title: item.title, count: item.count, systemImage: "externaldrive")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
    }

    private func insightRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .frame(width: 96, alignment: .trailing)
        }
        .frame(height: 24)
    }

    private func countListRow(title: String, count: Int, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: 24, height: 24)
                .background(accentColor.opacity(0.10), in: Circle())
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer()
            Text("\(count) \(viewModel.localized("次任务"))")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .frame(width: 86, alignment: .trailing)
        }
        .frame(height: 28)
    }

    private func percentText(numerator: Int, denominator: Int) -> String {
        guard denominator > 0 else { return "0%" }
        return "\(Int((Double(numerator) / Double(denominator) * 100).rounded()))%"
    }

    private func statisticsOverviewStrip(_ summary: CopyStatisticsSummary, availableWidth: CGFloat) -> some View {
        let compact = availableWidth < 720
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: compact ? 2 : 4)

        return LazyVGrid(columns: columns, spacing: 12) {
            statisticMetricCard(
                title: viewModel.localized("写入总量"),
                value: ByteDisplayFormatter.string(fromByteCount: summary.totalBytes),
                detail: equivalentStorageText(summary.totalBytes),
                systemImage: "externaldrive.fill.badge.checkmark",
                tint: accentColor
            )

            statisticMetricCard(
                title: viewModel.localized("近 7 天"),
                value: ByteDisplayFormatter.string(fromByteCount: summary.recent7Bytes),
                detail: recent7Detail(summary),
                systemImage: "calendar.badge.clock",
                tint: Color(red: 0.20, green: 0.62, blue: 0.45)
            )

            statisticMetricCard(
                title: viewModel.localized("报告数"),
                value: "\(summary.totalReports)",
                detail: "\(summary.successfulReports) \(viewModel.localized("成功")) · \(summary.totalFiles) \(viewModel.selectedLanguage == .english ? "files" : "个文件")",
                systemImage: "doc.text.magnifyingglass",
                tint: secondaryAccentColor
            )

            statisticMetricCard(
                title: viewModel.localized("进行中"),
                value: "\(summary.activeProjectCount)",
                detail: ByteDisplayFormatter.string(fromByteCount: summary.activeBytes),
                systemImage: "bolt.horizontal.circle.fill",
                tint: Color(red: 0.28, green: 0.58, blue: 1.00)
            )
        }
        .padding(24)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
        .animation(responsiveLayoutAnimation, value: compact)
    }

    private func statisticMetricCard(
        title: String,
        value: String,
        detail: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                Spacer()
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(size: 25, weight: .semibold, design: .serif))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(detail)
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .topLeading)
        .padding(16)
        .background(glassSurface(cornerRadius: 18, tint: tint, elevation: .tile))
    }

    private func activityHeatmapCard(_ summary: CopyStatisticsSummary, availableWidth: CGFloat) -> some View {
        let heatmap = viewModel.copyStatisticsHeatmaps.heatmap(for: selectedActivityMode)
        let narrowLayout = availableWidth < MainWindowLayoutPolicy.portraitWidthBreakpoint
        let heatmapWidth = narrowLayout ? max(620, availableWidth - 56) : heatmapGridAvailableWidth(from: availableWidth)
        let cellSize = heatmapCellSize(availableWidth: heatmapWidth, weekCount: heatmap.weeks.count)
        let cellGap = heatmapCellGap(availableWidth: heatmapWidth)

        return VStack(alignment: .leading, spacing: 18) {
            Group {
                if narrowLayout {
                    VStack(alignment: .leading, spacing: 14) {
                        heatmapTitleBlock
                        HStack(spacing: 8) {
                            activityModePicker
                            statisticsRefreshButton
                            Spacer()
                        }
                        heatmapFocusSummary(fallbackDay: heatmap.peakDay, compact: true)
                    }
                } else {
                    HStack(alignment: .top) {
                        heatmapTitleBlock
                        Spacer()
                        VStack(alignment: .trailing, spacing: 10) {
                            HStack(spacing: 8) {
                                activityModePicker
                                statisticsRefreshButton
                            }
                            heatmapFocusSummary(fallbackDay: heatmap.peakDay, compact: false)
                        }
                    }
                }
            }

            if narrowLayout {
                HStack(alignment: .top, spacing: 12) {
                    weekdayRail(cellSize: cellSize, cellGap: cellGap)
                    ScrollView(.horizontal) {
                        heatmapGrid(heatmap: heatmap, availableWidth: heatmapWidth)
                            .frame(width: heatmapWidth, alignment: .leading)
                    }
                    .scrollIndicators(.visible)
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    weekdayRail(cellSize: cellSize, cellGap: cellGap)
                    heatmapGrid(heatmap: heatmap, availableWidth: heatmapWidth)
                }
            }

            heatmapLegend(summary, compact: narrowLayout)

            if !summary.hasReportActivity {
                Text(viewModel.localized("完成一次拷贝后，这里会显示每日写入热力图、最近数据量和报告数量。"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 320, alignment: .topLeading)
        .padding(narrowLayout ? 18 : 30)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
        // hover 不再驱动整张卡片动画——高亮动画已下沉到单个格子（见 heatmapCell）。
        .animation(responsiveLayoutAnimation, value: selectedActivityMode)
        .animation(responsiveLayoutAnimation, value: narrowLayout)
    }

    private var heatmapTitleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.localized("拷贝活动"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(primaryTextColor)
            Text(viewModel.localized("颜色越深，当天写入量越大。统计来自 App 本地任务报告，主盘与备份阶段都会计入写入总量。"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statisticsRefreshButton: some View {
        Button {
            viewModel.refreshCopyStatistics()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(primaryTextColor)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(viewModel.selectedTheme == .night ? 0.10 : 0.26))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(viewModel.selectedTheme == .night ? 0.14 : 0.42), lineWidth: 0.7)
                )
        }
        .buttonStyle(.plain)
        .help(viewModel.localized("刷新统计"))
        .accessibilityLabel(Text(viewModel.localized("刷新统计")))
    }

    private var activityModePicker: some View {
        Picker(viewModel.localized("拷贝活动"), selection: $selectedActivityMode) {
            ForEach(StatisticsActivityMode.allCases) { mode in
                Text(viewModel.localized(mode.title)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 186)
        .onChange(of: selectedActivityMode) { _, _ in
            hoveredActivityDay = nil
        }
    }

    private func heatmapFocusSummary(fallbackDay: CopyActivityDay?, compact: Bool) -> some View {
        let focusedDay = hoveredActivityDay ?? fallbackDay
        let label = hoveredActivityDay == nil ? heatmapFallbackLabel : heatmapFocusedLabel

        return Group {
            let content = VStack(alignment: compact ? .leading : .trailing, spacing: 5) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)

                if let focusedDay {
                    Text("\(shortDateText(focusedDay.date)) · \(ByteDisplayFormatter.string(fromByteCount: focusedDay.bytes))")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)
                    Text(heatmapDayDetailText(focusedDay))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                } else {
                    Text(viewModel.selectedLanguage == .english ? "No data yet" : "暂无数据")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(primaryTextColor)
                }
            }

            if compact {
                content.frame(maxWidth: .infinity, alignment: .leading)
            } else {
                content.frame(minWidth: 168, alignment: .trailing)
            }
        }
    }

    private var heatmapFallbackLabel: String {
        switch selectedActivityMode {
        case .daily:
            return viewModel.localized("峰值日")
        case .weekly:
            return viewModel.selectedLanguage == .english ? "Peak Week" : "峰值周"
        case .cumulative:
            return viewModel.localized("累计")
        }
    }

    private var heatmapFocusedLabel: String {
        switch selectedActivityMode {
        case .daily:
            return viewModel.selectedLanguage == .english ? "Selected Day" : "选中日期"
        case .weekly:
            return viewModel.selectedLanguage == .english ? "Selected Week" : "选中周"
        case .cumulative:
            return viewModel.selectedLanguage == .english ? "Cumulative To Date" : "截至当天"
        }
    }

    private func heatmapGrid(heatmap: CopyStatisticsHeatmap, availableWidth: CGFloat) -> some View {
        let cellSize = heatmapCellSize(availableWidth: availableWidth, weekCount: heatmap.weeks.count)
        let cellGap = heatmapCellGap(availableWidth: availableWidth)
        // 提前算一次"今天"，避免在 371 个格子里各调一次 Calendar.startOfDay。
        let todayStart = Calendar.current.startOfDay(for: Date())

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: cellGap) {
                ForEach(Array(heatmap.weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: cellGap) {
                        ForEach(0..<week.count, id: \.self) { dayIndex in
                            if let day = week[dayIndex] {
                                heatmapCell(day, maxBytes: heatmap.maxBytes, size: cellSize, todayStart: todayStart)
                            } else {
                                heatmapEmptyCell(size: cellSize)
                            }
                        }
                    }
                }
            }
            // 用单个连续 hover 检测器代替每格的 onHover，避免几百个 NSTrackingArea 拖垮滚动。
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let point):
                    if let day = heatmapDay(at: point, in: heatmap, cellSize: cellSize, cellGap: cellGap),
                       hoveredActivityDay?.id != day.id {
                        hoveredActivityDay = day
                    }
                case .ended:
                    if hoveredActivityDay != nil {
                        hoveredActivityDay = nil
                    }
                }
            }

            HStack(alignment: .top, spacing: cellGap) {
                ForEach(Array(heatmap.weeks.enumerated()), id: \.offset) { index, week in
                    Text(heatmapMonthLabel(for: week, index: index, weeks: heatmap.weeks))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                        .frame(width: cellSize, alignment: .leading)
                }
            }
            .frame(height: 16, alignment: .leading)
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekdayRail(cellSize: CGFloat, cellGap: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: cellGap) {
            ForEach(0..<7, id: \.self) { index in
                Text(weekdayShortName(index))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(index == 1 || index == 3 || index == 5 ? secondaryTextColor : Color.clear)
                    .frame(width: 18, height: cellSize, alignment: .trailing)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func heatmapLegend(_ summary: CopyStatisticsSummary, compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 10) {
                heatmapLegendScale
                Text(viewModel.localized("等效容量") + ": " + equivalentStorageText(summary.totalBytes))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        } else {
            HStack(spacing: 8) {
                heatmapLegendScale
                Spacer()
                Text(viewModel.localized("等效容量") + ": " + equivalentStorageText(summary.totalBytes))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
    }

    private var heatmapLegendScale: some View {
        HStack(spacing: 8) {
            Text(viewModel.selectedLanguage == .english ? "Less" : "少")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            ForEach(0..<9, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(heatmapColor(level: level))
                    .frame(width: 16, height: 16)
            }
            Text(viewModel.selectedLanguage == .english ? "More" : "多")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
        }
    }

    private var statisticsRecentReportsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.localized("最近报告"))
                    .sectionTitle()
                Spacer()
                Text("\(viewModel.copyStatistics.totalReports)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(secondaryTextColor)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if viewModel.statisticsRecentReports.isEmpty {
                        emptyState(
                            title: viewModel.localized("暂无统计数据"),
                            detail: viewModel.localized("完成一次拷贝后，这里会显示每日写入热力图、最近数据量和报告数量。")
                        )
                    }

                    ForEach(viewModel.statisticsRecentReports) { report in
                        recentStatisticsReportRow(report)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
    }

    private func recentStatisticsReportRow(_ report: TransferReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(report.sourceName)
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
                Spacer()
                Text(report.success ? viewModel.localized("成功") : viewModel.localized("异常"))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(report.success ? .mint : .red)
            }

            Text("\(ByteDisplayFormatter.string(fromByteCount: report.totalBytes)) · \(report.selectedFileCount) \(viewModel.selectedLanguage == .english ? "files" : "个文件")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)

            Text(shortDateTimeText(report.finishedAt))
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(glassSurface(cornerRadius: 18, tint: report.success ? Color(red: 0.20, green: 0.62, blue: 0.45) : .orange, elevation: .tile))
    }

    private func bottomTabBar(availableWidth: CGFloat, heightCompact: Bool) -> some View {
        let compact = availableWidth < 520 || heightCompact
        let sectionCount = CGFloat(MainSection.allCases.count)
        let horizontalPadding: CGFloat = compact ? 16 : 20
        let totalSpacing = max(sectionCount - 1, 0) * (compact ? 7 : 10)
        let fittedButtonWidth = max(54, (availableWidth - horizontalPadding - totalSpacing) / max(sectionCount, 1))
        let buttonWidth = compact ? min(96, fittedButtonWidth) : 112
        let dashboardWidth = compact ? buttonWidth : 128
        let buttonHeight: CGFloat = compact ? 48 : 58
        let cornerRadius: CGFloat = compact ? 22 : 30
        let verticalPadding: CGFloat = compact ? 7 : 10

        return HStack(spacing: compact ? 7 : 10) {
            ForEach(MainSection.allCases) { section in
                Button {
                    withResponsiveAnimation {
                        viewModel.selectedSection = section
                    }
                } label: {
                    VStack(spacing: compact ? 4 : 5) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: compact ? 18 : (section == .dashboard ? 22 : 20), weight: .semibold))
                        Text(viewModel.localized(section.title))
                            .font((compact ? Font.caption2 : Font.caption).weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .foregroundStyle(viewModel.selectedSection == section ? Color.white : secondaryTextColor)
                    .frame(width: section == .dashboard ? dashboardWidth : buttonWidth, height: buttonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: compact ? 18 : 22, style: .continuous)
                            .fill(viewModel.selectedSection == section ? accentColor : Color.white.opacity(viewModel.selectedTheme == .night ? 0.09 : 0.34))
                    )
                    .scaleEffect(viewModel.selectedSection == section ? 1.015 : 1)
                    .airwangSoftShadow(
                        theme: viewModel.selectedTheme,
                        tint: viewModel.selectedSection == section ? accentColor : .clear,
                        tintStrength: viewModel.selectedSection == section ? 1 : 0,
                        elevation: viewModel.selectedSection == section ? .selected : .tile,
                        enabled: !reduceVisualEffects
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, verticalPadding)
        .background(glassSurface(cornerRadius: cornerRadius))
        .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.18, elevation: .floating, enabled: !reduceVisualEffects)
        .frame(height: buttonHeight + verticalPadding * 2)
        .frame(maxWidth: .infinity)
        .animation(responsiveLayoutAnimation, value: compact)
        .animation(responsiveLayoutAnimation, value: viewModel.selectedSection)
    }

    private func bottomTabBarHeight(availableWidth: CGFloat, heightCompact: Bool) -> CGFloat {
        let compact = availableWidth < 520 || heightCompact
        let buttonHeight: CGFloat = compact ? 48 : 58
        let verticalPadding: CGFloat = compact ? 7 : 10
        return buttonHeight + verticalPadding * 2
    }

    private func copyPresetCard(availableWidth: CGFloat) -> some View {
        let innerWidth = max(0, availableWidth - 48)
        let pickerWidth = min(240, max(200, innerWidth))
        let useCompactHeader = innerWidth < 560
        let useStackedTargets = innerWidth < 680
        let useStackedStats = innerWidth < 660

        return VStack(alignment: .leading, spacing: 18) {
            if useCompactHeader {
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.localized("拷贝项目创建"))
                        .sectionTitle()
                    executionModePicker(width: pickerWidth)
                }
            } else {
                HStack {
                    Text(viewModel.localized("拷贝项目创建"))
                        .sectionTitle()
                    Spacer()
                    executionModePicker(width: pickerWidth)
                }
            }

            Text(viewModel.executionMode.subtitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(secondaryTextColor)

            if useStackedTargets {
                VStack(spacing: 12) {
                    primaryTargetPresetBlock
                    backupTargetPresetBlock
                }
            } else {
                HStack(spacing: 14) {
                    primaryTargetPresetBlock
                    backupTargetPresetBlock
                }
            }

            if useStackedStats {
                VStack(spacing: 10) {
                    compactInfo(label: viewModel.localized("默认校验"), value: viewModel.selectedVerificationMode.shortTitle)
                    compactInfo(label: viewModel.localized("项目数"), value: "\(viewModel.copyProjects.count)")
                    compactInfo(label: viewModel.localized("运行中"), value: "\(viewModel.activeProjectIDs.count)")
                }
            } else {
                HStack(spacing: 12) {
                    compactInfo(label: viewModel.localized("默认校验"), value: viewModel.selectedVerificationMode.shortTitle)
                    compactInfo(label: viewModel.localized("项目数"), value: "\(viewModel.copyProjects.count)")
                    compactInfo(label: viewModel.localized("运行中"), value: "\(viewModel.activeProjectIDs.count)")
                }
            }

            Button {
                viewModel.startQueue()
            } label: {
                Label(viewModel.localized("执行任务队列"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .disabled(!viewModel.canStartQueue)
            .help(viewModel.startQueueDisabledHelp ?? viewModel.localized("开始执行排队中的拷贝项目"))
        }
        .padding(24)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
        .animation(responsiveLayoutAnimation, value: useCompactHeader)
        .animation(responsiveLayoutAnimation, value: useStackedTargets)
        .animation(responsiveLayoutAnimation, value: useStackedStats)
    }

    private func executionModePicker(width: CGFloat) -> some View {
        Picker(viewModel.localized("执行方式"), selection: $viewModel.executionMode) {
            ForEach(ProjectExecutionMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: width)
    }

    private var primaryTargetPresetBlock: some View {
        clickablePresetBlock(
            label: viewModel.localized("主目标盘"),
            value: viewModel.preferences.targetPath ?? viewModel.localized("尚未设置"),
            capacityLine: viewModel.targetCapacity?.capacityLine,
            accent: accentColor
        ) {
            viewModel.openFolderPicker(for: .target)
        }
    }

    private var backupTargetPresetBlock: some View {
        clickablePresetBlock(
            label: viewModel.localized("备份盘"),
            value: viewModel.preferences.backupEnabled ? (viewModel.preferences.backupPath ?? viewModel.localized("未设置备份位置")) : viewModel.localized("未启用"),
            capacityLine: viewModel.preferences.backupEnabled ? viewModel.backupCapacity?.capacityLine : viewModel.localized("点击选择后自动启用备份"),
            accent: secondaryAccentColor
        ) {
            viewModel.openFolderPicker(for: .backup)
        }
    }

    private func queueControlStrip(availableWidth: CGFloat) -> some View {
        let innerWidth = max(0, availableWidth - 36)
        let pickerWidth = min(250, max(200, innerWidth))
        let useStackedLayout = innerWidth < 720

        return Group {
            if useStackedLayout {
                VStack(alignment: .leading, spacing: 10) {
                    executionModePicker(width: pickerWidth)

                    Text(viewModel.executionMode.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        if viewModel.hasUnsavedChanges {
                            Button(viewModel.localized("重试保存")) {
                                viewModel.retrySavingPendingChanges()
                            }
                            .buttonStyle(.bordered)
                            .tint(.orange)
                        }

                        Button(viewModel.localized("执行队列")) {
                            viewModel.startQueue()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accentColor)
                        .disabled(!viewModel.canStartQueue)
                        .help(viewModel.startQueueDisabledHelp ?? viewModel.localized("开始执行排队中的拷贝项目"))
                    }
                }
            } else {
                HStack(spacing: 12) {
                    executionModePicker(width: pickerWidth)

                    Text(viewModel.executionMode.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)

                    if viewModel.hasUnsavedChanges {
                        Button(viewModel.localized("重试保存")) {
                            viewModel.retrySavingPendingChanges()
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }

                    Spacer()

                    Button(viewModel.localized("执行队列")) {
                        viewModel.startQueue()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentColor)
                    .disabled(!viewModel.canStartQueue)
                    .help(viewModel.startQueueDisabledHelp ?? viewModel.localized("开始执行排队中的拷贝项目"))
                }
            }
        }
        .padding(18)
        .background(glassSurface(cornerRadius: 22, elevation: .card))
        .transition(responsiveLayoutTransition)
        .animation(responsiveLayoutAnimation, value: useStackedLayout)
    }

    private var projectQueueCard: some View {
        let orderedProjects = viewModel.activeQueueProjects
        let firstProjectID = orderedProjects.first?.id
        let lastProjectID = orderedProjects.last?.id

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(viewModel.localized("任务队列"))
                    .sectionTitle()
                Spacer()
                Text(viewModel.localized(viewModel.executionMode.title))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(accentColor)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    if orderedProjects.isEmpty {
                        emptyState(title: viewModel.localized("队列为空"), detail: viewModel.localized("从左侧检测到的设备进入素材选择，创建项目后会出现在这里。"))
                    }

                    ForEach(orderedProjects) { project in
                        projectQueueRow(
                            project,
                            canMoveUp: firstProjectID != project.id,
                            canMoveDown: lastProjectID != project.id
                        )
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
    }

    private func clickablePresetBlock(
        label: String,
        value: String,
        capacityLine: String?,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                Text(value)
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(capacityLine ?? "容量暂不可读")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                Label("点击选择", systemImage: "folder")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
            .background(glassSurface(cornerRadius: 18, tint: accent, elevation: .tile))
        }
        .buttonStyle(.plain)
    }

    private func projectQueueRow(_ project: CopyProject, canMoveUp: Bool, canMoveDown: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)
                    Text(viewModel.localizedStatus(project.status))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(project.status))
                }
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        viewModel.moveProjectUp(project)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canMoveUp)

                    Button {
                        viewModel.moveProjectDown(project)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(!canMoveDown)
                }
            }

            if project.status == .running || project.status == .cancelling {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    projectQueueProgress(project, now: timeline.date)
                }
            } else {
                projectQueueProgress(project, now: Date())
            }

            if project.status == .queued, project.autoStartEnabled, project.autoStartDeadline != nil {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    autoStartCountdownRow(project, now: timeline.date)
                }
            }

            Text(project.sourceRootPath)
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
            Text("\(viewModel.localized("目标")): \(project.primaryImportURL.path)")
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
            if let backupImportURL = project.backupImportURL {
                Text("\(viewModel.localized("备份")): \(backupImportURL.path)")
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text(project.verificationMode.shortTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(secondaryAccentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(secondaryAccentColor)

                Text(project.hasBackup ? viewModel.localized("含备份") : viewModel.localized("仅主盘"))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((project.hasBackup ? accentColor : secondaryTextColor).opacity(0.12), in: Capsule())
                    .foregroundStyle(project.hasBackup ? accentColor : secondaryTextColor)

                Spacer()

                if project.status == .queued, project.autoStartEnabled || project.autoStartDeadline != nil {
                    Button(viewModel.localized("取消自动执行")) {
                        viewModel.cancelAutoStart(for: project)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                if viewModel.canEditBackup(for: project) {
                    Button(project.hasBackup ? viewModel.localized("更换备份") : viewModel.localized("添加备份")) {
                        viewModel.openProjectBackupPicker(for: project)
                    }
                    .buttonStyle(.bordered)
                    .tint(secondaryAccentColor)

                    if project.hasBackup {
                        Button(viewModel.localized("取消备份")) {
                            viewModel.removeBackup(from: project)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }

                if project.status == .running {
                    Button(viewModel.localized("取消")) {
                        viewModel.cancelProject(project)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else if project.status == .failed || project.status == .blocked || project.status == .cancelled {
                    Button(viewModel.localized("重试")) {
                        viewModel.retryProject(project)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                Button(viewModel.localized("改名")) {
                    viewModel.promptRenameProject(project)
                }
                .buttonStyle(.bordered)
                .disabled(project.status == .running || project.status == .cancelling)

                Button(viewModel.localized("删除")) {
                    viewModel.deleteProject(project)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(viewModel.activeProjectIDs.contains(project.id))
            }
        }
        .padding(14)
        .background(glassSurface(cornerRadius: 18, elevation: .tile))
    }

    private func autoStartCountdownRow(_ project: CopyProject, now: Date) -> some View {
        HStack(spacing: 8) {
            Label(autoStartCountdownText(project, now: now), systemImage: "timer")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.orange)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(viewModel.localized("创建后可在这里取消自动执行"))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(viewModel.selectedTheme == .night ? 0.14 : 0.10), in: Capsule())
    }

    private func autoStartCountdownText(_ project: CopyProject, now: Date) -> String {
        guard let deadline = project.autoStartDeadline else {
            return viewModel.localized("等待自动执行")
        }
        let remaining = max(deadline.timeIntervalSince(now), 0)
        if viewModel.selectedLanguage == .english {
            return "Auto-start in \(stopwatchText(remaining))"
        }
        return "\(stopwatchText(remaining)) 后自动执行"
    }

    private func projectQueueProgress(_ project: CopyProject, now: Date) -> some View {
        let progress = projectProgressFraction(project)
        let timeLine = projectTimeLine(project, now: now)

        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                Text(projectProgressTitle(project))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor(project.status))
                Spacer()
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(primaryTextColor)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(secondaryTextColor.opacity(viewModel.selectedTheme == .night ? 0.18 : 0.14))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [statusColor(project.status).opacity(0.95), statusColor(project.status).opacity(0.52)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, proxy.size.width * progress))
                }
            }
            .frame(height: 7)

            HStack(spacing: 8) {
                Label(timeLine, systemImage: project.status == .running || project.status == .cancelling ? "timer" : "clock")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                Spacer()
                Text(projectStageSummary(project))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(
            AirwangGlassSurface(
                cornerRadius: 16,
                theme: viewModel.selectedTheme,
                tint: statusColor(project.status),
                tintStrength: project.status == .running || project.status == .cancelling ? 0.30 : 0.12,
                elevation: .tile,
                reduceEffects: reduceGlassEffects
            )
        )
    }

    private func projectDashboardCard(_ project: CopyProject) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                    Text("\(project.sourceName) · \(ByteDisplayFormatter.string(fromByteCount: project.totalBytes)) · \(project.verificationMode.title)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                }
                Spacer()
                Text(viewModel.localizedStatus(project.status))
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(statusColor(project.status).opacity(0.16), in: Capsule())
                    .foregroundStyle(statusColor(project.status))
            }

            VStack(spacing: 10) {
                projectStageTrack(project.primaryCopyState, tint: accentColor)
                projectStageTrack(project.primaryVerifyState, tint: secondaryAccentColor)
                projectStageTrack(project.backupCopyState, tint: Color(red: 0.28, green: 0.58, blue: 1.00))
                projectStageTrack(project.backupVerifyState, tint: Color(red: 0.29, green: 0.78, blue: 0.58))
            }

            if let errorMessage = project.errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button(viewModel.localized("跳过校验")) {
                    viewModel.requestSkipVerification(for: project)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(project.verificationMode == .skipped || (project.status != .queued && project.status != .running))

                if viewModel.canEditBackup(for: project) {
                    Button(project.hasBackup ? viewModel.localized("更换备份盘") : viewModel.localized("添加备份盘")) {
                        viewModel.openProjectBackupPicker(for: project)
                    }
                    .buttonStyle(.bordered)
                    .tint(secondaryAccentColor)

                    if project.hasBackup {
                        Button(viewModel.localized("取消备份")) {
                            viewModel.removeBackup(from: project)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    }
                }

                Button(viewModel.localized("打开主盘")) {
                    viewModel.revealProjectOutput(project)
                }
                .buttonStyle(.bordered)
                .tint(accentColor)

                Button(viewModel.localized("主盘报告")) {
                    viewModel.openProjectReport(project, stage: .primary)
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .disabled(!viewModel.canOpenProjectReport(project, stage: .primary))

                if project.hasBackup {
                    Button(viewModel.localized("备份报告")) {
                        viewModel.openProjectReport(project, stage: .backup)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(secondaryAccentColor)
                    .disabled(!viewModel.canOpenProjectReport(project, stage: .backup))
                }

                Spacer()
            }
        }
        .padding(20)
        .background(glassSurface(cornerRadius: 24, tint: project.status == .running || project.status == .cancelling ? accentColor : nil, elevation: project.status == .running || project.status == .cancelling ? .selected : .panel))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(project.status == .running || project.status == .cancelling ? accentColor.opacity(0.54) : Color.clear, lineWidth: 1.4)
        )
    }

    private func backupProjectCard(_ project: CopyProject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                        .foregroundStyle(primaryTextColor)
                    Text(backupStatusText(project))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(project.status))
                }
                Spacer()
                if project.backupReportID != nil {
                    Button(viewModel.localized("查看备份报告")) {
                        viewModel.openProjectReport(project, stage: .backup)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(secondaryAccentColor)
                }
            }

            projectStageTrack(project.backupCopyState, tint: Color(red: 0.28, green: 0.58, blue: 1.00))
            projectStageTrack(project.backupVerifyState, tint: Color(red: 0.29, green: 0.78, blue: 0.58))

            detailRow(viewModel.localized("主目标地址"), value: project.primaryImportURL.path)
            detailRow(viewModel.localized("备份地址"), value: project.backupImportURL?.path ?? viewModel.localized("未配置"))
        }
        .padding(18)
        .background(glassSurface(cornerRadius: 20, elevation: .card))
    }

    private func projectStageTrack(_ state: ProjectStageState, tint: Color) -> some View {
        progressTrack(
            title: state.title,
            detail: "\(state.completedFiles)/\(state.totalFiles) · \(ByteDisplayFormatter.string(fromByteCount: state.processedBytes))/\(ByteDisplayFormatter.string(fromByteCount: state.totalBytes)) · \(ByteDisplayFormatter.string(fromByteCount: Int64(state.speedBytesPerSecond)))/s · 剩余 \(etaText(state.eta)) · \(state.currentFile.isEmpty ? state.detail : state.currentFile)",
            value: state.fraction,
            tint: state.isBlocked ? .orange : tint
        )
        .opacity(state.title.contains("备份") && state.detail == "未配置备份盘" ? 0.58 : 1)
    }

    private func statusColor(_ status: CopyProjectStatus) -> Color {
        switch status {
        case .queued: secondaryTextColor
        case .running: accentColor
        case .cancelling: .orange
        case .completed: .mint
        case .failed: .red
        case .blocked: .orange
        case .cancelled: .gray
        }
    }

    private func projectProgressTitle(_ project: CopyProject) -> String {
        switch project.status {
        case .queued:
            return "等待执行"
        case .running:
            if project.backupVerifyState.isActive { return "备份校验中" }
            if project.backupCopyState.isActive { return "备份中" }
            if project.primaryVerifyState.isActive { return "主盘校验中" }
            if project.primaryCopyState.isActive { return "主盘拷贝中" }
            return "正在准备"
        case .cancelling:
            return "取消收尾中"
        case .completed:
            return "已完成"
        case .failed:
            return "执行异常"
        case .blocked:
            return "备份阻塞"
        case .cancelled:
            return "已取消"
        }
    }

    private func projectStageSummary(_ project: CopyProject) -> String {
        if project.backupVerifyState.isActive || project.backupVerifyState.isComplete {
            return ProjectStageKind.backupVerify.title
        }
        if project.backupCopyState.isActive || project.backupCopyState.isComplete {
            return ProjectStageKind.backupCopy.title
        }
        if project.primaryVerifyState.isActive || project.primaryVerifyState.isComplete {
            return ProjectStageKind.primaryVerify.title
        }
        if project.primaryCopyState.isActive || project.primaryCopyState.isComplete {
            return ProjectStageKind.primaryCopy.title
        }
        return "尚未开始"
    }

    private func projectTimeLine(_ project: CopyProject, now: Date) -> String {
        switch project.status {
        case .queued:
            return "排队中"
        case .running:
            return "已用 \(stopwatchText(projectElapsed(project, now: now)))"
        case .cancelling:
            return "取消中，已用 \(stopwatchText(projectElapsed(project, now: now)))"
        case .completed:
            return "此项目用了 \(stopwatchText(projectElapsed(project, now: now)))"
        case .failed:
            return "异常前已用 \(stopwatchText(projectElapsed(project, now: now)))"
        case .blocked:
            return "阻塞前已用 \(stopwatchText(projectElapsed(project, now: now)))"
        case .cancelled:
            return "取消前已用 \(stopwatchText(projectElapsed(project, now: now)))"
        }
    }

    private func projectProgressFraction(_ project: CopyProject) -> Double {
        if project.status == .completed {
            return 1
        }

        let expectedStages = projectExpectedStages(project)
        let total = expectedStages.reduce(0) { $0 + $1.expectedBytes }
        guard total > 0 else { return 0 }

        let completed = expectedStages.reduce(Int64(0)) { partial, stage in
            partial + stageProcessedBytes(stage.state, expectedBytes: stage.expectedBytes)
        }
        return min(max(Double(completed) / Double(total), 0), 1)
    }

    private func projectExpectedStages(_ project: CopyProject) -> [(state: ProjectStageState, expectedBytes: Int64)] {
        var stages: [(ProjectStageState, Int64)] = [
            (project.primaryCopyState, max(project.primaryCopyState.totalBytes, project.totalBytes)),
            (project.primaryVerifyState, max(project.primaryVerifyState.totalBytes, project.totalBytes))
        ]

        if project.hasBackup {
            stages.append((project.backupCopyState, max(project.backupCopyState.totalBytes, project.totalBytes)))
            stages.append((project.backupVerifyState, max(project.backupVerifyState.totalBytes, project.totalBytes)))
        }

        return stages
    }

    private func stageProcessedBytes(_ state: ProjectStageState, expectedBytes: Int64) -> Int64 {
        guard expectedBytes > 0 else { return state.isComplete ? 1 : 0 }
        if state.isComplete {
            return expectedBytes
        }
        if state.totalBytes > 0 {
            return Int64((Double(expectedBytes) * state.fraction).rounded())
        }
        return min(max(state.processedBytes, 0), expectedBytes)
    }

    private func projectElapsed(_ project: CopyProject, now: Date) -> TimeInterval {
        guard let startedAt = projectStartedAt(project) else { return 0 }
        let finishedAt = projectFinishedAt(project) ?? (project.status == .running || project.status == .cancelling ? now : project.updatedAt)
        return max(finishedAt.timeIntervalSince(startedAt), 0)
    }

    private func projectStartedAt(_ project: CopyProject) -> Date? {
        let startedDates = [
            project.primaryCopyState.startedAt,
            project.primaryVerifyState.startedAt,
            project.backupCopyState.startedAt,
            project.backupVerifyState.startedAt
        ].compactMap { $0 }

        if let firstStageStart = startedDates.min() {
            return firstStageStart
        }

        switch project.status {
        case .running, .cancelling, .completed, .failed, .blocked, .cancelled:
            return project.createdAt
        case .queued:
            return nil
        }
    }

    private func projectFinishedAt(_ project: CopyProject) -> Date? {
        [
            project.primaryCopyState.finishedAt,
            project.primaryVerifyState.finishedAt,
            project.backupCopyState.finishedAt,
            project.backupVerifyState.finishedAt
        ]
        .compactMap { $0 }
        .max()
    }

    private func backupStatusText(_ project: CopyProject) -> String {
        if project.status == .blocked {
            return viewModel.localized("主盘异常，备份已阻塞")
        }
        if project.backupVerifyState.isComplete {
            return viewModel.localized("已完成")
        }
        if project.backupVerifyState.isActive {
            return viewModel.localized("正在校验备份")
        }
        if project.backupCopyState.isActive {
            return viewModel.localized("正在备份")
        }
        if project.primaryVerifyState.isComplete {
            return viewModel.localized("等待备份")
        }
        return viewModel.localized("等待主盘完成")
    }

    private var volumeListCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(viewModel.localized("已检测设备"))
                .sectionTitle()

            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.displayVolumes.isEmpty {
                        emptyState(
                            title: viewModel.localized("暂未发现可导入设备"),
                            detail: viewModel.localized("插入 SD 卡、相机盘或 SSD 后点击刷新设备。系统识别后这里会出现开始导入入口。")
                        )
                    }

                    ForEach(viewModel.displayVolumes) { volume in
                        HStack(alignment: .center, spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(accentColor.opacity(0.12))
                                    .frame(width: 50, height: 50)
                                    .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.35, elevation: .tile, enabled: !reduceVisualEffects)
                                Image(systemName: volume.isRemovable ? "externaldrive.connected.to.line.below.fill" : "internaldrive.fill")
                                    .font(.title3)
                                    .foregroundStyle(accentColor)
                                    .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.25, elevation: .tile, enabled: !reduceVisualEffects)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(volume.name)
                                        .font(.headline)
                                    Text(volume.isRemovable ? viewModel.localized("外部设备") : viewModel.localized("可用卷"))
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(accentColor.opacity(0.12), in: Capsule())
                                        .foregroundStyle(accentColor)
                                }
                                Text(volume.url.path)
                                    .font(.caption)
                                    .foregroundStyle(secondaryTextColor)
                                    .lineLimit(1)
                                Text(volume.capacityDescription)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(primaryTextColor)
                                CapacityMeter(
                                    totalCapacity: volume.totalCapacity,
                                    availableCapacity: volume.availableCapacity,
                                    tint: accentColor,
                                    backgroundColor: secondaryTextColor.opacity(0.16)
                                )
                                .frame(maxWidth: 320)
                            }
                            Spacer()
                            Button(viewModel.localized("开始导入")) {
                                viewModel.prepareImport(for: volume)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accentColor)
                        }
                        .padding(16)
                        .background(glassSurface(cornerRadius: 20, tint: accentColor, elevation: .card))
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
    }

    private var logCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.localized("任务日志"))
                    .sectionTitle()
                Spacer()
                Text("\(viewModel.localized("存储")): \(viewModel.taskLogScopeName)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if viewModel.reports.isEmpty {
                        Text(viewModel.localized("当前 App 存储暂无任务日志"))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(secondaryTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(glassSurface(cornerRadius: 18))
                    }

                    ForEach(viewModel.reports.prefix(8)) { report in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(report.title)
                                    .font(.headline)
                                Spacer()
                                Text(report.success ? viewModel.localized("成功") : viewModel.localized("异常"))
                                    .foregroundStyle(report.success ? .mint : .red)
                            }
                            Text(report.sourceName)
                                .foregroundStyle(primaryTextColor)
                            Text(report.targetPath)
                                .font(.caption)
                                .foregroundStyle(secondaryTextColor)
                            Text(reportSummaryLine(report))
                                .font(.caption)
                                .foregroundStyle(secondaryTextColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Label("\(viewModel.localized("开始")) \(preciseDateTimeText(report.startedAt))", systemImage: "play.circle")
                                Label("\(viewModel.localized("完成")) \(preciseDateTimeText(report.finishedAt))", systemImage: "checkmark.circle")
                            }
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(secondaryTextColor)
                            Text(report.verificationSummary)
                                .font(.caption)
                                .foregroundStyle(secondaryTextColor)
                            if let interruptionReason = report.interruptionReason {
                                Text("\(viewModel.localized("安全事件")): \(interruptionReason)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                            if report.reportDocumentWriteFailed {
                                Text(viewModel.localized("报告写入异常：请优先查看 App 本地报告或重新导出。"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                            HStack(spacing: 10) {
                                Button(viewModel.localized("在访达中打开")) {
                                    viewModel.revealReportInFinder(report)
                                }
                                .buttonStyle(.bordered)
                                .tint(accentColor)

                                Button(viewModel.localized("查看拷贝报告")) {
                                    viewModel.openReportDocument(report)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(secondaryAccentColor)

                                Spacer()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(glassSurface(cornerRadius: 18, elevation: .tile))
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
    }

    private func reportSummaryLine(_ report: TransferReport) -> String {
        if viewModel.selectedLanguage == .english {
            return "\(report.selectedFileCount) files · \(ByteDisplayFormatter.string(fromByteCount: report.totalBytes)) · total \(stopwatchText(report.duration))"
        }
        return "\(report.selectedFileCount) 个文件  ·  \(ByteDisplayFormatter.string(fromByteCount: report.totalBytes))  ·  总耗时 \(stopwatchText(report.duration))"
    }

    private func heatmapCell(_ day: CopyActivityDay, maxBytes: Int64, size: CGFloat, todayStart: Date) -> some View {
        let level = heatmapLevel(bytes: day.bytes, maxBytes: maxBytes)
        let isHovered = hoveredActivityDay?.id == day.id
        let isToday = day.date == todayStart

        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(heatmapColor(level: level))
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(
                        isHovered ? primaryTextColor.opacity(0.72) : (isToday ? primaryTextColor.opacity(0.38) : Color.clear),
                        lineWidth: isHovered ? 1.4 : 1
                    )
            )
            .frame(width: size, height: size)
            .scaleEffect(isHovered ? 1.10 : 1)
            .zIndex(isHovered ? 1 : 0)
            // 高亮动画只作用于当前格子，避免整张卡片随 hover 跑弹簧。
            .animation(reduceMotionEffects ? nil : .easeOut(duration: 0.12), value: isHovered)
    }

    /// 把网格本地坐标映射回某一天。每列恒为 7 格、列宽/行高为固定步长，可直接整除定位。
    private func heatmapDay(at point: CGPoint, in heatmap: CopyStatisticsHeatmap, cellSize: CGFloat, cellGap: CGFloat) -> CopyActivityDay? {
        let stride = cellSize + cellGap
        guard stride > 0, point.x >= 0, point.y >= 0 else { return nil }

        let column = Int(point.x / stride)
        let row = Int(point.y / stride)
        guard column >= 0, column < heatmap.weeks.count, row >= 0, row < 7 else { return nil }

        // 落在格间空隙里时返回 nil，由调用方保持上一次高亮，避免抖动。
        guard point.x - CGFloat(column) * stride <= cellSize,
              point.y - CGFloat(row) * stride <= cellSize else { return nil }

        let week = heatmap.weeks[column]
        guard row < week.count else { return nil }
        return week[row]
    }

    private func heatmapEmptyCell(size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.clear)
            .frame(width: size, height: size)
    }

    private func heatmapLevel(bytes: Int64, maxBytes: Int64) -> Int {
        guard bytes > 0, maxBytes > 0 else { return 0 }
        let fraction = Double(bytes) / Double(maxBytes)
        if fraction < 0.08 { return 1 }
        if fraction < 0.18 { return 2 }
        if fraction < 0.30 { return 3 }
        if fraction < 0.44 { return 4 }
        if fraction < 0.58 { return 5 }
        if fraction < 0.72 { return 6 }
        if fraction < 0.88 { return 7 }
        return 8
    }

    private func heatmapColor(level: Int) -> Color {
        let baseColor = Color(red: 0.23, green: 0.57, blue: 1.00)
        let nightOpacity: [Double] = [0.18, 0.28, 0.38, 0.48, 0.60, 0.72, 0.84, 0.92, 1.00]
        let dayOpacity: [Double] = [0.12, 0.20, 0.30, 0.40, 0.52, 0.64, 0.76, 0.86, 0.96]
        let index = min(max(level, 0), 8)

        switch level {
        case 0:
            return secondaryTextColor.opacity(viewModel.selectedTheme == .night ? 0.18 : 0.12)
        default:
            return baseColor.opacity(viewModel.selectedTheme == .night ? nightOpacity[index] : dayOpacity[index])
        }
    }

    private func heatmapGridAvailableWidth(from availableWidth: CGFloat) -> CGFloat {
        max(180, availableWidth - 90)
    }

    private func heatmapCellSize(availableWidth: CGFloat, weekCount: Int) -> CGFloat {
        let columns = CGFloat(max(weekCount, 1))
        let gap = heatmapCellGap(availableWidth: availableWidth)
        let gapWidth = gap * max(columns - 1, 0)
        let fitted = (availableWidth - gapWidth) / columns
        let clamped = min(20, max(3.0, fitted))
        return (clamped * 2).rounded(.down) / 2
    }

    private func heatmapCellGap(availableWidth: CGFloat) -> CGFloat {
        if availableWidth < 420 { return 1.5 }
        if availableWidth < 700 { return 2.5 }
        return 4
    }

    private func weekdayShortName(_ index: Int) -> String {
        if viewModel.selectedLanguage == .english {
            return ["S", "M", "T", "W", "T", "F", "S"][index]
        }
        return ["日", "一", "二", "三", "四", "五", "六"][index]
    }

    private func heatmapMonthLabel(for week: [CopyActivityDay?], index: Int, weeks: [[CopyActivityDay?]]) -> String {
        guard let firstDate = week.compactMap({ $0?.date }).first else { return "" }
        let calendar = Calendar.current
        let month = calendar.component(.month, from: firstDate)

        if index > 0,
           let previousDate = weeks[index - 1].compactMap({ $0?.date }).first,
           calendar.component(.month, from: previousDate) == month {
            return ""
        }

        if viewModel.selectedLanguage == .english {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: viewModel.selectedLanguage.localeIdentifier)
            formatter.setLocalizedDateFormatFromTemplate("MMM")
            return formatter.string(from: firstDate)
        }

        return "\(month)月"
    }

    private func heatmapDayDetailText(_ day: CopyActivityDay) -> String {
        if viewModel.selectedLanguage == .english {
            return "\(day.reportCount) reports · \(day.files) files"
        }
        return "\(day.reportCount) 份报告 · \(day.files) 个文件"
    }

    private func recent7Detail(_ summary: CopyStatisticsSummary) -> String {
        let daysWithActivity = summary.days.suffix(7).filter(\.hasActivity).count
        if viewModel.selectedLanguage == .english {
            return "\(daysWithActivity) active days"
        }
        return "\(daysWithActivity) 天有写入"
    }

    private func equivalentStorageText(_ bytes: Int64) -> String {
        guard bytes > 0 else {
            return viewModel.selectedLanguage == .english ? "No data yet" : "暂无数据"
        }
        let cardBytes = Double(128_000_000_000)
        let cardCount = Double(bytes) / cardBytes
        let formattedCount = cardCount >= 10
            ? String(format: "%.0f", cardCount)
            : String(format: "%.1f", max(cardCount, 0.1))
        if viewModel.selectedLanguage == .english {
            return "About \(formattedCount) x 128GB cards"
        }
        return "约 \(formattedCount) 张 128GB 卡"
    }

    private func shortDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: viewModel.selectedLanguage.localeIdentifier)
        if viewModel.selectedLanguage == .english {
            formatter.setLocalizedDateFormatFromTemplate("MMM d")
        } else {
            formatter.dateFormat = "M月d日"
        }
        return formatter.string(from: date)
    }

    private func shortDateTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: viewModel.selectedLanguage.localeIdentifier)
        if viewModel.selectedLanguage == .english {
            formatter.setLocalizedDateFormatFromTemplate("MMM d, HH:mm")
        } else {
            formatter.dateFormat = "M月d日 HH:mm"
        }
        return formatter.string(from: date)
    }

    private func destinationCard(badge: String, title: String, path: String?, actionTitle: String, action: @escaping () -> Void) -> some View {
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

    private func detailRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(primaryTextColor)
        }
    }

    private func progressTrack(title: String, detail: String, value: Double, tint: Color) -> some View {
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

    private func glassSurface(
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

    private func etaText(_ value: TimeInterval?) -> String {
        guard let value else { return "--" }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = value > 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: value) ?? "--"
    }

    private func stopwatchText(_ value: TimeInterval) -> String {
        let totalSeconds = max(Int(value.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func preciseDateTimeText(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm:ss"
        return formatter.string(from: value)
    }

    private func onboardingFeature(label: String, detail: String) -> some View {
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

    private func emphasisBlock(label: String, value: String, capacityLine: String?, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.08))
                .overlay(
                    VStack(alignment: .leading, spacing: 6) {
                        Text(value)
                            .font(.headline)
                            .foregroundStyle(primaryTextColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                            .minimumScaleFactor(0.88)
                        if let capacityLine {
                            Text(capacityLine)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(secondaryTextColor)
                                .lineLimit(1)
                        }
                    }
                    .padding(14)
                )
                .frame(height: 96)
                .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accent, tintStrength: 0.35, elevation: .tile, enabled: !reduceVisualEffects)
        }
    }

    private func emptyState(title: String, detail: String) -> some View {
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

    private func compactInfo(label: String, value: String) -> some View {
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

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(primaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(glassSurface(cornerRadius: 16, elevation: .tile))
    }

    private var musicBackdrop: some View {
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

    private var ambientAurora: some View {
        Group {
            if reduceGlassEffects {
                Color.clear
            } else {
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
                        // material 依赖实时背景采样,不能进 drawingGroup,单独保留。
                        RoundedRectangle(cornerRadius: 60, style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.50))
                            .frame(height: 340)
                            .blur(radius: 34)
                            .offset(y: -170)
                            .opacity(0.88)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var responsiveLayoutAnimation: Animation {
        .spring(response: 0.38, dampingFraction: 0.82, blendDuration: 0.12)
    }

    private var responsiveLayoutTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.985, anchor: .top))
    }

    private func withResponsiveAnimation(_ action: () -> Void) {
        if accessibilityReduceMotion {
            action()
        } else {
            withAnimation(responsiveLayoutAnimation) {
                action()
            }
        }
    }

    // 只在窗口缩放时降级视觉效果。此前滚动也会触发降级(isScrolling),
    // 导致滚动开始/结束时所有玻璃面板在两棵不同视图树之间整体切换。
    private var reduceVisualEffects: Bool {
        isWindowResizing
    }

    private var reduceGlassEffects: Bool {
        isWindowResizing
    }

    private var reduceMotionEffects: Bool {
        accessibilityReduceMotion
    }

    private func markWindowResizing() {
        if !isWindowResizing {
            withResponsiveAnimation {
                isWindowResizing = true
            }
        }

        resizeSettlingTask?.cancel()
        resizeSettlingTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            withResponsiveAnimation {
                isWindowResizing = false
            }
        }
    }

    // 颜色全部委托给 `AppTheme` 扩展(Views/Theme/AirwangPalette.swift),避免再次出现
    // 三套独立定义(见 TEST_REPORT.md #45/#46/#47)。
    private var primaryTextColor: Color { viewModel.selectedTheme.primaryTextColor }
    private var secondaryTextColor: Color { viewModel.selectedTheme.secondaryTextColor }
    private var accentColor: Color { viewModel.selectedTheme.accentColor }
    private var secondaryAccentColor: Color { viewModel.selectedTheme.secondaryAccentColor }

}

/// 全工程统一的投影标尺:每个海拔等级只有两层阴影 ——
/// ambient(环境光,大半径低不透明度,决定"浮多高")+ contact(接触影,
/// 小半径,把元素"压"在表面上)。此前每个表面叠 4 层(白色顶光 + 染色光晕 +
/// 两层黑),且大量调用点没有先做 compositingGroup,阴影按内部每个图元分别
/// 绘制,视觉上糊成一片、GPU 上是数倍浪费。顶光效果由玻璃面板的描边承担,
/// 染色光晕由选中态的描边承担,阴影只负责深度,层级一目了然。
private enum AirwangGlassElevation {
    case panel
    case card
    case tile
    case floating
    case selected

    var ambientRadius: CGFloat {
        switch self {
        case .panel: 26
        case .card: 18
        case .tile: 11
        case .floating: 34
        case .selected: 22
        }
    }

    var ambientY: CGFloat {
        switch self {
        case .panel: 13
        case .card: 9
        case .tile: 5
        case .floating: 17
        case .selected: 11
        }
    }

    var contactRadius: CGFloat {
        switch self {
        case .panel: 9
        case .card: 7
        case .tile: 4
        case .floating: 12
        case .selected: 8
        }
    }

    var contactY: CGFloat {
        switch self {
        case .panel: 4
        case .card: 3
        case .tile: 2
        case .floating: 6
        case .selected: 4
        }
    }

    /// 环境影不透明度(日 / 夜)。
    var ambientOpacity: (day: Double, night: Double) {
        switch self {
        case .panel: (0.09, 0.46)
        case .card: (0.08, 0.42)
        case .tile: (0.06, 0.34)
        case .floating: (0.13, 0.55)
        case .selected: (0.11, 0.50)
        }
    }

    /// 接触影不透明度(日 / 夜)。
    var contactOpacity: (day: Double, night: Double) {
        switch self {
        case .panel: (0.06, 0.24)
        case .card: (0.05, 0.22)
        case .tile: (0.04, 0.18)
        case .floating: (0.08, 0.28)
        case .selected: (0.07, 0.25)
        }
    }
}

private struct AirwangGlassSurface: View {
    let cornerRadius: CGFloat
    let theme: AppTheme
    let tint: Color
    let tintStrength: Double
    let elevation: AirwangGlassElevation
    var reduceEffects = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if reduceEffects {
            ZStack {
                shape
                    .fill(theme == .night ? Color(red: 0.10, green: 0.08, blue: 0.09).opacity(0.82) : Color.white.opacity(0.64))
                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(theme == .night ? 0.07 : 0.36),
                                tint.opacity(theme == .night ? 0.035 * tintStrength : 0.035 * tintStrength),
                                Color.black.opacity(theme == .night ? 0.08 : 0.018)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                shape
                    .strokeBorder(Color.white.opacity(theme == .night ? 0.18 : 0.66), lineWidth: theme == .night ? 0.9 : 0.75)
                shape
                    .strokeBorder(Color.black.opacity(theme == .night ? 0.22 : 0.025), lineWidth: 0.6)
            }
        } else {
            ZStack {
                shape
                    .fill(theme == .night ? Color(red: 0.095, green: 0.075, blue: 0.086).opacity(0.70) : Color.white.opacity(0.18))

                shape
                    .fill(.ultraThinMaterial.opacity(theme == .night ? 0.26 : 0.78))

                shape
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(theme == .night ? 0.08 : 0.34),
                                tint.opacity(theme == .night ? 0.032 * tintStrength : 0.07 * tintStrength),
                                Color.black.opacity(theme == .night ? 0.14 : 0.045)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(theme == .night ? .plusLighter : .screen)

                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(theme == .night ? 0.22 : 0.86),
                                Color.white.opacity(theme == .night ? 0.07 : 0.22),
                                tint.opacity(theme == .night ? 0.10 * tintStrength : 0.12 * tintStrength)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: theme == .night ? 1.15 : 0.9
                    )

                shape
                    .strokeBorder(Color.black.opacity(theme == .night ? 0.34 : 0.055), lineWidth: 0.7)
                    .blendMode(.multiply)

                shape
                    .inset(by: 1.2)
                    .strokeBorder(Color.white.opacity(theme == .night ? 0.05 : 0.42), lineWidth: 0.6)
            }
            // 注意:这里不再叠加 macOS 26 的 glassEffect —— 上面的 material + 渐变
            // 已经是完整的玻璃质感,双重玻璃 = 每帧两次背景采样,只贵不亮。
            .compositingGroup()
            .modifier(AirwangLayeredShadow(theme: theme, tint: tint, tintStrength: tintStrength, elevation: elevation))
        }
    }
}

private struct AirwangLayeredShadow: ViewModifier {
    let theme: AppTheme
    let tint: Color
    let tintStrength: Double
    let elevation: AirwangGlassElevation

    func body(content: Content) -> some View {
        let isNight = theme == .night
        let ambient = elevation.ambientOpacity
        let contact = elevation.contactOpacity
        // tint / tintStrength 参数保留以兼容既有调用点;
        // 染色光晕已从阴影系统移除(由选中态描边承担)。
        return content
            .shadow(
                color: Color.black.opacity(isNight ? ambient.night : ambient.day),
                radius: elevation.ambientRadius,
                x: 0,
                y: elevation.ambientY
            )
            .shadow(
                color: Color.black.opacity(isNight ? contact.night : contact.day),
                radius: elevation.contactRadius,
                x: 0,
                y: elevation.contactY
            )
    }
}

private extension View {
    @ViewBuilder
    func airwangSoftShadow(
        theme: AppTheme,
        tint: Color,
        tintStrength: Double = 0,
        elevation: AirwangGlassElevation = .tile,
        enabled: Bool = true
    ) -> some View {
        if enabled {
            // compositingGroup 把内容先合成为单层再投影:没有它,.shadow 会给
            // 视图内部每个图元各画一份阴影(文字、图标、描边各一份),又糊又慢。
            compositingGroup()
                .modifier(AirwangLayeredShadow(theme: theme, tint: tint, tintStrength: tintStrength, elevation: elevation))
        } else {
            self
        }
    }
}

private struct ImportSheet: View {
    let volume: StorageVolume
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var expandedGroupIDs: Set<String> = []
    @State private var selectedBrowserFolder = ""
    @State private var focusedGalleryItemID: String?

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button {
                    handlePrimaryBackAction()
                } label: {
                    Label(primaryBackTitle, systemImage: primaryBackIcon)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isScanning || (!viewModel.hasScannedSource && !canGoUp))

                VStack(alignment: .leading, spacing: 5) {
                    Text("新存储设备已接入")
                        .font(.title2.bold())
                    Text(volume.name)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.hasScannedSource {
                    Picker("模式", selection: $viewModel.selectedImportMode) {
                        ForEach(ImportMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                Button {
                    viewModel.closeImportSheet()
                } label: {
                    Label("退出", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            importStepRail

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.hasScannedSource {
                        Text(viewModel.selectedImportMode.subtitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(secondaryTextColor)
                    } else {
                        Text("先在当前设备里选择一个具体文件夹，再点击扫描。扫描完成后再选择需要拷贝的素材。")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(secondaryTextColor)
                    }

                    if viewModel.isScanning {
                        scanningState
                    } else if viewModel.hasScannedSource {
                        content
                    } else {
                        sourcePickerSection
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 500, alignment: .topLeading)

                ScrollView {
                    summarySection
                }
                .frame(width: 340)
            }
        }
        .padding(28)
        .frame(minWidth: 980, idealWidth: 1180, maxWidth: .infinity, minHeight: 660, idealHeight: 760, maxHeight: .infinity)
        .background(importSheetBackground)
        .background(ResizableSheetWindowConfigurator(minSize: NSSize(width: 980, height: 660), idealSize: NSSize(width: 1180, height: 760)))
        .fontDesign(.serif)
        .preferredColorScheme(viewModel.selectedTheme == .night ? .dark : .light)
    }

    private func handlePrimaryBackAction() {
        if viewModel.hasScannedSource {
            viewModel.returnToSourceFolderSelection()
        } else if canGoUp {
            viewModel.navigateSourceFolderUp()
        }
    }

    private var primaryBackTitle: String {
        if viewModel.isScanning {
            return "正在扫描"
        }
        if viewModel.hasScannedSource {
            return "重新选择文件夹"
        }
        if canGoUp {
            return "上一级"
        }
        return "设备根目录"
    }

    private var primaryBackIcon: String {
        if viewModel.isScanning {
            return "hourglass"
        }
        return "chevron.left"
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            scannedSelectionHeader

            if viewModel.scannedItems.isEmpty {
                importEmptyState(
                    title: "没有找到匹配素材",
                    detail: "可以切换扫描类型，或返回上一级选择更大的源文件夹后重新扫描。"
                )
            } else {
                switch viewModel.selectedImportMode {
                case .time:
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.timeGroups) { group in
                                timeGroupCard(group)
                            }
                        }
                    }
                case .free:
                    assetBrowserContent
                }
            }
        }
    }

    @ViewBuilder
    private var assetBrowserContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            browserModeBar

            switch viewModel.selectedAssetBrowserMode {
            case .icon:
                iconBrowser
            case .list:
                listBrowser
            case .column:
                columnBrowser
            case .gallery:
                galleryBrowser
            }
        }
    }

    private var browserModeBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("自由浏览")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                Text(viewModel.selectedAssetBrowserMode.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryTextColor)
            }
            Spacer()
            Picker("浏览方式", selection: $viewModel.selectedAssetBrowserMode) {
                ForEach(AssetBrowserMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 390)
        }
        .padding(14)
        .background(glassPanel(cornerRadius: 18))
    }

    private var iconBrowser: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(viewModel.scannedItems) { item in
                    freeSelectionTile(item)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var listBrowser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("名称")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("类型")
                    .frame(width: 72, alignment: .leading)
                Text("大小")
                    .frame(width: 100, alignment: .trailing)
                Text("创建时间")
                    .frame(width: 128, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(secondaryTextColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.35)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.scannedItems) { item in
                        listSelectionRow(item: item)
                    }
                }
                .padding(8)
            }
        }
        .background(glassPanel(cornerRadius: 20))
    }

    private var columnBrowser: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("文件夹")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(browserFolders, id: \.self) { folder in
                            Button {
                                selectedBrowserFolder = folder
                            } label: {
                                HStack {
                                    Image(systemName: folder.isEmpty ? "externaldrive.fill" : "folder.fill")
                                        .foregroundStyle(folder.isEmpty ? accentColor : .orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.isEmpty ? "扫描根目录" : folderName(folder))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(primaryTextColor)
                                            .lineLimit(1)
                                        Text(folder.isEmpty ? "根目录文件" : folder)
                                            .font(.caption2)
                                            .foregroundStyle(secondaryTextColor)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(items(in: folder).count)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(secondaryTextColor)
                                }
                                .padding(10)
                                .background(
                                    selectedBrowserFolder == folder ? accentColor.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
            }
            .frame(width: 260)
            .padding(14)
            .background(glassPanel(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedBrowserFolder.isEmpty ? "扫描根目录" : folderName(selectedBrowserFolder))
                            .font(.headline)
                            .foregroundStyle(primaryTextColor)
                        Text(selectedBrowserFolder.isEmpty ? "显示根目录下匹配文件" : selectedBrowserFolder)
                            .font(.caption)
                            .foregroundStyle(secondaryTextColor)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(columnItems.count) 个文件")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(columnItems) { item in
                            listSelectionRow(item: item)
                        }
                    }
                }
            }
            .padding(14)
            .background(glassPanel(cornerRadius: 20))
        }
        .onAppear {
            normalizeSelectedBrowserFolder()
        }
        .onChange(of: viewModel.scannedItems) { _, _ in
            normalizeSelectedBrowserFolder()
        }
    }

    private var galleryBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            let item = focusedGalleryItem
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(thumbFill)
                    if let item {
                        ThumbnailView(url: item.fileURL)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(14)
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 58, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 330)
                .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.24, elevation: .card)
                .onTapGesture {
                    if let item {
                        viewModel.toggle(item: item)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("预览详情")
                        .font(.headline)
                        .foregroundStyle(primaryTextColor)
                    if let item {
                        galleryDetail(label: "文件名", value: item.displayName)
                        galleryDetail(label: "路径", value: item.relativePath)
                    galleryDetail(label: "类型", value: mediaKindTitle(for: item))
                        galleryDetail(label: "大小", value: byteText(item.size))
                        galleryDetail(label: "创建时间", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))

                        Button(viewModel.selectedItemIDs.contains(item.id) ? "从导入中移除" : "加入导入选择") {
                            viewModel.toggle(item: item)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.selectedItemIDs.contains(item.id) ? .red : accentColor)
                        .controlSize(.large)
                    } else {
                        Text("没有可预览的素材")
                            .foregroundStyle(secondaryTextColor)
                    }
                    Spacer()
                }
                .frame(width: 240, alignment: .topLeading)
                .padding(16)
                .background(glassPanel(cornerRadius: 20))
            }

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(viewModel.scannedItems) { item in
                        galleryStripTile(item)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .background(glassPanel(cornerRadius: 22))
        .onAppear {
            normalizeFocusedGalleryItem()
        }
        .onChange(of: viewModel.scannedItems) { _, _ in
            normalizeFocusedGalleryItem()
        }
    }

    private var importStepRail: some View {
        // 步骤 3 的 active 条件不再依赖 `selectedItems.isEmpty`(扫描完成后会自动全选,
        // 导致这条件永远 false → 步骤 3 从未被点亮,见 TEST_REPORT.md #74)。
        // 现在的语义是:扫描完成后,用户处于"选择 / 复核素材"阶段,步骤 3 一直
        // 高亮直到 sheet 关闭。步骤 4 与之并列高亮,表示"下一步按钮已就绪"。
        //
        // 步骤 4 标题改为"加入任务队列",与按钮 `创建项目并加入队列` 的实际行为
        // 保持一致(原"开始拷贝+校验"具有误导性,见 #54 / #75)。
        let scanDone = viewModel.hasScannedSource
        return HStack(spacing: 10) {
            stepPill(index: "1", title: "选源文件夹", isActive: !scanDone && !viewModel.isScanning, isDone: viewModel.isScanning || scanDone)
            stepPill(index: "2", title: "扫描素材", isActive: viewModel.isScanning, isDone: scanDone)
            stepPill(index: "3", title: "选择素材", isActive: scanDone, isDone: false)
            stepPill(index: "4", title: "加入任务队列", isActive: scanDone && viewModel.canStartImport, isDone: false)
        }
        .padding(12)
        .background(glassPanel(cornerRadius: 22))
    }

    private func stepPill(index: String, title: String, isActive: Bool, isDone: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isDone ? accentColor : (isActive ? accentColor.opacity(0.16) : secondaryTextColor.opacity(0.14)))
                    .frame(width: 26, height: 26)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text(index)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isActive ? accentColor : secondaryTextColor)
                }
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive || isDone ? primaryTextColor : secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isActive ? accentColor.opacity(0.10) : Color.clear, in: Capsule())
    }

    private var scanningState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .scaleEffect(1.15)
            Text("正在扫描素材...")
                .font(.headline)
                .foregroundStyle(primaryTextColor)
            Text("当前只读取你选择的文件夹，不会浪费资源扫描整张卡。")
                .font(.subheadline)
                .foregroundStyle(secondaryTextColor)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 420)
        .background(glassPanel(cornerRadius: 24))
    }

    private var scannedSelectionHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("已扫描 \(viewModel.scannedItems.count) 个文件")
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                Text("当前选择 \(viewModel.selectedItems.count) 个 · \(byteText(viewModel.selectedTotalBytes)) / 扫描总量 \(byteText(viewModel.scannedTotalBytes))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                Text("勾选素材时会自动带上同文件夹、同文件名的 sidecar / 元数据文件。")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(secondaryTextColor)
            }
            Spacer()
            Button("全选") {
                viewModel.selectAllScannedItems()
            }
            .buttonStyle(.bordered)
            .tint(accentColor)

            Button("清空选择") {
                viewModel.clearScannedSelection()
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(16)
        .background(glassPanel(cornerRadius: 20))
    }

    private func timeGroupCard(_ group: TimeGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    viewModel.toggle(group: group)
                } label: {
                    Image(systemName: isGroupSelected(group) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isGroupSelected(group) ? accentColor : secondaryTextColor)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.headline)
                        .foregroundStyle(primaryTextColor)
                    Text("\(group.items.count) 个文件 · \(byteText(group.totalSize))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                }
                Spacer()
                Text(isGroupSelected(group) ? "整组已选" : "点击圆圈选择整组")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isGroupSelected(group) ? accentColor : secondaryTextColor)
            }

            ForEach(expandedGroupIDs.contains(group.id) ? group.items : Array(group.items.prefix(6))) { item in
                selectionRow(item: item)
            }

            if group.items.count > 6 {
                Button(expandedGroupIDs.contains(group.id) ? "收起" : "展开全部 \(group.items.count) 个文件") {
                    if expandedGroupIDs.contains(group.id) {
                        expandedGroupIDs.remove(group.id)
                    } else {
                        expandedGroupIDs.insert(group.id)
                    }
                }
                .buttonStyle(.borderless)
                .tint(accentColor)
            }
        }
        .padding(16)
        .background(glassPanel(cornerRadius: 20))
    }

    private func freeSelectionTile(_ item: MediaItem) -> some View {
        let isSelected = viewModel.selectedItemIDs.contains(item.id)

        return Button {
            viewModel.toggle(item: item)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ThumbnailView(url: item.fileURL)
                    .frame(height: 104)
                    .frame(maxWidth: .infinity)
                    .background(thumbFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.18, elevation: .tile)

                Text(item.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(2)
                Text(byteText(item.size))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? accentColor : Color.clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(accentColor)
                            .padding(8)
                            .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.45, elevation: .tile)
                }
            }
            .background(glassPanel(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func listSelectionRow(item: MediaItem) -> some View {
        let isSelected = viewModel.selectedItemIDs.contains(item.id)

        return Button {
            viewModel.toggle(item: item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? accentColor : secondaryTextColor)
                    .frame(width: 24)

                Image(systemName: mediaIcon(for: item))
                    .font(.headline)
                    .foregroundStyle(accentColor)
                    .frame(width: 24)
                    .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.18, elevation: .tile)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)
                    Text(item.relativePath)
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(mediaKindTitle(for: item))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 72, alignment: .leading)

                Text(byteText(item.size))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 100, alignment: .trailing)

                Text(item.createdAt.formatted(date: .numeric, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 128, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                isSelected ? accentColor.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func galleryDetail(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(primaryTextColor)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func galleryStripTile(_ item: MediaItem) -> some View {
        let isFocused = focusedGalleryItem?.id == item.id
        let isSelected = viewModel.selectedItemIDs.contains(item.id)

        return Button {
            focusedGalleryItemID = item.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ThumbnailView(url: item.fileURL)
                    .frame(width: 118, height: 72)
                    .background(thumbFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.15, elevation: .tile)

                Text(item.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
            }
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isFocused ? accentColor : (isSelected ? secondaryAccentColor : Color.clear), lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(secondaryAccentColor)
                            .padding(5)
                            .airwangSoftShadow(theme: viewModel.selectedTheme, tint: secondaryAccentColor, tintStrength: 0.45, elevation: .tile)
                }
            }
            .background(glassPanel(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var browserFolders: [String] {
        let folders = Set(viewModel.scannedItems.map(folderPath(for:)))
        return folders.sorted { lhs, rhs in
            if lhs.isEmpty { return true }
            if rhs.isEmpty { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private var columnItems: [MediaItem] {
        items(in: selectedBrowserFolder)
    }

    private var focusedGalleryItem: MediaItem? {
        if let focusedGalleryItemID,
           let item = viewModel.scannedItems.first(where: { $0.id == focusedGalleryItemID }) {
            return item
        }
        return viewModel.scannedItems.first
    }

    private func normalizeSelectedBrowserFolder() {
        guard !browserFolders.isEmpty else {
            selectedBrowserFolder = ""
            return
        }
        if !browserFolders.contains(selectedBrowserFolder) {
            selectedBrowserFolder = browserFolders.first ?? ""
        }
    }

    private func normalizeFocusedGalleryItem() {
        guard !viewModel.scannedItems.isEmpty else {
            focusedGalleryItemID = nil
            return
        }
        if let focusedGalleryItemID,
           viewModel.scannedItems.contains(where: { $0.id == focusedGalleryItemID }) {
            return
        }
        focusedGalleryItemID = viewModel.scannedItems.first?.id
    }

    private func items(in folder: String) -> [MediaItem] {
        viewModel.scannedItems.filter { folderPath(for: $0) == folder }
    }

    private func folderPath(for item: MediaItem) -> String {
        guard let slashIndex = item.relativePath.lastIndex(of: "/") else { return "" }
        return String(item.relativePath[..<slashIndex])
    }

    private func folderName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private func mediaIcon(for item: MediaItem) -> String {
        switch item.mediaKind {
        case .video:
            return "film.fill"
        case .photo:
            return "photo.fill"
        case .audio:
            return "waveform"
        case .all:
            return "doc.fill"
        }
    }

    private func mediaKindTitle(for item: MediaItem) -> String {
        switch item.mediaKind {
        case .video:
            return "视频"
        case .photo:
            return "照片"
        case .audio:
            return "音频"
        case .all:
            return item.fileURL.pathExtension.isEmpty ? "其他" : item.fileURL.pathExtension.uppercased()
        }
    }

    private func importEmptyState(title: String, detail: String) -> some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(accentColor)
            Text(title)
                .font(.headline)
                .foregroundStyle(primaryTextColor)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(24)
        .background(glassPanel(cornerRadius: 24))
    }

    private var sourcePickerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                sourceGuideCard(number: "1", title: "进入文件夹", detail: "只扫描你确认的目录")
                sourceGuideCard(number: "2", title: "选择类型", detail: "视频 / 照片 / 音频 / 全部")
                sourceGuideCard(number: "3", title: "开始扫描", detail: "扫描后再勾选素材")
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择源文件夹")
                        .font(.headline)
                    Text(viewModel.sourceFolderURL?.path ?? volume.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    viewModel.navigateSourceFolderUp()
                } label: {
                    Label("上一级", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(!canGoUp)
            }

            Picker("扫描类型", selection: Binding(
                get: { viewModel.selectedScanFilter },
                set: { viewModel.setScanFilter($0) }
            )) {
                ForEach(ScanFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            ScrollView {
                LazyVStack(spacing: 10) {
                    currentSourceFolderCard

                    if viewModel.isLoadingSourceFolderChildren {
                        ProgressView("正在读取文件夹...")
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    }

                    ForEach(viewModel.sourceFolderChildren) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                    .foregroundStyle(primaryTextColor)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(secondaryTextColor)
                                    .lineLimit(1)
                                Text(item.capacityLine)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(secondaryTextColor)
                                CapacityMeter(
                                    totalCapacity: item.totalCapacity,
                                    availableCapacity: item.availableCapacity,
                                    tint: accentColor,
                                    backgroundColor: secondaryTextColor.opacity(0.15)
                                )
                                .frame(maxWidth: 260)
                            }
                            Spacer()
                            Button("进入并设为当前") {
                                viewModel.navigateSourceFolder(to: item.url)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accentColor)
                        }
                        .padding(14)
                        .background(glassPanel(cornerRadius: 18))
                    }
                }
            }
        }
    }

    private var currentSourceFolderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前准备扫描")
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            Text(viewModel.selectedSourceFolderItem?.name ?? volume.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(primaryTextColor)
            Text(viewModel.selectedSourceFolderItem?.subtitle ?? volume.url.path)
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
            if let selectedSourceFolderItem = viewModel.selectedSourceFolderItem {
                Text(selectedSourceFolderItem.capacityLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                CapacityMeter(
                    totalCapacity: selectedSourceFolderItem.totalCapacity,
                    availableCapacity: selectedSourceFolderItem.availableCapacity,
                    tint: accentColor,
                    backgroundColor: secondaryTextColor.opacity(0.15)
                )
            }
            HStack {
                Text("只扫描这个目录")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                Spacer()
                Button("扫描此文件夹") {
                    viewModel.scanSelectedSourceFolder()
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
            }
        }
        .padding(18)
        .background(glassPanel(cornerRadius: 20))
    }

    private func sourceGuideCard(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(glassPanel(cornerRadius: 16))
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("导入摘要")
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                Spacer()
                Text(viewModel.hasScannedSource ? "已扫描" : "待扫描")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((viewModel.hasScannedSource ? accentColor : secondaryTextColor).opacity(0.14), in: Capsule())
                    .foregroundStyle(viewModel.hasScannedSource ? accentColor : secondaryTextColor)
            }

            let selectedItems = viewModel.selectedItems
            let totalBytes = viewModel.selectedTotalBytes

            VStack(alignment: .leading, spacing: 8) {
                Text("\(selectedItems.count) 个文件")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(primaryTextColor)
                Text("待拷贝总量 \(byteText(totalBytes))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Group {
                summaryRow("扫描目录", value: viewModel.sourceFolderURL?.path ?? volume.url.path)
                summaryRow("扫描类型", value: viewModel.selectedScanFilter.title)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("项目名称")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                Picker("项目名称", selection: $viewModel.projectNameMode) {
                    ForEach(ProjectNameMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if viewModel.projectNameMode == .custom {
                    TextField("例如 A_CAM_Day01_Card03", text: $viewModel.draftProjectName)
                        .textFieldStyle(.roundedBorder)
                }
                Text("当前名称：\(viewModel.projectNamePreview)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
            }
            .padding(12)
            .background(glassPanel(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 10) {
                Text("校验方式")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                Picker("校验方式", selection: $viewModel.selectedVerificationMode) {
                    ForEach(VerificationMode.selectableCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                Text(viewModel.selectedVerificationMode.detail)
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(glassPanel(cornerRadius: 16))

            destinationSummaryCard(
                title: "主目标盘",
                path: viewModel.preferences.targetPath ?? "-",
                capacity: viewModel.targetCapacity,
                tint: accentColor
            )

            if viewModel.preferences.backupEnabled {
                destinationSummaryCard(
                    title: "备份盘",
                    path: viewModel.preferences.backupPath ?? "未设置",
                    capacity: viewModel.backupCapacity,
                    tint: secondaryAccentColor
                )
            }

            ForEach(viewModel.destinationWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(startDisabledReason)
                .font(.caption.weight(.semibold))
                .foregroundStyle(viewModel.canStartImport && viewModel.hasScannedSource ? accentColor : secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)

            Button("创建项目并加入队列") {
                viewModel.startImport()
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(!viewModel.canStartImport || !viewModel.hasScannedSource)
        }
        .padding(18)
        .background(glassPanel(cornerRadius: 24))
    }

    private func destinationSummaryCard(
        title: String,
        path: String,
        capacity: StorageCapacitySnapshot?,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            Text(path)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(primaryTextColor)
                .lineLimit(2)
                .textSelection(.enabled)
            Text(capacity?.capacityLine ?? "容量暂不可读")
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            CapacityMeter(
                totalCapacity: capacity?.totalCapacity,
                availableCapacity: capacity?.availableCapacity,
                tint: tint,
                backgroundColor: secondaryTextColor.opacity(0.16)
            )
        }
        .padding(12)
        .background(
            AirwangGlassSurface(
                cornerRadius: 16,
                theme: viewModel.selectedTheme,
                tint: tint,
                tintStrength: 0.35,
                elevation: .tile,
                reduceEffects: false
            )
        )
    }

    private var startDisabledReason: String {
        if !viewModel.hasScannedSource {
            return "请先扫描源文件夹。"
        }
        if viewModel.selectedItems.isEmpty {
            return "请至少选择一个素材文件。"
        }
        if let warning = viewModel.destinationWarnings.first {
            return warning
        }
        return "准备就绪：开始后会创建项目，先主盘拷贝与校验，再按需从主盘串行备份。"
    }

    private func isGroupSelected(_ group: TimeGroup) -> Bool {
        Set(group.items.map(\.id)).isSubset(of: viewModel.selectedItemIDs)
    }

    private func selectionRow(item: MediaItem) -> some View {
        let isSelected = viewModel.selectedItemIDs.contains(item.id)

        return HStack {
            Button {
                viewModel.toggle(item: item)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? accentColor : secondaryTextColor)
            }
            .buttonStyle(.plain)
            ThumbnailView(url: item.fileURL)
                .frame(width: 54, height: 40)
                .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.16, elevation: .tile)
            VStack(alignment: .leading) {
                Text(item.displayName)
                    .foregroundStyle(primaryTextColor)
                Text(item.relativePath)
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }
            Spacer()
            Text(byteText(item.size))
                .foregroundStyle(secondaryTextColor)
        }
        .padding(8)
        .background(isSelected ? accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(secondaryTextColor)
            Text(value)
                .foregroundStyle(primaryTextColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private func byteText(_ value: Int64) -> String {
        ByteDisplayFormatter.string(fromByteCount: value)
    }

    private var importSheetBackground: some View {
        Group {
            if viewModel.selectedTheme == .night {
                LinearGradient(
                    colors: [
                        Color(red: 0.025, green: 0.028, blue: 0.042),
                        Color(red: 0.070, green: 0.036, blue: 0.070),
                        Color(red: 0.110, green: 0.052, blue: 0.080),
                        Color(red: 0.035, green: 0.045, blue: 0.068)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.96),
                        Color(red: 0.995, green: 0.925, blue: 0.930),
                        Color(red: 0.970, green: 0.860, blue: 0.895),
                        Color(red: 0.940, green: 0.835, blue: 0.920)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private func glassPanel(cornerRadius: CGFloat) -> some View {
        AirwangGlassSurface(
            cornerRadius: cornerRadius,
            theme: viewModel.selectedTheme,
            tint: accentColor,
            tintStrength: 0.22,
            elevation: .card,
            reduceEffects: false
        )
    }

    // 颜色委托给 `AppTheme` 扩展,与主面板保持一致(原本 ImportSheet 在白天模式
    // 走 `Color.primary` / `Color.secondary`,与暖色背景不协调,见 #45)。
    private var primaryTextColor: Color { viewModel.selectedTheme.primaryTextColor }
    private var secondaryTextColor: Color { viewModel.selectedTheme.secondaryTextColor }
    private var accentColor: Color { viewModel.selectedTheme.accentColor }
    private var secondaryAccentColor: Color { viewModel.selectedTheme.secondaryAccentColor }

    private var groupFill: Color {
        viewModel.selectedTheme == .night ? Color.white.opacity(0.08) : Color.gray.opacity(0.08)
    }

    private var thumbFill: Color {
        viewModel.selectedTheme == .night ? Color.white.opacity(0.06) : Color.black.opacity(0.08)
    }

    private var canGoUp: Bool {
        guard let sourceFolderURL = viewModel.sourceFolderURL else { return false }
        return sourceFolderURL.path != volume.url.path && sourceFolderURL.path != sourceFolderURL.deletingLastPathComponent().path
    }
}

private struct FolderPickerSheet: View {
    let purpose: FolderPickerPurpose
    @EnvironmentObject private var viewModel: AppViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    viewModel.closeFolderPicker()
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                VStack(alignment: .leading, spacing: 4) {
                    Text(purpose.title)
                        .font(.title2.weight(.semibold))
                    Text("在软件内浏览目录，并直接查看目标位置的可用容量。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider()

            HStack(spacing: 0) {
                rootSidebar
                Divider()
                folderBrowser
                Divider()
                selectionInspector
            }
        }
        .frame(minWidth: 980, idealWidth: 1160, maxWidth: .infinity, minHeight: 640, idealHeight: 740, maxHeight: .infinity)
        .background(
            Group {
                if viewModel.selectedTheme == .night {
                    LinearGradient(
                        colors: [
                            Color(red: 0.025, green: 0.028, blue: 0.042),
                            Color(red: 0.070, green: 0.036, blue: 0.070),
                            Color(red: 0.110, green: 0.052, blue: 0.080),
                            Color(red: 0.035, green: 0.045, blue: 0.068)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            Color(red: 0.995, green: 0.925, blue: 0.930),
                            Color(red: 0.970, green: 0.860, blue: 0.895),
                            Color(red: 0.940, green: 0.835, blue: 0.920)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        )
        .background(ResizableSheetWindowConfigurator(minSize: NSSize(width: 980, height: 640), idealSize: NSSize(width: 1160, height: 740)))
        .fontDesign(.serif)
        .preferredColorScheme(viewModel.selectedTheme == .night ? .dark : .light)
    }

    private var rootSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("位置")
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.folderRoots) { item in
                        Button {
                            viewModel.navigate(to: item.url)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: sidebarIcon(for: item.url))
                                    .foregroundStyle(themeAccentColor)
                                    .frame(width: 20)
                                    .airwangSoftShadow(theme: viewModel.selectedTheme, tint: themeAccentColor, tintStrength: 0.20, elevation: .tile)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .font(.headline)
                                        .foregroundStyle(themePrimaryTextColor)
                                    Text(item.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(themeSecondaryTextColor)
                                        .lineLimit(1)
                                    Text(item.capacityLine)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(themeSecondaryTextColor)
                                    CapacityMeter(
                                        totalCapacity: item.totalCapacity,
                                        availableCapacity: item.availableCapacity,
                                        tint: themeAccentColor,
                                        backgroundColor: themeSecondaryTextColor.opacity(0.16)
                                    )
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(themeGlassPanel(cornerRadius: 14, tint: isCurrent(item.url) ? themeAccentColor : nil))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 260, alignment: .topLeading)
    }

    private var folderBrowser: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    viewModel.navigateUp()
                } label: {
                    Label("上一级", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .tint(themeAccentColor)
                .disabled(!canGoUp)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentFolderURL?.lastPathComponent.isEmpty == false ? (viewModel.currentFolderURL?.lastPathComponent ?? "目录") : "目录")
                        .font(.headline)
                        .foregroundStyle(themePrimaryTextColor)
                    Text(viewModel.currentFolderURL?.path ?? "")
                        .font(.caption)
                        .foregroundStyle(themeSecondaryTextColor)
                }
                Spacer()
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    if viewModel.isLoadingFolderChildren {
                        ProgressView("正在读取文件夹...")
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    }

                    ForEach(viewModel.folderChildren) { item in
                        HStack(spacing: 12) {
                            Button {
                                viewModel.selectFolder(item.url)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(.orange)
                                        .airwangSoftShadow(theme: viewModel.selectedTheme, tint: .orange, tintStrength: 0.20, elevation: .tile)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                            .font(.headline)
                                            .foregroundStyle(themePrimaryTextColor)
                                        Text(item.subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(themeSecondaryTextColor)
                                            .lineLimit(1)
                                        Text(item.capacityLine)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(themeSecondaryTextColor)
                                        CapacityMeter(
                                            totalCapacity: item.totalCapacity,
                                            availableCapacity: item.availableCapacity,
                                            tint: themeAccentColor,
                                            backgroundColor: themeSecondaryTextColor.opacity(0.16)
                                        )
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)

                            Button("进入") {
                                viewModel.navigate(to: item.url)
                            }
                            .buttonStyle(.bordered)
                            .tint(themeAccentColor)
                        }
                        .padding(12)
                        .background(themeGlassPanel(cornerRadius: 16, tint: isSelected(item.url) ? themeAccentColor : nil))
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var selectionInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Text("已选目录")
                        .font(.headline)
                        .foregroundStyle(themePrimaryTextColor)

                    if let selection = viewModel.folderSelection {
                        inspectorCard(title: "目标路径", value: selection.subtitle)
                        inspectorCard(title: "目录名称", value: selection.name)
                        inspectorCard(title: "剩余容量", value: selection.availableCapacity.map(byteText) ?? "-")
                        inspectorCard(title: "总容量", value: selection.totalCapacity.map(byteText) ?? "-")
                        CapacityMeter(
                            totalCapacity: selection.totalCapacity,
                            availableCapacity: selection.availableCapacity,
                            tint: themeAccentColor,
                            backgroundColor: themeSecondaryTextColor.opacity(0.16)
                        )
                        Text("容量读取使用系统文件系统属性，并在不可读时自动回退，避免外置盘剩余空间显示错误。")
                            .font(.caption)
                            .foregroundStyle(themeSecondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("请选择一个目录")
                            .foregroundStyle(themeSecondaryTextColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Button(purpose.confirmTitle) {
                viewModel.confirmFolderSelection()
            }
            .buttonStyle(.borderedProminent)
            .tint(themeAccentColor)
            .disabled(viewModel.selectedFolderURL == nil)
        }
        .padding(20)
        .frame(width: 280, alignment: .topLeading)
    }

    private func inspectorCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(themeSecondaryTextColor)
            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(themePrimaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(themeGlassPanel(cornerRadius: 16))
    }

    private func sidebarIcon(for url: URL) -> String {
        Self.sidebarSpecialPaths[url.standardizedFileURL.path] ?? "externaldrive.fill"
    }

    private static let sidebarSpecialPaths: [String: String] = {
        let fileManager = FileManager.default
        let homePath = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        var paths: [String: String] = [homePath: "house.fill"]

        if let desktopPath = userDirectoryPath(.desktopDirectory) {
            paths[desktopPath] = "desktopcomputer"
        }
        if let moviesPath = userDirectoryPath(.moviesDirectory) {
            paths[moviesPath] = "film.fill"
        }
        if let documentsPath = userDirectoryPath(.documentDirectory) {
            paths[documentsPath] = "doc.text.fill"
        }

        return paths
    }()

    private static func userDirectoryPath(_ directory: FileManager.SearchPathDirectory) -> String? {
        FileManager.default.urls(for: directory, in: .userDomainMask).first?.standardizedFileURL.path
    }

    private func byteText(_ value: Int64) -> String {
        ByteDisplayFormatter.string(fromByteCount: value)
    }

    private func isCurrent(_ url: URL) -> Bool {
        viewModel.currentFolderURL?.path == url.path
    }

    private func isSelected(_ url: URL) -> Bool {
        viewModel.selectedFolderURL?.path == url.path
    }

    private var canGoUp: Bool {
        guard let current = viewModel.currentFolderURL else { return false }
        return current.path != current.deletingLastPathComponent().path
    }

    private func themeGlassPanel(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        AirwangGlassSurface(
            cornerRadius: cornerRadius,
            theme: viewModel.selectedTheme,
            tint: tint ?? themeAccentColor,
            tintStrength: tint == nil ? 0.0 : 0.32,
            elevation: .tile,
            reduceEffects: false
        )
    }

    // 颜色委托给 `AppTheme` 扩展,与主面板和 ImportSheet 保持一致(见 #46)。
    private var themePrimaryTextColor: Color { viewModel.selectedTheme.primaryTextColor }
    private var themeSecondaryTextColor: Color { viewModel.selectedTheme.secondaryTextColor }
    private var themeAccentColor: Color { viewModel.selectedTheme.accentColor }

}

private struct CapacityMeter: View {
    let totalCapacity: Int64?
    let availableCapacity: Int64?
    let tint: Color
    let backgroundColor: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(backgroundColor)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.55)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * usedFraction)
            }
        }
        .frame(height: 6)
        .opacity(totalCapacity == nil || availableCapacity == nil ? 0.42 : 1)
    }

    private var usedFraction: CGFloat {
        guard let totalCapacity, totalCapacity > 0, let availableCapacity else { return 0 }
        let used = 1 - (Double(availableCapacity) / Double(totalCapacity))
        return CGFloat(min(max(used, 0), 1))
    }
}

private struct ResizableSheetWindowConfigurator: NSViewRepresentable {
    let minSize: NSSize
    let idealSize: NSSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.postsFrameChangedNotifications = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window, coordinator: context.coordinator)
        }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }

        window.styleMask.insert(.resizable)
        window.minSize = minSize
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        guard !coordinator.didSetInitialSize else { return }
        coordinator.didSetInitialSize = true

        let currentSize = window.contentLayoutRect.size
        let targetSize = NSSize(
            width: max(currentSize.width, idealSize.width),
            height: max(currentSize.height, idealSize.height)
        )
        window.setContentSize(targetSize)
    }

    final class Coordinator {
        var didSetInitialSize = false
    }
}

private struct ThumbnailView: View {
    let url: URL
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            }
        }
        .task(id: "\(url.path)-\(viewModel.isImporting)") {
            guard !viewModel.isImporting else {
                image = nil
                return
            }
            image = await ThumbnailCache.shared.image(for: url)
        }
    }
}

@MainActor
private final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var activeRequests = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let maxConcurrentRequests = 4

    func image(for url: URL) async -> NSImage? {
        let key = url.path as NSString
        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }
        if let task = inFlight[url.path] {
            return await task.value
        }

        let task = Task { @MainActor in
            await acquireSlot()
            defer { releaseSlot() }
            return await Self.generateThumbnail(for: url)
        }
        inFlight[url.path] = task

        let generatedImage = await task.value
        if let generatedImage {
            cache.setObject(generatedImage, forKey: key)
        }
        inFlight[url.path] = nil
        return generatedImage
    }

    private func acquireSlot() async {
        if activeRequests < maxConcurrentRequests {
            activeRequests += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        activeRequests += 1
    }

    private func releaseSlot() {
        activeRequests = max(activeRequests - 1, 0)
        guard !waiters.isEmpty else { return }
        let continuation = waiters.removeFirst()
        continuation.resume()
    }

    private static func generateThumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 320, height: 180),
            scale: 2,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
                if let thumbnail {
                    continuation.resume(returning: thumbnail.nsImage)
                } else if error != nil {
                    continuation.resume(returning: NSWorkspace.shared.icon(forFile: url.path))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private extension Text {
    func sectionTitle() -> some View {
        self.font(.title3.weight(.semibold))
    }
}
