import Darwin
import Foundation

/// The export is an allow-list of scalar diagnostics. Models containing media
/// names, paths, checksums and raw errors never enter the encoded document.
struct SupportDiagnosticsSnapshot: Codable, Sendable {
    static let formatIdentifier = "com.airwang.dit.support-diagnostics"

    let format: String
    let schemaVersion: Int
    let generatedAt: Date
    let application: Application
    let environment: Environment
    let activity: Activity
    let projects: ProjectSummary
    let reports: ReportSummary
    let recentReports: [ReportSample]
    let privacy: Privacy

    struct Application: Codable, Sendable {
        let version: String
        let build: String
        let bundleIdentifier: String
        let developmentBuild: Bool
        let isolatedDevelopmentData: Bool
        let sourceRevision: String
        let buildInputSHA256: String
        let sourceState: String

        static func current() -> Self {
            #if DEBUG
            let development = true
            let variables = ProcessInfo.processInfo.environment
            let isolated = (variables["AIRWANG_DIT_UI_TESTING"] == "1" || variables["AIRWANG_DIT_UNIT_TESTING"] == "1")
                && !(variables["AIRWANG_DIT_APP_SUPPORT_DIR"] ?? "").isEmpty
            #else
            let development = false
            let isolated = false
            #endif
            return fromMetadata(Bundle.main.infoDictionary ?? [:],
                developmentBuild: development,
                isolatedDevelopmentData: isolated
            )
        }

        static func fromMetadata(
            _ metadata: [String: Any], developmentBuild: Bool, isolatedDevelopmentData: Bool
        ) -> Self {
            let state = metadata["AirwangSourceState"] as? String ?? "unknown"
            return Self(
                version: metadata["CFBundleShortVersionString"] as? String ?? "unknown",
                build: metadata["CFBundleVersion"] as? String ?? "unknown",
                bundleIdentifier: metadata["CFBundleIdentifier"] as? String ?? "com.airwang.ditformac",
                developmentBuild: developmentBuild, isolatedDevelopmentData: isolatedDevelopmentData,
                sourceRevision: hexIdentifier(metadata["AirwangSourceRevision"], length: 40),
                buildInputSHA256: hexIdentifier(metadata["AirwangBuildInputSHA256"], length: 64),
                sourceState: ["committed", "working-tree"].contains(state) ? state : "unknown"
            )
        }

        private static func hexIdentifier(_ value: Any?, length: Int) -> String {
            guard let value = value as? String, value.utf8.count == length,
                  value.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                return "unknown"
            }
            return value
        }
    }

    struct Environment: Codable, Sendable {
        let operatingSystem: String
        let architecture: String
        let processorCount: Int
        let physicalMemoryBytes: UInt64

        static func current() -> Self {
            let system = ProcessInfo.processInfo.operatingSystemVersion
            #if arch(arm64)
            let architecture = "arm64"
            #elseif arch(x86_64)
            let architecture = "x86_64"
            #else
            let architecture = "unknown"
            #endif
            return Self(
                operatingSystem: "macOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
                architecture: architecture,
                processorCount: ProcessInfo.processInfo.processorCount,
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
            )
        }
    }

    enum ErrorCategory: String, Codable, Sendable {
        case none, persistence, scan, transfer, organizer, other

        static func classify(_ message: String?) -> Self {
            guard let message, !message.isEmpty else { return .none }
            if message.hasPrefix("保存") || message.contains("JSON") { return .persistence }
            if message.hasPrefix("扫描") { return .scan }
            if message.hasPrefix("规整") || message.hasPrefix("生成规整") { return .organizer }
            if message.hasPrefix("项目执行") || message.hasPrefix("导入任务") { return .transfer }
            return .other
        }
    }

    struct Activity: Codable, Sendable {
        var language = "chinese"
        var theme = "day"
        var executionMode = "sequential"
        var selectedVerificationMode = "sha256"
        var backupEnabled = false
        var scanning = false
        var importing = false
        var organizing = false
        var activeProjectCount = 0
        var unsavedChanges = false
        var errorCategory: ErrorCategory = .none
    }

    struct StageSummary: Codable, Sendable {
        var active = 0
        var complete = 0
        var blocked = 0
        var withFailures = 0
    }

    struct ProjectSummary: Codable, Sendable {
        var total = 0
        var statusCounts: [String: Int] = [:]
        var verificationModeCounts: [String: Int] = [:]
        var withBackup = 0
        var recoveryEnabled = 0
        var stages: [String: StageSummary] = [:]
    }

    struct ReportSummary: Codable, Sendable {
        var total = 0
        var successful = 0
        var cancelled = 0
        var interrupted = 0
        var reportWriteFailures = 0
        var withCopyFailures = 0
        var withVerificationFailures = 0
        var withSkippedFiles = 0
        var invalidMetrics = 0
        var verificationModeCounts: [String: Int] = [:]
    }

    struct ReportSample: Codable, Sendable {
        let reference: Int
        let finishedAt: Date
        let success: Bool
        let cancelled: Bool
        let interrupted: Bool
        let reportWriteFailed: Bool
        let verificationMode: String
        let selectedFileCount: Int
        let copyFailureCount: Int
        let verificationFailureCount: Int
        let skippedFileCount: Int
        let resumedFileCount: Int
    }

    struct Privacy: Codable, Sendable {
        let redacted: Bool
        let includesMediaContent: Bool
        let includesFileNames: Bool
        let includesPaths: Bool
        let includesRawErrors: Bool
        let includesDeviceIdentifiers: Bool
        let includesEnvironmentVariables: Bool
        let automaticallyUploaded: Bool

        init() {
            redacted = true
            includesMediaContent = false
            includesFileNames = false
            includesPaths = false
            includesRawErrors = false
            includesDeviceIdentifiers = false
            includesEnvironmentVariables = false
            automaticallyUploaded = false
        }
    }

    static func capture(
        projects: [CopyProject], reports: [TransferReport], activity: Activity,
        application: Application = .current(), environment: Environment = .current(), now: Date = Date()
    ) -> Self {
        var projectSummary = ProjectSummary(total: projects.count)
        for project in projects {
            projectSummary.statusCounts[project.status.rawValue, default: 0] += 1
            projectSummary.verificationModeCounts[project.verificationMode.rawValue, default: 0] += 1
            projectSummary.withBackup += project.backupRootPath == nil ? 0 : 1
            projectSummary.recoveryEnabled += project.resumeExistingFiles ? 1 : 0
            for (kind, stage) in [
                (ProjectStageKind.primaryCopy, project.primaryCopyState),
                (.primaryVerify, project.primaryVerifyState),
                (.backupCopy, project.backupCopyState),
                (.backupVerify, project.backupVerifyState)
            ] {
                var summary = projectSummary.stages[kind.rawValue] ?? StageSummary()
                summary.active += stage.isActive ? 1 : 0
                summary.complete += stage.isComplete ? 1 : 0
                summary.blocked += stage.isBlocked ? 1 : 0
                summary.withFailures += stage.failedFiles.isEmpty ? 0 : 1
                projectSummary.stages[kind.rawValue] = summary
            }
        }
        var reportSummary = ReportSummary(total: reports.count)
        var samples: [ReportSample] = []
        for (index, report) in reports.enumerated() {
            let mode = verificationModeIdentifier(report.verificationMode)
            reportSummary.successful += report.success ? 1 : 0
            reportSummary.cancelled += report.cancelled ? 1 : 0
            reportSummary.interrupted += report.interruptionReason == nil ? 0 : 1
            reportSummary.reportWriteFailures += report.reportDocumentWriteFailed ? 1 : 0
            reportSummary.withCopyFailures += report.copyFailedFiles.isEmpty ? 0 : 1
            reportSummary.withVerificationFailures += report.verificationFailedFiles.isEmpty ? 0 : 1
            reportSummary.withSkippedFiles += report.skippedFiles.isEmpty ? 0 : 1
            reportSummary.invalidMetrics += report.selectedFileCount < 0 || report.totalBytes < 0 || !report.duration.isFinite ? 1 : 0
            reportSummary.verificationModeCounts[mode, default: 0] += 1
            // AppViewModel maintains its report list in newest-first order. The
            // sample is bounded; the totals above still include all reports.
            if index < 25 {
                samples.append(ReportSample(
                    reference: index + 1, finishedAt: report.finishedAt,
                    success: report.success, cancelled: report.cancelled,
                    interrupted: report.interruptionReason != nil,
                    reportWriteFailed: report.reportDocumentWriteFailed,
                    verificationMode: mode, selectedFileCount: max(0, report.selectedFileCount),
                    copyFailureCount: report.copyFailedFiles.count,
                    verificationFailureCount: report.verificationFailedFiles.count,
                    skippedFileCount: report.skippedFiles.count, resumedFileCount: report.resumedFiles.count
                ))
            }
        }
        return Self(
            format: formatIdentifier, schemaVersion: 1, generatedAt: now,
            application: application, environment: environment, activity: activity,
            projects: projectSummary, reports: reportSummary, recentReports: samples, privacy: Privacy()
        )
    }

    private static func verificationModeIdentifier(_ label: String) -> String {
        VerificationMode.allCases.first { mode in
            [mode.rawValue, mode.title, mode.shortTitle,
             AppLocalization.text(mode.title, language: .english),
             AppLocalization.text(mode.shortTitle, language: .english)].contains(label)
        }?.rawValue ?? "unknown"
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

enum SupportDiagnosticsExporter {
    enum ExportError: Error {
        case invalidDestination
        case destinationExists
    }

    static func defaultFileName(at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return "Airwang-DIT-Diagnostics-\(formatter.string(from: date))-\(UUID().uuidString.prefix(8)).json"
    }

    static func write(_ snapshot: SupportDiagnosticsSnapshot, to selectedOutput: URL) throws {
        try Task.checkCancellation()
        guard selectedOutput.isFileURL, selectedOutput.pathExtension.lowercased() == "json" else {
            throw ExportError.invalidDestination
        }
        let manager = FileManager.default
        // NSSavePanel can return /private/var while Foundation standardizes its
        // existing parent to /var. Rebuild the new leaf from that same parent
        // so containment compares one spelling. Do not resolve user symlinks.
        let parent = selectedOutput.deletingLastPathComponent().standardizedFileURL
        let output = parent.appendingPathComponent(selectedOutput.lastPathComponent, isDirectory: false)
        var directory: ObjCBool = false
        guard manager.fileExists(atPath: parent.path, isDirectory: &directory), directory.boolValue else {
            throw ExportError.invalidDestination
        }
        try PathSafety.ensureSafeWritableFileTarget(for: output, under: parent)
        guard !manager.fileExists(atPath: output.path) else { throw ExportError.destinationExists }
        let replacement = try manager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: output, create: true
        )
        defer { try? manager.removeItem(at: replacement) }
        let staged = replacement.appendingPathComponent("diagnostics.json")
        try snapshot.encoded().write(to: staged, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staged.path)
        let handle = try FileHandle(forWritingTo: staged)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        try Task.checkCancellation()
        try PathSafety.ensureSafeWritableFileTarget(for: output, under: parent)
        let result = staged.path.withCString { source in
            output.path.withCString { target in renamex_np(source, target, UInt32(RENAME_EXCL)) }
        }
        if result != 0 {
            if errno == EEXIST { throw ExportError.destinationExists }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
