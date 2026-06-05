import Foundation

enum ImportMode: String, CaseIterable, Identifiable {
    case time
    case free

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: "时间模式"
        case .free: "自由模式"
        }
    }

    var subtitle: String {
        switch self {
        case .time: "按日期自动分组，适合快速按拍摄批次整理"
        case .free: "缩略图浏览与手动多选，适合精细挑选素材"
        }
    }
}

enum AssetBrowserMode: String, CaseIterable, Identifiable {
    case icon
    case list
    case column
    case gallery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: "图标"
        case .list: "列表"
        case .column: "分栏"
        case .gallery: "画廊"
        }
    }

    var systemImage: String {
        switch self {
        case .icon: "square.grid.2x2"
        case .list: "list.bullet"
        case .column: "rectangle.split.3x1"
        case .gallery: "rectangle.on.rectangle"
        }
    }

    var subtitle: String {
        switch self {
        case .icon: "缩略图快速扫片"
        case .list: "按名称、路径、大小、时间精确核对"
        case .column: "按文件夹结构理解卡内素材"
        case .gallery: "大预览配合胶片条精挑"
        }
    }
}

enum MainSection: String, CaseIterable, Identifiable {
    case copy
    case dashboard
    case backup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: "拷贝"
        case .dashboard: "仪表盘"
        case .backup: "备份"
        }
    }

    var systemImage: String {
        switch self {
        case .copy: "square.and.arrow.down.on.square"
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .backup: "externaldrive.badge.timemachine"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case day
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "白天"
        case .night: "夜晚"
        }
    }
}

enum ScanFilter: String, CaseIterable, Identifiable {
    case video
    case photo
    case audio
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: "视频"
        case .photo: "照片"
        case .audio: "音频"
        case .all: "全部"
        }
    }
}

struct AppPreferences: Codable {
    var targetPath: String?
    var backupEnabled: Bool
    var backupPath: String?

    static let `default` = AppPreferences(targetPath: nil, backupEnabled: false, backupPath: nil)

    enum CodingKeys: String, CodingKey {
        case targetPath
        case backupEnabled
        case backupPath
    }

    init(targetPath: String?, backupEnabled: Bool, backupPath: String?) {
        self.targetPath = targetPath
        self.backupEnabled = backupEnabled
        self.backupPath = backupPath
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetPath = try container.decodeIfPresent(String.self, forKey: .targetPath)
        backupEnabled = try container.decodeIfPresent(Bool.self, forKey: .backupEnabled) ?? false
        backupPath = try container.decodeIfPresent(String.self, forKey: .backupPath)
    }

    var targetURL: URL? {
        targetPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var backupURL: URL? {
        guard backupEnabled, let backupPath else { return nil }
        return URL(fileURLWithPath: backupPath, isDirectory: true)
    }
}

enum AppStorageScope {
    static var displayName: String { "App 专属存储" }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.airwang.ditformac"
    }

    static var applicationSupportURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    static var dataURL: URL {
        applicationSupportURL.appendingPathComponent("Data", isDirectory: true)
    }

    static var preferencesURL: URL {
        dataURL.appendingPathComponent("preferences.json")
    }

    static var uiSettingsURL: URL {
        dataURL.appendingPathComponent("ui-settings.json")
    }

    static var taskLogURL: URL {
        dataURL
            .appendingPathComponent("import-reports.json")
    }

    static var copyProjectsURL: URL {
        dataURL
            .appendingPathComponent("copy-projects.json")
    }

    static func localReportDocumentURL(taskFolder: String) -> URL {
        localReportDocumentURL(taskFolder: taskFolder, reportKind: "Copy")
    }

    static func localReportDocumentURL(taskFolder: String, reportKind: String) -> URL {
        applicationSupportURL
            .appendingPathComponent("Reports", isDirectory: true)
            .appendingPathComponent("Airwang_\(FileNameSanitizer.safeComponent(reportKind, fallback: "Copy"))_Report_\(FileNameSanitizer.safeComponent(taskFolder)).txt")
    }
}

struct AppUISettings: Codable {
    var theme: AppTheme

    static let `default` = AppUISettings(theme: .day)

    enum CodingKeys: String, CodingKey {
        case theme
    }

    init(theme: AppTheme) {
        self.theme = theme
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .day
    }
}

enum FolderPickerPurpose: Identifiable {
    case target
    case backup
    case projectBackup(UUID)

    var id: String {
        switch self {
        case .target:
            return "target"
        case .backup:
            return "backup"
        case let .projectBackup(id):
            return "projectBackup-\(id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .target: "选择主目标盘"
        case .backup: "选择备份盘"
        case .projectBackup: "选择项目备份盘"
        }
    }

    var confirmTitle: String {
        switch self {
        case .target: "设为主目标盘"
        case .backup: "设为备份盘"
        case .projectBackup: "应用到此项目"
        }
    }
}

struct StorageCapacitySnapshot: Equatable, Hashable {
    let totalCapacity: Int64?
    let availableCapacity: Int64?
    let source: String

    var isReadable: Bool {
        totalCapacity != nil || availableCapacity != nil
    }

    var usageFraction: Double? {
        guard let totalCapacity, totalCapacity > 0, let availableCapacity else { return nil }
        return min(max(1 - (Double(availableCapacity) / Double(totalCapacity)), 0), 1)
    }

    var capacityLine: String {
        guard isReadable else { return "容量暂不可读" }
        let free = availableCapacity.map { Self.byteFormatter.string(fromByteCount: $0) } ?? "-"
        let total = totalCapacity.map { Self.byteFormatter.string(fromByteCount: $0) } ?? "-"
        return "可用 \(free) / 总计 \(total)"
    }

    var shortAvailableText: String {
        availableCapacity.map { Self.byteFormatter.string(fromByteCount: $0) } ?? "未知"
    }

    private static var byteFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useTB]
        formatter.countStyle = .file
        return formatter
    }
}

enum DiskCapacityResolver {
    static func capacity(for url: URL) -> StorageCapacitySnapshot {
        let normalizedURL = url.standardizedFileURL

        // `resourceValues` can report nil or APFS "important usage" values that do not
        // match what users see in Finder. File-system attributes are the safer primary
        // source for DIT preflight checks on SD cards and external SSDs.
        if let filesystemCapacity = capacityFromFilesystemAttributes(for: normalizedURL) {
            return filesystemCapacity
        }

        if let resourceCapacity = capacityFromResourceValues(for: normalizedURL) {
            return resourceCapacity
        }

        return StorageCapacitySnapshot(
            totalCapacity: nil,
            availableCapacity: nil,
            source: "unreadable"
        )
    }

    static func volumeRootPath(for url: URL) -> String? {
        let candidatePaths = [url.standardizedFileURL.path]
        let mountedVolumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        let roots = (mountedVolumes + [URL(fileURLWithPath: "/", isDirectory: true)])
            .map { $0.standardizedFileURL.path }
            .sorted { $0.count > $1.count }

        for root in roots {
            for path in candidatePaths {
                if path == root {
                    return root
                }
                if root != "/" && path.hasPrefix(root + "/") {
                    return root
                }
            }
        }

        return nil
    }

    private static func capacityFromFilesystemAttributes(for url: URL) -> StorageCapacitySnapshot? {
        let path = nearestExistingPath(for: url)
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path) else {
            return nil
        }

        let total = int64Value(from: attributes[.systemSize])
        let free = int64Value(from: attributes[.systemFreeSize])
        guard total != nil || free != nil else { return nil }

        return StorageCapacitySnapshot(
            totalCapacity: total,
            availableCapacity: free,
            source: "filesystem"
        )
    }

    private static func capacityFromResourceValues(for url: URL) -> StorageCapacitySnapshot? {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }

        let total = values.volumeTotalCapacity.map { Int64($0) }
        let available = values.volumeAvailableCapacity.map { Int64($0) }
            ?? values.volumeAvailableCapacityForImportantUsage.map { Int64($0) }
        guard total != nil || available != nil else { return nil }

        return StorageCapacitySnapshot(
            totalCapacity: total,
            availableCapacity: available,
            source: "resourceValues"
        )
    }

    private static func nearestExistingPath(for url: URL) -> String {
        let fileManager = FileManager.default
        var candidate = url

        while !fileManager.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { break }
            candidate = parent
        }

        return candidate.path
    }

    private static func int64Value(from value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let int = value as? Int {
            return Int64(int)
        }
        if let int64 = value as? Int64 {
            return int64
        }
        return nil
    }
}

struct StorageVolume: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
    let isRemovable: Bool
    let isInternal: Bool
    let totalCapacity: Int64?
    let availableCapacity: Int64?

    var capacityDescription: String {
        StorageCapacitySnapshot(
            totalCapacity: totalCapacity,
            availableCapacity: availableCapacity,
            source: "stored"
        )
        .capacityLine
    }
}

struct FolderBrowserItem: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let subtitle: String
    let totalCapacity: Int64?
    let availableCapacity: Int64?

    var capacityLine: String {
        StorageCapacitySnapshot(
            totalCapacity: totalCapacity,
            availableCapacity: availableCapacity,
            source: "stored"
        )
        .capacityLine
    }
}

struct MediaItem: Identifiable, Hashable {
    let id: String
    let fileURL: URL
    let relativePath: String
    let displayName: String
    let createdAt: Date
    let size: Int64
    let isVideo: Bool
    let mediaKind: ScanFilter
}

struct TimeGroup: Identifiable {
    let id: String
    let date: Date
    let items: [MediaItem]
    let totalSize: Int64
}

struct ImportSelectionSummary {
    let sourceVolume: StorageVolume
    let sourceRootURL: URL
    let selectedItems: [MediaItem]
    let totalSize: Int64
    let targetURL: URL
    let backupURL: URL?
    let verificationMode: String
    let namingRule: String
}

enum ProjectExecutionMode: String, CaseIterable, Identifiable, Codable {
    case sequential
    case parallel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequential: "按序执行"
        case .parallel: "并行执行"
        }
    }

    var subtitle: String {
        switch self {
        case .sequential: "默认最稳妥，一次只跑一个项目"
        case .parallel: "最多 3 个项目同时跑，单项目内部仍严格先主盘后备份"
        }
    }

    var maximumConcurrentProjects: Int {
        switch self {
        case .sequential: 1
        case .parallel: 3
        }
    }
}

enum VerificationMode: String, CaseIterable, Identifiable, Codable {
    case sha256
    case fastFingerprint
    case sizeOnly
    case skipped

    var id: String { rawValue }

    static var selectableCases: [VerificationMode] {
        [.sha256, .fastFingerprint, .sizeOnly]
    }

    var title: String {
        switch self {
        case .sha256: "SHA-256 全量校验"
        case .fastFingerprint: "快速指纹校验"
        case .sizeOnly: "大小校验"
        case .skipped: "跳过校验"
        }
    }

    var shortTitle: String {
        switch self {
        case .sha256: "SHA-256"
        case .fastFingerprint: "快速指纹"
        case .sizeOnly: "大小"
        case .skipped: "已跳过"
        }
    }

    var detail: String {
        switch self {
        case .sha256: "完整读取源/目标/备份并比对 SHA-256，最安全，速度最慢。"
        case .fastFingerprint: "比对大小，并抽样读取头部/中部/尾部生成指纹，速度快但不能保证发现所有损坏。"
        case .sizeOnly: "只确认文件存在和大小一致，最快，但不能发现内容损坏。"
        case .skipped: "用户主动跳过校验，报告会明确标记，不代表素材完整性已确认。"
        }
    }

    var reportWarning: String {
        switch self {
        case .sha256: "完整性校验：已执行 SHA-256 全量比对。"
        case .fastFingerprint: "风险提示：快速指纹校验为性能优先方案，不能替代 SHA-256 全量校验。"
        case .sizeOnly: "风险提示：大小校验只能证明文件大小一致，不能证明内容完全一致。"
        case .skipped: "高风险提示：用户主动跳过校验，本报告不代表素材完整性已确认。"
        }
    }
}

enum ProjectNameMode: String, CaseIterable, Identifiable, Codable {
    case automatic
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "按创建时间自动生成"
        case .custom: "自定义项目名称"
        }
    }
}

enum CopyProjectStatus: String, Codable {
    case queued
    case running
    case cancelling
    case completed
    case failed
    case blocked
    case cancelled

    var title: String {
        switch self {
        case .queued: "排队中"
        case .running: "执行中"
        case .cancelling: "取消中"
        case .completed: "已完成"
        case .failed: "异常"
        case .blocked: "已阻塞"
        case .cancelled: "已取消"
        }
    }
}

enum ProjectStageKind: String, CaseIterable, Codable {
    case primaryCopy
    case primaryVerify
    case backupCopy
    case backupVerify

    var title: String {
        switch self {
        case .primaryCopy: "主盘拷贝"
        case .primaryVerify: "主盘校验"
        case .backupCopy: "备份拷贝"
        case .backupVerify: "备份校验"
        }
    }
}

struct ProjectStageState: Codable, Equatable {
    var title: String
    var detail: String
    var totalBytes: Int64
    var processedBytes: Int64
    var completedFiles: Int
    var totalFiles: Int
    var currentFile: String
    var speedBytesPerSecond: Double
    var startedAt: Date?
    var finishedAt: Date?
    var failedFiles: [String]
    var reportDocumentPath: String?
    var localReportDocumentPath: String?
    var isActive: Bool
    var isComplete: Bool
    var isBlocked: Bool

    enum CodingKeys: String, CodingKey {
        case title
        case detail
        case totalBytes
        case processedBytes
        case completedFiles
        case totalFiles
        case currentFile
        case speedBytesPerSecond
        case startedAt
        case finishedAt
        case failedFiles
        case reportDocumentPath
        case localReportDocumentPath
        case isActive
        case isComplete
        case isBlocked
    }

    init(
        title: String = "等待",
        detail: String = "尚未开始",
        totalBytes: Int64 = 0,
        processedBytes: Int64 = 0,
        completedFiles: Int = 0,
        totalFiles: Int = 0,
        currentFile: String = "",
        speedBytesPerSecond: Double = 0,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        failedFiles: [String] = [],
        reportDocumentPath: String? = nil,
        localReportDocumentPath: String? = nil,
        isActive: Bool = false,
        isComplete: Bool = false,
        isBlocked: Bool = false
    ) {
        self.title = title
        self.detail = detail
        self.totalBytes = totalBytes
        self.processedBytes = processedBytes
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
        self.currentFile = currentFile
        self.speedBytesPerSecond = speedBytesPerSecond
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.failedFiles = failedFiles
        self.reportDocumentPath = reportDocumentPath
        self.localReportDocumentPath = localReportDocumentPath
        self.isActive = isActive
        self.isComplete = isComplete
        self.isBlocked = isBlocked
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "等待"
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? "尚未开始"
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        processedBytes = try container.decodeIfPresent(Int64.self, forKey: .processedBytes) ?? 0
        completedFiles = try container.decodeIfPresent(Int.self, forKey: .completedFiles) ?? 0
        totalFiles = try container.decodeIfPresent(Int.self, forKey: .totalFiles) ?? 0
        currentFile = try container.decodeIfPresent(String.self, forKey: .currentFile) ?? ""
        speedBytesPerSecond = try container.decodeIfPresent(Double.self, forKey: .speedBytesPerSecond) ?? 0
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        failedFiles = try container.decodeIfPresent([String].self, forKey: .failedFiles) ?? []
        reportDocumentPath = try container.decodeIfPresent(String.self, forKey: .reportDocumentPath)
        localReportDocumentPath = try container.decodeIfPresent(String.self, forKey: .localReportDocumentPath)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
        isBlocked = try container.decodeIfPresent(Bool.self, forKey: .isBlocked) ?? false
    }

    var fraction: Double {
        guard totalBytes > 0 else { return isComplete ? 1 : 0 }
        return min(max(Double(processedBytes) / Double(totalBytes), 0), 1)
    }

    var eta: TimeInterval? {
        guard speedBytesPerSecond > 0, totalBytes > processedBytes else { return nil }
        return Double(totalBytes - processedBytes) / speedBytesPerSecond
    }
}

struct ProjectMediaItem: Codable, Identifiable, Hashable {
    let id: String
    let filePath: String
    let relativePath: String
    let displayName: String
    let createdAt: Date
    let size: Int64
    let mediaKindRawValue: String

    enum CodingKeys: String, CodingKey {
        case id
        case filePath
        case relativePath
        case displayName
        case createdAt
        case size
        case mediaKindRawValue
    }

    init(
        id: String,
        filePath: String,
        relativePath: String,
        displayName: String,
        createdAt: Date,
        size: Int64,
        mediaKindRawValue: String
    ) {
        self.id = id
        self.filePath = filePath
        self.relativePath = relativePath
        self.displayName = displayName
        self.createdAt = createdAt
        self.size = size
        self.mediaKindRawValue = mediaKindRawValue
    }

    init(mediaItem: MediaItem) {
        id = mediaItem.id
        filePath = mediaItem.fileURL.path
        relativePath = mediaItem.relativePath
        displayName = mediaItem.displayName
        createdAt = mediaItem.createdAt
        size = mediaItem.size
        mediaKindRawValue = mediaItem.mediaKind.rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedRelativePath = try container.decodeIfPresent(String.self, forKey: .relativePath)
        let decodedFilePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        let fallbackName = decodedFilePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown"

        relativePath = decodedRelativePath ?? fallbackName
        filePath = decodedFilePath ?? relativePath
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? URL(fileURLWithPath: relativePath).lastPathComponent
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? relativePath
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        size = try container.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        mediaKindRawValue = try container.decodeIfPresent(String.self, forKey: .mediaKindRawValue) ?? ScanFilter.all.rawValue
    }

    var fileURL: URL {
        URL(fileURLWithPath: filePath, isDirectory: false)
    }

    var mediaKind: ScanFilter {
        ScanFilter(rawValue: mediaKindRawValue) ?? .all
    }
}

struct CopyProject: Codable, Identifiable {
    let id: UUID
    var name: String
    var taskFolderName: String
    var createdAt: Date
    var updatedAt: Date
    var sourceName: String
    var sourceVolumePath: String
    var sourceRootPath: String
    var targetRootPath: String
    var backupRootPath: String?
    var selectedItems: [ProjectMediaItem]
    var totalBytes: Int64
    var verificationMode: VerificationMode
    var status: CopyProjectStatus
    var orderIndex: Int
    var primaryCopyState: ProjectStageState
    var primaryVerifyState: ProjectStageState
    var backupCopyState: ProjectStageState
    var backupVerifyState: ProjectStageState
    var primaryReportID: UUID?
    var backupReportID: UUID?
    var skipVerificationConfirmations: Int
    var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case taskFolderName
        case createdAt
        case updatedAt
        case sourceName
        case sourceVolumePath
        case sourceRootPath
        case targetRootPath
        case backupRootPath
        case selectedItems
        case totalBytes
        case verificationMode
        case status
        case orderIndex
        case primaryCopyState
        case primaryVerifyState
        case backupCopyState
        case backupVerifyState
        case primaryReportID
        case backupReportID
        case skipVerificationConfirmations
        case errorMessage
    }

    init(
        id: UUID = UUID(),
        name: String,
        taskFolderName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceName: String,
        sourceVolumePath: String,
        sourceRootPath: String,
        targetRootPath: String,
        backupRootPath: String?,
        selectedItems: [ProjectMediaItem],
        totalBytes: Int64,
        verificationMode: VerificationMode,
        status: CopyProjectStatus = .queued,
        orderIndex: Int
    ) {
        self.id = id
        self.name = name
        self.taskFolderName = taskFolderName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceName = sourceName
        self.sourceVolumePath = sourceVolumePath
        self.sourceRootPath = sourceRootPath
        self.targetRootPath = targetRootPath
        self.backupRootPath = backupRootPath
        self.selectedItems = selectedItems
        self.totalBytes = totalBytes
        self.verificationMode = verificationMode
        self.status = status
        self.orderIndex = orderIndex
        primaryCopyState = ProjectStageState(title: ProjectStageKind.primaryCopy.title)
        primaryVerifyState = ProjectStageState(title: ProjectStageKind.primaryVerify.title)
        backupCopyState = ProjectStageState(title: ProjectStageKind.backupCopy.title, detail: backupRootPath == nil ? "未配置备份盘" : "等待主盘完成")
        backupVerifyState = ProjectStageState(title: ProjectStageKind.backupVerify.title, detail: backupRootPath == nil ? "未配置备份盘" : "等待备份完成")
        primaryReportID = nil
        backupReportID = nil
        skipVerificationConfirmations = 0
        errorMessage = nil
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名项目"
        taskFolderName = try container.decodeIfPresent(String.self, forKey: .taskFolderName)
            ?? FileNameSanitizer.safeComponent(name)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? "未知源设备"
        sourceVolumePath = try container.decodeIfPresent(String.self, forKey: .sourceVolumePath) ?? ""
        sourceRootPath = try container.decodeIfPresent(String.self, forKey: .sourceRootPath) ?? sourceVolumePath
        targetRootPath = try container.decodeIfPresent(String.self, forKey: .targetRootPath) ?? ""
        backupRootPath = try container.decodeIfPresent(String.self, forKey: .backupRootPath)
        selectedItems = try container.decodeIfPresent([ProjectMediaItem].self, forKey: .selectedItems) ?? []
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes)
            ?? selectedItems.reduce(Int64(0)) { $0 + $1.size }

        if let rawVerificationMode = try container.decodeIfPresent(String.self, forKey: .verificationMode),
           let decodedVerificationMode = VerificationMode(rawValue: rawVerificationMode) {
            verificationMode = decodedVerificationMode
        } else {
            verificationMode = .sha256
        }

        if let rawStatus = try container.decodeIfPresent(String.self, forKey: .status),
           let decodedStatus = CopyProjectStatus(rawValue: rawStatus) {
            status = decodedStatus
        } else {
            status = .queued
        }

        orderIndex = try container.decodeIfPresent(Int.self, forKey: .orderIndex) ?? 0
        primaryCopyState = try container.decodeIfPresent(ProjectStageState.self, forKey: .primaryCopyState)
            ?? ProjectStageState(title: ProjectStageKind.primaryCopy.title, totalBytes: totalBytes, totalFiles: selectedItems.count)
        primaryVerifyState = try container.decodeIfPresent(ProjectStageState.self, forKey: .primaryVerifyState)
            ?? ProjectStageState(title: ProjectStageKind.primaryVerify.title, totalBytes: totalBytes, totalFiles: selectedItems.count)
        backupCopyState = try container.decodeIfPresent(ProjectStageState.self, forKey: .backupCopyState)
            ?? ProjectStageState(
                title: ProjectStageKind.backupCopy.title,
                detail: backupRootPath == nil ? "未配置备份盘" : "等待主盘完成",
                totalBytes: backupRootPath == nil ? 0 : totalBytes,
                totalFiles: backupRootPath == nil ? 0 : selectedItems.count
            )
        backupVerifyState = try container.decodeIfPresent(ProjectStageState.self, forKey: .backupVerifyState)
            ?? ProjectStageState(
                title: ProjectStageKind.backupVerify.title,
                detail: backupRootPath == nil ? "未配置备份盘" : "等待备份完成",
                totalBytes: backupRootPath == nil ? 0 : totalBytes,
                totalFiles: backupRootPath == nil ? 0 : selectedItems.count
            )
        primaryReportID = try container.decodeIfPresent(UUID.self, forKey: .primaryReportID)
        backupReportID = try container.decodeIfPresent(UUID.self, forKey: .backupReportID)
        skipVerificationConfirmations = try container.decodeIfPresent(Int.self, forKey: .skipVerificationConfirmations) ?? 0
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }

    var sourceRootURL: URL {
        URL(fileURLWithPath: sourceRootPath, isDirectory: true)
    }

    var targetRootURL: URL {
        URL(fileURLWithPath: targetRootPath, isDirectory: true)
    }

    var backupRootURL: URL? {
        backupRootPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var primaryImportURL: URL {
        targetRootURL.appendingPathComponent(taskFolderName, isDirectory: true)
    }

    var backupImportURL: URL? {
        backupRootURL?.appendingPathComponent(taskFolderName, isDirectory: true)
    }

    var hasBackup: Bool {
        backupRootPath != nil
    }
}

enum FileNameSanitizer {
    static func safeComponent(_ rawValue: String, fallback: String = "Airwang_DIT_Project", maximumLength: Int = 80) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? fallback : trimmed
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_()[]"))
        let scalars = base.unicodeScalars.map { scalar -> Character in
            if allowed.contains(scalar) {
                return Character(scalar)
            }
            return "_"
        }
        let collapsed = String(scalars)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "._- "))
        let safe = collapsed.isEmpty ? fallback : collapsed
        if safe.count <= maximumLength {
            return safe
        }
        return String(safe.prefix(maximumLength)).trimmingCharacters(in: CharacterSet(charactersIn: "._- "))
    }
}

final class ImportInterruptionToken: @unchecked Sendable {
    private let lock = NSLock()
    private var storedReason: String?
    private var storedVerificationModeOverride: VerificationMode?

    var reason: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedReason
    }

    var verificationModeOverride: VerificationMode? {
        lock.lock()
        defer { lock.unlock() }
        return storedVerificationModeOverride
    }

    func reset() {
        lock.lock()
        storedReason = nil
        storedVerificationModeOverride = nil
        lock.unlock()
    }

    func stop(reason: String) {
        lock.lock()
        if storedReason == nil {
            storedReason = reason
        }
        lock.unlock()
    }

    func overrideVerificationMode(_ mode: VerificationMode) {
        lock.lock()
        storedVerificationModeOverride = mode
        lock.unlock()
    }
}

struct TransferState {
    var totalBytes: Int64 = 0
    var processedBytes: Int64 = 0
    var verificationTotalBytes: Int64 = 0
    var verificationProcessedBytes: Int64 = 0
    var copiedFiles: Int = 0
    var verifiedFiles: Int = 0
    var verificationCheckedFiles: Int = 0
    var totalFiles: Int = 0
    var startedAt = Date()
    var verificationStartedAt: Date?
    var currentFile = ""
    var verificationStatus = "等待校验"
    var failedFiles: [String] = []
    var copyFailedFiles: [String] = []
    var verificationFailedFiles: [String] = []
    var skippedFiles: [String] = []
    var phaseTitle = "等待任务"
    var reportSummary = ""
    var isCancelled = false
    var currentSpeedBytesPerSecond: Double = 0
    var currentVerificationSpeedBytesPerSecond: Double = 0
    var interruptionReason: String?

    var copyFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(processedBytes) / Double(totalBytes), 0), 1)
    }

    var verificationFraction: Double {
        if verificationTotalBytes > 0 {
            return min(max(Double(verificationProcessedBytes) / Double(verificationTotalBytes), 0), 1)
        }
        guard totalFiles > 0 else { return 0 }
        return min(max(Double(verificationCheckedFiles) / Double(totalFiles), 0), 1)
    }

    var copySpeedBytesPerSecond: Double {
        if currentSpeedBytesPerSecond > 0 {
            return currentSpeedBytesPerSecond
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 0 else { return 0 }
        return Double(processedBytes) / elapsed
    }

    var verificationSpeedBytesPerSecond: Double {
        if currentVerificationSpeedBytesPerSecond > 0 {
            return currentVerificationSpeedBytesPerSecond
        }

        guard let verificationStartedAt else { return 0 }
        let elapsed = Date().timeIntervalSince(verificationStartedAt)
        guard elapsed > 0 else { return 0 }
        return Double(verificationProcessedBytes) / elapsed
    }

    var speedBytesPerSecond: Double {
        isVerifying ? verificationSpeedBytesPerSecond : copySpeedBytesPerSecond
    }

    var copyETA: TimeInterval? {
        let speed = copySpeedBytesPerSecond
        guard speed > 0 else { return nil }
        return Double(max(totalBytes - processedBytes, 0)) / speed
    }

    var verificationETA: TimeInterval? {
        let speed = verificationSpeedBytesPerSecond
        guard verificationTotalBytes > 0, speed > 0 else { return nil }
        return Double(max(verificationTotalBytes - verificationProcessedBytes, 0)) / speed
    }

    var eta: TimeInterval? {
        isVerifying ? verificationETA : copyETA
    }

    var isVerifying: Bool {
        verificationStartedAt != nil && verificationCheckedFiles < totalFiles
    }
}

struct FileVerificationRecord: Codable, Identifiable {
    var id: String { relativePath }
    let relativePath: String
    let size: Int64
    let sourceChecksum: String?
    let targetChecksum: String?
    let backupChecksum: String?
    let status: String
    let message: String
}

struct TransferReport: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let sourceName: String
    let sourcePath: String
    let sourceRootPath: String?
    let targetPath: String
    let backupPath: String?
    let selectedFileCount: Int
    let totalBytes: Int64
    let verificationMode: String
    let namingRule: String
    let success: Bool
    let cancelled: Bool
    let failedFiles: [String]
    let copyFailedFiles: [String]
    let verificationFailedFiles: [String]
    let skippedFiles: [String]
    let verificationSummary: String
    let interruptionReason: String?
    let duration: TimeInterval
    let reportDocumentPath: String?
    let localReportDocumentPath: String?
    let reportDocumentWriteFailed: Bool
    let importedItems: [String]
    let fileRecords: [FileVerificationRecord]

    var title: String {
        if cancelled {
            return "导入已取消"
        }
        if interruptionReason != nil {
            return "任务已中断"
        }
        if reportDocumentWriteFailed {
            return "报告写入异常"
        }
        return success ? "导入完成" : "导入存在异常"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case finishedAt
        case sourceName
        case sourcePath
        case sourceRootPath
        case targetPath
        case backupPath
        case selectedFileCount
        case totalBytes
        case verificationMode
        case namingRule
        case success
        case cancelled
        case failedFiles
        case copyFailedFiles
        case verificationFailedFiles
        case skippedFiles
        case verificationSummary
        case interruptionReason
        case duration
        case reportDocumentPath
        case localReportDocumentPath
        case reportDocumentWriteFailed
        case importedItems
        case fileRecords
    }

    init(
        id: UUID,
        startedAt: Date,
        finishedAt: Date,
        sourceName: String,
        sourcePath: String,
        sourceRootPath: String?,
        targetPath: String,
        backupPath: String?,
        selectedFileCount: Int,
        totalBytes: Int64,
        verificationMode: String,
        namingRule: String,
        success: Bool,
        cancelled: Bool,
        failedFiles: [String],
        copyFailedFiles: [String],
        verificationFailedFiles: [String],
        skippedFiles: [String],
        verificationSummary: String,
        interruptionReason: String?,
        duration: TimeInterval,
        reportDocumentPath: String?,
        localReportDocumentPath: String?,
        reportDocumentWriteFailed: Bool = false,
        importedItems: [String],
        fileRecords: [FileVerificationRecord]
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.sourceName = sourceName
        self.sourcePath = sourcePath
        self.sourceRootPath = sourceRootPath
        self.targetPath = targetPath
        self.backupPath = backupPath
        self.selectedFileCount = selectedFileCount
        self.totalBytes = totalBytes
        self.verificationMode = verificationMode
        self.namingRule = namingRule
        self.success = success
        self.cancelled = cancelled
        self.failedFiles = failedFiles
        self.copyFailedFiles = copyFailedFiles
        self.verificationFailedFiles = verificationFailedFiles
        self.skippedFiles = skippedFiles
        self.verificationSummary = verificationSummary
        self.interruptionReason = interruptionReason
        self.duration = duration
        self.reportDocumentPath = reportDocumentPath
        self.localReportDocumentPath = localReportDocumentPath
        self.reportDocumentWriteFailed = reportDocumentWriteFailed
        self.importedItems = importedItems
        self.fileRecords = fileRecords
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? .distantPast
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt) ?? startedAt
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? "未知源设备"
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath) ?? ""
        sourceRootPath = try container.decodeIfPresent(String.self, forKey: .sourceRootPath)
        targetPath = try container.decodeIfPresent(String.self, forKey: .targetPath) ?? ""
        backupPath = try container.decodeIfPresent(String.self, forKey: .backupPath)
        selectedFileCount = try container.decodeIfPresent(Int.self, forKey: .selectedFileCount) ?? 0
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        verificationMode = try container.decodeIfPresent(String.self, forKey: .verificationMode) ?? VerificationMode.sha256.title
        namingRule = try container.decodeIfPresent(String.self, forKey: .namingRule) ?? "时间戳+源盘"
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        cancelled = try container.decodeIfPresent(Bool.self, forKey: .cancelled) ?? false
        failedFiles = try container.decodeIfPresent([String].self, forKey: .failedFiles) ?? []
        copyFailedFiles = try container.decodeIfPresent([String].self, forKey: .copyFailedFiles) ?? []
        verificationFailedFiles = try container.decodeIfPresent([String].self, forKey: .verificationFailedFiles) ?? []
        skippedFiles = try container.decodeIfPresent([String].self, forKey: .skippedFiles) ?? []
        verificationSummary = try container.decodeIfPresent(String.self, forKey: .verificationSummary) ?? ""
        interruptionReason = try container.decodeIfPresent(String.self, forKey: .interruptionReason)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
            ?? max(finishedAt.timeIntervalSince(startedAt), 0)
        reportDocumentPath = try container.decodeIfPresent(String.self, forKey: .reportDocumentPath)
        localReportDocumentPath = try container.decodeIfPresent(String.self, forKey: .localReportDocumentPath)
            ?? Self.inferredLocalReportPath(reportDocumentPath: reportDocumentPath, targetPath: targetPath)
        reportDocumentWriteFailed = try container.decodeIfPresent(Bool.self, forKey: .reportDocumentWriteFailed) ?? false
        importedItems = try container.decodeIfPresent([String].self, forKey: .importedItems) ?? []
        fileRecords = try container.decodeIfPresent([FileVerificationRecord].self, forKey: .fileRecords) ?? []
    }

    private static func inferredLocalReportPath(reportDocumentPath: String?, targetPath: String) -> String? {
        let taskFolder = URL(fileURLWithPath: targetPath, isDirectory: true).lastPathComponent
        guard !taskFolder.isEmpty else { return nil }

        let reportKind: String
        if let reportDocumentPath,
           URL(fileURLWithPath: reportDocumentPath).lastPathComponent.localizedCaseInsensitiveContains("backup") {
            reportKind = "Backup"
        } else {
            reportKind = "Copy"
        }
        let localURL = AppStorageScope.localReportDocumentURL(taskFolder: taskFolder, reportKind: reportKind)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL.path
        }

        guard let reportDocumentPath else { return nil }
        let reportName = URL(fileURLWithPath: reportDocumentPath).lastPathComponent
        guard reportName == localURL.lastPathComponent else { return nil }
        return localURL.path
    }
}
