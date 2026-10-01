import AppKit
import SwiftUI

/// 拷贝 / 仪表盘 / 备份三个工作区,以及任务队列、设备列表与日志卡片。
extension ContentView {
    @ViewBuilder
    func copyWorkspace(availableWidth: CGFloat, portraitOptimized: Bool) -> some View {
        if portraitOptimized {
            VStack(spacing: 14) {
                copyPresetCard(availableWidth: availableWidth)
                volumeListCard
                    .frame(minHeight: 320, maxHeight: 520)
                projectQueueCard
                    .frame(minHeight: 420, maxHeight: 620)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
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
    func dashboardWorkspace(availableWidth: CGFloat, portraitOptimized: Bool) -> some View {
        if portraitOptimized {
            VStack(spacing: 14) {
                queueControlStrip(availableWidth: availableWidth)
                dashboardProjectList
                    .frame(minHeight: 420, maxHeight: 620)
                logCard
                    .frame(minHeight: 340, maxHeight: 540)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)
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

    var dashboardProjectList: some View {
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

    func backupWorkspace(portraitOptimized: Bool) -> some View {
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

    var backupWorkspaceTitle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.localized("备份工作台"))
                .sectionTitle()
            Text(viewModel.localized("这里只显示在拷贝项目里配置了备份盘的项目，备份来源固定为主目标盘。"))
                .foregroundStyle(secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var backupWorkspaceStartButton: some View {
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

    func copyPresetCard(availableWidth: CGFloat) -> some View {
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
        .animation(stableLayoutAnimation, value: useCompactHeader)
        .animation(stableLayoutAnimation, value: useStackedTargets)
        .animation(stableLayoutAnimation, value: useStackedStats)
    }

    func executionModePicker(width: CGFloat) -> some View {
        Picker(viewModel.localized("执行方式"), selection: $viewModel.executionMode) {
            ForEach(ProjectExecutionMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: width)
    }

    var primaryTargetPresetBlock: some View {
        clickablePresetBlock(
            label: viewModel.localized("主目标盘"),
            value: viewModel.preferences.targetPath ?? viewModel.localized("尚未设置"),
            capacityLine: viewModel.targetCapacity?.capacityLine,
            accent: accentColor
        ) {
            viewModel.openFolderPicker(for: .target)
        }
    }

    var backupTargetPresetBlock: some View {
        clickablePresetBlock(
            label: viewModel.localized("备份盘"),
            value: viewModel.preferences.backupEnabled ? (viewModel.preferences.backupPath ?? viewModel.localized("未设置备份位置")) : viewModel.localized("未启用"),
            capacityLine: viewModel.preferences.backupEnabled ? viewModel.backupCapacity?.capacityLine : viewModel.localized("点击选择后自动启用备份"),
            accent: secondaryAccentColor
        ) {
            viewModel.openFolderPicker(for: .backup)
        }
    }

    func queueControlStrip(availableWidth: CGFloat) -> some View {
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
        .animation(stableLayoutAnimation, value: useStackedLayout)
    }

    var projectQueueCard: some View {
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

    func clickablePresetBlock(
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

    func projectQueueRow(_ project: CopyProject, canMoveUp: Bool, canMoveDown: Bool) -> some View {
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
            if project.backupOnlyRetry {
                Text(viewModel.localized("此次执行从主盘读取，主盘完成状态和原报告已保留。"))
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            backupRetryAction(for: project)
        }
        .padding(14)
        .background(glassSurface(cornerRadius: 18, elevation: .tile))
    }

    func autoStartCountdownRow(_ project: CopyProject, now: Date) -> some View {
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

    @ViewBuilder
    func backupRetryAction(for project: CopyProject) -> some View {
        if !(project.backupOnlyRetry && project.status == .queued), viewModel.canRetryBackup(for: project) {
            HStack(alignment: .center, spacing: 10) {
                Button(viewModel.localized("仅重试备份")) {
                    viewModel.retryBackupProject(project)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityIdentifier("backup-retry-" + project.id.uuidString)
                Text(viewModel.localized("按原主盘报告复核后补备份，可拔出原始源卡。"))
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func autoStartCountdownText(_ project: CopyProject, now: Date) -> String {
        guard let deadline = project.autoStartDeadline else {
            return viewModel.localized("等待自动执行")
        }
        let remaining = max(deadline.timeIntervalSince(now), 0)
        if viewModel.selectedLanguage == .english {
            return "Auto-start in \(stopwatchText(remaining))"
        }
        return "\(stopwatchText(remaining)) 后自动执行"
    }

    func projectQueueProgress(_ project: CopyProject, now: Date) -> some View {
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

    func projectDashboardCard(_ project: CopyProject) -> some View {
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

    func backupProjectCard(_ project: CopyProject) -> some View {
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
            backupRetryAction(for: project)
        }
        .padding(18)
        .background(glassSurface(cornerRadius: 20, elevation: .card))
    }

    func projectStageTrack(_ state: ProjectStageState, tint: Color) -> some View {
        progressTrack(
            title: state.title,
            detail: "\(state.completedFiles)/\(state.totalFiles) · \(ByteDisplayFormatter.string(fromByteCount: state.processedBytes))/\(ByteDisplayFormatter.string(fromByteCount: state.totalBytes)) · \(ByteDisplayFormatter.string(fromByteCount: Int64(state.speedBytesPerSecond)))/s · 剩余 \(etaText(state.eta)) · \(state.currentFile.isEmpty ? state.detail : state.currentFile)",
            value: state.fraction,
            tint: state.isBlocked ? .orange : tint
        )
        .opacity(state.title.contains("备份") && state.detail == "未配置备份盘" ? 0.58 : 1)
    }

    func statusColor(_ status: CopyProjectStatus) -> Color {
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

    func projectProgressTitle(_ project: CopyProject) -> String {
        switch project.status {
        case .queued:
            return project.backupOnlyRetry ? viewModel.localized("等待独立备份重试") : "等待执行"
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

    func projectStageSummary(_ project: CopyProject) -> String {
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

    func projectTimeLine(_ project: CopyProject, now: Date) -> String {
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

    func projectProgressFraction(_ project: CopyProject) -> Double {
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

    func projectExpectedStages(_ project: CopyProject) -> [(state: ProjectStageState, expectedBytes: Int64)] {
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

    func stageProcessedBytes(_ state: ProjectStageState, expectedBytes: Int64) -> Int64 {
        guard expectedBytes > 0 else { return state.isComplete ? 1 : 0 }
        if state.isComplete {
            return expectedBytes
        }
        if state.totalBytes > 0 {
            return Int64((Double(expectedBytes) * state.fraction).rounded())
        }
        return min(max(state.processedBytes, 0), expectedBytes)
    }

    func projectElapsed(_ project: CopyProject, now: Date) -> TimeInterval {
        guard let startedAt = projectStartedAt(project) else { return 0 }
        let finishedAt = projectFinishedAt(project) ?? (project.status == .running || project.status == .cancelling ? now : project.updatedAt)
        return max(finishedAt.timeIntervalSince(startedAt), 0)
    }

    func projectStartedAt(_ project: CopyProject) -> Date? {
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

    func projectFinishedAt(_ project: CopyProject) -> Date? {
        [
            project.primaryCopyState.finishedAt,
            project.primaryVerifyState.finishedAt,
            project.backupCopyState.finishedAt,
            project.backupVerifyState.finishedAt
        ]
        .compactMap { $0 }
        .max()
    }

    func backupStatusText(_ project: CopyProject) -> String {
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

    var volumeListCard: some View {
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

    var logCard: some View {
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

    func reportSummaryLine(_ report: TransferReport) -> String {
        if viewModel.selectedLanguage == .english {
            return "\(report.selectedFileCount) files · \(ByteDisplayFormatter.string(fromByteCount: report.totalBytes)) · total \(stopwatchText(report.duration))"
        }
        return "\(report.selectedFileCount) 个文件  ·  \(ByteDisplayFormatter.string(fromByteCount: report.totalBytes))  ·  总耗时 \(stopwatchText(report.duration))"
    }

    func shortDateTimeText(_ date: Date) -> String {
        let isEnglish = viewModel.selectedLanguage == .english
        return CachedDateFormatters
            .formatter(localeIdentifier: viewModel.selectedLanguage.localeIdentifier,
                       template: isEnglish ? "MMM d, HH:mm" : nil,
                       fixedFormat: isEnglish ? nil : "M月d日 HH:mm")
            .string(from: date)
    }
}
