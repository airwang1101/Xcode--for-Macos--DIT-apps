import AppKit
import SwiftUI

/// 规整(Organizer)工作区:源/目标选择、预览计划与执行进度。
extension ContentView {
    @ViewBuilder
    func organizeWorkspace(availableWidth: CGFloat) -> some View {
        let stacked = availableWidth < 1040
        let sideWidth = min(420, max(360, availableWidth * 0.34))

        Group {
            if stacked {
                VStack(spacing: 16) {
                    organizerSetupCard
                    organizerProgressCard
                    organizerPreviewCard
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        organizerSetupCard
                        organizerProgressCard
                    }
                    .frame(width: sideWidth, alignment: .top)

                    organizerPreviewCard
                        .frame(maxWidth: .infinity, minHeight: 520, alignment: .top)
                }
            }
        }
        .transition(responsiveLayoutTransition)
        .animation(stableLayoutAnimation, value: stacked)
    }

    var organizerSetupCard: some View {
        let warnings = viewModel.organizerWarnings

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("规整工作台")
                    .sectionTitle()
                Text("规则结构：年 / 月 / 日 / 设备，例如 2020 / 6 / 20 / a7m3。")
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                organizerPathCard(
                    title: "待规整文件夹",
                    url: viewModel.organizerSourceURL,
                    placeholder: "选择一个混乱素材文件夹",
                    systemImage: "folder"
                ) {
                    viewModel.openFolderPicker(for: .organizerSource)
                }

                organizerPathCard(
                    title: "规整目标文件夹",
                    url: viewModel.organizerDestinationURL,
                    placeholder: "选择输出位置",
                    systemImage: "folder.badge.plus"
                ) {
                    viewModel.openFolderPicker(for: .organizerDestination)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                organizerPickerLabel("素材类型")
                Picker("素材类型", selection: Binding(
                    get: { viewModel.organizerScanFilter },
                    set: { viewModel.setOrganizerScanFilter($0) }
                )) {
                    ForEach(ScanFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 10) {
                organizerPickerLabel("执行方式")
                Picker("执行方式", selection: Binding(
                    get: { viewModel.organizerOperationMode },
                    set: { viewModel.setOrganizerOperationMode($0) }
                )) {
                    ForEach(OrganizerOperationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Text(viewModel.organizerOperationMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                organizerPickerLabel("同名处理")
                Picker("同名处理", selection: Binding(
                    get: { viewModel.organizerDuplicatePolicy },
                    set: { viewModel.setOrganizerDuplicatePolicy($0) }
                )) {
                    ForEach(OrganizerDuplicatePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .pickerStyle(.segmented)
                Text(viewModel.organizerDuplicatePolicy.subtitle)
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.buildOrganizerPlan()
                } label: {
                    Label(viewModel.isBuildingOrganizerPlan ? "生成中" : "生成预览", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
                .disabled(!viewModel.organizerCanBuildPlan)

                Button {
                    if viewModel.isBuildingOrganizerPlan || viewModel.isRunningOrganizer {
                        viewModel.cancelOrganizerExecution()
                    } else {
                        viewModel.startOrganizerExecution()
                    }
                } label: {
                    Label(
                        viewModel.isBuildingOrganizerPlan || viewModel.isRunningOrganizer ? "取消" : "执行规整",
                        systemImage: viewModel.isBuildingOrganizerPlan || viewModel.isRunningOrganizer ? "xmark" : "play.fill"
                    )
                }
                .buttonStyle(.bordered)
                .tint(viewModel.isBuildingOrganizerPlan || viewModel.isRunningOrganizer ? .red : accentColor)
                .disabled(!(viewModel.isBuildingOrganizerPlan || viewModel.isRunningOrganizer) && !viewModel.organizerCanRun)
            }
        }
        .padding(22)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
    }

    var organizerProgressCard: some View {
        let state = viewModel.organizerExecutionState

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("执行状态")
                    .sectionTitle()
                Spacer()
                if viewModel.isBuildingOrganizerPlan || viewModel.isRunningOrganizer {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.organizerStatusMessage ?? "等待生成规整预览")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
                if !state.currentFile.isEmpty {
                    Text(state.currentFile)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            ProgressView(value: state.fraction)
                .tint(accentColor)

            HStack(spacing: 10) {
                organizerMetricBlock(value: "\(state.processedFiles)/\(state.totalFiles)", label: "文件")
                organizerMetricBlock(value: ByteDisplayFormatter.string(fromByteCount: state.processedBytes), label: "已处理")
                organizerMetricBlock(value: "\(state.duplicateFiles)", label: "查重跳过")
                organizerMetricBlock(value: "\(state.skippedFiles - state.duplicateFiles)", label: "其他跳过")
            }

            if let summary = viewModel.organizerLastSummary {
                Divider().opacity(0.18)
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.success ? "上次规整完成" : "上次规整有异常")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(summary.success ? .mint : .orange)
                    Text("\(summary.completedFiles) 个已处理，\(summary.skippedFiles) 个跳过（查重 \(summary.duplicateFiles)），\(ByteDisplayFormatter.string(fromByteCount: summary.totalBytes))。")
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(22)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
    }

    var organizerPreviewCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("规整预览")
                        .sectionTitle()
                    Text("同名文件先做逐字节查重：内容相同自动跳过，不同才改名或跳过。")
                        .foregroundStyle(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let plan = viewModel.organizerPlan {
                    Text("\(plan.executableFiles) / \(plan.totalFiles)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(primaryTextColor)
                }
            }

            if let plan = viewModel.organizerPlan {
                LazyVGrid(columns: [
                    GridItem(.flexible(minimum: 90), spacing: 10),
                    GridItem(.flexible(minimum: 90), spacing: 10),
                    GridItem(.flexible(minimum: 90), spacing: 10),
                    GridItem(.flexible(minimum: 90), spacing: 10),
                    GridItem(.flexible(minimum: 90), spacing: 10)
                ], spacing: 10) {
                    organizerPlanMetric(value: "\(plan.dayCount)", label: "日期")
                    organizerPlanMetric(value: "\(plan.deviceCount)", label: "设备")
                    organizerPlanMetric(value: "\(plan.duplicateFiles)", label: "内容重复")
                    organizerPlanMetric(value: "\(plan.renamedFiles)", label: "改名")
                    organizerPlanMetric(value: ByteDisplayFormatter.string(fromByteCount: plan.totalBytes), label: "容量")
                }

                organizerPreviewList(plan: plan)
            } else {
                emptyState(
                    title: "还没有规整预览",
                    detail: "选择源文件夹和目标文件夹后，先生成预览，再执行规整。"
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
        .padding(22)
        .background(glassSurface(cornerRadius: 24, elevation: .panel))
    }

    @ViewBuilder
    private func organizerPreviewList(plan: OrganizerPlan) -> some View {
        let filter = viewModel.organizerPreviewFilter
        let visibleItems = plan.previewItems(filter: filter)

        HStack(spacing: 10) {
            Picker("预览范围", selection: Binding(
                get: { viewModel.organizerPreviewFilter },
                set: { viewModel.organizerPreviewFilter = $0 }
            )) {
                ForEach(OrganizerPreviewFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 220, alignment: .leading)

            Spacer(minLength: 0)

            if filter == .conflicts {
                Text("\(plan.conflictFiles) 个冲突")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }
        }

        if visibleItems.isEmpty {
            emptyState(
                title: filter == .conflicts ? "没有冲突文件" : "预览为空",
                detail: filter == .conflicts ? "所有文件都会直接写入目标位置，无查重命中。" : "当前筛选没有可显示的文件。"
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(visibleItems) { item in
                        organizerPreviewRow(item: item, plan: plan)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(minHeight: 320, maxHeight: 560)

            let hiddenCount = (filter == .all ? plan.totalFiles : plan.conflictFiles) - visibleItems.count
            if hiddenCount > 0 {
                Text("已显示前 \(visibleItems.count) 个文件，还有 \(hiddenCount) 个未列出，执行时会处理完整预览计划。")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func organizerPickerLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.bold))
            .foregroundStyle(secondaryTextColor)
    }

    func organizerPathCard(
        title: String,
        url: URL?,
        placeholder: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        let name = url?.lastPathComponent.isEmpty == false ? url?.lastPathComponent : url?.path
        let subtitle = url?.path

        return Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(accentColor)
                    .frame(width: 30, height: 30)
                    .background(accentColor.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(secondaryTextColor)
                    Text(name ?? placeholder)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)
                    Text(subtitle ?? "点击选择")
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(secondaryTextColor)
            }
            .padding(14)
            .background(glassSurface(cornerRadius: 18, tint: url == nil ? nil : accentColor, elevation: .tile))
        }
        .buttonStyle(.plain)
    }

    func organizerMetricBlock(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(Color.white.opacity(viewModel.selectedTheme == .night ? 0.06 : 0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    func organizerPlanMetric(value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.bold))
                .foregroundStyle(primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(Color.white.opacity(viewModel.selectedTheme == .night ? 0.06 : 0.30), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    func organizerPreviewRow(item: OrganizerPlanItem, plan: OrganizerPlan) -> some View {
        let rowTint = organizerRowTint(item.conflictResolution)

        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.mediaKind.systemImageName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(rowTint)
                .frame(width: 28, height: 28)
                .background(rowTint.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    organizerConflictBadge(item.conflictResolution)
                    Spacer(minLength: 0)
                }

                Text(organizerRelativeDestination(item, plan: plan))
                    .font(.caption.monospaced())
                    .foregroundStyle(primaryTextColor.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(organizerDateText(item.capturedAt))
                    Text(item.deviceFolderName)
                    Text(ByteDisplayFormatter.string(fromByteCount: item.size))
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
                .lineLimit(1)
            }
        }
        .padding(13)
        .background(glassSurface(cornerRadius: 18, tint: item.isExecutable ? nil : rowTint, elevation: .tile))
    }

    /// 行主色按冲突类型区分：查重命中是安全信息（薄荷绿），
    /// 名字冲突跳过是需要注意的信息（橙色）。
    private func organizerRowTint(_ resolution: OrganizerConflictResolution) -> Color {
        switch resolution {
        case .none, .renamed:
            return accentColor
        case .duplicate:
            return .mint
        case .skipped:
            return .orange
        }
    }

    @ViewBuilder
    func organizerConflictBadge(_ resolution: OrganizerConflictResolution) -> some View {
        switch resolution {
        case .none:
            EmptyView()
        case .renamed:
            Text("改名")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.12), in: Capsule())
        case .skipped:
            Text("跳过")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.red)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.red.opacity(0.12), in: Capsule())
        case .duplicate:
            Text("内容重复")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.mint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.mint.opacity(0.14), in: Capsule())
        }
    }

    func organizerRelativeDestination(_ item: OrganizerPlanItem, plan: OrganizerPlan) -> String {
        (try? PathSafety.relativePath(for: item.destinationURL, under: plan.destinationURL)) ?? item.destinationURL.path
    }

    func organizerDateText(_ date: Date) -> String {
        CachedDateFormatters
            .formatter(localeIdentifier: viewModel.selectedLanguage.localeIdentifier, fixedFormat: "yyyy/M/d")
            .string(from: date)
    }

}
