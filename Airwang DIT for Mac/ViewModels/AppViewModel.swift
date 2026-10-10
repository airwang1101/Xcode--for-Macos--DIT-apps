import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// 把高频进度状态合并到固定发布节奏:间隔内只保留最新一份,尾沿必定送达。
///
/// TransferService 只在单文件内部按时间节流 chunk 级进度,但每个文件边界
/// (开始/写入确认/收尾/校验完成)都会无条件发布一次;小文件密集的素材卡
/// (照片、RAW 帧序列)每秒能产生数百次发布,每次都让整棵主界面视图树
/// 重算一遍。汇聚点统一按时间合并后,发布频率与文件大小和数量解耦。
@MainActor
final class TransferProgressCoalescer {
    private let interval: TimeInterval
    private let apply: (TransferState) -> Void
    private var lastPublishAt = Date.distantPast
    private var pending: TransferState?
    private var flushTask: Task<Void, Never>?

    init(interval: TimeInterval = 0.4, apply: @escaping (TransferState) -> Void) {
        self.interval = interval
        self.apply = apply
    }

    func ingest(_ state: TransferState) {
        let now = Date()
        if now.timeIntervalSince(lastPublishAt) >= interval {
            deliver(state, at: now)
            return
        }

        pending = state
        guard flushTask == nil else { return }
        let delay = max(interval - now.timeIntervalSince(lastPublishAt), 0.01)
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.flushTask = nil
            if let pending = self.pending {
                self.pending = nil
                self.deliver(pending, at: Date())
            }
        }
    }

    /// 丢弃积压并停止尾沿投递。终态(完成/取消/失败)由调用方直接写入,
    /// 写入前必须调用,避免迟到的进度覆盖终态。
    func cancelPending() {
        flushTask?.cancel()
        flushTask = nil
        pending = nil
    }

    private func deliver(_ state: TransferState, at now: Date) {
        lastPublishAt = now
        pending = nil
        flushTask?.cancel()
        flushTask = nil
        apply(state)
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var preferences: AppPreferences {
        didSet { rebuildDisplayVolumesCache() }
    }
    @Published var interfaceStyle: InterfaceStyle = .paper
    @Published var selectedTheme: AppTheme = .day
    @Published var selectedLanguage: AppLanguage = .chinese
    @Published var autoStartQueuedProjects = false
    @Published private(set) var gettingStartedProgress = GettingStartedProgress()
    @Published private(set) var isShowingGettingStarted = false
    private var resumesGettingStartedAfterFolderPicker = false
    @Published var selectedSection: MainSection = .copy
    @Published var copyProjects: [CopyProject] = [] {
        didSet { orderedProjectsCache = Self.sortedProjects(copyProjects) }
    }
    private(set) var orderedProjectsCache: [CopyProject] = []
    @Published var executionMode: ProjectExecutionMode = .sequential {
        didSet {
            if oldValue != executionMode, !activeProjectIDs.isEmpty {
                continueQueueAfterStateChange()
            }
        }
    }
    @Published var selectedVerificationMode: VerificationMode = .sha256
    @Published var projectNameMode: ProjectNameMode = .automatic
    @Published var draftProjectName = ""
    @Published var activeProjectIDs: Set<UUID> = []
    @Published var mountedVolumes: [StorageVolume] = [] {
        didSet { rebuildDisplayVolumesCache() }
    }
    private(set) var displayVolumesCache: [StorageVolume] = []
    @Published var pendingImportVolume: StorageVolume?
    @Published var selectedImportMode: ImportMode = .time
    @Published var selectedAssetBrowserMode: AssetBrowserMode = .icon
    @Published var selectedScanFilter: ScanFilter = .all
    @Published var scannedItems: [MediaItem] = [] {
        didSet {
            rebuildScanIndexes()
        }
    }
    @Published var timeGroups: [TimeGroup] = []
    @Published var selectedItemIDs: Set<String> = [] {
        didSet { selectedItemsSnapshot = nil }
    }
    @Published var isScanning = false
    @Published var isImporting = false
    @Published var reports: [TransferReport] = []
    @Published private(set) var copyStatistics = CopyStatisticsSummary.make(reports: [], projects: [])
    @Published private(set) var copyStatisticsHeatmaps = CopyStatisticsHeatmaps.make(days: [])
    @Published private(set) var statisticsRecentReports: [TransferReport] = []
    @Published private(set) var statisticsRefreshedAt = Date.distantPast
    @Published private(set) var isRefreshingStatistics = false
    @Published var organizerSourceURL: URL?
    @Published var organizerDestinationURL: URL?
    @Published var organizerScanFilter: ScanFilter = .all
    @Published var organizerOperationMode: OrganizerOperationMode = .copy
    @Published var organizerDuplicatePolicy: OrganizerDuplicatePolicy = .rename
    @Published private(set) var organizerPlan: OrganizerPlan?
    @Published private(set) var organizerExecutionState = OrganizerExecutionState()
    @Published private(set) var organizerLastSummary: OrganizerRunSummary?
    @Published private(set) var isBuildingOrganizerPlan = false
    @Published private(set) var isRunningOrganizer = false
    @Published var organizerStatusMessage: String?
    @Published var organizerPreviewFilter: OrganizerPreviewFilter = .all
    @Published var importError: String?
    @Published var hasUnsavedChanges = false
    @Published private(set) var isExportingDiagnostics = false
    @Published private(set) var isChoosingDiagnosticsDestination = false
    @Published private(set) var diagnosticsExportStatus: String?
    @Published private(set) var isExportingPDFReport = false
    @Published private(set) var isChoosingPDFReportDestination = false
    @Published private(set) var pdfReportExportStatus: String?
    @Published private(set) var pdfReportExportID: UUID?
    @Published var activeFolderPicker: FolderPickerPurpose?
    @Published var folderRoots: [FolderBrowserItem] = []
    @Published var folderChildren: [FolderBrowserItem] = []
    @Published var isLoadingFolderChildren = false
    @Published var currentFolderURL: URL?
    @Published var selectedFolderURL: URL?
    @Published var sourceFolderURL: URL?
    @Published var sourceFolderChildren: [FolderBrowserItem] = []
    @Published var isLoadingSourceFolderChildren = false
    @Published var hasScannedSource = false
    @Published private(set) var taskLogScopeName = AppStorageScope.displayName

    let settingsStore: SettingsStore
    private let volumeMonitor = VolumeMonitor()
    private let scanner = MediaScanner()
    private let transferService = TransferService()
    private let organizerService = OrganizerService()
    private static let projectAutoStartDelay: TimeInterval = 300
    private static let statisticsRefreshInterval: TimeInterval = 600
    private let reportURL: URL
    private let projectURL: URL
    private let statisticsIndexURL: URL
    private var projectTasks: [UUID: Task<Void, Never>] = [:]
    private var projectTokens: [UUID: ImportInterruptionToken] = [:]
    private var pendingDeleteProjectIDs: Set<UUID> = []
    private var autoStartTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var organizerPlanTask: Task<Void, Never>?
    private var organizerExecutionTask: Task<Void, Never>?
    private var folderChildrenTask: Task<Void, Never>?
    private var sourceFolderChildrenTask: Task<Void, Never>?
    private var statisticsRefreshTask: Task<Void, Never>?
    private var statisticsBuildTask: Task<Void, Never>?
    private var statisticsRevision: UInt64 = 0
    private var organizerPlanGeneration = UUID()
    private var scanSessionID = UUID()
    private var folderNavigationID = UUID()
    private var sourceFolderNavigationID = UUID()
    private var selectedItemsSnapshot: (items: [MediaItem], totalBytes: Int64)?
    private var scannedTotalBytesCache: Int64 = 0
    private var scannedItemsByID: [String: MediaItem] = [:]
    private var scannedItemOrder: [String: Int] = [:]
    private var relatedIDsByItemID: [String: Set<String>] = [:]
    private var projectsNeedSave = false
    private var reportsNeedSave = false
    private var statisticsIndexNeedSave = false
    private var copyStatisticsIndex = CopyStatisticsIndex()
    private var manualQueueRunActive = false
    private var diagnosticsExportTask: Task<Void, Never>?
    private var pdfReportExportTask: Task<Void, Never>?
    private let backupChangeConfirmation: ((String, String) -> Bool)?

    init(dataDirectory: URL? = nil, backupChangeConfirmation: ((String, String) -> Bool)? = nil) {
        self.backupChangeConfirmation = backupChangeConfirmation
        if let dataDirectory {
            settingsStore = SettingsStore(
                preferencesURL: dataDirectory.appendingPathComponent(AppStorageScope.preferencesURL.lastPathComponent),
                uiSettingsURL: dataDirectory.appendingPathComponent(AppStorageScope.uiSettingsURL.lastPathComponent)
            )
        } else {
            settingsStore = SettingsStore()
        }
        preferences = settingsStore.load()
        let uiSettings = settingsStore.loadUISettings()
        interfaceStyle = uiSettings.interfaceStyle
        selectedTheme = uiSettings.theme
        selectedLanguage = uiSettings.language
        autoStartQueuedProjects = uiSettings.autoStartQueuedProjects
        reportURL = dataDirectory?.appendingPathComponent(Self.makeReportURL().lastPathComponent) ?? Self.makeReportURL()
        projectURL = dataDirectory?.appendingPathComponent(Self.makeProjectURL().lastPathComponent) ?? Self.makeProjectURL()
        statisticsIndexURL = dataDirectory?.appendingPathComponent(Self.makeStatisticsIndexURL().lastPathComponent) ?? Self.makeStatisticsIndexURL()
        let reportLoad = Self.loadReports(from: reportURL)
        reports = reportLoad.items
        let statisticsIndexLoad = Self.loadStatisticsIndex(from: statisticsIndexURL)
        copyStatisticsIndex = statisticsIndexLoad.value
        organizerDestinationURL = preferences.targetURL
        let projectLoad = Self.loadProjects(from: projectURL)
        let storedProjects = projectLoad.items
        gettingStartedProgress = .initial(
            saved: uiSettings.gettingStarted,
            hasExistingData: settingsStore.hasSavedSettings || preferences.targetPath != nil
                || !storedProjects.isEmpty || !reportLoad.items.isEmpty
        )
        let recoveredProjects = Self.recoverInterruptedProjects(storedProjects)
        copyProjects = recoveredProjects
        orderedProjectsCache = Self.sortedProjects(recoveredProjects)
        rebuildCopyStatistics()
        importError = [settingsStore.lastLoadWarning, reportLoad.warning, statisticsIndexLoad.warning, projectLoad.warning]
            .compactMap { $0 }
            .joined(separator: "\n")
        if importError?.isEmpty == true {
            importError = nil
        }

        volumeMonitor.onNewExternalVolume = { [weak self] volume in
            guard let self, self.pendingImportVolume == nil else { return }
            self.mountedVolumes = self.volumeMonitor.volumes
            guard self.shouldShowAsImportSource(volume) else { return }
            self.pendingImportVolume = volume
        }
        volumeMonitor.onVolumeUnmounted = { [weak self] url in
            self?.handleUnmountedVolume(url)
        }
        mountedVolumes = volumeMonitor.volumes
        // init 内的赋值不触发属性观察器,缓存必须手动建一次,
        // 否则冷启动时已挂载的设备不会出现在列表里。
        rebuildDisplayVolumesCache()
        if storedProjects.contains(where: { $0.status == .running || $0.status == .cancelling }) {
            saveProjects()
        }
        scheduleNextAutoStartCheck()
        startStatisticsRefreshTimer()
    }

    deinit {
        diagnosticsExportTask?.cancel()
        pdfReportExportTask?.cancel()
        statisticsRefreshTask?.cancel()
        statisticsBuildTask?.cancel()
        autoStartTask?.cancel()
        scanTask?.cancel()
        organizerPlanTask?.cancel()
        organizerExecutionTask?.cancel()
        folderChildrenTask?.cancel()
        sourceFolderChildrenTask?.cancel()
    }

    var isConfigured: Bool {
        preferences.targetURL != nil
    }

    func localized(_ key: String) -> String {
        AppLocalization.text(key, language: selectedLanguage)
    }

    func localizedStatus(_ status: CopyProjectStatus) -> String {
        localized(status.title)
    }

    func localizedThemeTitle(_ theme: AppTheme) -> String {
        localized(theme.title)
    }

    var selectedItems: [MediaItem] { importSelectionSnapshot.items }

    var selectedTotalBytes: Int64 { importSelectionSnapshot.totalBytes }

    var scannedTotalBytes: Int64 { scannedTotalBytesCache }

    // Reuse selection work across UI reads. Either input invalidates this snapshot.
    private var importSelectionSnapshot: (items: [MediaItem], totalBytes: Int64) {
        if let selectedItemsSnapshot { return selectedItemsSnapshot }
        let items = selectedItemIDs
            .compactMap { scannedItemsByID[$0] }
            .sorted {
                (scannedItemOrder[$0.id] ?? Int.max) < (scannedItemOrder[$1.id] ?? Int.max)
            }
        let snapshot = (items: items, totalBytes: items.reduce(Int64(0)) { $0 + $1.size })
        selectedItemsSnapshot = snapshot
        return snapshot
    }

    // shouldShowAsImportSource 要做卷标识符解析(文件系统调用),不能放在
    // 每次视图 body 求值的路径上;缓存只在挂载列表或偏好变化时重建。
    var displayVolumes: [StorageVolume] { displayVolumesCache }

    private func rebuildDisplayVolumesCache() {
        displayVolumesCache = mountedVolumes.filter { volume in
            shouldShowAsImportSource(volume)
        }
    }

    var selectedSourceFolderItem: FolderBrowserItem? {
        guard let sourceFolderURL else { return nil }
        return makeFolderItem(from: sourceFolderURL, fallbackName: sourceFolderURL.lastPathComponent)
    }

    var selectionSummary: ImportSelectionSummary? {
        guard let volume = pendingImportVolume,
              let targetURL = preferences.targetURL else {
            return nil
        }
        let selection = importSelectionSnapshot
        guard !selection.items.isEmpty else { return nil }

        return ImportSelectionSummary(
            sourceVolume: volume,
            sourceRootURL: sourceFolderURL ?? volume.url,
            selectedItems: selection.items,
            totalSize: selection.totalBytes,
            targetURL: targetURL,
            backupURL: preferences.backupURL,
            verificationMode: selectedVerificationMode.title,
            namingRule: projectNameMode.title
        )
    }

    var destinationWarnings: [String] {
        guard let summary = selectionSummary else { return [] }
        var warnings: [String] = []
        let requirement = SpacePreflightPolicy.requirement(for: summary.totalSize)

        if let preflight = targetSpacePreflight {
            switch preflight.status {
            case .passed:
                break
            case .insufficient:
                warnings.append("主目标盘空间不足：最低需要 \(ByteDisplayFormatter.string(fromByteCount: preflight.requirement.requiredBytes))，可用 \(ByteDisplayFormatter.string(fromByteCount: preflight.availableBytes ?? 0))")
            case .capacityUnavailable:
                warnings.append("主目标盘容量不可读，为避免写满或中断，已阻止创建项目。")
            }
        }
        if !isWritableDestination(summary.targetURL) {
            warnings.append("主目标盘不可写或位于只读卷，请重新选择。")
        }

        if let preflight = backupSpacePreflight {
            switch preflight.status {
            case .passed:
                break
            case .insufficient:
                warnings.append("备份盘空间不足：最低需要 \(ByteDisplayFormatter.string(fromByteCount: preflight.requirement.requiredBytes))，可用 \(ByteDisplayFormatter.string(fromByteCount: preflight.availableBytes ?? 0))")
            case .capacityUnavailable:
                warnings.append("备份盘容量不可读，为避免写满或中断，已阻止创建项目。")
            }
        }
        if let backupURL = summary.backupURL, !isWritableDestination(backupURL) {
            warnings.append("备份盘不可写或位于只读卷，请重新选择。")
        }

        if let backupURL = summary.backupURL,
           let targetRoot = DiskCapacityResolver.volumeRootPath(for: summary.targetURL),
           let backupRoot = DiskCapacityResolver.volumeRootPath(for: backupURL),
           targetRoot == backupRoot,
           let available = availableCapacity(for: summary.targetURL) {
            let (combinedRequired, overflowed) = requirement.requiredBytes.multipliedReportingOverflow(by: 2)
            let safeCombinedRequired = overflowed ? Int64.max : combinedRequired
            if available < safeCombinedRequired {
                warnings.append("主目标盘和备份盘在同一磁盘卷上：双写最低需要 \(ByteDisplayFormatter.string(fromByteCount: safeCombinedRequired))，当前可用 \(ByteDisplayFormatter.string(fromByteCount: available))")
            }
        }

        if PathSafety.pathsOverlap(summary.sourceRootURL, summary.targetURL) {
            warnings.append("主目标盘不能与源素材目录相同、包含源素材目录，或位于源素材目录内部。")
        }
        if PathSafety.pathsShareVolume(summary.sourceVolume.url, summary.targetURL)
            || PathSafety.pathsShareVolume(summary.sourceRootURL, summary.targetURL) {
            warnings.append("主目标盘不能位于源设备同一个磁盘卷上，请选择独立工作盘。")
        }

        if let backupURL = summary.backupURL {
            if PathSafety.pathsOverlap(summary.sourceRootURL, backupURL) {
                warnings.append("备份盘不能与源素材目录相同、包含源素材目录，或位于源素材目录内部。")
            }
            if PathSafety.pathsShareVolume(summary.sourceVolume.url, backupURL)
                || PathSafety.pathsShareVolume(summary.sourceRootURL, backupURL) {
                warnings.append("备份盘不能位于源设备同一个磁盘卷上，请选择独立备份盘。")
            }

            if PathSafety.pathsOverlap(summary.targetURL, backupURL) {
                warnings.append("主目标盘与备份盘不能相同，也不能互相包含。")
            }
            if PathSafety.pathsShareVolume(summary.targetURL, backupURL) {
                warnings.append("主目标盘与备份盘不能位于同一个磁盘卷上，请选择独立备份盘。")
            }
        }

        return warnings
    }

    var canStartImport: Bool {
        selectionSummary != nil && destinationWarnings.isEmpty
    }

    var canStartQueue: Bool {
        orderedProjects.contains { $0.status == .queued } && !hasUnsavedChanges
    }

    /// 解释为什么"执行任务队列"按钮被禁用,给 SwiftUI `.help()` tooltip 用。
    /// 见 TEST_REPORT #70 — 之前用户点禁用按钮没有任何反馈。
    var startQueueDisabledHelp: String? {
        if canStartQueue { return nil }
        if hasUnsavedChanges {
            return localized("数据正在保存中，请稍后再试")
        }
        if !orderedProjects.contains(where: { $0.status == .queued }) {
            return localized("当前没有排队中的项目，请先创建拷贝任务")
        }
        return localized("当前无法执行队列")
    }

    var hasActiveFileOperations: Bool {
        hasActiveTransfers || isRunningOrganizer || organizerExecutionTask != nil || isExportingPDFReport
    }

    var hasActiveTransfers: Bool {
        isImporting || !activeProjectIDs.isEmpty || !projectTasks.isEmpty
    }

    var orderedProjects: [CopyProject] { orderedProjectsCache }

    /// 队列与仪表盘只展示"未完成"的项目；已完成项目只保留在任务日志中。
    /// 数据仍保留在 copyProjects 内(不删除),报告(import-reports.json)已独立持久化,
    /// 因此完成项的记录通过任务日志卡片继续可查、可打开报告。
    /// 失败/阻塞/取消的项目仍保留在队列里,以便重试或删除。
    var activeQueueProjects: [CopyProject] {
        orderedProjects.filter { $0.status != .completed }
    }

    private static func sortedProjects(_ projects: [CopyProject]) -> [CopyProject] {
        projects.sorted {
            if $0.orderIndex == $1.orderIndex {
                return $0.createdAt < $1.createdAt
            }
            return $0.orderIndex < $1.orderIndex
        }
    }

    var backupProjects: [CopyProject] {
        orderedProjects.filter(\.hasBackup)
    }

    var projectNamePreview: String {
        guard let volume = pendingImportVolume else {
            return automaticProjectName(sourceName: "Source", date: Date())
        }
        switch projectNameMode {
        case .automatic:
            return automaticProjectName(sourceName: volume.name, date: Date())
        case .custom:
            let cleaned = draftProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? "请输入项目名称" : cleaned
        }
    }

    var folderSelection: FolderBrowserItem? {
        guard let selectedFolderURL else { return nil }
        return makeFolderItem(from: selectedFolderURL, fallbackName: selectedFolderURL.lastPathComponent)
    }

    var targetCapacity: StorageCapacitySnapshot? {
        guard let targetURL = preferences.targetURL else { return nil }
        return DiskCapacityResolver.capacity(for: targetURL)
    }

    var backupCapacity: StorageCapacitySnapshot? {
        guard let backupURL = preferences.backupURL else { return nil }
        return DiskCapacityResolver.capacity(for: backupURL)
    }

    var organizerRule: OrganizerRule {
        OrganizerRule(
            scanFilter: organizerScanFilter,
            operationMode: organizerOperationMode,
            duplicatePolicy: organizerDuplicatePolicy
        )
    }

    var organizerStatistics: OrganizerStatisticsSnapshot {
        OrganizerStatisticsSnapshot.make(plan: organizerPlan, lastSummary: organizerLastSummary)
    }

    var organizerWarnings: [String] {
        var warnings: [String] = []
        guard let sourceURL = organizerSourceURL,
              let destinationURL = organizerDestinationURL else {
            return warnings
        }
        if PathSafety.pathsOverlap(sourceURL, destinationURL) {
            warnings.append("源文件夹和目标文件夹不能相同，也不能互相包含。")
        }
        if hasActiveTransfers {
            warnings.append("当前有导入或备份任务运行，请等任务完成后再执行规整，避免同时抢占磁盘。")
        }
        return warnings
    }

    var organizerCanBuildPlan: Bool {
        organizerSourceURL != nil
            && organizerDestinationURL != nil
            && organizerWarnings.filter { !$0.contains("导入或备份任务") }.isEmpty
            && !isBuildingOrganizerPlan
            && !isRunningOrganizer
    }

    var organizerCanRun: Bool {
        guard let organizerPlan else { return false }
        return organizerPlan.executableFiles > 0
            && organizerWarnings.isEmpty
            && !isBuildingOrganizerPlan
            && !isRunningOrganizer
    }

    var targetSpacePreflight: DestinationSpacePreflight? {
        guard let summary = selectionSummary else { return nil }
        return SpacePreflightPolicy.evaluate(
            destinationLabel: "主目标盘",
            destinationPath: summary.targetURL.path,
            payloadBytes: summary.totalSize,
            availableBytes: targetCapacity?.availableCapacity
        )
    }

    var backupSpacePreflight: DestinationSpacePreflight? {
        guard let summary = selectionSummary,
              let backupURL = summary.backupURL else { return nil }
        return SpacePreflightPolicy.evaluate(
            destinationLabel: "备份盘",
            destinationPath: backupURL.path,
            payloadBytes: summary.totalSize,
            availableBytes: backupCapacity?.availableCapacity
        )
    }

    func openFolderPicker(for purpose: FolderPickerPurpose) {
        refreshVolumes()
        activeFolderPicker = purpose
        folderRoots = makeFolderRoots()

        let existingURL: URL?
        switch purpose {
        case .target:
            existingURL = preferences.targetURL
        case .backup:
            existingURL = preferences.backupURL
        case let .projectBackup(projectID):
            existingURL = copyProjects.first(where: { $0.id == projectID })?.backupRootURL
                ?? preferences.backupURL
        case .organizerSource:
            existingURL = organizerSourceURL
        case .organizerDestination:
            existingURL = organizerDestinationURL ?? preferences.targetURL
        }

        let initial = existingURL ?? folderRoots.first?.url
        selectedFolderURL = initial
        if let initial {
            navigate(to: initial)
        }
    }

    func closeFolderPicker() {
        folderChildrenTask?.cancel()
        folderChildrenTask = nil
        isLoadingFolderChildren = false
        activeFolderPicker = nil
    }

    func navigateUp() {
        guard let currentFolderURL else { return }
        let parent = currentFolderURL.deletingLastPathComponent()
        guard parent.path != currentFolderURL.path else { return }
        navigate(to: parent)
    }

    func navigate(to url: URL) {
        currentFolderURL = url
        selectedFolderURL = url
        loadFolderChildrenAsync(for: url)
    }

    func selectFolder(_ url: URL) {
        selectedFolderURL = url
    }

    func confirmFolderSelection() {
        guard let purpose = activeFolderPicker, let selectedFolderURL else { return }
        guard validateFolderSelection(selectedFolderURL, purpose: purpose) else { return }
        switch purpose {
        case .target:
            preferences.targetPath = selectedFolderURL.path
            if organizerDestinationURL == nil {
                organizerDestinationURL = selectedFolderURL
            }
            savePreferences()
        case .backup:
            preferences.backupEnabled = true
            preferences.backupPath = selectedFolderURL.path
            savePreferences()
        case let .projectBackup(projectID):
            guard let project = copyProjects.first(where: { $0.id == projectID }) else {
                importError = "找不到要修改备份策略的项目。"
                closeFolderPicker()
                return
            }
            if let reason = projectBackupEditBlockReason(project) {
                importError = reason
                closeFolderPicker()
                return
            }
            guard confirmProjectBackupChange(
                title: project.backupRootPath == nil ? "添加项目备份盘" : "更换项目备份盘",
                message: "确认把项目“\(project.name)”的备份盘设置为：\n\(selectedFolderURL.path)\n\n如果项目正在执行，这个修改只会在备份阶段尚未开始时生效。"
            ) else {
                return
            }
            guard applyProjectBackup(projectID: projectID, backupURL: selectedFolderURL) else {
                return
            }
        case .organizerSource:
            organizerSourceURL = selectedFolderURL
            resetOrganizerPlan()
        case .organizerDestination:
            organizerDestinationURL = selectedFolderURL
            resetOrganizerPlan()
        }
        closeFolderPicker()
    }

    func setBackupEnabled(_ enabled: Bool) {
        preferences.backupEnabled = enabled
        if !enabled {
            preferences.backupPath = nil
        }
        savePreferences()
    }

    func canEditBackup(for project: CopyProject) -> Bool {
        projectBackupEditBlockReason(project) == nil
    }

    func openProjectBackupPicker(for project: CopyProject) {
        if let reason = projectBackupEditBlockReason(project) {
            importError = reason
            return
        }
        openFolderPicker(for: .projectBackup(project.id))
    }

    func removeBackup(from project: CopyProject) {
        if let reason = projectBackupEditBlockReason(project) {
            importError = reason
            return
        }
        guard project.backupRootPath != nil else {
            importError = "项目“\(project.name)”当前没有配置备份盘。"
            return
        }
        guard confirmProjectBackupChange(
            title: "取消项目备份",
            message: "确认取消项目“\(project.name)”的备份阶段？\n\n如果项目正在执行，这个修改只会在备份阶段尚未开始时生效。主目标盘拷贝与主盘报告不受影响。"
        ) else {
            return
        }
        _ = applyProjectBackup(projectID: project.id, backupURL: nil)
    }

    private func validateFolderSelection(_ url: URL, purpose: FolderPickerPurpose) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            importError = "所选文件夹已不可访问：\(url.path)"
            return false
        }
        let values = try? url.resourceValues(forKeys: [.isWritableKey, .volumeIsReadOnlyKey])
        let requiresWritableDestination: Bool
        switch purpose {
        case .target, .backup, .projectBackup, .organizerDestination:
            requiresWritableDestination = true
        case .organizerSource:
            requiresWritableDestination = false
        }
        if requiresWritableDestination,
           (values?.volumeIsReadOnly == true || values?.isWritable == false || !FileManager.default.isWritableFile(atPath: url.path)) {
            importError = "所选目标不可写或位于只读卷：\(url.path)"
            return false
        }
        return true
    }

    private func validateImportSummaryStillAvailable(_ summary: ImportSelectionSummary) -> Bool {
        guard FileManager.default.fileExists(atPath: summary.sourceRootURL.path) else {
            importError = "源素材目录已不可访问：\(summary.sourceRootURL.path)"
            return false
        }
        guard validateDestinationURL(summary.targetURL, label: "主目标盘") else {
            return false
        }
        if let backupURL = summary.backupURL,
           !validateDestinationURL(backupURL, label: "备份盘") {
            return false
        }
        return true
    }

    private func validateDestinationURL(_ url: URL, label: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            importError = "\(label) 已不可访问：\(url.path)"
            return false
        }
        let values = try? url.resourceValues(forKeys: [.isWritableKey, .volumeIsReadOnlyKey])
        guard values?.volumeIsReadOnly != true,
              values?.isWritable != false,
              FileManager.default.isWritableFile(atPath: url.path) else {
            importError = "\(label) 不可写或位于只读卷：\(url.path)"
            return false
        }
        return true
    }

    func setInterfaceStyle(_ style: InterfaceStyle) {
        interfaceStyle = style
        saveUISettings()
    }

    func setTheme(_ theme: AppTheme) {
        selectedTheme = theme
        saveUISettings()
    }

    func setLanguage(_ language: AppLanguage) {
        selectedLanguage = language
        saveUISettings()
    }

    func setAutoStartQueuedProjects(_ enabled: Bool) {
        autoStartQueuedProjects = enabled
        saveUISettings()
    }

    var canPresentGettingStarted: Bool {
        !isShowingGettingStarted && !hasActiveFileOperations && !isExportingDiagnostics && !isChoosingDiagnosticsDestination
            && !isChoosingPDFReportDestination && pendingImportVolume == nil
            && activeFolderPicker == nil && importError == nil
    }

    func presentGettingStartedIfNeeded() {
        guard gettingStartedProgress.shouldPresentAutomatically || resumesGettingStartedAfterFolderPicker,
              !isShowingGettingStarted, canPresentGettingStarted else { return }
        resumesGettingStartedAfterFolderPicker = false
        isShowingGettingStarted = true
        saveUISettings()
    }

    func reopenGettingStarted() {
        guard canPresentGettingStarted else { return }
        gettingStartedProgress.lastVisitedStep = GettingStartedStep.welcome.rawValue
        isShowingGettingStarted = true
        saveUISettings()
    }

    func visitGettingStartedStep(_ step: GettingStartedStep) {
        gettingStartedProgress.lastVisitedStep = step.rawValue
        saveUISettings()
    }

    func chooseGettingStartedDestination(backup: Bool) {
        guard isShowingGettingStarted, pendingImportVolume == nil, activeFolderPicker == nil,
              !hasActiveFileOperations else { return }
        resumesGettingStartedAfterFolderPicker = true
        isShowingGettingStarted = false
        if backup { setBackupEnabled(true) }
        openFolderPicker(for: backup ? .backup : .target)
    }

    func dismissGettingStarted() {
        resumesGettingStartedAfterFolderPicker = false
        gettingStartedProgress.completedVersion = max(
            gettingStartedProgress.completedVersion, GettingStartedProgress.currentVersion
        )
        isShowingGettingStarted = false
        saveUISettings()
    }

    private func saveUISettings() {
        do {
            try settingsStore.saveUISettings(
                AppUISettings(
                    theme: selectedTheme,
                    language: selectedLanguage,
                    autoStartQueuedProjects: autoStartQueuedProjects,
                    interfaceStyle: interfaceStyle,
                    gettingStarted: gettingStartedProgress
                )
            )
        } catch {
            importError = "保存界面设置失败：\(error.localizedDescription)"
        }
    }

    func revealReportInFinder(_ report: TransferReport) {
        let primaryURL = URL(fileURLWithPath: report.targetPath, isDirectory: true)
        if FileManager.default.fileExists(atPath: primaryURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([primaryURL])
            return
        }

        if let backupPath = report.backupPath {
            let backupURL = URL(fileURLWithPath: backupPath, isDirectory: true)
            if FileManager.default.fileExists(atPath: backupURL.path) {
                NSWorkspace.shared.activateFileViewerSelecting([backupURL])
                return
            }
        }

        if let reportURL = existingReportDocumentURL(for: report) {
            NSWorkspace.shared.activateFileViewerSelecting([reportURL])
            return
        }

        importError = "找不到目标文件夹或本地备份报告，可能已被删除。"
    }

    func openReportDocument(_ report: TransferReport) {
        if let documentURL = existingReportDocumentURL(for: report) {
            NSWorkspace.shared.open(documentURL)
        } else {
            importError = "找不到拷贝报告。目标报告和 App 本地备份报告都不存在，可能已被手动删除。"
        }
    }

    func exportPDFReport(_ report: TransferReport) {
        guard !isExportingPDFReport, !isChoosingPDFReportDestination else { return }
        guard let source = existingReportDocumentURL(for: report) else {
            importError = localized("找不到原始 TXT 报告，无法导出完整 PDF。")
            return
        }
        isChoosingPDFReportDestination = true
        let panel = NSSavePanel()
        panel.title = localized("导出 PDF 报告")
        panel.message = localized("PDF 包含原始 TXT 的完整明细，请选择新名称以保留已有文件。")
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = ReportPDFExporter.defaultFileName(for: source)
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard let self else { return }
            self.isChoosingPDFReportDestination = false
            guard response == .OK, let destination = panel.url else { return }
            self.beginPDFReportExport(sourceURL: source, to: destination, reportID: report.id)
        }
    }

    func cancelPDFReportExport() {
        pdfReportExportTask?.cancel()
    }

    func beginPDFReportExport(sourceURL: URL, to destination: URL, reportID: UUID) {
        guard !isExportingPDFReport else { return }
        isExportingPDFReport = true
        pdfReportExportID = reportID
        pdfReportExportStatus = localized("正在导出 PDF 报告…")
        let worker = Task.detached(priority: .utility) { () -> Result<Int, any Error> in
            let accessing = destination.startAccessingSecurityScopedResource()
            defer { if accessing { destination.stopAccessingSecurityScopedResource() } }
            do {
                return .success(try ReportPDFExporter.export(sourceURL: sourceURL, to: destination))
            } catch {
                return .failure(error)
            }
        }
        pdfReportExportTask = Task { [weak self] in
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self else { return }
            self.isExportingPDFReport = false
            self.pdfReportExportTask = nil
            switch result {
            case let .success(pages):
                self.pdfReportExportStatus = String(format: self.localized("PDF 报告已导出（%d 页）。"), pages)
            case let .failure(error):
                let detail: String
                if error is CancellationError {
                    detail = self.localized("PDF 导出已取消。")
                } else if let exportError = error as? ReportPDFExporter.ExportError {
                    switch exportError {
                    case .destinationExists: detail = self.localized("已有文件已保留，请选择新名称。")
                    case .invalidDestination: detail = self.localized("请选择可写文件夹中的 PDF 文件。")
                    case .invalidSource: detail = self.localized("找不到有效的原始 TXT 报告。")
                    case .sourceChanged: detail = self.localized("原始 TXT 报告在读取期间发生变化，导出已停止。")
                    case .renderingFailed: detail = self.localized("无法完整生成 PDF 报告。")
                    }
                } else {
                    detail = error.localizedDescription
                }
                self.pdfReportExportStatus = detail
            }
        }
    }

    func exportDiagnostics() {
        guard !isExportingDiagnostics, !isChoosingDiagnosticsDestination else { return }
        isChoosingDiagnosticsDestination = true
        let panel = NSSavePanel()
        panel.title = localized("导出诊断")
        panel.message = localized("请选择新名称以保留已有诊断文件。")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = SupportDiagnosticsExporter.defaultFileName()
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard let self else { return }
            self.isChoosingDiagnosticsDestination = false
            guard response == .OK, let url = panel.url else { return }
            self.beginDiagnosticsExport(to: url)
        }
    }

    func cancelDiagnosticsExport() {
        diagnosticsExportTask?.cancel()
    }

    private func beginDiagnosticsExport(to url: URL) {
        guard !isExportingDiagnostics else { return }
        let projects = copyProjects
        let history = reports
        var activity = SupportDiagnosticsSnapshot.Activity()
        activity.language = selectedLanguage.rawValue
        activity.theme = selectedTheme.rawValue
        activity.executionMode = executionMode.rawValue
        activity.selectedVerificationMode = selectedVerificationMode.rawValue
        activity.backupEnabled = preferences.backupEnabled
        activity.scanning = isScanning
        activity.importing = isImporting
        activity.organizing = isRunningOrganizer
        activity.activeProjectCount = activeProjectIDs.count
        activity.unsavedChanges = hasUnsavedChanges
        activity.errorCategory = .classify(importError)
        let capturedActivity = activity
        isExportingDiagnostics = true
        diagnosticsExportStatus = localized("正在导出诊断…")
        let worker = Task.detached(priority: .utility) { () -> Result<Void, any Error> in
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            do {
                let snapshot = SupportDiagnosticsSnapshot.capture(projects: projects, reports: history, activity: capturedActivity)
                try SupportDiagnosticsExporter.write(snapshot, to: url)
                return .success(())
            } catch {
                return .failure(error)
            }
        }
        diagnosticsExportTask = Task { [weak self] in
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self else { return }
            self.isExportingDiagnostics = false
            self.diagnosticsExportTask = nil
            switch result {
            case .success:
                self.diagnosticsExportStatus = self.localized("已导出诊断，可先检查文件再提供给支持人员。")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            case .failure(let error):
                if error is CancellationError {
                    self.diagnosticsExportStatus = self.localized("诊断导出已取消")
                } else {
                    let detail: String
                    if let exportError = error as? SupportDiagnosticsExporter.ExportError {
                        switch exportError {
                        case .destinationExists: detail = self.localized("已有文件已保留，请选择新名称。")
                        case .invalidDestination: detail = self.localized("请选择可写文件夹中的 JSON 文件。")
                        }
                    } else {
                        detail = error.localizedDescription
                    }
                    self.diagnosticsExportStatus = self.localized("诊断导出失败") + ": " + detail
                }
            }
        }
    }

    func refreshVolumes() {
        volumeMonitor.refreshVolumes()
        mountedVolumes = volumeMonitor.volumes
        if activeFolderPicker != nil {
            folderRoots = makeFolderRoots()
        }
    }

    func prepareImport(for volume: StorageVolume) {
        cancelActiveScan()
        pendingImportVolume = volume
        scannedItems = []
        timeGroups = []
        selectedItemIDs = []
        hasScannedSource = false
        sourceFolderURL = volume.url
        loadSourceFolderChildrenAsync(for: volume.url)
    }

    func closeImportSheet() {
        cancelActiveScan()
        sourceFolderChildrenTask?.cancel()
        sourceFolderChildrenTask = nil
        pendingImportVolume = nil
        scannedItems = []
        timeGroups = []
        selectedItemIDs = []
        isScanning = false
        hasScannedSource = false
        sourceFolderURL = nil
        sourceFolderChildren = []
        isLoadingSourceFolderChildren = false
    }

    func setScanFilter(_ filter: ScanFilter) {
        cancelActiveScan()
        selectedScanFilter = filter
        hasScannedSource = false
        scannedItems = []
        timeGroups = []
        selectedItemIDs = []
    }

    func navigateSourceFolder(to url: URL) {
        cancelActiveScan()
        sourceFolderURL = url
        loadSourceFolderChildrenAsync(for: url)
        hasScannedSource = false
        scannedItems = []
        timeGroups = []
        selectedItemIDs = []
    }

    func returnToSourceFolderSelection() {
        cancelActiveScan()
        hasScannedSource = false
        scannedItems = []
        timeGroups = []
        selectedItemIDs = []
        if let sourceFolderURL {
            loadSourceFolderChildrenAsync(for: sourceFolderURL)
        }
    }

    func navigateSourceFolderUp() {
        guard let sourceFolderURL else { return }
        let parent = sourceFolderURL.deletingLastPathComponent()
        guard parent.path != sourceFolderURL.path else { return }
        navigateSourceFolder(to: parent)
    }

    func scanSelectedSourceFolder() {
        guard let pendingImportVolume, let sourceFolderURL else { return }
        cancelActiveScan(clearLoadingState: false)
        let sessionID = UUID()
        scanSessionID = sessionID
        isScanning = true
        importError = nil

        let scanner = self.scanner
        let volume = pendingImportVolume
        let rootURL = sourceFolderURL
        let filter = selectedScanFilter

        scanTask = Task.detached(priority: .userInitiated) { [scanner, volume, rootURL, filter, sessionID] in
            do {
                let items = try scanner.scan(volume: volume, rootURL: rootURL, filter: filter)
                let groups = scanner.makeTimeGroups(items: items)
                try Task.checkCancellation()

                await MainActor.run { [weak self] in
                    guard let self,
                          self.scanSessionID == sessionID,
                          self.pendingImportVolume?.id == volume.id,
                          self.sourceFolderURL?.path == rootURL.path else {
                        return
                    }
                    self.scannedItems = items
                    self.timeGroups = groups
                    self.selectedItemIDs = Set(items.map(\.id))
                    self.hasScannedSource = true
                    self.isScanning = false
                    self.scanTask = nil
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self, self.scanSessionID == sessionID else { return }
                    self.isScanning = false
                    self.scanTask = nil
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.scanSessionID == sessionID else { return }
                    self.importError = "扫描素材失败：\(error.localizedDescription)"
                    self.isScanning = false
                    self.scanTask = nil
                }
            }
        }
    }

    func toggle(group: TimeGroup) {
        let groupIDs = Set(group.items.flatMap { relatedItemIDs(for: $0) })
        if groupIDs.isSubset(of: selectedItemIDs) {
            selectedItemIDs.subtract(groupIDs)
        } else {
            selectedItemIDs.formUnion(groupIDs)
        }
    }

    func toggle(item: MediaItem) {
        let relatedIDs = relatedItemIDs(for: item)
        if relatedIDs.isSubset(of: selectedItemIDs) {
            selectedItemIDs.subtract(relatedIDs)
        } else {
            selectedItemIDs.formUnion(relatedIDs)
        }
    }

    func selectAllScannedItems() {
        selectedItemIDs = Set(scannedItems.map(\.id))
    }

    func clearScannedSelection() {
        selectedItemIDs = []
    }

    func startImport() {
        guard let summary = selectionSummary else { return }
        guard destinationWarnings.isEmpty else {
            importError = destinationWarnings.joined(separator: "\n")
            return
        }
        guard validateImportSummaryStillAvailable(summary) else { return }

        let createdAt = Date()
        let rawName: String
        switch projectNameMode {
        case .automatic:
            rawName = automaticProjectName(sourceName: summary.sourceVolume.name, date: createdAt)
        case .custom:
            let cleaned = draftProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
            rawName = cleaned.isEmpty ? automaticProjectName(sourceName: summary.sourceVolume.name, date: createdAt) : cleaned
        }
        let projectID = UUID()
        let shortID = String(projectID.uuidString.prefix(8).lowercased())
        let taskFolderName = FileNameSanitizer.safeComponent(rawName, fallback: automaticProjectName(sourceName: summary.sourceVolume.name, date: createdAt)) + "_" + shortID
        let autoStartDeadline = autoStartQueuedProjects
            ? createdAt.addingTimeInterval(Self.projectAutoStartDelay)
            : nil
        let project = CopyProject(
            id: projectID,
            name: rawName,
            taskFolderName: taskFolderName,
            createdAt: createdAt,
            updatedAt: createdAt,
            sourceName: summary.sourceVolume.name,
            sourceVolumePath: summary.sourceVolume.url.path,
            sourceRootPath: summary.sourceRootURL.path,
            targetRootPath: summary.targetURL.path,
            backupRootPath: summary.backupURL?.path,
            selectedItems: summary.selectedItems.map(ProjectMediaItem.init(mediaItem:)),
            totalBytes: summary.totalSize,
            verificationMode: selectedVerificationMode,
            orderIndex: nextProjectOrderIndex(),
            autoStartEnabled: autoStartQueuedProjects,
            autoStartDeadline: autoStartDeadline
        )
        let previousProjects = copyProjects
        copyProjects.append(project)
        normalizeProjectOrder()
        guard saveProjects() else {
            copyProjects = previousProjects
            importError = "项目“\(project.name)”未能保存，已取消加入队列。请处理保存错误后重试。"
            return
        }
        closeImportSheet()
        selectedSection = .copy
        scheduleNextAutoStartCheck()
        if let autoStartDeadline {
            importError = "已创建项目“\(project.name)”并加入任务队列。5 分钟内可取消自动执行，超时会自动开始写盘。预计启动：\(shortTimeText(autoStartDeadline))。"
        } else {
            importError = "已创建项目“\(project.name)”并加入任务队列。自动执行已在设置中关闭，需要手动点击“执行任务队列”才会开始写盘。"
        }
    }

    func startQueue() {
        guard !hasUnsavedChanges else {
            importError = "项目队列有未保存变更。请先重试保存，避免执行状态丢失。"
            return
        }
        guard orderedProjects.contains(where: { $0.status == .queued }) else {
            importError = "当前没有排队中的项目。"
            return
        }
        manualQueueRunActive = true
        clearAutoStartForQueuedProjects()
        scheduleQueuedProjects()
        scheduleNextAutoStartCheck()
    }

    func retrySavingPendingChanges() {
        var messages: [String] = []
        if projectsNeedSave, saveProjects() {
            messages.append("项目队列已保存")
        }
        if reportsNeedSave, saveReports() {
            messages.append("任务日志已保存")
        }
        if statisticsIndexNeedSave, saveStatisticsIndex() {
            messages.append("统计索引已保存")
        }
        if !hasUnsavedChanges, !messages.isEmpty {
            importError = messages.joined(separator: "，") + "。"
        }
    }

    func refreshCopyStatistics() {
        rebuildCopyStatistics()
    }

    func setOrganizerScanFilter(_ filter: ScanFilter) {
        guard organizerScanFilter != filter else { return }
        organizerScanFilter = filter
        resetOrganizerPlan()
    }

    func setOrganizerOperationMode(_ mode: OrganizerOperationMode) {
        guard organizerOperationMode != mode else { return }
        organizerOperationMode = mode
        resetOrganizerPlan()
    }

    func setOrganizerDuplicatePolicy(_ policy: OrganizerDuplicatePolicy) {
        guard organizerDuplicatePolicy != policy else { return }
        organizerDuplicatePolicy = policy
        resetOrganizerPlan()
    }

    func buildOrganizerPlan() {
        guard let sourceURL = organizerSourceURL,
              let destinationURL = organizerDestinationURL else {
            importError = "请先选择待规整文件夹和规整目标文件夹。"
            return
        }
        let blockingWarnings = organizerWarnings.filter { !$0.contains("导入或备份任务") }
        guard blockingWarnings.isEmpty else {
            importError = blockingWarnings.joined(separator: "\n")
            return
        }

        organizerPlanTask?.cancel()
        let generation = UUID()
        organizerPlanGeneration = generation
        isBuildingOrganizerPlan = true
        organizerStatusMessage = "正在扫描并生成规整预览..."
        organizerPlan = nil
        organizerLastSummary = nil
        organizerExecutionState = OrganizerExecutionState()
        let rule = organizerRule

        organizerPlanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let plan = try await organizerService.makePlan(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    rule: rule,
                    progress: { [weak self] progress in
                        Task { @MainActor [weak self] in
                            guard let self, self.organizerPlanGeneration == generation, self.isBuildingOrganizerPlan else { return }
                            self.organizerStatusMessage = progress.message
                        }
                    }
                )
                try Task.checkCancellation()
                await MainActor.run { [weak self] in
                    guard let self, self.organizerPlanGeneration == generation else { return }
                    self.organizerPlan = plan
                    self.isBuildingOrganizerPlan = false
                    self.organizerPlanTask = nil
                    var message = "已生成预览：\(plan.executableFiles) 个可执行文件，\(ByteDisplayFormatter.string(fromByteCount: plan.totalBytes))。"
                    if plan.duplicateFiles > 0 {
                        message += "查重命中 \(plan.duplicateFiles) 个内容重复文件，将跳过。"
                    }
                    self.organizerStatusMessage = message
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self, self.organizerPlanGeneration == generation else { return }
                    self.isBuildingOrganizerPlan = false
                    self.organizerPlanTask = nil
                    self.organizerStatusMessage = "已取消生成预览。"
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.organizerPlanGeneration == generation else { return }
                    self.isBuildingOrganizerPlan = false
                    self.organizerPlanTask = nil
                    self.organizerStatusMessage = nil
                    self.importError = "生成规整预览失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func startOrganizerExecution() {
        guard !isRunningOrganizer else { return }
        guard let plan = organizerPlan else {
            importError = "请先生成规整预览。"
            return
        }
        guard organizerWarnings.isEmpty else {
            importError = organizerWarnings.joined(separator: "\n")
            return
        }
        guard plan.executableFiles > 0 else {
            importError = "当前预览没有可执行文件。"
            return
        }

        organizerExecutionTask?.cancel()
        isRunningOrganizer = true
        organizerLastSummary = nil
        organizerStatusMessage = plan.rule.operationMode == .copy ? "正在复制规整..." : "正在移动规整..."

        organizerExecutionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await organizerService.execute(plan: plan) { [weak self] state in
                    await MainActor.run { [weak self] in
                        self?.organizerExecutionState = state
                    }
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isRunningOrganizer = false
                    self.organizerExecutionTask = nil
                    self.organizerLastSummary = summary
                    var message = summary.success
                        ? "规整完成：\(summary.completedFiles) 个文件已处理。"
                        : "规整完成：\(summary.completedFiles) 个文件已处理，\(summary.failedFiles.count) 个失败。"
                    if summary.duplicateFiles > 0 {
                        message += "查重跳过 \(summary.duplicateFiles) 个内容重复文件。"
                    }
                    self.organizerStatusMessage = message
                    self.organizerPlan = nil
                }
            } catch is CancellationError {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isRunningOrganizer = false
                    self.organizerExecutionTask = nil
                    self.organizerExecutionState.isActive = false
                    self.organizerExecutionState.phaseTitle = "已取消规整"
                    self.organizerStatusMessage = "已取消规整。"
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isRunningOrganizer = false
                    self.organizerExecutionTask = nil
                    self.organizerExecutionState.isActive = false
                    self.organizerStatusMessage = nil
                    self.importError = "规整执行失败：\(error.localizedDescription)"
                }
            }
        }
    }

    func cancelOrganizerExecution() {
        if isBuildingOrganizerPlan {
            organizerPlanTask?.cancel()
        }
        if isRunningOrganizer {
            organizerExecutionTask?.cancel()
        }
    }

    private func resetOrganizerPlan() {
        organizerPlanGeneration = UUID()
        organizerPlanTask?.cancel()
        organizerPlanTask = nil
        organizerPlan = nil
        organizerLastSummary = nil
        organizerStatusMessage = nil
        organizerPreviewFilter = .all
        if isBuildingOrganizerPlan {
            isBuildingOrganizerPlan = false
        }
        if !isRunningOrganizer {
            organizerExecutionState = OrganizerExecutionState()
        }
    }

    private func startStatisticsRefreshTimer() {
        statisticsRefreshTask?.cancel()
        statisticsRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let nanoseconds = UInt64(Self.statisticsRefreshInterval * 1_000_000_000)
                do {
                    try await Task.sleep(nanoseconds: nanoseconds)
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                self?.rebuildCopyStatistics()
            }
        }
    }

    private func rebuildCopyStatistics(now: Date = Date()) {
        statisticsRevision &+= 1
        // 同一时间只运行一份统计计算；期间的新报告合并为下一次请求。
        guard statisticsBuildTask == nil else { return }
        let revision = statisticsRevision
        let reportsSnapshot = reports
        let projectsSnapshot = orderedProjects
        let indexSnapshot = copyStatisticsIndex
        let calendar = Calendar.current
        isRefreshingStatistics = true
        statisticsBuildTask = Task { [weak self] in
            let worker = Task.detached(priority: .utility) {
                let needsRebuild = !indexSnapshot.matches(reports: reportsSnapshot, calendar: calendar, now: now)
                let index = needsRebuild
                    ? CopyStatisticsIndex.make(reports: reportsSnapshot, calendar: calendar, now: now)
                    : indexSnapshot
                let summary = index.summary(projects: projectsSnapshot, calendar: calendar, now: now)
                let heatmaps = CopyStatisticsHeatmaps.make(days: summary.days, calendar: calendar)
                return (index, summary, heatmaps, needsRebuild)
            }
            let (index, summary, heatmaps, needsRebuild) = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard let self, !Task.isCancelled else { return }
            self.statisticsBuildTask = nil
            guard self.statisticsRevision == revision else {
                self.rebuildCopyStatistics()
                return
            }
            self.copyStatisticsIndex = index
            if needsRebuild { self.saveStatisticsIndex() }
            if self.copyStatistics != summary { self.copyStatistics = summary }
            if self.copyStatisticsHeatmaps != heatmaps { self.copyStatisticsHeatmaps = heatmaps }
            // 同 ID 的报告内容也可能变化，不能仅通过 ID 判断是否刷新。
            self.statisticsRecentReports = Array(reportsSnapshot.prefix(8))
            self.statisticsRefreshedAt = now
            self.isRefreshingStatistics = false
        }
    }

    private func recordFinishedReport(_ report: TransferReport) {
        reports.insert(report, at: 0)
        saveReports()
        copyStatisticsIndex.add(report)
        saveStatisticsIndex()
        rebuildCopyStatistics()
    }

    func cancelProject(_ project: CopyProject) {
        guard let currentProject = copyProjects.first(where: { $0.id == project.id }) else { return }
        if currentProject.status == .cancelling {
            importError = "项目“\(currentProject.name)”已经在取消收尾中，请等待报告生成完成。"
            return
        }
        guard activeProjectIDs.contains(project.id) else {
            importError = "项目“\(currentProject.name)”当前没有正在执行的任务。"
            return
        }

        projectTokens[project.id]?.stop(reason: "用户取消了导入任务")
        projectTasks[project.id]?.cancel()
        updateProject(project.id) { item in
            item.status = .cancelling
            item.errorMessage = "正在取消，等待当前文件操作结束并生成报告。"
            if item.primaryCopyState.isActive {
                item.primaryCopyState.detail = "正在取消，等待当前写入完成"
            }
            if item.primaryVerifyState.isActive {
                item.primaryVerifyState.detail = "正在取消，等待当前校验完成"
            }
            if item.backupCopyState.isActive {
                item.backupCopyState.detail = "正在取消，等待当前备份写入完成"
            }
            if item.backupVerifyState.isActive {
                item.backupVerifyState.detail = "正在取消，等待当前备份校验完成"
            }
        }
    }

    func deleteProject(_ project: CopyProject) {
        if activeProjectIDs.contains(project.id) {
            if project.status != .cancelling {
                cancelProject(project)
            }
            pendingDeleteProjectIDs.insert(project.id)
            importError = "项目“\(project.name)”正在执行，已先进入取消收尾，收尾完成后将自动删除。"
            saveProjects()
            updateGlobalImportFlag()
            return
        }
        if project.status == .running || project.status == .cancelling {
            importError = "项目“\(project.name)”仍处于运行状态，请先取消并等待收尾完成后再删除。"
            return
        }
        copyProjects.removeAll { $0.id == project.id }
        projectTasks[project.id] = nil
        projectTokens[project.id] = nil
        activeProjectIDs.remove(project.id)
        normalizeProjectOrder()
        saveProjects()
        updateGlobalImportFlag()
    }

    func retryProject(_ project: CopyProject) {
        guard !activeProjectIDs.contains(project.id), project.status != .running, project.status != .cancelling else {
            importError = "项目“\(project.name)”仍在执行或取消收尾，完成后才能重试。"
            return
        }

        updateProject(project.id) { item in
            item.prepareForRetry()
        }
        scheduleNextAutoStartCheck()
        selectedSection = .copy
        importError = "已将项目“\(project.name)”重新加入任务队列。已有文件会完整复核 SHA-256，缺失文件会补拷，内容不一致的文件将保留并报告异常。需要手动点击“执行任务队列”才会开始。"
    }

    func canRetryBackup(for project: CopyProject) -> Bool {
        guard let current = copyProjects.first(where: { $0.id == project.id }),
              !activeProjectIDs.contains(current.id), current.canPrepareBackupRetry,
              let report = primaryReferenceReport(for: current) else { return false }
        return report.success && !report.cancelled && !report.reportDocumentWriteFailed
            && report.fileRecords.count == current.selectedItems.count
    }

    private func primaryReferenceReport(for project: CopyProject) -> TransferReport? {
        if let reference = project.primaryCompletionReference { return reference.report }
        return reports.first(where: { $0.id == project.primaryReportID })
    }

    func retryBackupProject(_ project: CopyProject) {
        guard canRetryBackup(for: project), let current = copyProjects.first(where: { $0.id == project.id }) else {
            importError = localized("主盘完成记录不足，或项目仍在执行，无法独立重试备份。")
            return
        }
        do {
            _ = try TransferService.backupRetryReference(
                project: current, report: primaryReferenceReport(for: current)
            )
        } catch {
            importError = localized("无法独立重试备份") + ": " + error.localizedDescription
            return
        }
        updateProject(current.id) { item in item.prepareForBackupRetry() }
        scheduleNextAutoStartCheck()
        selectedSection = .copy
        let executionNote = manualQueueRunActive
            ? localized("当前手动队列会继续执行此项目。")
            : localized("请手动执行任务队列。")
        importError = String(format: localized("项目“%@”已加入独立备份重试队列。主盘完成状态和原报告已保留，已有备份文件会完整复核 SHA-256。"), current.name)
            + " " + executionNote
    }

    func cancelAutoStart(for project: CopyProject) {
        guard project.status == .queued else {
            importError = "项目“\(project.name)”已经不在排队状态，无法取消自动执行。"
            return
        }
        guard project.autoStartEnabled || project.autoStartDeadline != nil else {
            importError = "项目“\(project.name)”没有启用自动执行。"
            return
        }
        updateProject(project.id) { item in
            item.autoStartEnabled = false
            item.autoStartDeadline = nil
        }
        scheduleNextAutoStartCheck()
        importError = "已取消项目“\(project.name)”的 5 分钟自动执行。仍可手动执行任务队列。"
    }

    func moveProjectUp(_ project: CopyProject) {
        var ordered = orderedProjects
        guard let index = ordered.firstIndex(where: { $0.id == project.id }) else { return }
        // 已完成项目在队列里被隐藏,但仍存在于 orderedProjects 中。
        // 与上一个"可见"(未完成)邻居交换,保证 ↑ 始终相对队列里看得见的相邻项移动,
        // 不会和被隐藏的完成项做无效空交换。
        guard let targetIndex = ordered[..<index].lastIndex(where: { $0.status != .completed }) else { return }
        ordered.swapAt(index, targetIndex)
        applyProjectOrder(ordered)
    }

    func moveProjectDown(_ project: CopyProject) {
        var ordered = orderedProjects
        guard let index = ordered.firstIndex(where: { $0.id == project.id }) else { return }
        // 与下一个"可见"(未完成)邻居交换,跨过被隐藏的已完成项目。
        let after = ordered.index(after: index)
        guard after < ordered.endIndex,
              let targetIndex = ordered[after...].firstIndex(where: { $0.status != .completed }) else { return }
        ordered.swapAt(index, targetIndex)
        applyProjectOrder(ordered)
    }

    func renameProject(_ project: CopyProject, to name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        updateProject(project.id) { item in
            item.name = cleaned
            if item.status == .queued, !item.backupOnlyRetry {
                let shortID = String(item.id.uuidString.prefix(8).lowercased())
                item.taskFolderName = FileNameSanitizer.safeComponent(cleaned) + "_" + shortID
            }
        }
    }

    func promptRenameProject(_ project: CopyProject) {
        guard project.status != .running, project.status != .cancelling else {
            importError = "运行或取消收尾中的项目不能改名，请等待任务结束。"
            return
        }

        let alert = NSAlert()
        alert.messageText = "修改项目名称"
        alert.informativeText = project.backupOnlyRetry
            ? localized("独立备份重试只修改显示名称与后续报告标题，已有主盘文件夹保持不变。")
            : "名称会用于队列显示、报告标题；排队中的项目还会同步更新目标文件夹名。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        textField.stringValue = project.name
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        renameProject(project, to: textField.stringValue)
    }

    func requestSkipVerification(for project: CopyProject) {
        guard project.status == .queued || project.status == .running else { return }
        updateProject(project.id) { item in
            item.skipVerificationConfirmations += 1
            switch item.skipVerificationConfirmations {
            case 1:
                importError = "第一次确认：跳过校验会让报告标记为“未确认完整性”。如果确实需要，请再点一次。"
            case 2:
                importError = "第二次确认：这会跳过当前项目后续校验。再点第三次才会真正生效。"
            default:
                item.verificationMode = .skipped
                item.skipVerificationConfirmations = 0
                projectTokens[project.id]?.overrideVerificationMode(.skipped)
                importError = "项目“\(item.name)”后续校验已设置为跳过，报告会明确标记风险。"
            }
        }
    }

    func openProjectReport(_ project: CopyProject, stage: TransferService.ProjectTransferStage) {
        let reportID = stage == .primary ? project.primaryReportID : project.backupReportID
        guard let reportID,
              let report = reports.first(where: { $0.id == reportID }) else {
            importError = "这个项目还没有生成\(stage == .primary ? "主盘" : "备份")报告。"
            return
        }
        openReportDocument(report)
    }

    func canOpenProjectReport(_ project: CopyProject, stage: TransferService.ProjectTransferStage) -> Bool {
        let reportID = stage == .primary ? project.primaryReportID : project.backupReportID
        guard let reportID else { return false }
        return reports.contains { $0.id == reportID }
    }

    func revealProjectOutput(_ project: CopyProject, stage: TransferService.ProjectTransferStage = .primary) {
        let url = stage == .backup ? (project.backupImportURL ?? project.primaryImportURL) : project.primaryImportURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }
        importError = "找不到项目输出文件夹：\(url.path)"
    }

    private func scheduleQueuedProjects(automaticOnlyAt now: Date? = nil) {
        // Only block on unsaved *project* state; a stale report file must not freeze the queue.
        guard !projectsNeedSave else {
            updateGlobalImportFlag()
            return
        }
        let availableSlots = max(executionMode.maximumConcurrentProjects - activeProjectIDs.count, 0)
        guard availableSlots > 0 else {
            updateGlobalImportFlag()
            return
        }

        let queued = orderedProjects.filter { project in
            guard project.status == .queued else { return false }
            if let now {
                return project.isAutoStartReady(at: now)
            }
            return true
        }
        var launched = 0
        for project in queued where launched < availableSlots {
            guard canRunAlongsideActiveProjects(project) else { continue }
            launchProject(project)
            launched += 1
        }
        if manualQueueRunActive,
           activeProjectIDs.isEmpty,
           !orderedProjects.contains(where: { $0.status == .queued }) {
            manualQueueRunActive = false
        }
        updateGlobalImportFlag()
    }

    private func launchProject(_ project: CopyProject) {
        guard projectTasks[project.id] == nil else { return }
        let token = ImportInterruptionToken()
        token.reset()
        projectTokens[project.id] = token
        activeProjectIDs.insert(project.id)
        updateProject(project.id) { item in
            item.status = .running
            item.errorMessage = nil
            item.autoStartEnabled = false
            item.autoStartDeadline = nil
            item.updatedAt = Date()
        }

        projectTasks[project.id] = Task { [weak self, projectID = project.id, token] in
            guard let self else { return }
            await self.runQueuedProject(projectID: projectID, token: token)
        }
        updateGlobalImportFlag()
    }

    private func runQueuedProject(projectID: UUID, token: ImportInterruptionToken) async {
        guard let primaryProject = copyProjects.first(where: { $0.id == projectID }) else { return }

        // 每阶段一个合并器:文件边界的进度发布不经节流直达这里,
        // 小文件批次下必须在汇聚点按时间合并(见 TransferProgressCoalescer)。
        let primaryProgress = TransferProgressCoalescer { [weak self] state in
            self?.applyProgress(state, to: projectID, stage: .primary)
        }
        var backupProgress: TransferProgressCoalescer?

        do {
            var primaryResult: TransferService.ProjectStageResult?
            if !primaryProject.backupOnlyRetry {
                let result = try await transferService.runPrimaryStage(
                    project: primaryProject,
                    interruptionToken: token,
                    language: selectedLanguage
                ) { state in
                    await MainActor.run {
                        primaryProgress.ingest(state)
                    }
                }
                primaryResult = result
                primaryProgress.cancelPending()
                finishPrimaryStage(projectID: projectID, result: result)
            }

            guard let currentProject = copyProjects.first(where: { $0.id == projectID }) else {
                finishProjectTask(projectID)
                return
            }
            if currentProject.status == .cancelling {
                updateProject(projectID) { item in
                    item.status = .cancelled
                    item.errorMessage = item.backupOnlyRetry
                        ? localized("独立备份重试已取消，主盘完成状态已保留。")
                        : "用户取消了导入任务，主盘阶段已收尾，后续阶段未执行。"
                }
                finishProjectTask(projectID)
                return
            }
            guard currentProject.status == .running else {
                finishProjectTask(projectID)
                return
            }

            if let primaryResult, !primaryResult.report.success {
                updateProject(projectID) { item in
                    if item.hasBackup {
                        item.status = .blocked
                        item.errorMessage = "\(primaryResult.report.verificationSummary) 备份已阻塞，请查看第一份主盘报告后重试。"
                        item.backupCopyState.isBlocked = true
                        item.backupCopyState.detail = "主盘异常，备份已阻塞"
                        item.backupVerifyState.isBlocked = true
                        item.backupVerifyState.detail = "主盘异常，备份已阻塞"
                    } else {
                        item.status = .failed
                        item.errorMessage = primaryResult.report.verificationSummary
                        item.backupCopyState.detail = "未配置备份盘"
                        item.backupVerifyState.detail = "未配置备份盘"
                    }
                }
                finishProjectTask(projectID)
                return
            }

            guard currentProject.hasBackup else {
                updateProject(projectID) { item in
                    item.status = .completed
                    item.errorMessage = nil
                }
                finishProjectTask(projectID)
                return
            }

            let backupCoalescer = TransferProgressCoalescer { [weak self] state in
                self?.applyProgress(state, to: projectID, stage: .backup)
            }
            backupProgress = backupCoalescer

            let backupResult = try await transferService.runBackupStage(
                project: currentProject,
                primaryReferenceReport: currentProject.backupOnlyRetry
                    ? primaryReferenceReport(for: currentProject) : nil,
                interruptionToken: token,
                language: selectedLanguage
            ) { state in
                await MainActor.run {
                    backupCoalescer.ingest(state)
                }
            }
            backupCoalescer.cancelPending()
            finishBackupStage(projectID: projectID, result: backupResult)
        } catch is CancellationError {
            // Use the token's stop reason when available (e.g. device disconnect),
            // otherwise fall back to the generic user-cancel message.
            primaryProgress.cancelPending()
            backupProgress?.cancelPending()
            let cancelReason = projectTokens[projectID]?.reason ?? "用户取消了导入任务"
            updateProject(projectID) { item in
                item.status = .cancelled
                item.errorMessage = cancelReason
            }
        } catch {
            primaryProgress.cancelPending()
            backupProgress?.cancelPending()
            updateProject(projectID) { item in
                item.status = .failed
                item.errorMessage = error.localizedDescription
            }
            importError = "项目执行失败：\(error.localizedDescription)"
        }

        finishProjectTask(projectID)
    }

    private func finishPrimaryStage(projectID: UUID, result: TransferService.ProjectStageResult) {
        recordFinishedReport(result.report)

        updateProject(projectID) { item in
            item.primaryReportID = result.report.id
            item.primaryCompletionReference = result.report.success
                ? PrimaryCompletionReference(report: result.report) : nil
            item.primaryCopyState.isActive = false
            item.primaryCopyState.isComplete = result.finalState.copiedFiles >= result.finalState.totalFiles
                && result.finalState.copyFailedFiles.isEmpty
            item.primaryCopyState.finishedAt = Date()
            item.primaryVerifyState.isActive = false
            item.primaryVerifyState.isComplete = result.report.success
            item.primaryVerifyState.finishedAt = Date()
            item.primaryVerifyState.reportDocumentPath = result.report.reportDocumentPath
            item.primaryVerifyState.localReportDocumentPath = result.report.localReportDocumentPath
            if result.report.cancelled || item.status == .cancelling {
                item.status = .cancelled
                item.errorMessage = "用户取消了导入任务，已生成取消报告。"
            } else {
                item.errorMessage = result.report.success ? nil : result.report.verificationSummary
            }
        }
    }

    private func finishBackupStage(projectID: UUID, result: TransferService.ProjectStageResult) {
        recordFinishedReport(result.report)

        updateProject(projectID) { item in
            item.backupReportID = result.report.id
            item.backupCopyState.isActive = false
            item.backupCopyState.isComplete = result.finalState.copiedFiles >= result.finalState.totalFiles
                && result.finalState.copyFailedFiles.isEmpty
            item.backupCopyState.finishedAt = Date()
            item.backupVerifyState.isActive = false
            item.backupVerifyState.isComplete = result.report.success
            item.backupVerifyState.finishedAt = Date()
            item.backupVerifyState.reportDocumentPath = result.report.reportDocumentPath
            item.backupVerifyState.localReportDocumentPath = result.report.localReportDocumentPath
            if result.report.cancelled || item.status == .cancelling {
                item.status = .cancelled
                item.errorMessage = "用户取消了导入任务，已生成取消报告。"
            } else {
                item.status = result.report.success ? .completed : .failed
                item.errorMessage = result.report.success ? nil : result.report.verificationSummary
            }
        }
    }

    private func finishProjectTask(_ projectID: UUID) {
        projectTasks[projectID] = nil
        projectTokens[projectID] = nil
        activeProjectIDs.remove(projectID)
        if pendingDeleteProjectIDs.contains(projectID) {
            pendingDeleteProjectIDs.remove(projectID)
            copyProjects.removeAll { $0.id == projectID }
            normalizeProjectOrder()
        }
        updateGlobalImportFlag()
        saveProjects()
        continueQueueAfterStateChange()
    }

    private func continueQueueAfterStateChange() {
        if manualQueueRunActive {
            scheduleQueuedProjects()
        } else {
            scheduleQueuedProjects(automaticOnlyAt: Date())
        }
        scheduleNextAutoStartCheck()
    }

    private func scheduleNextAutoStartCheck() {
        autoStartTask?.cancel()
        autoStartTask = nil

        guard !projectsNeedSave else { return }

        let now = Date()
        let candidates = orderedProjects
            .filter { $0.status == .queued && $0.autoStartEnabled && $0.autoStartDeadline != nil }

        guard let earliestDeadline = candidates.compactMap(\.autoStartDeadline).min() else { return }

        let availableSlots = max(executionMode.maximumConcurrentProjects - activeProjectIDs.count, 0)
        if earliestDeadline <= now, availableSlots > 0 {
            scheduleQueuedProjects(automaticOnlyAt: now)
            return
        }

        let delay = max(earliestDeadline.timeIntervalSince(now), 0.5)
        autoStartTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            // Always pass the current time so the auto-start deadline filter is enforced,
            // even when a manual queue run is also active.
            self?.scheduleQueuedProjects(automaticOnlyAt: Date())
            self?.scheduleNextAutoStartCheck()
        }
    }

    private func clearAutoStartForQueuedProjects() {
        var changed = false
        for index in copyProjects.indices where copyProjects[index].status == .queued {
            if copyProjects[index].autoStartEnabled || copyProjects[index].autoStartDeadline != nil {
                copyProjects[index].autoStartEnabled = false
                copyProjects[index].autoStartDeadline = nil
                copyProjects[index].updatedAt = Date()
                changed = true
            }
        }
        if changed {
            saveProjects()
        }
    }

    private func applyProgress(_ state: TransferState, to projectID: UUID, stage: TransferService.ProjectTransferStage) {
        updateProject(projectID, saveImmediately: false) { item in
            item.updatedAt = Date()
            if item.status != .cancelling {
                item.status = .running
            }

            if state.verificationStartedAt == nil {
                let stageState = makeCopyStageState(from: state, title: stage == .primary ? ProjectStageKind.primaryCopy.title : ProjectStageKind.backupCopy.title)
                if stage == .primary {
                    item.primaryCopyState = stageState
                    item.primaryVerifyState.detail = "等待主盘拷贝完成"
                } else {
                    item.backupCopyState = stageState
                    item.backupVerifyState.detail = "等待备份拷贝完成"
                }
            } else {
                let stageState = makeVerificationStageState(from: state, title: stage == .primary ? ProjectStageKind.primaryVerify.title : ProjectStageKind.backupVerify.title)
                if stage == .primary {
                    item.primaryCopyState.isActive = false
                    item.primaryCopyState.isComplete = state.copiedFiles >= state.totalFiles && state.copyFailedFiles.isEmpty
                    item.primaryVerifyState = stageState
                } else {
                    item.backupCopyState.isActive = false
                    item.backupCopyState.isComplete = state.copiedFiles >= state.totalFiles && state.copyFailedFiles.isEmpty
                    item.backupVerifyState = stageState
                }
            }
        }
    }

    private func makeCopyStageState(from state: TransferState, title: String) -> ProjectStageState {
        ProjectStageState(
            title: title,
            detail: state.phaseTitle,
            totalBytes: state.totalBytes,
            processedBytes: state.processedBytes,
            completedFiles: state.copiedFiles,
            totalFiles: state.totalFiles,
            currentFile: state.currentFile,
            speedBytesPerSecond: state.copySpeedBytesPerSecond,
            startedAt: state.startedAt,
            failedFiles: state.copyFailedFiles,
            isActive: true,
            isComplete: state.copiedFiles >= state.totalFiles && state.copyFailedFiles.isEmpty
        )
    }

    private func makeVerificationStageState(from state: TransferState, title: String) -> ProjectStageState {
        ProjectStageState(
            title: title,
            detail: state.verificationStatus,
            totalBytes: state.verificationTotalBytes,
            processedBytes: state.verificationProcessedBytes,
            completedFiles: state.verificationCheckedFiles,
            totalFiles: state.totalFiles,
            currentFile: state.currentFile,
            speedBytesPerSecond: state.verificationSpeedBytesPerSecond,
            startedAt: state.verificationStartedAt,
            failedFiles: state.verificationFailedFiles,
            isActive: true,
            isComplete: state.verificationCheckedFiles >= state.totalFiles && state.verificationFailedFiles.isEmpty
        )
    }

    private func canRunAlongsideActiveProjects(_ project: CopyProject) -> Bool {
        for activeID in activeProjectIDs {
            guard let active = copyProjects.first(where: { $0.id == activeID }) else { continue }
            let source = project.backupOnlyRetry ? project.primaryImportURL : project.sourceRootURL
            let activeSource = active.backupOnlyRetry ? active.primaryImportURL : active.sourceRootURL
            let sourceVolume = project.backupOnlyRetry ? project.targetRootURL : URL(fileURLWithPath: project.sourceVolumePath, isDirectory: true)
            let activeSourceVolume = active.backupOnlyRetry ? active.targetRootURL : URL(fileURLWithPath: active.sourceVolumePath, isDirectory: true)
            if PathSafety.pathsShareVolume(source, activeSource)
                || PathSafety.pathsShareVolume(sourceVolume, activeSourceVolume) {
                return false
            }
            if PathSafety.pathsShareVolume(project.targetRootURL, active.targetRootURL) {
                return false
            }
            if let projectBackup = project.backupRootURL,
               PathSafety.pathsShareVolume(projectBackup, active.targetRootURL) {
                return false
            }
            if let activeBackup = active.backupRootURL,
               PathSafety.pathsShareVolume(project.targetRootURL, activeBackup) {
                return false
            }
            if let projectBackup = project.backupRootURL,
               let activeBackup = active.backupRootURL,
               PathSafety.pathsShareVolume(projectBackup, activeBackup) {
                return false
            }
        }
        return true
    }

    private func updateGlobalImportFlag() {
        isImporting = !activeProjectIDs.isEmpty
    }

    private func updateProject(
        _ id: UUID,
        saveImmediately: Bool = true,
        mutate: (inout CopyProject) -> Void
    ) {
        guard let index = copyProjects.firstIndex(where: { $0.id == id }) else { return }
        mutate(&copyProjects[index])
        copyProjects[index].updatedAt = Date()
        if saveImmediately {
            saveProjects()
        }
    }

    private func applyProjectOrder(_ ordered: [CopyProject]) {
        for (index, project) in ordered.enumerated() {
            updateProject(project.id, saveImmediately: false) { item in
                item.orderIndex = index
            }
        }
        saveProjects()
    }

    private func normalizeProjectOrder() {
        let ordered = orderedProjects
        for (index, project) in ordered.enumerated() {
            if let existingIndex = copyProjects.firstIndex(where: { $0.id == project.id }) {
                copyProjects[existingIndex].orderIndex = index
            }
        }
    }

    private func nextProjectOrderIndex() -> Int {
        (copyProjects.map(\.orderIndex).max() ?? -1) + 1
    }

    private func projectBackupEditBlockReason(_ project: CopyProject) -> String? {
        if project.status == .cancelling {
            return "项目“\(project.name)”正在取消收尾，不能修改备份策略，避免报告和实际路径不一致。"
        }

        if activeProjectIDs.contains(project.id) || project.status == .running {
            if project.backupCopyState.isActive || project.backupCopyState.isComplete
                || project.backupVerifyState.isActive || project.backupVerifyState.isComplete {
                return "项目“\(project.name)”的备份阶段已经开始或完成，不能再修改备份盘，避免报告和实际路径不一致。"
            }
            if project.primaryVerifyState.isComplete {
                return "项目“\(project.name)”主盘阶段已经完成，不能在同一次执行里追加或取消备份。请新建一个备份项目或重试后再调整。"
            }
            return nil
        }

        if project.status == .queued {
            return nil
        }

        return "只有排队中的项目，或正在执行但尚未完成主盘校验的项目，可以修改备份策略。"
    }

    private func applyProjectBackup(projectID: UUID, backupURL: URL?) -> Bool {
        guard let project = copyProjects.first(where: { $0.id == projectID }) else {
            importError = "找不到要修改备份策略的项目。"
            return false
        }

        if let backupURL {
            let warnings = projectBackupWarnings(for: project, backupURL: backupURL)
            guard warnings.isEmpty else {
                importError = warnings.joined(separator: "\n")
                return false
            }
        }

        updateProject(projectID) { item in
            item.backupRootPath = backupURL?.path
            item.backupVolumeIdentifier = backupURL.flatMap {
                (try? $0.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
            }
            item.backupReportID = nil
            if backupURL == nil {
                if item.backupOnlyRetry {
                    item.status = .completed
                    item.backupOnlyRetry = false
                }
                item.backupCopyState = ProjectStageState(
                    title: ProjectStageKind.backupCopy.title,
                    detail: "未配置备份盘"
                )
                item.backupVerifyState = ProjectStageState(
                    title: ProjectStageKind.backupVerify.title,
                    detail: "未配置备份盘"
                )
            } else {
                item.backupCopyState = ProjectStageState(
                    title: ProjectStageKind.backupCopy.title,
                    detail: item.primaryVerifyState.isComplete ? "等待备份" : "等待主盘完成",
                    totalBytes: item.totalBytes,
                    totalFiles: item.selectedItems.count
                )
                item.backupVerifyState = ProjectStageState(
                    title: ProjectStageKind.backupVerify.title,
                    detail: "等待备份完成",
                    totalBytes: item.totalBytes,
                    totalFiles: item.selectedItems.count
                )
            }
            if item.status != .blocked && item.status != .failed {
                item.errorMessage = nil
            }
        }

        if let backupURL {
            importError = "已为项目“\(project.name)”设置备份盘：\(backupURL.path)"
        } else {
            importError = "已取消项目“\(project.name)”的备份阶段。"
        }
        return true
    }

    private func projectBackupWarnings(for project: CopyProject, backupURL: URL) -> [String] {
        var warnings: [String] = []
        let sourceVolumeURL = URL(fileURLWithPath: project.sourceVolumePath, isDirectory: true)

        let sharesOriginalSourceVolume: Bool
        if project.backupOnlyRetry {
            let backupID = try? backupURL.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
            sharesOriginalSourceVolume = project.sourceVolumeIdentifier != nil
                && project.sourceVolumeIdentifier == backupID
        } else {
            sharesOriginalSourceVolume = PathSafety.pathsShareVolume(sourceVolumeURL, backupURL)
                || PathSafety.pathsShareVolume(project.sourceRootURL, backupURL)
        }
        if PathSafety.pathsOverlap(project.sourceRootURL, backupURL)
            || sharesOriginalSourceVolume {
            warnings.append("备份盘不能位于源设备同一个磁盘卷上，请选择独立备份盘。")
        }

        if PathSafety.pathsOverlap(project.targetRootURL, backupURL)
            || PathSafety.pathsShareVolume(project.targetRootURL, backupURL) {
            warnings.append("备份盘不能与主目标盘相同、互相包含，或位于同一个磁盘卷上。")
        }

        if let available = availableCapacity(for: backupURL), available < project.totalBytes {
            warnings.append("备份盘空间不足：需要 \(ByteDisplayFormatter.string(fromByteCount: project.totalBytes))，可用 \(ByteDisplayFormatter.string(fromByteCount: available))。")
        }
        if !isWritableDestination(backupURL) {
            warnings.append("备份盘不可写或位于只读卷，请重新选择。")
        }

        return warnings
    }

    private func confirmProjectBackupChange(title: String, message: String) -> Bool {
        if let backupChangeConfirmation { return backupChangeConfirmation(title, message) }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "确认")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func handleUnmountedVolume(_ url: URL) {
        mountedVolumes = volumeMonitor.volumes
        var messages: [String] = []
        if let pendingImportVolume,
           PathSafety.isContained(pendingImportVolume.url, in: url) {
            closeImportSheet()
            messages.append("源设备已断开，导入窗口已关闭：\(url.path)")
        }
        if let selectedFolderURL,
           PathSafety.isContained(selectedFolderURL, in: url) {
            closeFolderPicker()
            messages.append("所选文件夹所在磁盘已断开，请重新选择：\(url.path)")
        }

        for project in copyProjects where activeProjectIDs.contains(project.id) {
            let affectedRole: String?
            if !project.backupOnlyRetry,
               PathSafety.isContained(URL(fileURLWithPath: project.sourceVolumePath, isDirectory: true), in: url)
                || PathSafety.isContained(project.sourceRootURL, in: url) {
                affectedRole = "源设备"
            } else if PathSafety.isContained(project.targetRootURL, in: url)
                || PathSafety.isContained(project.primaryImportURL, in: url) {
                affectedRole = "主目标盘"
            } else if let backupRootURL = project.backupRootURL,
                      PathSafety.isContained(backupRootURL, in: url) {
                affectedRole = "备份盘"
            } else {
                affectedRole = nil
            }

            guard let affectedRole else { continue }
            let reason = "\(affectedRole) 在项目“\(project.name)”执行中断开：\(url.path)"
            projectTokens[project.id]?.stop(reason: reason)
            projectTasks[project.id]?.cancel()
            messages.append(reason)
        }

        if !messages.isEmpty {
            importError = messages.joined(separator: "\n")
        }
    }

    private func existingReportDocumentURL(for report: TransferReport) -> URL? {
        for path in reportDocumentCandidatePaths(for: report) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func reportDocumentCandidatePaths(for report: TransferReport) -> [String] {
        var paths: [String] = []
        if let reportDocumentPath = report.reportDocumentPath {
            paths.append(reportDocumentPath)
        }
        if let localReportDocumentPath = report.localReportDocumentPath,
           !paths.contains(localReportDocumentPath) {
            paths.append(localReportDocumentPath)
        }
        return paths
    }

    private func savePreferences() {
        do {
            try settingsStore.save(preferences)
        } catch {
            importError = "保存工作预设失败：\(error.localizedDescription)"
        }
    }

    @discardableResult
    private func saveReports() -> Bool {
        do {
            try JSONPersistence.writeReports(reports, to: reportURL)
            reportsNeedSave = false
            hasUnsavedChanges = projectsNeedSave || reportsNeedSave || statisticsIndexNeedSave
            return true
        } catch {
            reportsNeedSave = true
            hasUnsavedChanges = true
            importError = "保存日志失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    private func saveStatisticsIndex() -> Bool {
        do {
            try JSONPersistence.writeStatisticsIndex(copyStatisticsIndex, to: statisticsIndexURL)
            statisticsIndexNeedSave = false
            hasUnsavedChanges = projectsNeedSave || reportsNeedSave || statisticsIndexNeedSave
            return true
        } catch {
            statisticsIndexNeedSave = true
            hasUnsavedChanges = true
            importError = "保存统计索引失败：\(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    private func saveProjects() -> Bool {
        do {
            try JSONPersistence.writeProjects(orderedProjects, to: projectURL)
            projectsNeedSave = false
            hasUnsavedChanges = projectsNeedSave || reportsNeedSave || statisticsIndexNeedSave
            return true
        } catch {
            projectsNeedSave = true
            hasUnsavedChanges = true
            importError = "保存项目队列失败：\(error.localizedDescription)"
            return false
        }
    }

    private func cancelActiveScan(clearLoadingState: Bool = true) {
        scanTask?.cancel()
        scanTask = nil
        scanSessionID = UUID()
        if clearLoadingState {
            isScanning = false
        }
    }

    private func shouldShowAsImportSource(_ volume: StorageVolume) -> Bool {
        guard volume.url.path != "/",
              volume.isRemovable || !volume.isInternal || volume.url.path.hasPrefix("/Volumes/") else {
            return false
        }
        if let targetURL = preferences.targetURL, PathSafety.pathsShareVolume(volume.url, targetURL) {
            return false
        }
        if let backupURL = preferences.backupURL, PathSafety.pathsShareVolume(volume.url, backupURL) {
            return false
        }
        return true
    }

    private func relatedItemIDs(for item: MediaItem) -> Set<String> {
        relatedIDsByItemID[item.id] ?? [item.id]
    }

    private func folderPath(for relativePath: String) -> String {
        guard let slashIndex = relativePath.lastIndex(of: "/") else { return "" }
        return String(relativePath[..<slashIndex])
    }

    private func baseName(for relativePath: String) -> String {
        let name = URL(fileURLWithPath: relativePath).lastPathComponent
        let base = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        return base.isEmpty ? name : base
    }

    private func rebuildScanIndexes() {
        selectedItemsSnapshot = nil
        scannedTotalBytesCache = scannedItems.reduce(0) { $0 + $1.size }
        scannedItemsByID = Dictionary(uniqueKeysWithValues: scannedItems.map { ($0.id, $0) })
        scannedItemOrder = Dictionary(uniqueKeysWithValues: scannedItems.enumerated().map { ($0.element.id, $0.offset) })
        var groupedIDs: [String: Set<String>] = [:]
        for item in scannedItems {
            let key = relatedItemKey(for: item.relativePath)
            groupedIDs[key, default: []].insert(item.id)
        }
        relatedIDsByItemID = Dictionary(uniqueKeysWithValues: scannedItems.map { item in
            let ids = groupedIDs[relatedItemKey(for: item.relativePath)] ?? [item.id]
            return (item.id, ids)
        })
    }

    private func relatedItemKey(for relativePath: String) -> String {
        let folder = folderPath(for: relativePath).precomposedStringWithCanonicalMapping
        let base = baseName(for: relativePath)
            .precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return "\(folder)\u{0}\(base)"
    }

    private static func loadReports(from url: URL) -> (items: [TransferReport], warning: String?) {
        let result = JSONPersistence.loadReports(from: url)
        return (result.value.sorted { $0.startedAt > $1.startedAt }, result.warning)
    }

    private static func loadStatisticsIndex(from url: URL) -> PersistentLoadResult<CopyStatisticsIndex> {
        JSONPersistence.loadStatisticsIndex(from: url)
    }

    private static func loadProjects(from url: URL) -> (items: [CopyProject], warning: String?) {
        let result = JSONPersistence.loadProjects(from: url)
        return (result.value.sorted {
            if $0.orderIndex == $1.orderIndex {
                return $0.createdAt < $1.createdAt
            }
            return $0.orderIndex < $1.orderIndex
        }, result.warning)
    }

    private static func recoverInterruptedProjects(_ projects: [CopyProject]) -> [CopyProject] {
        projects.map { project in
            guard project.status == .running || project.status == .cancelling else { return project }
            var recovered = project
            recovered.status = .failed
            recovered.autoStartEnabled = false
            recovered.autoStartDeadline = nil
            recovered.errorMessage = "应用上次退出或崩溃时任务仍在运行或取消收尾，已自动转为异常状态。"
            recovered.primaryCopyState.isActive = false
            recovered.primaryVerifyState.isActive = false
            recovered.backupCopyState.isActive = false
            recovered.backupVerifyState.isActive = false
            return recovered
        }
    }

    private static func makeReportURL() -> URL {
        AppStorageScope.taskLogURL
    }

    private static func makeStatisticsIndexURL() -> URL {
        AppStorageScope.statisticsIndexURL
    }

    private static func makeProjectURL() -> URL {
        AppStorageScope.copyProjectsURL
    }

    private func automaticProjectName(sourceName: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let source = FileNameSanitizer.safeComponent(sourceName, fallback: "Source")
        return "\(formatter.string(from: date))_\(source)"
    }

    private func shortTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: selectedLanguage.localeIdentifier)
        formatter.dateFormat = selectedLanguage == .chinese ? "HH:mm:ss" : "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func makeFolderRoots() -> [FolderBrowserItem] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        let movies = home.appendingPathComponent("Movies", isDirectory: true)
        let documents = home.appendingPathComponent("Documents", isDirectory: true)

        let defaults = [home, desktop, movies, documents]
            .filter { fileManager.fileExists(atPath: $0.path) }
            .compactMap { makeFolderItem(from: $0, fallbackName: $0.lastPathComponent) }

        let volumes = mountedVolumes
            .compactMap { makeFolderItem(from: $0.url, fallbackName: $0.name) }

        var seen = Set<String>()
        return (volumes + defaults).filter { item in
            seen.insert(item.url.path).inserted
        }
    }

    private func loadFolderChildrenAsync(for url: URL) {
        folderChildrenTask?.cancel()
        let navigationID = UUID()
        folderNavigationID = navigationID
        isLoadingFolderChildren = true
        folderChildren = []

        folderChildrenTask = Task { [weak self] in
            let result = await Self.cancellableFolderChildrenSnapshot(for: url)
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self, self.folderNavigationID == navigationID else { return }
                self.folderChildren = result.items
                self.isLoadingFolderChildren = false
                self.folderChildrenTask = nil
                if let errorMessage = result.errorMessage {
                    self.importError = errorMessage
                }
            }
        }
    }

    private func loadSourceFolderChildrenAsync(for url: URL) {
        sourceFolderChildrenTask?.cancel()
        let navigationID = UUID()
        sourceFolderNavigationID = navigationID
        isLoadingSourceFolderChildren = true
        sourceFolderChildren = []

        sourceFolderChildrenTask = Task { [weak self] in
            let result = await Self.cancellableFolderChildrenSnapshot(for: url)
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                guard let self, self.sourceFolderNavigationID == navigationID else { return }
                self.sourceFolderChildren = result.items
                self.isLoadingSourceFolderChildren = false
                self.sourceFolderChildrenTask = nil
                if let errorMessage = result.errorMessage {
                    self.importError = errorMessage
                }
            }
        }
    }

    nonisolated private static func cancellableFolderChildrenSnapshot(for url: URL) async -> (items: [FolderBrowserItem], errorMessage: String?) {
        let worker = Task.detached { loadFolderChildrenSnapshot(for: url) }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated private static func loadFolderChildrenSnapshot(for url: URL) -> (items: [FolderBrowserItem], errorMessage: String?) {
        do {
            try Task.checkCancellation()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            let parentCapacity = DiskCapacityResolver.capacity(for: url)
            let shouldResolveEachChild = url.path == "/" || url.path == "/Volumes"
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .localizedNameKey, .nameKey]
            var enumerationError: Error?
            guard let children = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants],
                errorHandler: { _, error in enumerationError = error; return false }
            ) else { throw CocoaError(.fileReadUnknown) }

            var items: [FolderBrowserItem] = []
            for case let child as URL in children {
                try Task.checkCancellation()
                let values = try child.resourceValues(forKeys: keys)
                guard values.isDirectory == true, values.isHidden != true else { continue }
                let name = values.localizedName ?? values.name ?? child.lastPathComponent
                let capacity = shouldResolveEachChild ? DiskCapacityResolver.capacity(for: child) : parentCapacity
                items.append(FolderBrowserItem(
                    id: child.path, name: name.isEmpty ? child.lastPathComponent : name,
                    url: child, subtitle: child.path,
                    totalCapacity: capacity.totalCapacity, availableCapacity: capacity.availableCapacity
                ))
            }
            try Task.checkCancellation()
            if let enumerationError { throw enumerationError }
            items.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return (items, nil)
        } catch is CancellationError {
            return ([], nil)
        } catch {
            return ([], "读取文件夹失败：\(error.localizedDescription)")
        }
    }

    private func makeFolderItem(from url: URL, fallbackName: String) -> FolderBrowserItem? {
        let keys: Set<URLResourceKey> = [
            .nameKey,
            .localizedNameKey
        ]
        let values = try? url.resourceValues(forKeys: keys)
        let capacity = DiskCapacityResolver.capacity(for: url)

        let displayName = values?.localizedName ?? values?.name ?? fallbackName
        let subtitle = url.path
        return FolderBrowserItem(
            id: url.path,
            name: displayName.isEmpty ? url.lastPathComponent : displayName,
            url: url,
            subtitle: subtitle,
            totalCapacity: capacity.totalCapacity,
            availableCapacity: capacity.availableCapacity
        )
    }

    private func availableCapacity(for url: URL) -> Int64? {
        DiskCapacityResolver.capacity(for: url).availableCapacity
    }

    private func isWritableDestination(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        let values = try? url.resourceValues(forKeys: [.isWritableKey, .volumeIsReadOnlyKey])
        return values?.volumeIsReadOnly != true
            && values?.isWritable != false
            && FileManager.default.isWritableFile(atPath: url.path)
    }
}
