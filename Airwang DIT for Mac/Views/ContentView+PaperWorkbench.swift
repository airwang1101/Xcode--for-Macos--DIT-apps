import AppKit
import SwiftUI

extension ContentView {
    var paperRoot: some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width - 48)
            let compact = proxy.size.width < 1000
            VStack(spacing: 0) {
                paperWindowHeader
                Rectangle().fill(paperPalette.divider).frame(height: 0.7)
                if viewModel.isConfigured {
                    paperWorkspaceHeader(compact: compact)
                        .padding(.horizontal, 24)
                    paperWorkspace(width: width, compact: compact)
                        .padding(.horizontal, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("workspace-\(viewModel.selectedSection.rawValue)")
                    paperBottomNavigation(width: width)
                        .padding(.top, 10)
                        .padding(.bottom, 12)
                } else {
                    onboardingView
                }
            }
            .background(paperPalette.background)
            .foregroundStyle(paperPalette.ink)
            .font(.system(size: 14))
            .tint(paperPalette.accent)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("main-dashboard")
    }

    var paperWindowHeader: some View {
        HStack(spacing: 18) {
            Text("Airwang DIT")
                .font(.system(size: 17, weight: .medium, design: .serif))
                .padding(.leading, 84)
            Spacer(minLength: 8)
            paperUtilityButton("arrow.clockwise", title: "刷新设备") { viewModel.refreshVolumes() }
                .accessibilityIdentifier("paper-refresh-volumes")
            paperUtilityButton(viewModel.selectedTheme == .night ? "sun.max" : "moon",
                               title: viewModel.selectedTheme == .night ? "白天" : "夜晚") {
                viewModel.setTheme(viewModel.selectedTheme == .night ? .day : .night)
            }
            paperUtilityButton("globe", title: "语言") {
                viewModel.setLanguage(viewModel.selectedLanguage == .chinese ? .english : .chinese)
            }
            Menu {
                Section(viewModel.localized("界面外观")) {
                    ForEach(InterfaceStyle.allCases) { style in
                        Button(viewModel.localized(style.title)) { viewModel.setInterfaceStyle(style) }
                    }
                }
                Toggle(viewModel.localized("新建任务默认 5 分钟后自动执行"), isOn: Binding(
                    get: { viewModel.autoStartQueuedProjects }, set: { viewModel.setAutoStartQueuedProjects($0) }
                ))
                Button(viewModel.localized("选择主目标盘")) { viewModel.openFolderPicker(for: .target) }
                Button(viewModel.localized("选择备份盘")) { viewModel.openFolderPicker(for: .backup) }
                Button(viewModel.localized("导出诊断")) { viewModel.exportDiagnostics() }
                    .disabled(viewModel.isExportingDiagnostics || viewModel.isChoosingDiagnosticsDestination)
                if viewModel.isExportingPDFReport {
                    Button(viewModel.localized("取消 PDF 导出")) { viewModel.cancelPDFReportExport() }
                }
            } label: { Image(systemName: "gearshape").font(.system(size: 17)) }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(viewModel.localized("界面设置"))
            .accessibilityIdentifier("paper-settings-menu")
        }
        .padding(.trailing, 24)
        .frame(height: 48)
    }

    func paperUtilityButton(_ icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 16)).frame(width: 26, height: 28) }
            .buttonStyle(.plain)
            .foregroundStyle(paperPalette.secondary)
            .help(viewModel.localized(title))
            .accessibilityLabel(viewModel.localized(title))
    }

    @ViewBuilder
    func paperWorkspaceHeader(compact: Bool) -> some View {
        let title = Text(viewModel.localized(viewModel.selectedSection.title))
            .font(.system(size: 28, weight: .semibold))
            .accessibilityIdentifier("paper-workspace-title")
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.selectedSection == .copy {
                if compact {
                    title.padding(.top, 16)
                    paperSecondaryNavigation.padding(.top, 8)
                } else {
                    HStack(spacing: 36) { title; paperSecondaryNavigation; Spacer(minLength: 0) }
                        .padding(.top, 8)
                }
            } else {
                title.padding(.vertical, 14)
            }
            Rectangle().fill(paperPalette.divider).frame(height: 0.7)
        }
        .padding(.bottom, 18)
    }

    var paperSecondaryNavigation: some View {
        HStack(spacing: 10) {
            ForEach(PaperCopyTab.allCases) { tab in
                Button { paperCopyTab = tab } label: {
                    Text(viewModel.localized(tab.title))
                        .font(.system(size: 14, weight: paperCopyTab == tab ? .semibold : .regular))
                        .foregroundStyle(paperCopyTab == tab ? paperPalette.accent : paperPalette.secondary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 45)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(paperCopyTab == tab ? paperPalette.accent : .clear).frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("paper-copy-tab-\(tab.rawValue)")
                .accessibilityAddTraits(paperCopyTab == tab ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paper-secondary-navigation")
    }

    func paperBottomNavigation(width: CGFloat) -> some View {
        HStack(spacing: 4) {
            ForEach(MainSection.allCases) { section in
                let selected = viewModel.selectedSection == section
                Button { viewModel.selectedSection = section } label: {
                    VStack(spacing: 5) {
                        Image(systemName: section.systemImage).font(.system(size: 19, weight: .medium))
                        Text(viewModel.localized(section.title)).font(.system(size: 11, weight: selected ? .semibold : .regular))
                    }
                    .frame(width: min(90, max(56, (width - 40) / 5)), height: 52)
                    .foregroundStyle(selected ? paperPalette.accent : paperPalette.secondary)
                    .background(selected ? paperPalette.accent.opacity(0.09) : .clear, in: Capsule())
                    .contentShape(Capsule())
                    .accessibilityIdentifier("bottom-tab-label-\(section.rawValue)")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(viewModel.localized(section.title))
                .accessibilityIdentifier("bottom-tab-\(section.rawValue)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(7)
        .background(paperPalette.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(paperPalette.divider, lineWidth: 0.7))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bottom-tab-bar")
    }

    @ViewBuilder
    func paperWorkspace(width: CGFloat, compact: Bool) -> some View {
        switch viewModel.selectedSection {
        case .copy:
            switch paperCopyTab {
            case .create:
                if compact {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            paperCreateForm
                            Divider()
                            paperTaskRail
                        }
                        .padding(.bottom, 10)
                    }
                } else {
                    HStack(alignment: .top, spacing: 24) {
                        ScrollView { paperCreateForm.padding(.bottom, 8) }
                            .frame(maxWidth: .infinity)
                        Rectangle().fill(paperPalette.divider).frame(width: 0.7)
                        ScrollView { paperTaskRail.padding(.bottom, 8) }
                            .frame(width: min(340, max(290, width * 0.29)))
                    }
                }
            case .devices:
                volumeListCard.accessibilityIdentifier("paper-devices")
            case .queue:
                VStack(spacing: 14) {
                    queueControlStrip(availableWidth: width)
                    projectQueueCard
                }.accessibilityIdentifier("paper-queue")
            case .reports:
                logCard.accessibilityIdentifier("paper-reports")
            }
        case .dashboard:
            ScrollView { dashboardWorkspace(availableWidth: width, portraitOptimized: compact).frame(minHeight: 600) }
        case .backup:
            backupWorkspace(portraitOptimized: compact)
        case .organize:
            ScrollView { organizeWorkspace(availableWidth: width).frame(minHeight: 600) }
        case .statistics:
            ScrollView { statisticsWorkspace(availableWidth: width) }
        }
    }

    var paperSelectedVolume: StorageVolume? {
        if let id = paperSelectedVolumeID { return viewModel.displayVolumes.first { $0.id == id } }
        return viewModel.displayVolumes.first
    }

    var paperCreateForm: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    paperStepHeading("1", title: "来源", detail: "选择相机卡或存储设备作为来源。")
                    Spacer()
                    Button { viewModel.refreshVolumes() } label: { Label(viewModel.localized("重新扫描"), systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("paper-rescan")
                }
                Button { paperShowsSources = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "externaldrive").font(.system(size: 25)).foregroundStyle(paperPalette.secondary)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(paperSelectedVolume?.name ?? viewModel.localized("选择来源设备"))
                                .font(.system(size: 15, weight: .semibold))
                            Text(paperSelectedVolume?.url.path ?? viewModel.localized("当前没有可用来源，请连接设备或刷新。"))
                                .font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
                                .lineLimit(2).textSelection(.enabled)
                        }
                        Spacer(minLength: 10)
                        if let volume = paperSelectedVolume {
                            Text(volume.capacityDescription)
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(paperPalette.secondary).multilineTextAlignment(.trailing)
                        }
                        Image(systemName: "chevron.down").font(.system(size: 11))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(paperPalette.surface, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(paperPalette.divider, lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $paperShowsSources, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(viewModel.localized("选择来源设备")).font(.headline)
                        if viewModel.displayVolumes.isEmpty {
                            Text(viewModel.localized("当前没有可用来源，请连接设备或刷新。"))
                                .foregroundStyle(paperPalette.secondary)
                        }
                        ForEach(viewModel.displayVolumes) { volume in
                            Button {
                                paperSelectedVolumeID = volume.id
                                paperShowsSources = false
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "externaldrive")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(volume.name).font(.system(size: 14, weight: .medium))
                                        Text(volume.url.path).font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
                                    }
                                    Spacer()
                                    if paperSelectedVolume?.id == volume.id { Image(systemName: "checkmark") }
                                }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }.padding(18).frame(width: 380)
                        .background(paperPalette.surface)
                        .foregroundStyle(paperPalette.ink)
                }
                .accessibilityIdentifier("paper-source-picker")
                Label(viewModel.localized("选择素材后确认文件数与拷贝容量，保留全部素材选择方式。"), systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                paperStepHeading("2", title: "存储", detail: "选择存储位置，用于保存拷贝的素材。")
                paperDestinationRow(title: "主存储位置", path: viewModel.preferences.targetPath,
                                    capacity: viewModel.targetCapacity, purpose: .target)
                HStack {
                    Toggle(viewModel.localized("主盘校验后备份"), isOn: Binding(
                        get: { viewModel.preferences.backupEnabled }, set: { viewModel.setBackupEnabled($0) }
                    )).toggleStyle(.checkbox).accessibilityIdentifier("paper-backup-toggle")
                    Spacer()
                }
                paperDestinationRow(title: "备份盘", path: viewModel.preferences.backupPath,
                                    capacity: viewModel.backupCapacity, purpose: .backup)
                    .opacity(viewModel.preferences.backupEnabled ? 1 : 0.65)
                Text(viewModel.localized("备份从主目标盘读取，按当前任务选择的校验方式执行。"))
                    .font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                paperStepHeading("3", title: "校验", detail: "选择校验方式与执行模式。")
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) {
                        paperVerificationPicker
                        paperExecutionPicker
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        paperVerificationPicker
                        paperExecutionPicker
                    }
                }
                HStack(spacing: 16) {
                    Text(viewModel.localized("项目名称")).foregroundStyle(paperPalette.secondary)
                    Picker(viewModel.localized("项目名称"), selection: $viewModel.projectNameMode) {
                        ForEach(ProjectNameMode.allCases) { mode in Text(viewModel.localized(mode.title)).tag(mode) }
                    }.pickerStyle(.segmented).frame(maxWidth: 300)
                }
                if viewModel.projectNameMode == .custom {
                    TextField(viewModel.localized("任务名称（可选）"), text: $viewModel.draftProjectName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("paper-project-name")
                }
                Text(viewModel.localized(viewModel.autoStartQueuedProjects
                    ? "加入队列，5 分钟后自动执行" : "加入队列，等待手动执行"))
                    .font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { paperCreateButton; Spacer(minLength: 8); paperPreviewButton; paperOptionsButton }
                    VStack(alignment: .leading, spacing: 12) {
                        paperCreateButton
                        HStack { paperPreviewButton; paperOptionsButton }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paper-create-form")
    }

    func paperStepHeading(_ number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.system(size: 20, weight: .medium).monospacedDigit())
                .foregroundStyle(viewModel.selectedTheme == .night ? Color.black : Color.white)
                .frame(width: 36, height: 36)
                .background(paperPalette.accent, in: RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.localized(title)).font(.system(size: 19, weight: .semibold))
                Text(viewModel.localized(detail)).font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func paperDestinationRow(title: String, path: String?, capacity: StorageCapacitySnapshot?, purpose: FolderPickerPurpose) -> some View {
        Button { viewModel.openFolderPicker(for: purpose) } label: {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive").font(.system(size: 24)).foregroundStyle(paperPalette.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.localized(title)).font(.system(size: 13, weight: .semibold))
                    Text(path ?? viewModel.localized("尚未设置"))
                        .font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
                        .lineLimit(2).textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Text(capacity?.capacityLine ?? viewModel.localized("容量暂不可读"))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(paperPalette.secondary).multilineTextAlignment(.trailing)
                Image(systemName: "chevron.right").font(.system(size: 11))
            }.padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(paperPalette.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(paperPalette.divider, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .help(path ?? viewModel.localized("点击选择"))
        .accessibilityIdentifier("paper-destination-\(purpose.id)")
    }

    var paperVerificationPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.localized("校验方式")).font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
            Picker(viewModel.localized("校验方式"), selection: $viewModel.selectedVerificationMode) {
                ForEach(VerificationMode.selectableCases) { mode in Text(viewModel.localized(mode.title)).tag(mode) }
            }.labelsHidden().frame(minWidth: 220, maxWidth: .infinity)
                .accessibilityIdentifier("paper-verification-picker")
            Text(viewModel.localized(viewModel.selectedVerificationMode.detail))
                .font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var paperExecutionPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(viewModel.localized("执行方式")).font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
            Picker(viewModel.localized("执行方式"), selection: $viewModel.executionMode) {
                ForEach(ProjectExecutionMode.allCases) { mode in Text(viewModel.localized(mode.title)).tag(mode) }
            }.labelsHidden().frame(minWidth: 180, maxWidth: .infinity)
                .accessibilityIdentifier("paper-execution-picker")
            Text(viewModel.localized(viewModel.executionMode.subtitle))
                .font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var paperCreateButton: some View {
        Button { if let volume = paperSelectedVolume { viewModel.prepareImport(for: volume) } } label: {
            Label(viewModel.localized("选择素材并加入队列"), systemImage: "play.fill").frame(minWidth: 180)
        }
        .buttonStyle(PaperPrimaryButtonStyle(palette: paperPalette))
        .disabled(paperSelectedVolume == nil)
        .help(viewModel.localized("进入现有素材选择界面，确认文件后创建项目。"))
        .accessibilityIdentifier("paper-create-project")
    }

    var paperPreviewButton: some View {
        Button { if let volume = paperSelectedVolume { viewModel.prepareImport(for: volume) } } label: {
            Label(viewModel.localized("预览文件"), systemImage: "folder")
        }.buttonStyle(.bordered).disabled(paperSelectedVolume == nil)
    }

    var paperOptionsButton: some View {
        Menu {
            Toggle(viewModel.localized("新建任务默认 5 分钟后自动执行"), isOn: Binding(
                get: { viewModel.autoStartQueuedProjects }, set: { viewModel.setAutoStartQueuedProjects($0) }
            ))
            Button(viewModel.localized("纸面工作台")) { viewModel.setInterfaceStyle(.paper) }
            Button(viewModel.localized("经典界面")) { viewModel.setInterfaceStyle(.classic) }
        } label: { Label(viewModel.localized("更多选项"), systemImage: "slider.horizontal.3") }
        .fixedSize().accessibilityIdentifier("paper-more-options")
    }

    var paperTaskRail: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                paperRailTitle("当前任务", count: nil)
                if let project = viewModel.activeQueueProjects.first(where: { $0.status == .running || $0.status == .cancelling }) {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in paperActiveTask(project) }
                } else {
                    Text(viewModel.localized("暂无运行中的任务"))
                        .font(.system(size: 13)).foregroundStyle(paperPalette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 20)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                paperRailTitle("任务队列", count: viewModel.activeQueueProjects.count)
                if viewModel.activeQueueProjects.isEmpty {
                    Text(viewModel.localized("队列为空"))
                        .font(.system(size: 13)).foregroundStyle(paperPalette.secondary)
                }
                ForEach(viewModel.activeQueueProjects.prefix(4)) { project in
                    Button { paperCopyTab = .queue } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: project.status == .running ? "circle.fill" : "circle")
                                .font(.system(size: 9)).padding(.top, 4)
                                .foregroundStyle(paperStatusColor(project.status))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(project.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(viewModel.localizedStatus(project.status)).font(.system(size: 12))
                                    .foregroundStyle(paperPalette.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(paperPalette.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 7)
                    }.buttonStyle(.plain)
                    Divider()
                }
                HStack {
                    Button(viewModel.localized("执行队列")) { viewModel.startQueue() }
                        .buttonStyle(.bordered).disabled(!viewModel.canStartQueue)
                        .help(viewModel.startQueueDisabledHelp ?? viewModel.localized("开始执行排队中的拷贝项目"))
                        .accessibilityIdentifier("paper-start-queue")
                    Spacer()
                    Button(viewModel.localized("查看全部")) { paperCopyTab = .queue }.buttonStyle(.plain)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                paperRailTitle("已完成", count: viewModel.reports.count)
                if let report = viewModel.reports.first {
                    paperRecentReport(report)
                } else {
                    Text(viewModel.localized("当前 App 存储暂无任务日志"))
                        .font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
                }
                Button(viewModel.localized("全部报告")) { paperCopyTab = .reports }.buttonStyle(.plain)
            }
            if let status = viewModel.pdfReportExportStatus {
                Text(status).font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
                if viewModel.isExportingPDFReport {
                    Button(viewModel.localized("取消 PDF 导出")) { viewModel.cancelPDFReportExport() }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("paper-task-rail")
    }

    func paperRailTitle(_ title: String, count: Int?) -> some View {
        HStack {
            Text(viewModel.localized(title)).font(.system(size: 17, weight: .semibold))
            Spacer()
            if let count { Text("\(count)").font(.system(size: 12).monospacedDigit()).foregroundStyle(paperPalette.secondary) }
        }
    }

    func paperActiveTask(_ project: CopyProject) -> some View {
        let stages = [project.primaryCopyState, project.primaryVerifyState, project.backupCopyState, project.backupVerifyState]
        let stage = stages.first(where: \.isActive)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Text(project.name).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Spacer()
                Text(viewModel.localizedStatus(project.status)).font(.system(size: 11))
                    .foregroundStyle(paperStatusColor(project.status))
            }
            Text(project.sourceName + " → " + URL(fileURLWithPath: project.targetRootPath).lastPathComponent)
                .font(.system(size: 12)).foregroundStyle(paperPalette.secondary).lineLimit(2)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.offset) { index, state in
                    VStack(spacing: 7) {
                        Image(systemName: state.isComplete ? "checkmark.circle.fill" : (state.isActive ? "circle.fill" : "circle"))
                            .font(.system(size: 13))
                        Text(viewModel.localized(state.title)).font(.system(size: 10)).lineLimit(2)
                    }.frame(maxWidth: .infinity)
                        .foregroundStyle(state.isComplete ? paperPalette.success : (state.isActive ? paperPalette.accent : paperPalette.secondary))
                        .opacity(index >= 2 && !project.hasBackup ? 0.4 : 1)
                }
            }
            HStack {
                Text(viewModel.localized(projectProgressTitle(project))).font(.system(size: 12))
                Spacer()
                Text("\(Int(((stage?.fraction ?? projectProgressFraction(project)) * 100).rounded()))%")
                    .font(.system(size: 24, weight: .semibold).monospacedDigit())
            }
            ProgressView(value: stage?.fraction ?? projectProgressFraction(project)).tint(paperPalette.accent)
            HStack {
                Text(ByteDisplayFormatter.string(fromByteCount: Int64(stage?.speedBytesPerSecond ?? 0)) + "/s")
                Spacer()
                Text(viewModel.localized("剩余") + " " + etaText(stage?.eta))
            }.font(.system(size: 12).monospacedDigit()).foregroundStyle(paperPalette.secondary)
            Divider()
            paperTaskDetail("已处理", value: ByteDisplayFormatter.string(fromByteCount: stage?.processedBytes ?? 0)
                            + " / " + ByteDisplayFormatter.string(fromByteCount: stage?.totalBytes ?? project.totalBytes))
            paperTaskDetail("文件", value: "\(stage?.completedFiles ?? 0) / \(stage?.totalFiles ?? project.selectedItems.count)")
            if let file = stage?.currentFile, !file.isEmpty { paperTaskDetail("当前文件", value: file) }
            if let error = project.errorMessage { Text(error).font(.system(size: 12)).foregroundStyle(paperPalette.error).textSelection(.enabled) }
            Button(viewModel.localized("取消任务")) { viewModel.cancelProject(project) }
                .buttonStyle(.bordered).tint(paperPalette.error)
                .disabled(project.status == .cancelling)
                .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(paperPalette.surface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(paperPalette.divider, lineWidth: 0.7))
    }

    func paperTaskDetail(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(viewModel.localized(title)).foregroundStyle(paperPalette.secondary)
            Spacer(minLength: 0)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.system(size: 12).monospacedDigit())
    }

    func paperRecentReport(_ report: TransferReport) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(report.title, systemImage: report.success ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(report.success ? paperPalette.success : paperPalette.error)
            Text(reportSummaryLine(report)).font(.system(size: 12)).foregroundStyle(paperPalette.secondary)
            HStack(spacing: 8) {
                Button("TXT") { viewModel.openReportDocument(report) }.buttonStyle(.bordered)
                Button("PDF") { viewModel.exportPDFReport(report) }.buttonStyle(.bordered)
                    .disabled(viewModel.isExportingPDFReport || viewModel.isChoosingPDFReportDestination)
                Button { viewModel.revealReportInFinder(report) } label: { Image(systemName: "folder") }
                    .buttonStyle(.bordered).help(viewModel.localized("在访达中打开"))
            }
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(paperPalette.surface, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(paperPalette.divider, lineWidth: 0.7))
    }

    func paperStatusColor(_ status: CopyProjectStatus) -> Color {
        switch status {
        case .completed: paperPalette.success
        case .failed, .blocked: paperPalette.error
        case .cancelled, .cancelling: paperPalette.warning
        case .running: paperPalette.accent
        case .queued: paperPalette.secondary
        }
    }
}
