import Foundation

enum OrganizerOperationMode: String, CaseIterable, Identifiable, Sendable {
    case copy
    case move

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: "复制规整"
        case .move: "移动规整"
        }
    }

    var subtitle: String {
        switch self {
        case .copy: "保留原文件，在目标文件夹生成规整结构"
        case .move: "完成后源文件会离开原位置，执行前先看预览"
        }
    }

    var systemImage: String {
        switch self {
        case .copy: "doc.on.doc"
        case .move: "arrowshape.turn.up.right"
        }
    }
}

enum OrganizerDuplicatePolicy: String, CaseIterable, Identifiable, Sendable {
    case rename
    case skip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rename: "自动加序号"
        case .skip: "跳过已存在"
        }
    }

    var subtitle: String {
        switch self {
        case .rename: "同名不同内容时保留两份，例如 A001 2.mov；内容相同自动跳过"
        case .skip: "目标位置已有同名文件时不写入；内容相同标记为重复"
        }
    }
}

/// 规整预览列表的显示范围。
enum OrganizerPreviewFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case conflicts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .conflicts: "仅冲突"
        }
    }
}

/// 生成规整预览时的阶段性进度，用于把长时间的扫描/查重过程反馈到界面。
enum OrganizerPlanProgress: Equatable, Sendable {
    case scanning(found: Int)
    case readingMetadata(processed: Int, total: Int)
    case resolving(processed: Int, total: Int)

    var message: String {
        switch self {
        case let .scanning(found):
            return "正在扫描：已发现 \(found) 个文件"
        case let .readingMetadata(processed, total):
            return "读取拍摄信息：\(processed)/\(total)"
        case let .resolving(processed, total):
            return "查重与冲突检查：\(processed)/\(total)"
        }
    }
}

struct OrganizerRule: Equatable, Sendable {
    var scanFilter: ScanFilter
    var operationMode: OrganizerOperationMode
    var duplicatePolicy: OrganizerDuplicatePolicy
}

enum OrganizerConflictResolution: Hashable, Sendable {
    case none
    case renamed(originalPath: String)
    case skipped(existingPath: String)
    /// 查重命中：目标位置（或同批更早的文件）已有一份内容完全相同的文件，
    /// 无需再写一份副本。与 `skipped` 的区别是它经过了逐字节内容比对，
    /// 跳过它不会丢失任何素材。
    case duplicate(existingPath: String)

    var title: String {
        switch self {
        case .none: "直接写入"
        case .renamed: "已改名"
        case .skipped: "跳过"
        case .duplicate: "内容重复"
        }
    }

    var isConflict: Bool {
        if case .none = self { return false }
        return true
    }
}

struct OrganizerPlanItem: Identifiable, Hashable, Sendable {
    let id: String
    let sourceURL: URL
    let destinationURL: URL
    let relativePath: String
    let displayName: String
    let capturedAt: Date
    let deviceName: String
    let deviceFolderName: String
    let size: Int64
    let mediaKind: ScanFilter
    let conflictResolution: OrganizerConflictResolution

    var isExecutable: Bool {
        switch conflictResolution {
        case .skipped, .duplicate:
            return false
        case .none, .renamed:
            return true
        }
    }
}

struct OrganizerPlan: Sendable {
    let id: UUID
    let sourceURL: URL
    let destinationURL: URL
    let rule: OrganizerRule
    let createdAt: Date
    let items: [OrganizerPlanItem]

    // 计数器在构造时单遍算好存下来。它们被规整预览卡和统计页在每次 body
    // 求值时反复读取；若保持计算属性，万级条目的计划会在每次 @Published
    // 发布时做几十万次迭代（dayCount 还带 startOfDay 日历调用）。
    let totalFiles: Int
    let executableFiles: Int
    let totalBytes: Int64
    let dayCount: Int
    let deviceCount: Int
    let renamedFiles: Int
    /// 查重命中的文件数：目标或同批已有内容完全相同的副本。
    let duplicateFiles: Int
    let conflictFiles: Int

    var skippedFiles: Int { totalFiles - executableFiles }

    init(
        id: UUID,
        sourceURL: URL,
        destinationURL: URL,
        rule: OrganizerRule,
        createdAt: Date,
        items: [OrganizerPlanItem]
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.rule = rule
        self.createdAt = createdAt
        self.items = items

        var executable = 0
        var bytes: Int64 = 0
        var renamed = 0
        var duplicates = 0
        var conflicts = 0
        var days = Set<Date>()
        var devices = Set<String>()
        let calendar = Calendar.current
        for item in items {
            if item.isExecutable {
                executable += 1
                bytes += item.size
            }
            switch item.conflictResolution {
            case .none: break
            case .renamed:
                renamed += 1
                conflicts += 1
            case .duplicate:
                duplicates += 1
                conflicts += 1
            case .skipped:
                conflicts += 1
            }
            days.insert(calendar.startOfDay(for: item.capturedAt))
            devices.insert(item.deviceFolderName)
        }
        totalFiles = items.count
        executableFiles = executable
        totalBytes = bytes
        renamedFiles = renamed
        duplicateFiles = duplicates
        conflictFiles = conflicts
        dayCount = days.count
        deviceCount = devices.count
    }

    /// 预览列表数据：全部时截取前 80 条；仅冲突时上限放宽，方便逐条核对查重结果。
    func previewItems(filter: OrganizerPreviewFilter) -> [OrganizerPlanItem] {
        switch filter {
        case .all:
            return Array(items.prefix(80))
        case .conflicts:
            return Array(items.lazy.filter { $0.conflictResolution.isConflict }.prefix(300))
        }
    }
}

struct OrganizerExecutionState: Equatable, Sendable {
    var totalBytes: Int64 = 0
    var processedBytes: Int64 = 0
    var totalFiles: Int = 0
    var processedFiles: Int = 0
    var skippedFiles: Int = 0
    /// skippedFiles 的子集：因为内容与目标完全一致而跳过的文件。
    var duplicateFiles: Int = 0
    var failedFiles: [String] = []
    var currentFile: String = ""
    var phaseTitle: String = "等待规整"
    var startedAt: Date?
    var finishedAt: Date?
    var isActive: Bool = false

    var fraction: Double {
        guard totalBytes > 0 else { return totalFiles > 0 && processedFiles >= totalFiles ? 1 : 0 }
        return min(max(Double(processedBytes) / Double(totalBytes), 0), 1)
    }
}

struct OrganizerRunSummary: Equatable, Sendable {
    let operationMode: OrganizerOperationMode
    let totalFiles: Int
    let completedFiles: Int
    let skippedFiles: Int
    /// skippedFiles 的子集：内容查重命中而跳过的文件。
    var duplicateFiles: Int = 0
    let failedFiles: [String]
    let totalBytes: Int64
    let startedAt: Date
    let finishedAt: Date

    var success: Bool {
        failedFiles.isEmpty
    }
}

struct OrganizerStatisticsSnapshot: Equatable, Sendable {
    let plannedFiles: Int
    let executableFiles: Int
    let previewSkippedFiles: Int
    let plannedBytes: Int64
    let dayCount: Int
    let deviceCount: Int
    let renamedFiles: Int
    /// 预览中查重命中的文件数。
    var duplicateFiles: Int = 0
    let lastOperationMode: OrganizerOperationMode?
    let lastTotalFiles: Int
    let lastCompletedFiles: Int
    let lastSkippedFiles: Int
    let lastFailedFiles: Int
    let lastBytes: Int64
    let lastDuration: TimeInterval

    var hasPreviewData: Bool {
        plannedFiles > 0
    }

    var hasLastRunData: Bool {
        lastTotalFiles > 0
    }

    var hasAnyData: Bool {
        hasPreviewData || hasLastRunData
    }

    static func make(plan: OrganizerPlan?, lastSummary: OrganizerRunSummary?) -> OrganizerStatisticsSnapshot {
        let lastDuration: TimeInterval
        if let lastSummary {
            lastDuration = max(lastSummary.finishedAt.timeIntervalSince(lastSummary.startedAt), 0)
        } else {
            lastDuration = 0
        }

        return OrganizerStatisticsSnapshot(
            plannedFiles: plan?.totalFiles ?? 0,
            executableFiles: plan?.executableFiles ?? 0,
            previewSkippedFiles: plan?.skippedFiles ?? 0,
            plannedBytes: plan?.totalBytes ?? 0,
            dayCount: plan?.dayCount ?? 0,
            deviceCount: plan?.deviceCount ?? 0,
            renamedFiles: plan?.renamedFiles ?? 0,
            duplicateFiles: plan?.duplicateFiles ?? 0,
            lastOperationMode: lastSummary?.operationMode,
            lastTotalFiles: lastSummary?.totalFiles ?? 0,
            lastCompletedFiles: lastSummary?.completedFiles ?? 0,
            lastSkippedFiles: lastSummary?.skippedFiles ?? 0,
            lastFailedFiles: lastSummary?.failedFiles.count ?? 0,
            lastBytes: lastSummary?.totalBytes ?? 0,
            lastDuration: lastDuration
        )
    }
}
