import AppKit
import SwiftUI

/// 统计工作区:概览、规整统计、洞察与活跃热力图。
extension ContentView {
    @ViewBuilder
    func statisticsWorkspace(availableWidth: CGFloat) -> some View {
        let summary = viewModel.copyStatistics
        let stackedInsights = availableWidth < 900
        let insightsWidth = min(500, max(360, availableWidth * 0.46))

        VStack(spacing: 16) {
            statisticsProfileCard(summary, availableWidth: availableWidth)
            activityHeatmapCard(summary, availableWidth: availableWidth)
            organizerStatisticsCard(viewModel.organizerStatistics, availableWidth: availableWidth)

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
        .transition(responsiveLayoutTransition)
        .animation(stableLayoutAnimation, value: stackedInsights)
        .accessibilityIdentifier("statistics-workspace")
    }

    func statisticsProfileCard(_ summary: CopyStatisticsSummary, availableWidth: CGFloat) -> some View {
        let compact = availableWidth < 800
        let statColumns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12), count: StatisticsLayoutPolicy.metricColumnCount(availableWidth: availableWidth))

        return VStack(spacing: 0) {
            LazyVGrid(columns: statColumns, spacing: 16) {
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
        .animation(stableLayoutAnimation, value: compact)
        .accessibilityIdentifier("statistics-profile-card")
    }

    func profileStatBlock(value: String, label: String, compact: Bool) -> some View {
        VStack(spacing: compact ? 3 : 5) {
            Text(value)
                .font(.system(size: compact ? 20 : 24, weight: .semibold, design: .serif).monospacedDigit())
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(label)
                .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .serif))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, minHeight: compact ? 56 : 64)
    }

    func organizerStatisticsCard(_ snapshot: OrganizerStatisticsSnapshot, availableWidth: CGFloat) -> some View {
        let compact = availableWidth < 760
        let columns = Array(
            repeating: GridItem(.flexible(minimum: compact ? 118 : 132), spacing: 10),
            count: compact ? 2 : 4
        )

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("规整数据")
                    .sectionTitle()
                Spacer()
                Text(viewModel.organizerOperationMode.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }

            if snapshot.hasAnyData {
                LazyVGrid(columns: columns, spacing: 10) {
                    organizerStatisticMetric(
                        value: "\(snapshot.plannedFiles)",
                        label: "预览文件",
                        systemImage: "doc.text.magnifyingglass",
                        tint: accentColor
                    )
                    organizerStatisticMetric(
                        value: "\(snapshot.executableFiles)",
                        label: "可执行",
                        systemImage: "play.circle",
                        tint: .mint
                    )
                    organizerStatisticMetric(
                        value: "\(snapshot.dayCount)/\(snapshot.deviceCount)",
                        label: "日期/设备",
                        systemImage: "calendar.badge.clock",
                        tint: secondaryAccentColor
                    )
                    organizerStatisticMetric(
                        value: ByteDisplayFormatter.string(fromByteCount: snapshot.plannedBytes),
                        label: "预计容量",
                        systemImage: "internaldrive",
                        tint: accentColor
                    )
                }

                if snapshot.previewSkippedFiles > 0 || snapshot.renamedFiles > 0 || snapshot.duplicateFiles > 0 {
                    HStack(spacing: 10) {
                        organizerStatisticsPill(title: "查重", value: snapshot.duplicateFiles, tint: .mint)
                        organizerStatisticsPill(title: "改名", value: snapshot.renamedFiles, tint: .orange)
                        organizerStatisticsPill(title: "预览跳过", value: snapshot.previewSkippedFiles, tint: .red)
                    }
                }

                if snapshot.hasLastRunData {
                    Divider().opacity(0.22)
                    organizerStatisticsLastRun(snapshot)
                }
            } else {
                emptyState(
                    title: "暂无规整数据",
                    detail: "在规整页生成预览或完成一次规整后，这里会显示文件数、日期设备分布、容量和上次执行结果。"
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 22)
        .padding(.vertical, 20)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
        .accessibilityIdentifier("statistics-organizer-card")
    }

    func organizerStatisticMetric(value: String, label: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 24, height: 24)
                    .background(tint.opacity(0.10), in: Circle())
                Spacer(minLength: 0)
            }
            Text(value)
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(14)
        .background(glassSurface(cornerRadius: 18, tint: tint, elevation: .tile))
    }

    func organizerStatisticsPill(title: String, value: Int, tint: Color) -> some View {
        Text("\(title) \(value)")
            .font(.caption.monospacedDigit().weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12), in: Capsule())
    }

    func organizerStatisticsLastRun(_ snapshot: OrganizerStatisticsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("上次规整")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                Spacer()
                Text(snapshot.lastOperationMode?.title ?? "规整")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(secondaryTextColor)
            }

            HStack(spacing: 10) {
                organizerStatisticsPill(title: "完成", value: snapshot.lastCompletedFiles, tint: .mint)
                organizerStatisticsPill(title: "跳过", value: snapshot.lastSkippedFiles, tint: .orange)
                organizerStatisticsPill(title: "失败", value: snapshot.lastFailedFiles, tint: .red)
            }

            Text("\(ByteDisplayFormatter.string(fromByteCount: snapshot.lastBytes)) · \(stopwatchText(snapshot.lastDuration)) · \(snapshot.lastTotalFiles) 个文件")
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
    }

    func activityInsightsCard(_ summary: CopyStatisticsSummary) -> some View {
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
        .accessibilityIdentifier("statistics-activity-insights-card")
    }

    func commonStatisticsCard(_ summary: CopyStatisticsSummary) -> some View {
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
        .accessibilityIdentifier("statistics-common-card")
    }

    func insightRow(_ title: String, value: String) -> some View {
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
                .minimumScaleFactor(0.75)
                .help(value)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .frame(height: 24)
    }

    func countListRow(title: String, count: Int, systemImage: String) -> some View {
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
                .minimumScaleFactor(0.75)
                .frame(minWidth: 72, alignment: .trailing)
        }
        .frame(height: 28)
    }

    func percentText(numerator: Int, denominator: Int) -> String {
        guard denominator > 0 else { return "0%" }
        return "\(Int((Double(numerator) / Double(denominator) * 100).rounded()))%"
    }

    func activityHeatmapCard(_ summary: CopyStatisticsSummary, availableWidth: CGFloat) -> some View {
        // .equatable() + 卡片的窄值输入：拷贝进度等无关的 @Published 发布
        // 不再重跑热力图 body（性能账本 #7 的针对性落地）。
        StatisticsActivityHeatmapCard(
            summary: summary,
            heatmaps: viewModel.copyStatisticsHeatmaps,
            availableWidth: availableWidth,
            theme: viewModel.selectedTheme,
            language: viewModel.selectedLanguage,
            stableLayoutAnimation: stableLayoutAnimation,
            controlAnimation: controlAnimation,
            reduceMotionEffects: reduceMotionEffects,
            reduceGlassEffects: reduceGlassEffects,
            isRefreshing: viewModel.isRefreshingStatistics,
            onRefresh: viewModel.refreshCopyStatistics
        )
        .equatable()
    }

    var statisticsRecentReportsCard: some View {
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
        .accessibilityIdentifier("statistics-recent-reports-card")
    }

    func recentStatisticsReportRow(_ report: TransferReport) -> some View {
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
}

/// GitHub 式活动热力图卡片。
///
/// 性能设计（统计页此前最卡的部分）：
/// 1. 整个网格 + 月份标签用单个 `Canvas` 一次绘制。此前 53 周 × 7 天要生成
///    700+ 个带 overlay/scaleEffect/animation 的独立视图，每次 hover 移动都要
///    对全部格子重新 diff；Canvas 把它压成一次纯绘制调用。
/// 2. 卡片不再观察整个 `AppViewModel`，改为窄值输入并实现 `Equatable`，配合
///    调用点的 `.equatable()`：拷贝进行中的进度发布不再重跑热力图 body。
/// 3. hover 命中沿用坐标数学计算，高亮只触发一次 Canvas 重绘，不做树级动画。
private struct StatisticsActivityHeatmapCard: View, Equatable {
    let summary: CopyStatisticsSummary
    let heatmaps: CopyStatisticsHeatmaps
    let availableWidth: CGFloat
    let theme: AppTheme
    let language: AppLanguage
    let stableLayoutAnimation: Animation?
    let controlAnimation: Animation?
    let reduceMotionEffects: Bool
    let reduceGlassEffects: Bool
    let isRefreshing: Bool
    let onRefresh: () -> Void

    @State private var selectedActivityMode: StatisticsActivityMode = .daily
    @State private var hoveredActivityDay: CopyActivityDay?

    /// 闭包与 Animation 不参与比较：onRefresh 语义恒定；动画参数只在窗口缩放
    /// 期间变化，而那时 availableWidth 必然同步变化并触发重新渲染。
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.summary == rhs.summary
            && lhs.heatmaps == rhs.heatmaps
            && lhs.availableWidth == rhs.availableWidth
            && lhs.theme == rhs.theme
            && lhs.language == rhs.language
            && lhs.reduceMotionEffects == rhs.reduceMotionEffects
            && lhs.reduceGlassEffects == rhs.reduceGlassEffects
            && lhs.isRefreshing == rhs.isRefreshing
    }

    var body: some View {
        let heatmap = heatmaps.heatmap(for: selectedActivityMode)
        let narrowLayout = availableWidth < 900
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
                Text(localized("完成一次拷贝后，这里会显示每日写入热力图、最近数据量和报告数量。"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: 320, alignment: .topLeading)
        .padding(narrowLayout ? 18 : 30)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
        .animation(controlAnimation, value: selectedActivityMode)
        .animation(stableLayoutAnimation, value: narrowLayout)
        .accessibilityIdentifier("statistics-activity-heatmap-card")
        .onChange(of: heatmaps) { _, _ in hoveredActivityDay = nil }
    }

    private var heatmapTitleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(localized("拷贝活动"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(primaryTextColor)
            Text(localized("颜色越深，当天写入量越大。统计来自 App 本地任务报告，主盘与备份阶段都会计入写入总量。"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statisticsRefreshButton: some View {
        Button(action: onRefresh) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(primaryTextColor)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.white.opacity(theme == .night ? 0.10 : 0.26))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(theme == .night ? 0.14 : 0.42), lineWidth: 0.7)
                )
        }
        .buttonStyle(.plain)
        .disabled(isRefreshing)
        .overlay {
            if isRefreshing {
                ProgressView().controlSize(.small)
                    .frame(width: 30, height: 30)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
            }
        }
        .help(isRefreshing ? (language == .english ? "Updating statistics…" : "正在更新统计…") : localized("刷新统计"))
        .accessibilityLabel(Text(localized("刷新统计")))
        .accessibilityIdentifier("statistics-refresh-button")
    }

    private var activityModePicker: some View {
        Picker(localized("拷贝活动"), selection: $selectedActivityMode) {
            ForEach(StatisticsActivityMode.allCases) { mode in
                Text(localized(mode.title)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 186)
        .accessibilityIdentifier("statistics-activity-mode-picker")
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
                    Text(language == .english ? "No data yet" : "暂无数据")
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
        .frame(height: 62, alignment: .top)
        .accessibilityIdentifier("statistics-heatmap-focus-summary")
    }

    private var heatmapFallbackLabel: String {
        switch selectedActivityMode {
        case .daily:
            return localized("峰值日")
        case .weekly:
            return language == .english ? "Peak Week" : "峰值周"
        case .cumulative:
            return localized("累计")
        }
    }

    private var heatmapFocusedLabel: String {
        switch selectedActivityMode {
        case .daily:
            return language == .english ? "Selected Day" : "选中日期"
        case .weekly:
            return language == .english ? "Selected Week" : "选中周"
        case .cumulative:
            return language == .english ? "Cumulative To Date" : "截至当天"
        }
    }

    /// 网格 + 月份标签的单 Canvas 绘制。所有颜色在进入绘制闭包前解析好，
    /// 闭包里只剩纯路径填充。
    private func heatmapGrid(heatmap: CopyStatisticsHeatmap, availableWidth: CGFloat) -> some View {
        let cellSize = heatmapCellSize(availableWidth: availableWidth, weekCount: heatmap.weeks.count)
        let cellGap = heatmapCellGap(availableWidth: availableWidth)
        let strideLength = cellSize + cellGap
        let columnCount = max(heatmap.weeks.count, 1)
        let gridWidth = CGFloat(columnCount) * strideLength - cellGap
        let gridHeight = 7 * strideLength - cellGap
        let labelBandHeight: CGFloat = 16
        let todayStart = Calendar.current.startOfDay(for: Date())
        let levelColors = (0...8).map { heatmapColor(level: $0) }
        let monthLabels = monthLabels(for: heatmap.weeks)
        let hoveredID = hoveredActivityDay?.id
        let labelColor = secondaryTextColor
        let hoverStroke = primaryTextColor.opacity(0.72)
        let todayStroke = primaryTextColor.opacity(0.38)

        return Canvas { context, _ in
            for (columnIndex, week) in heatmap.weeks.enumerated() {
                let x = CGFloat(columnIndex) * strideLength
                for (rowIndex, day) in week.enumerated() {
                    guard let day else { continue }
                    let isHovered = day.id == hoveredID
                    var rect = CGRect(
                        x: x,
                        y: CGFloat(rowIndex) * strideLength,
                        width: cellSize,
                        height: cellSize
                    )
                    if isHovered {
                        rect = rect.insetBy(dx: -cellSize * 0.05, dy: -cellSize * 0.05)
                    }
                    let path = Path(roundedRect: rect, cornerRadius: 3, style: .continuous)
                    context.fill(
                        path,
                        with: .color(levelColors[heatmapLevel(bytes: day.bytes, maxBytes: heatmap.maxBytes)])
                    )
                    if isHovered {
                        context.stroke(path, with: .color(hoverStroke), lineWidth: 1.4)
                    } else if day.date == todayStart {
                        context.stroke(path, with: .color(todayStroke), lineWidth: 1)
                    }
                }
            }

            let labelY = gridHeight + 4
            for label in monthLabels {
                context.draw(
                    Text(label.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(labelColor),
                    at: CGPoint(x: CGFloat(label.weekIndex) * strideLength, y: labelY),
                    anchor: .topLeading
                )
            }
        }
        .frame(width: gridWidth, height: gridHeight + labelBandHeight + 4)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                let day = heatmapDay(at: CGPoint(x: point.x, y: point.y - 3), in: heatmap, cellSize: cellSize, cellGap: cellGap)
                if hoveredActivityDay?.id != day?.id { hoveredActivityDay = day }
            case .ended:
                if hoveredActivityDay != nil {
                    hoveredActivityDay = nil
                }
            }
        }
        .accessibilityLabel(Text(language == .english ? "Copy activity heatmap" : "拷贝活动热力图"))
        .accessibilityValue(Text("\(heatmap.days.count) " + (language == .english ? "days" : "天")))
        .accessibilityIdentifier("statistics-heatmap-grid")
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
                Text(localized("等效容量") + ": " + equivalentStorageText(summary.totalBytes))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        } else {
            HStack(spacing: 8) {
                heatmapLegendScale
                Spacer()
                Text(localized("等效容量") + ": " + equivalentStorageText(summary.totalBytes))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
    }

    private var heatmapLegendScale: some View {
        HStack(spacing: 8) {
            Text(language == .english ? "Less" : "少")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            ForEach(0..<9, id: \.self) { level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(heatmapColor(level: level))
                    .frame(width: 16, height: 16)
            }
            Text(language == .english ? "More" : "多")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
        }
    }

    private func heatmapDay(at point: CGPoint, in heatmap: CopyStatisticsHeatmap, cellSize: CGFloat, cellGap: CGFloat) -> CopyActivityDay? {
        let stride = cellSize + cellGap
        guard stride > 0, point.x >= 0, point.y >= 0 else { return nil }

        let column = Int(point.x / stride)
        let row = Int(point.y / stride)
        guard column >= 0, column < heatmap.weeks.count, row >= 0, row < 7 else { return nil }
        guard point.x - CGFloat(column) * stride <= cellSize,
              point.y - CGFloat(row) * stride <= cellSize else { return nil }

        let week = heatmap.weeks[column]
        guard row < week.count else { return nil }
        return week[row]
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

    private static let heatmapBaseColor = Color(red: 0.23, green: 0.57, blue: 1.00)
    private static let nightLevelOpacity: [Double] = [0.18, 0.28, 0.38, 0.48, 0.60, 0.72, 0.84, 0.92, 1.00]
    private static let dayLevelOpacity: [Double] = [0.12, 0.20, 0.30, 0.40, 0.52, 0.64, 0.76, 0.86, 0.96]

    private func heatmapColor(level: Int) -> Color {
        let index = min(max(level, 0), 8)
        switch level {
        case 0:
            return secondaryTextColor.opacity(theme == .night ? 0.18 : 0.12)
        default:
            return Self.heatmapBaseColor.opacity(theme == .night ? Self.nightLevelOpacity[index] : Self.dayLevelOpacity[index])
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
        if language == .english {
            return ["S", "M", "T", "W", "T", "F", "S"][index]
        }
        return ["日", "一", "二", "三", "四", "五", "六"][index]
    }

    /// 预计算月份标签：仅在月份切换的那一周输出一个标签。
    private func monthLabels(for weeks: [[CopyActivityDay?]]) -> [(weekIndex: Int, title: String)] {
        var labels: [(weekIndex: Int, title: String)] = []
        var previousMonth = -1
        let calendar = Calendar.current
        for (index, week) in weeks.enumerated() {
            guard let firstDate = week.compactMap({ $0?.date }).first else { continue }
            let month = calendar.component(.month, from: firstDate)
            guard month != previousMonth else { continue }
            previousMonth = month
            labels.append((weekIndex: index, title: monthLabelTitle(month: month, date: firstDate)))
        }
        return labels
    }

    private func monthLabelTitle(month: Int, date: Date) -> String {
        if language == .english {
            return CachedDateFormatters
                .formatter(localeIdentifier: language.localeIdentifier, template: "MMM")
                .string(from: date)
        }
        return "\(month)月"
    }

    private func heatmapDayDetailText(_ day: CopyActivityDay) -> String {
        if language == .english {
            return "\(day.reportCount) reports · \(day.files) files"
        }
        return "\(day.reportCount) 份报告 · \(day.files) 个文件"
    }

    private func equivalentStorageText(_ bytes: Int64) -> String {
        guard bytes > 0 else {
            return language == .english ? "No data yet" : "暂无数据"
        }
        let cardBytes = Double(128_000_000_000)
        let cardCount = Double(bytes) / cardBytes
        let formattedCount = cardCount >= 10
            ? String(format: "%.0f", cardCount)
            : String(format: "%.1f", max(cardCount, 0.1))
        if language == .english {
            return "About \(formattedCount) x 128GB cards"
        }
        return "约 \(formattedCount) 张 128GB 卡"
    }

    private func shortDateText(_ date: Date) -> String {
        let isEnglish = language == .english
        return CachedDateFormatters
            .formatter(localeIdentifier: language.localeIdentifier,
                       template: isEnglish ? "MMM d" : nil,
                       fixedFormat: isEnglish ? nil : "M月d日")
            .string(from: date)
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: language)
    }

    private func glassSurface(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        elevation: AirwangGlassElevation = .panel
    ) -> some View {
        AirwangGlassSurface(
            cornerRadius: cornerRadius,
            theme: theme,
            tint: tint ?? accentColor,
            tintStrength: tint == nil ? 0.0 : 1.0,
            elevation: elevation,
            reduceEffects: reduceGlassEffects
        )
    }

    private var primaryTextColor: Color { theme.primaryTextColor }
    private var secondaryTextColor: Color { theme.secondaryTextColor }
    private var accentColor: Color { theme.accentColor }
}
