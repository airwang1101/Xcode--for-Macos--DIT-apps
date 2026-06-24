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
        case .rename: "同名文件保留两份，例如 A001 2.mov"
        case .skip: "目标位置已有同名文件时不写入"
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

    var title: String {
        switch self {
        case .none: "直接写入"
        case .renamed: "已改名"
        case .skipped: "跳过"
        }
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
        if case .skipped = conflictResolution {
            return false
        }
        return true
    }
}

struct OrganizerPlan: Sendable {
    let id: UUID
    let sourceURL: URL
    let destinationURL: URL
    let rule: OrganizerRule
    let createdAt: Date
    let items: [OrganizerPlanItem]

    var totalFiles: Int { items.count }
    var executableFiles: Int { items.filter(\.isExecutable).count }
    var skippedFiles: Int { items.count - executableFiles }
    var totalBytes: Int64 { items.filter(\.isExecutable).reduce(0) { $0 + $1.size } }

    var dayCount: Int {
        Set(items.map { Calendar.current.startOfDay(for: $0.capturedAt) }).count
    }

    var deviceCount: Int {
        Set(items.map(\.deviceFolderName)).count
    }

    var renamedFiles: Int {
        items.reduce(0) { count, item in
            if case .renamed = item.conflictResolution {
                return count + 1
            }
            return count
        }
    }

    var sampleItems: [OrganizerPlanItem] {
        Array(items.prefix(80))
    }
}

struct OrganizerExecutionState: Equatable, Sendable {
    var totalBytes: Int64 = 0
    var processedBytes: Int64 = 0
    var totalFiles: Int = 0
    var processedFiles: Int = 0
    var skippedFiles: Int = 0
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
    let failedFiles: [String]
    let totalBytes: Int64
    let startedAt: Date
    let finishedAt: Date

    var success: Bool {
        failedFiles.isEmpty
    }
}
