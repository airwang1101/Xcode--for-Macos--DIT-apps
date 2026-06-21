import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var preferences: AppPreferences
    @Published var selectedTheme: AppTheme = .day
    @Published var selectedLanguage: AppLanguage = .chinese
    @Published var autoStartQueuedProjects = false
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
    @Published var mountedVolumes: [StorageVolume] = []
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
    @Published var selectedItemIDs: Set<String> = []
    @Published var isScanning = false
    @Published var isImporting = false
    @Published var transferState = TransferState()
    @Published var latestReport: TransferReport?
    @Published var reports: [TransferReport] = []
    @Published private(set) var copyStatistics = CopyStatisticsSummary.make(reports: [], projects: [])
    @Published private(set) var copyStatisticsHeatmaps = CopyStatisticsHeatmaps.make(days: [])
    @Published private(set) var statisticsRecentReports: [TransferReport] = []
    @Published private(set) var statisticsRefreshedAt = Date.distantPast
    @Published var importError: String?
    @Published var hasUnsavedChanges = false
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

    let settingsStore = SettingsStore()
    private let volumeMonitor = VolumeMonitor()
    private let scanner = MediaScanner()
    private let transferService = TransferService()
    private let interruptionToken = ImportInterruptionToken()
    private static let projectAutoStartDelay: TimeInterval = 300
    private static let statisticsRefreshInterval: TimeInterval = 600
    private let reportURL: URL
    private let projectURL: URL
    private let statisticsIndexURL: URL
    private var importTask: Task<Void, Never>?
    private var projectTasks: [UUID: Task<Void, Never>] = [:]
    private var projectTokens: [UUID: ImportInterruptionToken] = [:]
    private var pendingDeleteProjectIDs: Set<UUID> = []
    private var autoStartTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var folderChildrenTask: Task<Void, Never>?
    private var sourceFolderChildrenTask: Task<Void, Never>?
    private var statisticsRefreshTask: Task<Void, Never>?
    private var activeImportSummary: ImportSelectionSummary?
    private var retrySourceItems: [MediaItem] = []
    private var scanSessionID = UUID()
    private var folderNavigationID = UUID()
    private var sourceFolderNavigationID = UUID()
    private var scannedItemsByID: [String: MediaItem] = [:]
    private var scannedItemOrder: [String: Int] = [:]
    private var relatedIDsByItemID: [String: Set<String>] = [:]
    private var projectsNeedSave = false
    private var reportsNeedSave = false
    private var statisticsIndexNeedSave = false
    private var copyStatisticsIndex = CopyStatisticsIndex()
    private var manualQueueRunActive = false

    init() {
        preferences = settingsStore.load()
        let uiSettings = settingsStore.loadUISettings()
        selectedTheme = uiSettings.theme
        selectedLanguage = uiSettings.language
        autoStartQueuedProjects = uiSettings.autoStartQueuedProjects
        reportURL = Self.makeReportURL()
        projectURL = Self.makeProjectURL()
        statisticsIndexURL = Self.makeStatisticsIndexURL()
        let reportLoad = Self.loadReports(from: reportURL)
        reports = reportLoad.items
        let statisticsIndexLoad = Self.loadStatisticsIndex(from: statisticsIndexURL)
        copyStatisticsIndex = statisticsIndexLoad.value
        let projectLoad = Self.loadProjects(from: projectURL)
        let storedProjects = projectLoad.items
        let recoveredProjects = Self.recoverInterruptedProjects(storedProjects)
        copyProjects = recoveredProjects
        orderedProjectsCache = Self.sortedProjects(recoveredProjects)
        reconcileStatisticsIndexIfNeeded()
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
        if storedProjects.contains(where: { $0.status == .running || $0.status == .cancelling }) {
            saveProjects()
        }
        scheduleNextAutoStartCheck()
        startStatisticsRefreshTimer()
    }

    deinit {
        statisticsRefreshTask?.cancel()
        autoStartTask?.cancel()
        scanTask?.cancel()
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

    var selectedItems: [MediaItem] {
        selectedItemIDs
            .compactMap { scannedItemsByID[$0] }
            .sorted {
                (scannedItemOrder[$0.id] ?? Int.max) < (scannedItemOrder[$1.id] ?? Int.max)
            }
    }

    var selectedTotalBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.size }
    }

    var scannedTotalBytes: Int64 {
        scannedItems.reduce(0) { $0 + $1.size }
    }

    var displayVolumes: [StorageVolume] {
        mountedVolumes.filter { volume in
            shouldShowAsImportSource(volume)
        }
    }

    var selectedSourceFolderItem: FolderBrowserItem? {
        guard let sourceFolderURL else { return nil }
        return makeFolderItem(from: sourceFolderURL, fallbackName: sourceFolderURL.lastPathComponent)
    }

    var selectionSummary: ImportSelectionSummary? {
        guard let volume = pendingImportVolume,
              let targetURL = preferences.targetURL,
              !selectedItems.isEmpty else {
            return nil
        }

        return ImportSelectionSummary(
            sourceVolume: volume,
            sourceRootURL: sourceFolderURL ?? volume.url,
            selectedItems: selectedItems,
            totalSize: selectedItems.reduce(0) { $0 + $1.size },
            targetURL: targetURL,
            backupURL: preferences.backupURL,
            verificationMode: selectedVerificationMode.title,
            namingRule: projectNameMode.title
        )
    }

    var destinationWarnings: [String] {
        guard let summary = selectionSummary else { return [] }
        var warnings: [String] = []
        let required = summary.totalSize

        if let available = availableCapacity(for: summary.targetURL), available < required {
            warnings.append("主目标盘空间不足：需要 \(ByteDisplayFormatter.string(fromByteCount: required))，可用 \(ByteDisplayFormatter.string(fromByteCount: available))")
        }
        if !isWritableDestination(summary.targetURL) {
            warnings.append("主目标盘不可写或位于只读卷，请重新选择。")
        }

        if let backupURL = summary.backupURL,
           let available = availableCapacity(for: backupURL),
           available < required {
            warnings.append("备份盘空间不足：需要 \(ByteDisplayFormatter.string(fromByteCount: required))，可用 \(ByteDisplayFormatter.string(fromByteCount: available))")
        }
        if let backupURL = summary.backupURL, !isWritableDestination(backupURL) {
            warnings.append("备份盘不可写或位于只读卷，请重新选择。")
        }

        if let backupURL = summary.backupURL,
           let targetRoot = DiskCapacityResolver.volumeRootPath(for: summary.targetURL),
           let backupRoot = DiskCapacityResolver.volumeRootPath(for: backupURL),
           targetRoot == backupRoot,
           let available = availableCapacity(for: summary.targetURL) {
            let combinedRequired = required * 2
            if available < combinedRequired {
                warnings.append("主目标盘和备份盘在同一磁盘卷上：双写需要 \(ByteDisplayFormatter.string(fromByteCount: combinedRequired))，当前可用 \(ByteDisplayFormatter.string(fromByteCount: available))")
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

    var hasActiveTransfers: Bool {
        isImporting || !activeProjectIDs.isEmpty || importTask != nil || !projectTasks.isEmpty
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

    var selectedSourceCapacity: StorageCapacitySnapshot? {
        guard let sourceFolderURL else { return nil }
        return DiskCapacityResolver.capacity(for: sourceFolderURL)
    }

    var targetCapacity: StorageCapacitySnapshot? {
        guard let targetURL = preferences.targetURL else { return nil }
        return DiskCapacityResolver.capacity(for: targetURL)
    }

    var backupCapacity: StorageCapacitySnapshot? {
        guard let backupURL = preferences.backupURL else { return nil }
        return DiskCapacityResolver.capacity(for: backupURL)
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
        case .target, .backup, .projectBackup:
            requiresWritableDestination = true
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

    private func saveUISettings() {
        do {
            try settingsStore.saveUISettings(
                AppUISettings(
                    theme: selectedTheme,
                    language: selectedLanguage,
                    autoStartQueuedProjects: autoStartQueuedProjects
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
        retrySourceItems = summary.selectedItems
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
        reconcileStatisticsIndexIfNeeded()
        rebuildCopyStatistics()
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
        let summary = copyStatisticsIndex.summary(projects: orderedProjects, now: now)
        copyStatistics = summary
        copyStatisticsHeatmaps = CopyStatisticsHeatmaps.make(days: summary.days)
        statisticsRecentReports = Array(reports.prefix(8))
        statisticsRefreshedAt = now
    }

    private func reconcileStatisticsIndexIfNeeded() {
        guard !copyStatisticsIndex.matches(reports: reports) else { return }
        copyStatisticsIndex = CopyStatisticsIndex.make(reports: reports)
        saveStatisticsIndex()
    }

    private func recordFinishedReport(_ report: TransferReport) {
        latestReport = report
        reports.insert(report, at: 0)
        saveReports()
        copyStatisticsIndex.add(report)
        saveStatisticsIndex()
        rebuildCopyStatistics()
    }

    func cancelImport() {
        interruptionToken.stop(reason: "用户取消了导入任务")
        importTask?.cancel()
        transferState.phaseTitle = "正在取消"
        transferState.verificationStatus = "等待当前文件操作结束"
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
            item.status = .queued
            item.errorMessage = nil
            item.skipVerificationConfirmations = 0
            item.primaryCopyState = ProjectStageState(
                title: ProjectStageKind.primaryCopy.title,
                totalBytes: item.totalBytes,
                totalFiles: item.selectedItems.count
            )
            item.primaryVerifyState = ProjectStageState(
                title: ProjectStageKind.primaryVerify.title,
                totalBytes: item.totalBytes,
                totalFiles: item.selectedItems.count
            )
            item.backupCopyState = ProjectStageState(
                title: ProjectStageKind.backupCopy.title,
                detail: item.hasBackup ? "等待主盘完成" : "未配置备份盘",
                totalBytes: item.hasBackup ? item.totalBytes : 0,
                totalFiles: item.hasBackup ? item.selectedItems.count : 0
            )
            item.backupVerifyState = ProjectStageState(
                title: ProjectStageKind.backupVerify.title,
                detail: item.hasBackup ? "等待备份完成" : "未配置备份盘",
                totalBytes: item.hasBackup ? item.totalBytes : 0,
                totalFiles: item.hasBackup ? item.selectedItems.count : 0
            )
            item.primaryReportID = nil
            item.backupReportID = nil
            item.autoStartEnabled = false
            item.autoStartDeadline = nil
        }
        scheduleNextAutoStartCheck()
        selectedSection = .copy
        importError = "已将项目“\(project.name)”重新加入任务队列。需要手动点击“执行任务队列”才会开始写盘。"
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
            if item.status == .queued {
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
        alert.informativeText = "名称会用于队列显示、报告标题；排队中的项目还会同步更新目标文件夹名。"
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

    func retryLatestFailedItems() {
        guard let latestReport else {
            importError = "当前还没有可重试的任务日志。"
            return
        }
        guard !latestReport.failedFiles.isEmpty else {
            importError = "最新任务没有异常素材，不需要重试。"
            return
        }

        let retryItems = retryItems(for: latestReport)
        guard !retryItems.isEmpty else {
            importError = "当前会话里找不到可重试的异常素材，请重新选择源文件夹扫描后再试。"
            return
        }

        let createdAt = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let retryName = "重试异常_\(latestReport.namingRule)_\(formatter.string(from: createdAt))"
        let safeFolderName = FileNameSanitizer.safeComponent(
            retryName,
            fallback: "Retry_\(formatter.string(from: createdAt))"
        )
        let targetRootURL = URL(fileURLWithPath: latestReport.targetPath, isDirectory: true)
            .deletingLastPathComponent()
        let backupRootPath = latestReport.backupPath.map {
            URL(fileURLWithPath: $0, isDirectory: true).deletingLastPathComponent().path
        }
        let verificationMode = VerificationMode.allCases.first {
            $0.title == latestReport.verificationMode || $0.shortTitle == latestReport.verificationMode
        } ?? selectedVerificationMode
        let autoStartDeadline = autoStartQueuedProjects
            ? createdAt.addingTimeInterval(Self.projectAutoStartDelay)
            : nil

        let project = CopyProject(
            name: retryName,
            taskFolderName: safeFolderName,
            createdAt: createdAt,
            updatedAt: createdAt,
            sourceName: latestReport.sourceName,
            sourceVolumePath: latestReport.sourcePath,
            sourceRootPath: latestReport.sourceRootPath ?? latestReport.sourcePath,
            targetRootPath: targetRootURL.path,
            backupRootPath: backupRootPath,
            selectedItems: retryItems.map(ProjectMediaItem.init(mediaItem:)),
            totalBytes: retryItems.reduce(0) { $0 + $1.size },
            verificationMode: verificationMode,
            orderIndex: nextProjectOrderIndex(),
            autoStartEnabled: autoStartQueuedProjects,
            autoStartDeadline: autoStartDeadline
        )

        copyProjects.append(project)
        normalizeProjectOrder()
        saveProjects()
        scheduleNextAutoStartCheck()
        selectedSection = .copy
        if let autoStartDeadline {
            importError = "已把 \(retryItems.count) 个异常素材创建为新的重试项目。5 分钟内可取消自动执行，预计启动：\(shortTimeText(autoStartDeadline))。"
        } else {
            importError = "已把 \(retryItems.count) 个异常素材创建为新的重试项目，需要手动执行队列才会开始。"
        }
    }

    private func startImport(with summary: ImportSelectionSummary) {
        isImporting = true
        let destinationCount = destinationCount(for: summary)
        transferState = TransferState(
            totalBytes: summary.totalSize * Int64(destinationCount),
            processedBytes: 0,
            verificationTotalBytes: summary.totalSize * Int64(1 + destinationCount),
            copiedFiles: 0,
            verifiedFiles: 0,
            verificationCheckedFiles: 0,
            totalFiles: summary.selectedItems.count,
            startedAt: Date(),
            currentFile: "",
            verificationStatus: "等待整批校验",
            failedFiles: [],
            phaseTitle: "正在准备导入",
            reportSummary: ""
        )
        interruptionToken.reset()
        activeImportSummary = summary
        retrySourceItems = summary.selectedItems

        let transferService = self.transferService
        importTask = Task { [weak self, summary, interruptionToken, transferService] in
            guard let self else { return }
            do {
                let result = try await transferService.runImport(
                    summary: summary,
                    interruptionToken: interruptionToken,
                    language: self.selectedLanguage
                ) { [weak self] state in
                    await MainActor.run { [weak self] in
                        self?.transferState = state
                    }
                }
                self.recordFinishedReport(result.report)
            } catch is CancellationError {
                self.transferState.phaseTitle = "任务已取消"
                self.transferState.verificationStatus = "用户已取消"
                self.transferState.isCancelled = true
            } catch {
                self.importError = "导入任务失败：\(error.localizedDescription)"
            }

            self.isImporting = false
            self.importTask = nil
            self.activeImportSummary = nil
        }
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

        do {
            let primaryResult = try await transferService.runPrimaryStage(
                project: primaryProject,
                interruptionToken: token,
                language: selectedLanguage
            ) { [weak self] state in
                await MainActor.run { [weak self] in
                    self?.applyProgress(state, to: projectID, stage: .primary)
                }
            }
            finishPrimaryStage(projectID: projectID, result: primaryResult)

            guard let currentProject = copyProjects.first(where: { $0.id == projectID }) else {
                finishProjectTask(projectID)
                return
            }
            if currentProject.status == .cancelling {
                updateProject(projectID) { item in
                    item.status = .cancelled
                    item.errorMessage = "用户取消了导入任务，主盘阶段已收尾，后续阶段未执行。"
                }
                finishProjectTask(projectID)
                return
            }
            guard currentProject.status == .running else {
                finishProjectTask(projectID)
                return
            }

            if !primaryResult.report.success {
                updateProject(projectID) { item in
                    if item.hasBackup {
                        item.status = .blocked
                        item.errorMessage = "主盘异常，备份已阻塞。请查看第一份主盘报告后重试。"
                        item.backupCopyState.isBlocked = true
                        item.backupCopyState.detail = "主盘异常，备份已阻塞"
                        item.backupVerifyState.isBlocked = true
                        item.backupVerifyState.detail = "主盘异常，备份已阻塞"
                    } else {
                        item.status = .failed
                        item.errorMessage = "主盘拷贝或校验异常。此项目未配置备份盘，请查看主盘报告后重试。"
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

            let backupResult = try await transferService.runBackupStage(
                project: currentProject,
                interruptionToken: token,
                language: selectedLanguage
            ) { [weak self] state in
                await MainActor.run { [weak self] in
                    self?.applyProgress(state, to: projectID, stage: .backup)
                }
            }
            finishBackupStage(projectID: projectID, result: backupResult)
        } catch is CancellationError {
            // Use the token's stop reason when available (e.g. device disconnect),
            // otherwise fall back to the generic user-cancel message.
            let cancelReason = projectTokens[projectID]?.reason ?? "用户取消了导入任务"
            updateProject(projectID) { item in
                item.status = .cancelled
                item.errorMessage = cancelReason
            }
        } catch {
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
            item.primaryCopyState.isActive = false
            item.primaryCopyState.isComplete = result.finalState.copyFailedFiles.isEmpty
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
            item.backupCopyState.isComplete = result.finalState.copyFailedFiles.isEmpty
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
                    item.primaryCopyState.isComplete = state.copyFailedFiles.isEmpty
                    item.primaryVerifyState = stageState
                } else {
                    item.backupCopyState.isActive = false
                    item.backupCopyState.isComplete = state.copyFailedFiles.isEmpty
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
            isComplete: state.processedBytes >= state.totalBytes && state.copyFailedFiles.isEmpty
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
            if PathSafety.pathsShareVolume(project.sourceRootURL, active.sourceRootURL)
                || PathSafety.pathsShareVolume(URL(fileURLWithPath: project.sourceVolumePath, isDirectory: true), URL(fileURLWithPath: active.sourceVolumePath, isDirectory: true)) {
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
        isImporting = !activeProjectIDs.isEmpty || importTask != nil
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

    private func retryItems(for report: TransferReport) -> [MediaItem] {
        let sourceRootURL = URL(fileURLWithPath: report.sourceRootPath ?? report.sourcePath, isDirectory: true)
        let cachedItems = (retrySourceItems + scannedItems).reduce(into: [String: MediaItem]()) { result, item in
            guard PathSafety.isContained(item.fileURL, in: sourceRootURL) else { return }
            result[item.relativePath] = item
        }
        var items: [MediaItem] = []
        var seen = Set<String>()

        for relativePath in report.failedFiles where seen.insert(relativePath).inserted {
            guard (try? SafeRelativePath(relativePath)) != nil else { continue }
            if let cachedItem = cachedItems[relativePath],
               FileManager.default.fileExists(atPath: cachedItem.fileURL.path) {
                items.append(cachedItem)
                continue
            }

            guard let fileURL = try? PathSafety.resolvedURL(for: relativePath, under: sourceRootURL) else {
                continue
            }
            guard let item = makeRetryMediaItem(relativePath: relativePath, fileURL: fileURL) else {
                continue
            }
            items.append(item)
        }

        return items
    }

    private func makeRetryMediaItem(relativePath: String, fileURL: URL) -> MediaItem? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let keys: Set<URLResourceKey> = [
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .nameKey,
            .isRegularFileKey
        ]
        guard let values = try? fileURL.resourceValues(forKeys: keys),
              values.isRegularFile == true else {
            return nil
        }

        let mediaKind = mediaKind(for: fileURL.pathExtension.lowercased())
        return MediaItem(
            id: relativePath,
            fileURL: fileURL,
            relativePath: relativePath,
            displayName: values.name ?? fileURL.lastPathComponent,
            createdAt: values.creationDate ?? values.contentModificationDate ?? .now,
            size: Int64(values.fileSize ?? 0),
            isVideo: mediaKind == .video,
            mediaKind: mediaKind
        )
    }

    private func mediaKind(for fileExtension: String) -> ScanFilter {
        if ["mov", "mp4", "mxf", "r3d", "braw", "ari", "crm", "avi", "mkv", "mts", "m2ts"].contains(fileExtension) {
            return .video
        }
        if ["jpg", "jpeg", "png", "heic", "tif", "tiff", "dng", "cr2", "cr3", "nef", "arw", "raf", "rw2"].contains(fileExtension) {
            return .photo
        }
        if ["wav", "aif", "aiff", "mp3", "m4a", "flac"].contains(fileExtension) {
            return .audio
        }
        return .all
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
            item.backupReportID = nil
            if backupURL == nil {
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

        if PathSafety.pathsOverlap(project.sourceRootURL, backupURL)
            || PathSafety.pathsShareVolume(sourceVolumeURL, backupURL)
            || PathSafety.pathsShareVolume(project.sourceRootURL, backupURL) {
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
            if PathSafety.isContained(URL(fileURLWithPath: project.sourceVolumePath, isDirectory: true), in: url)
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

        guard isImporting, let activeImportSummary else { return }

        let affectedRole: String?
        if PathSafety.isContained(activeImportSummary.sourceVolume.url, in: url) {
            affectedRole = "源设备"
        } else if PathSafety.isContained(activeImportSummary.targetURL, in: url) {
            affectedRole = "主目标盘"
        } else if let backupURL = activeImportSummary.backupURL,
                  PathSafety.isContained(backupURL, in: url) {
            affectedRole = "备份盘"
        } else {
            affectedRole = nil
        }

        guard let affectedRole else { return }
        let reason = "\(affectedRole) 在导入任务执行中断开：\(url.path)"
        interruptionToken.stop(reason: reason)
        importTask?.cancel()
        transferState.phaseTitle = "设备中断，正在安全收尾"
        transferState.verificationStatus = "停止新写入并生成报告"
        transferState.interruptionReason = reason
        transferState.reportSummary = reason
        importError = reason
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

    private func destinationCount(for summary: ImportSelectionSummary) -> Int {
        summary.backupURL == nil ? 1 : 2
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
            let result = await Task.detached {
                Self.loadFolderChildrenSnapshot(for: url)
            }.value

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
            let result = await Task.detached {
                Self.loadFolderChildrenSnapshot(for: url)
            }.value

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

    nonisolated private static func loadFolderChildrenSnapshot(for url: URL) -> (items: [FolderBrowserItem], errorMessage: String?) {
        do {
            let parentCapacity = DiskCapacityResolver.capacity(for: url)
            let shouldResolveEachChild = url.path == "/" || url.path == "/Volumes"

            let children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isHiddenKey,
                    .localizedNameKey,
                    .nameKey
                ],
                options: [.skipsPackageDescendants]
            )

            let items: [FolderBrowserItem] = children.compactMap { child -> FolderBrowserItem? in
                guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey, .localizedNameKey, .nameKey]),
                      values.isDirectory == true,
                      values.isHidden != true else {
                    return nil
                }
                let name = values.localizedName ?? values.name ?? child.lastPathComponent
                let capacity = shouldResolveEachChild ? DiskCapacityResolver.capacity(for: child) : parentCapacity
                return FolderBrowserItem(
                    id: child.path,
                    name: name.isEmpty ? child.lastPathComponent : name,
                    url: child,
                    subtitle: child.path,
                    totalCapacity: capacity.totalCapacity,
                    availableCapacity: capacity.availableCapacity
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            return (items, nil)
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
