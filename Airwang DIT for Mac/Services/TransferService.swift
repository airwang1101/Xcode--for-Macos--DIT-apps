import CryptoKit
import Darwin
import Foundation

struct TransferService {
    private static let userCancellationReason = "用户取消了导入任务"

    enum TransferError: LocalizedError {
        case insufficientSpace(destination: String, available: Int64, required: Int64)
        case deviceUnavailable(role: String, path: String)
        case destinationNotWritable(role: String, path: String)
        case transferInterrupted(reason: String)
        case pathOverlap(String)
        case copySizeMismatch(file: String, expected: Int64, actual: Int64)

        var errorDescription: String? {
            switch self {
            case let .insufficientSpace(destination, available, required):
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                return "\(destination) 剩余空间不足：需要 \(formatter.string(fromByteCount: required))，当前可用 \(formatter.string(fromByteCount: available))。"
            case let .deviceUnavailable(role, path):
                return "\(role) 已断开或不可访问：\(path)"
            case let .destinationNotWritable(role, path):
                return "\(role) 不可写或位于只读卷：\(path)"
            case let .transferInterrupted(reason):
                return reason
            case let .pathOverlap(message):
                return message
            case let .copySizeMismatch(file, expected, actual):
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                return "\(file) 写入大小不一致：应为 \(formatter.string(fromByteCount: expected))，实际 \(formatter.string(fromByteCount: actual))。"
            }
        }
    }

    struct Destination {
        let rootURL: URL
        let label: String
    }

    struct TransferResult {
        let report: TransferReport
    }

    enum ProjectTransferStage {
        case primary
        case backup

        var destinationLabel: String {
            switch self {
            case .primary: "主目标盘"
            case .backup: "备份盘"
            }
        }

        var reportKind: String {
            switch self {
            case .primary: "Primary_Copy"
            case .backup: "Backup"
            }
        }

        var reportTitle: String {
            switch self {
            case .primary: "Airwang DIT for Mac 主盘拷贝报告"
            case .backup: "Airwang DIT for Mac 备份报告"
            }
        }

        var copyPhaseTitle: String {
            switch self {
            case .primary: "正在拷贝到主目标盘"
            case .backup: "正在从主目标盘备份"
            }
        }

        var verifyPhaseTitle: String {
            switch self {
            case .primary: "正在校验主目标盘"
            case .backup: "正在校验备份盘"
            }
        }
    }

    struct ProjectStageResult {
        let report: TransferReport
        let finalState: TransferState
    }

    private struct ReportDocumentWriteResult {
        let requestedTargetURL: URL?
        let targetURL: URL?
        let localURL: URL?
        let note: String?

        var hasFailure: Bool {
            localURL == nil || (requestedTargetURL != nil && targetURL == nil)
        }
    }

    func runPrimaryStage(
        project: CopyProject,
        interruptionToken: ImportInterruptionToken? = nil,
        language: AppLanguage = .chinese,
        progress: @escaping @Sendable (TransferState) async -> Void
    ) async throws -> ProjectStageResult {
        try await runProjectStage(
            project: project,
            stage: .primary,
            interruptionToken: interruptionToken,
            language: language,
            progress: progress
        )
    }

    func runBackupStage(
        project: CopyProject,
        interruptionToken: ImportInterruptionToken? = nil,
        language: AppLanguage = .chinese,
        progress: @escaping @Sendable (TransferState) async -> Void
    ) async throws -> ProjectStageResult {
        try await runProjectStage(
            project: project,
            stage: .backup,
            interruptionToken: interruptionToken,
            language: language,
            progress: progress
        )
    }

    private func runProjectStage(
        project: CopyProject,
        stage: ProjectTransferStage,
        interruptionToken: ImportInterruptionToken?,
        language: AppLanguage,
        progress: @escaping @Sendable (TransferState) async -> Void
    ) async throws -> ProjectStageResult {
        let startedAt = Date()
        let sources = project.selectedItems
        let totalBytes = project.totalBytes
        let totalFiles = sources.count
        let sourceBaseURL: URL
        let sourceLabel: String
        let destinationRootURL: URL
        let destinationFolderURL: URL

        switch stage {
        case .primary:
            sourceBaseURL = project.sourceRootURL
            sourceLabel = "源设备"
            destinationRootURL = project.targetRootURL
            destinationFolderURL = project.primaryImportURL
        case .backup:
            guard let backupRootURL = project.backupRootURL,
                  let backupImportURL = project.backupImportURL else {
                throw TransferError.deviceUnavailable(role: "备份盘", path: project.backupRootPath ?? "未配置")
            }
            sourceBaseURL = project.primaryImportURL
            sourceLabel = "主目标盘"
            destinationRootURL = backupRootURL
            destinationFolderURL = backupImportURL
        }

        let destination = Destination(rootURL: destinationRootURL, label: stage.destinationLabel)
        // SHA-256 模式下源哈希在拷贝读取时内联计算,校验阶段只需重读目标一遍,
        // 因此预估工作量按"全部源已预哈希"计。
        let plannedInlineHashing = project.verificationMode == .sha256
        let verificationTotalWorkBytes = verificationWorkBytes(
            for: sources,
            mode: project.verificationMode,
            destinationCount: 1,
            prehashedPaths: plannedInlineHashing ? Set(sources.map(\.relativePath)) : []
        )
        let reportDocumentURL = destinationFolderURL
            .appendingPathComponent("Airwang_\(stage.reportKind)_Report_\(project.taskFolderName).txt")
        let fallbackReportDocumentURL = AppStorageScope.localReportDocumentURL(
            taskFolder: project.taskFolderName,
            reportKind: stage.reportKind
        )

        var state = TransferState(
            totalBytes: totalBytes,
            processedBytes: 0,
            verificationTotalBytes: verificationTotalWorkBytes,
            verificationProcessedBytes: 0,
            copiedFiles: 0,
            verifiedFiles: 0,
            verificationCheckedFiles: 0,
            totalFiles: totalFiles,
            startedAt: startedAt,
            verificationStartedAt: nil,
            currentFile: "",
            verificationStatus: "等待校验",
            failedFiles: [],
            phaseTitle: stage.copyPhaseTitle,
            reportSummary: ""
        )
        await progress(state)

        var failedFiles: [String] = []
        var copyFailedFiles: [String] = []
        var verificationFailedFiles: [String] = []
        var skippedFiles: [String] = []
        var fileRecords: [FileVerificationRecord] = []
        var copiedItemPaths = Set<String>()
        var fatalStopReason: String?
        var preflightFailureMessage: String?
        var stageVerificationMode = project.verificationMode
        var inlineSourceHashes: [String: String] = [:]

        do {
            try validateProjectStageSeparation(project: project, stage: stage)
            try validateRelativePaths(sources)
            try ensureAvailable(sourceBaseURL, role: sourceLabel)
            try ensureAvailable(destinationRootURL, role: stage.destinationLabel)
            try ensureWritableDestination(destinationRootURL, role: stage.destinationLabel)
            try preflightSpace(destinations: [destination], requiredBytes: totalBytes)
            sweepStaleTempFiles(in: destinationFolderURL)
        } catch {
            preflightFailureMessage = error.localizedDescription
            failedFiles = sources.map(\.relativePath)
            skippedFiles = failedFiles
            fileRecords = sources.map { item in
                FileVerificationRecord(
                    relativePath: item.relativePath,
                    size: item.size,
                    sourceChecksum: nil,
                    targetChecksum: nil,
                    backupChecksum: nil,
                    status: "未执行",
                    message: "阶段预检失败，未开始拷贝：\(error.localizedDescription)"
                )
            }
            state.phaseTitle = "预检失败，已生成报告"
            state.verificationStatus = "未开始拷贝"
            state.failedFiles = failedFiles
            state.skippedFiles = skippedFiles
            state.reportSummary = "阶段预检失败：\(error.localizedDescription)"
            await progress(state)
        }

        if preflightFailureMessage == nil {
            for (index, item) in sources.enumerated() {
                state.currentFile = item.relativePath
                state.phaseTitle = stage.copyPhaseTitle
                state.verificationStatus = "等待校验"
                await progress(state)

                do {
                    try checkInterruption(interruptionToken)
                    try ensureAvailable(sourceBaseURL, role: sourceLabel)
                    try ensureAvailable(destinationRootURL, role: stage.destinationLabel)
                    let sourceFileURL = try PathSafety.resolvedURL(for: item.relativePath, under: sourceBaseURL)
                    let targetFileURL = try PathSafety.resolvedURL(for: item.relativePath, under: destinationFolderURL)
                    // 校验模式可能在拷贝途中被用户改为"跳过",逐文件取当前生效模式。
                    let wantsInlineHash = (interruptionToken?.verificationModeOverride ?? project.verificationMode) == .sha256
                    if let inlineHash = try await copySourceFile(
                        sourceURL: sourceFileURL,
                        relativePath: item.relativePath,
                        expectedSize: item.size,
                        to: targetFileURL,
                        destination: destination,
                        sourceRoot: sourceBaseURL,
                        sourceRole: sourceLabel,
                        computeSourceHash: wantsInlineHash,
                        interruptionToken: interruptionToken,
                        state: &state,
                        progress: progress
                    ) {
                        inlineSourceHashes[item.relativePath] = inlineHash
                    }

                    copiedItemPaths.insert(item.relativePath)
                    state.copiedFiles += 1
                    await progress(state)
                } catch {
                    let handledError: Error = error is CancellationError
                        ? TransferError.transferInterrupted(reason: Self.userCancellationReason)
                        : error
                    let message = handledError.localizedDescription
                    appendUnique(item.relativePath, to: &failedFiles)
                    appendUnique(item.relativePath, to: &copyFailedFiles)
                    fileRecords.append(
                        FileVerificationRecord(
                            relativePath: item.relativePath,
                            size: item.size,
                            sourceChecksum: nil,
                            targetChecksum: nil,
                            backupChecksum: nil,
                            status: "拷贝失败",
                            message: message
                        )
                    )
                    state.failedFiles = failedFiles
                    state.copyFailedFiles = copyFailedFiles
                    state.currentSpeedBytesPerSecond = 0
                    state.verificationStatus = "拷贝异常"
                    await progress(state)

                    if let reason = fatalInterruptionReason(
                        for: handledError,
                        sourceURL: sourceBaseURL,
                        destinations: [destination],
                        sourceRole: sourceLabel
                    ) {
                        fatalStopReason = reason
                        state.phaseTitle = "设备中断，正在安全收尾"
                        state.verificationStatus = "任务已停止"
                        state.interruptionReason = reason

                        for remainingItem in sources.dropFirst(index + 1) {
                            appendUnique(remainingItem.relativePath, to: &failedFiles)
                            appendUnique(remainingItem.relativePath, to: &skippedFiles)
                        }
                        state.failedFiles = failedFiles
                        state.skippedFiles = skippedFiles
                        await progress(state)
                        break
                    }
                }
            }
        }

        if preflightFailureMessage == nil {
            if let fatalStopReason {
                for item in sources where !fileRecords.contains(where: { $0.relativePath == item.relativePath }) {
                    appendUnique(item.relativePath, to: &failedFiles)
                    appendUnique(item.relativePath, to: &skippedFiles)
                    fileRecords.append(
                        FileVerificationRecord(
                            relativePath: item.relativePath,
                            size: item.size,
                            sourceChecksum: nil,
                            targetChecksum: nil,
                            backupChecksum: nil,
                            status: copiedItemPaths.contains(item.relativePath) ? "未校验" : "未执行",
                            message: "任务中断，未完成阶段校验：\(fatalStopReason)"
                        )
                    )
                }
                state.phaseTitle = "设备中断，任务已安全停止"
                state.verificationStatus = "未完成校验"
                state.verificationCheckedFiles = totalFiles
                state.failedFiles = failedFiles
                state.skippedFiles = skippedFiles
                state.interruptionReason = fatalStopReason
                await progress(state)
            } else {
                stageVerificationMode = interruptionToken?.verificationModeOverride ?? project.verificationMode
                state.phaseTitle = stage.verifyPhaseTitle
                state.verificationStatus = stageVerificationMode == .skipped ? "用户已跳过校验" : "校验中"
                state.currentFile = "正在校验 \(stage.destinationLabel)"
                state.currentSpeedBytesPerSecond = 0
                state.verificationStartedAt = Date()
                state.verificationTotalBytes = verificationWorkBytes(for: sources, mode: stageVerificationMode, destinationCount: 1, prehashedPaths: Set(inlineSourceHashes.keys))
                state.verificationProcessedBytes = 0
                state.currentVerificationSpeedBytesPerSecond = 0
                await progress(state)

                for (index, item) in sources.enumerated() {
                    let effectiveVerificationMode = interruptionToken?.verificationModeOverride ?? stageVerificationMode
                    if effectiveVerificationMode != stageVerificationMode {
                        stageVerificationMode = effectiveVerificationMode
                        let remainingWorkBytes = sources.dropFirst(index).reduce(Int64(0)) {
                            $0 + verificationWorkBytes(for: $1, mode: stageVerificationMode, destinationCount: 1, prehashedPaths: Set(inlineSourceHashes.keys))
                        }
                        state.verificationTotalBytes = max(state.verificationProcessedBytes + remainingWorkBytes, state.verificationProcessedBytes)
                        state.verificationStatus = stageVerificationMode == .skipped ? "用户已跳过校验" : "校验中"
                        await progress(state)
                    }

                    let itemWorkBytes = verificationWorkBytes(for: item, mode: stageVerificationMode, destinationCount: 1, prehashedPaths: Set(inlineSourceHashes.keys))
                    let itemStartBytes = state.verificationProcessedBytes

                    if copyFailedFiles.contains(item.relativePath) {
                        appendUnique(item.relativePath, to: &skippedFiles)
                        state.skippedFiles = skippedFiles
                        state.verificationCheckedFiles += 1
                        completeVerificationProgress(
                            itemStartBytes: itemStartBytes,
                            itemWorkBytes: itemWorkBytes,
                            state: &state
                        )
                        await progress(state)
                        continue
                    }

                    state.currentFile = item.relativePath
                    await progress(state)
                    do {
                        try checkInterruption(interruptionToken)
                        let sourceFileURL = try PathSafety.resolvedURL(for: item.relativePath, under: sourceBaseURL)
                        let targetFileURL = try PathSafety.resolvedURL(for: item.relativePath, under: destinationFolderURL)
                        let record = try await verifyProjectFile(
                            item: item,
                            sourceURL: sourceFileURL,
                            targetURL: targetFileURL,
                            sourceRoot: sourceBaseURL,
                            destinationRoot: destination.rootURL,
                            mode: stageVerificationMode,
                            stage: stage,
                            itemStartBytes: itemStartBytes,
                            itemWorkBytes: itemWorkBytes,
                            precomputedSourceHash: inlineSourceHashes[item.relativePath],
                            interruptionToken: interruptionToken,
                            state: &state,
                            progress: progress
                        )
                        fileRecords.append(record)
                        completeVerificationProgress(
                            itemStartBytes: itemStartBytes,
                            itemWorkBytes: itemWorkBytes,
                            state: &state
                        )
                        if stageVerificationMode == .skipped {
                            appendUnique(item.relativePath, to: &skippedFiles)
                            state.skippedFiles = skippedFiles
                        } else {
                            state.verifiedFiles += 1
                        }
                        state.verificationCheckedFiles += 1
                        await progress(state)
                    } catch {
                        let handledError: Error = error is CancellationError
                            ? TransferError.transferInterrupted(reason: Self.userCancellationReason)
                            : error
                        let message = handledError.localizedDescription
                        appendUnique(item.relativePath, to: &failedFiles)
                        appendUnique(item.relativePath, to: &verificationFailedFiles)
                        state.failedFiles = failedFiles
                        state.verificationFailedFiles = verificationFailedFiles
                        state.verificationCheckedFiles += 1
                        completeVerificationProgress(
                            itemStartBytes: itemStartBytes,
                            itemWorkBytes: itemWorkBytes,
                            state: &state
                        )
                        state.verificationStatus = "校验发现异常"
                        fileRecords.append(
                            FileVerificationRecord(
                                relativePath: item.relativePath,
                                size: item.size,
                                sourceChecksum: nil,
                                targetChecksum: nil,
                                backupChecksum: nil,
                                status: "异常",
                                message: message
                            )
                        )
                        await progress(state)

                        if let reason = fatalInterruptionReason(
                            for: handledError,
                            sourceURL: sourceBaseURL,
                            destinations: [destination],
                            sourceRole: sourceLabel
                        ) {
                            fatalStopReason = reason
                            state.phaseTitle = "设备中断，任务已安全停止"
                            state.verificationStatus = "校验被中断"
                            state.interruptionReason = reason

                            for remainingItem in sources.dropFirst(index + 1) {
                                appendUnique(remainingItem.relativePath, to: &failedFiles)
                                appendUnique(remainingItem.relativePath, to: &skippedFiles)
                                if !fileRecords.contains(where: { $0.relativePath == remainingItem.relativePath }) {
                                    fileRecords.append(
                                        FileVerificationRecord(
                                            relativePath: remainingItem.relativePath,
                                            size: remainingItem.size,
                                            sourceChecksum: nil,
                                            targetChecksum: nil,
                                            backupChecksum: nil,
                                            status: "未校验",
                                            message: "校验中断，未继续处理：\(reason)"
                                        )
                                    )
                                }
                            }
                            state.failedFiles = failedFiles
                            state.skippedFiles = skippedFiles
                            state.verificationCheckedFiles = totalFiles
                            await progress(state)
                            break
                        }
                    }
                }
            }
        }

        let finishedAt = Date()
        let wasCancelled = fatalStopReason == Self.userCancellationReason
        let verificationSummary = makeProjectVerificationSummary(
            stage: stage,
            mode: stageVerificationMode,
            totalFiles: totalFiles,
            failedFiles: failedFiles,
            preflightFailureMessage: preflightFailureMessage,
            fatalStopReason: fatalStopReason
        )
        var reportProject = project
        reportProject.verificationMode = stageVerificationMode
        let reportDocumentWriteResult = writeProjectReportDocument(
            to: preflightFailureMessage == nil ? reportDocumentURL : nil,
            fallbackURL: fallbackReportDocumentURL,
            targetRootURL: destination.rootURL,
            startedAt: startedAt,
            finishedAt: finishedAt,
            project: reportProject,
            stage: stage,
            sourceBaseURL: sourceBaseURL,
            destinationFolderURL: destinationFolderURL,
            destination: destination,
            copyFailedFiles: copyFailedFiles,
            verificationFailedFiles: verificationFailedFiles,
            skippedFiles: skippedFiles,
            fileRecords: fileRecords,
            failedFiles: failedFiles,
            interruptionReason: fatalStopReason,
            verificationSummary: verificationSummary,
            language: language
        )
        let finalVerificationSummary = [verificationSummary, reportDocumentWriteResult.note]
            .compactMap { $0 }
            .joined(separator: " ")
        let reportWriteFailed = reportDocumentWriteResult.hasFailure

        state.phaseTitle = finalProjectPhaseTitle(
            stage: stage,
            failedFiles: failedFiles,
            cancelled: wasCancelled,
            reportWriteFailed: reportWriteFailed,
            preflightFailureMessage: preflightFailureMessage
        )
        state.verificationStatus = failedFiles.isEmpty && !reportWriteFailed ? "阶段完成" : "阶段存在异常"
        state.failedFiles = failedFiles
        state.copyFailedFiles = copyFailedFiles
        state.verificationFailedFiles = verificationFailedFiles
        state.skippedFiles = skippedFiles
        state.reportSummary = finalVerificationSummary
        state.interruptionReason = fatalStopReason
        await progress(state)

        let report = TransferReport(
            id: UUID(),
            startedAt: startedAt,
            finishedAt: finishedAt,
            sourceName: project.sourceName,
            sourcePath: project.sourceVolumePath,
            sourceRootPath: project.sourceRootPath,
            targetPath: project.primaryImportURL.path,
            backupPath: project.backupImportURL?.path,
            selectedFileCount: totalFiles,
            totalBytes: totalBytes,
            verificationMode: stageVerificationMode.title,
            namingRule: project.name,
            success: failedFiles.isEmpty && !wasCancelled && !reportWriteFailed,
            cancelled: wasCancelled,
            failedFiles: failedFiles,
            copyFailedFiles: copyFailedFiles,
            verificationFailedFiles: verificationFailedFiles,
            skippedFiles: skippedFiles,
            verificationSummary: finalVerificationSummary,
            interruptionReason: fatalStopReason,
            duration: finishedAt.timeIntervalSince(startedAt),
            reportDocumentPath: reportDocumentWriteResult.targetURL?.path,
            localReportDocumentPath: reportDocumentWriteResult.localURL?.path,
            reportDocumentWriteFailed: reportWriteFailed,
            importedItems: sources.map(\.relativePath),
            fileRecords: fileRecords
        )

        return ProjectStageResult(report: report, finalState: state)
    }

    func runImport(
        summary: ImportSelectionSummary,
        interruptionToken: ImportInterruptionToken? = nil,
        language: AppLanguage = .chinese,
        progress: @escaping @Sendable (TransferState) async -> Void
    ) async throws -> TransferResult {
        let startedAt = Date()
        let sources = summary.selectedItems
        let totalBytes = sources.reduce(0) { $0 + $1.size }
        let totalFiles = sources.count
        let taskFolder = makeTaskFolderName(from: startedAt, sourceName: summary.sourceVolume.name)
        let destinations = buildDestinations(targetURL: summary.targetURL, backupURL: summary.backupURL)
        let copyWorkBytes = totalBytes * Int64(destinations.count)
        let verificationWorkBytes = totalBytes * Int64(1 + destinations.count)
        let primaryImportFolder = summary.targetURL.appendingPathComponent(taskFolder, isDirectory: true)
        let reportDocumentURL = primaryImportFolder.appendingPathComponent("Airwang_Copy_Report_\(taskFolder).txt")
        let fallbackReportDocumentURL = localReportDocumentURL(taskFolder: taskFolder)

        var state = TransferState(
            totalBytes: copyWorkBytes,
            processedBytes: 0,
            verificationTotalBytes: verificationWorkBytes,
            verificationProcessedBytes: 0,
            copiedFiles: 0,
            verifiedFiles: 0,
            verificationCheckedFiles: 0,
            totalFiles: totalFiles,
            startedAt: startedAt,
            verificationStartedAt: nil,
            currentFile: "",
            verificationStatus: "等待整批校验",
            failedFiles: [],
            phaseTitle: "正在拷贝素材",
            reportSummary: ""
        )
        await progress(state)

        var failedFiles: [String] = []
        var copyFailedFiles: [String] = []
        var verificationFailedFiles: [String] = []
        var skippedFiles: [String] = []
        var fileRecords: [FileVerificationRecord] = []
        var copiedItemPaths: Set<String> = []
        var fatalStopReason: String?

        do {
            try validateDestinationSeparation(summary: summary)
            try validateRelativePaths(sources)
            try ensureRequiredLocations(summary: summary, destinations: destinations)
            try preflightSpace(destinations: destinations, requiredBytes: totalBytes)
        } catch {
            let result = makePreflightFailureResult(
                error: error,
                state: &state,
                startedAt: startedAt,
                taskFolder: taskFolder,
                summary: summary,
                destinations: destinations,
                primaryImportFolder: primaryImportFolder,
                reportDocumentURL: reportDocumentURL,
                fallbackReportDocumentURL: fallbackReportDocumentURL,
                language: language
            )
            await progress(state)
            return result
        }

        for (index, item) in sources.enumerated() {
            state.currentFile = item.relativePath
            state.phaseTitle = "正在拷贝素材"
            state.verificationStatus = "等待整批校验"
            await progress(state)

            var installedFiles: [URL] = []
            do {
                try checkInterruption(interruptionToken)
                try ensureRequiredLocations(summary: summary, destinations: destinations)

                for destination in destinations {
                    let targetFolder = destination.rootURL.appendingPathComponent(taskFolder, isDirectory: true)
                    let targetFile = try PathSafety.resolvedURL(for: item.relativePath, under: targetFolder)
                    let sourceFile = try PathSafety.resolvedURL(for: item.relativePath, under: summary.sourceRootURL)
                    try await copy(
                        item: item,
                        sourceURL: sourceFile,
                        to: targetFile,
                        destination: destination,
                        sourceRoot: summary.sourceRootURL,
                        interruptionToken: interruptionToken,
                        state: &state,
                        progress: progress
                    )
                    installedFiles.append(targetFile)
                }

                state.copiedFiles += 1
                copiedItemPaths.insert(item.relativePath)
                await progress(state)
            } catch {
                let cleanupMessage = cleanupInstalledCopies(installedFiles)
                let handledError: Error = error is CancellationError
                    ? TransferError.transferInterrupted(reason: Self.userCancellationReason)
                    : error
                let message = [handledError.localizedDescription, cleanupMessage]
                    .compactMap { $0 }
                    .joined(separator: " ")
                appendUnique(item.relativePath, to: &failedFiles)
                appendUnique(item.relativePath, to: &copyFailedFiles)
                fileRecords.append(
                    FileVerificationRecord(
                        relativePath: item.relativePath,
                        size: item.size,
                        sourceChecksum: nil,
                        targetChecksum: nil,
                        backupChecksum: nil,
                        status: "拷贝失败",
                        message: message
                    )
                )
                state.failedFiles = failedFiles
                state.copyFailedFiles = copyFailedFiles
                state.currentSpeedBytesPerSecond = 0
                state.verificationStatus = "拷贝异常"
                await progress(state)

                if let reason = fatalInterruptionReason(
                    for: handledError,
                    summary: summary,
                    destinations: destinations
                ) {
                    fatalStopReason = reason
                    state.phaseTitle = "设备中断，正在安全收尾"
                    state.verificationStatus = "任务已停止"
                    state.interruptionReason = reason

                    for remainingItem in sources.dropFirst(index + 1) {
                        appendUnique(remainingItem.relativePath, to: &failedFiles)
                        appendUnique(remainingItem.relativePath, to: &skippedFiles)
                    }
                    state.failedFiles = failedFiles
                    state.skippedFiles = skippedFiles
                    await progress(state)
                    break
                }
            }
        }

        if let fatalStopReason {
            for item in sources where !fileRecords.contains(where: { $0.relativePath == item.relativePath }) {
                let copiedButUnverified = copiedItemPaths.contains(item.relativePath)
                appendUnique(item.relativePath, to: &failedFiles)
                appendUnique(item.relativePath, to: &skippedFiles)
                fileRecords.append(
                    FileVerificationRecord(
                        relativePath: item.relativePath,
                        size: item.size,
                        sourceChecksum: nil,
                        targetChecksum: nil,
                        backupChecksum: nil,
                        status: copiedButUnverified ? "未校验" : "未执行",
                        message: copiedButUnverified
                            ? "文件已复制，但因设备中断未完成整批校验：\(fatalStopReason)"
                            : "任务已停止，未继续复制：\(fatalStopReason)"
                    )
                )
            }

            state.phaseTitle = "设备中断，任务已安全停止"
            state.verificationStatus = "未执行整批校验"
            state.currentFile = "请检查报告后重新连接设备"
            state.failedFiles = failedFiles
            state.skippedFiles = skippedFiles
            state.verificationCheckedFiles = totalFiles
            state.interruptionReason = fatalStopReason
            await progress(state)
        } else {
            state.phaseTitle = "正在整批校验"
            state.verificationStatus = "整批校验中"
            state.currentFile = "正在校验全部已导入素材"
            state.currentSpeedBytesPerSecond = 0
            state.verificationStartedAt = Date()
            state.verificationTotalBytes = verificationWorkBytes
            state.verificationProcessedBytes = 0
            state.currentVerificationSpeedBytesPerSecond = 0
            await progress(state)

            for (index, item) in sources.enumerated() {
                let itemVerificationWorkBytes = verificationBytesForItem(item, destinations: destinations)
                if copyFailedFiles.contains(item.relativePath) {
                    appendUnique(item.relativePath, to: &skippedFiles)
                    state.skippedFiles = skippedFiles
                    state.verificationCheckedFiles += 1
                    updateVerificationProgress(logicalBytes: itemVerificationWorkBytes, state: &state)
                    await progress(state)
                    continue
                }
                state.currentFile = item.relativePath
                await progress(state)

                let itemVerificationStartBytes = state.verificationProcessedBytes
                do {
                    try checkInterruption(interruptionToken)
                    try ensureRequiredLocations(summary: summary, destinations: destinations)

                    let sourceFile = try PathSafety.resolvedURL(for: item.relativePath, under: summary.sourceRootURL)
                    try PathSafety.ensureSafeExistingFileTarget(for: sourceFile, under: summary.sourceRootURL)
                    let sourceHash = try await checksum(
                        for: sourceFile,
                        interruptionToken: interruptionToken,
                        state: &state,
                        progress: progress
                    )
                    var targetChecksum: String?
                    var backupChecksum: String?
                    for destination in destinations {
                        let targetFolder = destination.rootURL.appendingPathComponent(taskFolder, isDirectory: true)
                        let targetFile = try PathSafety.resolvedURL(for: item.relativePath, under: targetFolder)
                        try PathSafety.ensureSafeExistingFileTarget(for: targetFile, under: destination.rootURL)
                        let targetHash = try await checksum(
                            for: targetFile,
                            interruptionToken: interruptionToken,
                            state: &state,
                            progress: progress
                        )
                        if destination.label == "主目标盘" {
                            targetChecksum = targetHash
                        } else if destination.label == "备份盘" {
                            backupChecksum = targetHash
                        }
                        if sourceHash != targetHash {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                    }
                    fileRecords.append(
                        FileVerificationRecord(
                            relativePath: item.relativePath,
                            size: item.size,
                            sourceChecksum: sourceHash,
                            targetChecksum: targetChecksum,
                            backupChecksum: backupChecksum,
                            status: "通过",
                            message: "所有目标与源文件 SHA-256 一致"
                        )
                    )
                    completeVerificationProgress(
                        itemStartBytes: itemVerificationStartBytes,
                        itemWorkBytes: itemVerificationWorkBytes,
                        state: &state
                    )
                    state.verifiedFiles += 1
                    state.verificationCheckedFiles += 1
                    await progress(state)
                } catch {
                    let handledError: Error = error is CancellationError
                        ? TransferError.transferInterrupted(reason: Self.userCancellationReason)
                        : error
                    let message = handledError.localizedDescription
                    appendUnique(item.relativePath, to: &failedFiles)
                    appendUnique(item.relativePath, to: &verificationFailedFiles)
                    state.failedFiles = failedFiles
                    state.verificationFailedFiles = verificationFailedFiles
                    state.verificationCheckedFiles += 1
                    completeVerificationProgress(
                        itemStartBytes: itemVerificationStartBytes,
                        itemWorkBytes: itemVerificationWorkBytes,
                        state: &state
                    )
                    state.verificationStatus = "校验发现异常"
                    fileRecords.append(
                        FileVerificationRecord(
                            relativePath: item.relativePath,
                            size: item.size,
                            sourceChecksum: nil,
                            targetChecksum: nil,
                            backupChecksum: nil,
                            status: "异常",
                            message: message
                        )
                    )
                    await progress(state)

                    if let reason = fatalInterruptionReason(
                        for: handledError,
                        summary: summary,
                        destinations: destinations
                    ) {
                        fatalStopReason = reason
                        state.phaseTitle = "设备中断，任务已安全停止"
                        state.verificationStatus = "校验被中断"
                        state.interruptionReason = reason

                        for remainingItem in sources.dropFirst(index + 1) {
                            appendUnique(remainingItem.relativePath, to: &failedFiles)
                            appendUnique(remainingItem.relativePath, to: &skippedFiles)
                            if !fileRecords.contains(where: { $0.relativePath == remainingItem.relativePath }) {
                                fileRecords.append(
                                    FileVerificationRecord(
                                        relativePath: remainingItem.relativePath,
                                        size: remainingItem.size,
                                        sourceChecksum: nil,
                                        targetChecksum: nil,
                                        backupChecksum: nil,
                                        status: "未校验",
                                        message: "校验中断，未继续处理：\(reason)"
                                    )
                                )
                            }
                        }
                        state.failedFiles = failedFiles
                        state.skippedFiles = skippedFiles
                        state.verificationCheckedFiles = totalFiles
                        await progress(state)
                        break
                    }
                }
            }
        }

        let finishedAt = Date()
        let wasCancelled = fatalStopReason == Self.userCancellationReason
        let verificationSummary: String
        if wasCancelled {
            verificationSummary = "任务已取消：已停止新写入，未完成的文件已标记为异常或未校验。"
        } else if let fatalStopReason {
            verificationSummary = "任务已安全停止：\(fatalStopReason)。未完成的文件已标记为异常或未校验，请重新连接设备后重试。"
        } else if failedFiles.isEmpty {
            verificationSummary = "全部 \(totalFiles) 个文件已完成整批校验，未发现丢失或不一致。"
        } else {
            verificationSummary = "整批校验完成，发现 \(failedFiles.count) 个异常文件，请复核日志。"
        }
        state.phaseTitle = failedFiles.isEmpty ? "导入与校验完成" : (fatalStopReason == nil ? "导入完成，校验有异常" : (wasCancelled ? "任务已取消，已生成报告" : "设备中断，任务已安全停止"))
        state.verificationStatus = failedFiles.isEmpty ? "整批校验完成" : (fatalStopReason == nil ? "整批校验有异常" : "已生成异常报告")

        let reportDocumentWriteResult = writeReportDocument(
            to: reportDocumentURL,
            fallbackURL: fallbackReportDocumentURL,
            targetRootURL: summary.targetURL,
            startedAt: startedAt,
            finishedAt: finishedAt,
            taskFolder: taskFolder,
            summary: summary,
            destinations: destinations,
            copyFailedFiles: copyFailedFiles,
            verificationFailedFiles: verificationFailedFiles,
            skippedFiles: skippedFiles,
            fileRecords: fileRecords,
            failedFiles: failedFiles,
            interruptionReason: fatalStopReason,
            verificationSummary: verificationSummary,
            language: language
        )
        let finalVerificationSummary = [verificationSummary, reportDocumentWriteResult.note]
            .compactMap { $0 }
            .joined(separator: " ")
        let reportWriteFailed = reportDocumentWriteResult.hasFailure
        if reportWriteFailed, failedFiles.isEmpty, !wasCancelled {
            state.phaseTitle = "导入完成，报告写入异常"
            state.verificationStatus = "报告写入异常"
        }
        state.reportSummary = finalVerificationSummary
        await progress(state)

        let report = TransferReport(
            id: UUID(),
            startedAt: startedAt,
            finishedAt: finishedAt,
            sourceName: summary.sourceVolume.name,
            sourcePath: summary.sourceVolume.url.path,
            sourceRootPath: summary.sourceRootURL.path,
            targetPath: primaryImportFolder.path,
            backupPath: summary.backupURL?.appendingPathComponent(taskFolder, isDirectory: true).path,
            selectedFileCount: totalFiles,
            totalBytes: totalBytes,
            verificationMode: summary.verificationMode,
            namingRule: summary.namingRule,
            success: failedFiles.isEmpty && !wasCancelled && !reportWriteFailed,
            cancelled: wasCancelled,
            failedFiles: failedFiles,
            copyFailedFiles: copyFailedFiles,
            verificationFailedFiles: verificationFailedFiles,
            skippedFiles: skippedFiles,
            verificationSummary: finalVerificationSummary,
            interruptionReason: fatalStopReason,
            duration: finishedAt.timeIntervalSince(startedAt),
            reportDocumentPath: reportDocumentWriteResult.targetURL?.path,
            localReportDocumentPath: reportDocumentWriteResult.localURL?.path,
            reportDocumentWriteFailed: reportWriteFailed,
            importedItems: sources.map(\.relativePath),
            fileRecords: fileRecords
        )

        return TransferResult(report: report)
    }

    private func makePreflightFailureResult(
        error: Error,
        state: inout TransferState,
        startedAt: Date,
        taskFolder: String,
        summary: ImportSelectionSummary,
        destinations: [Destination],
        primaryImportFolder: URL,
        reportDocumentURL: URL,
        fallbackReportDocumentURL: URL,
        language: AppLanguage
    ) -> TransferResult {
        let finishedAt = Date()
        let failureMessage = error.localizedDescription
        let failedFiles = summary.selectedItems.map(\.relativePath)
        let skippedFiles = failedFiles
        let fileRecords = summary.selectedItems.map { item in
            FileVerificationRecord(
                relativePath: item.relativePath,
                size: item.size,
                sourceChecksum: nil,
                targetChecksum: nil,
                backupChecksum: nil,
                status: "未执行",
                message: "任务预检失败，未开始拷贝：\(failureMessage)"
            )
        }
        let verificationSummary = "任务未开始：预检失败：\(failureMessage)"
        let shouldWriteTargetReport = !isPathOverlapError(error)

        state.phaseTitle = "预检失败，已生成报告"
        state.verificationStatus = "未开始拷贝"
        state.currentFile = "请检查目标盘、备份盘或源设备设置"
        state.failedFiles = failedFiles
        state.skippedFiles = skippedFiles
        state.reportSummary = verificationSummary

        let reportDocumentWriteResult = writeReportDocument(
            to: shouldWriteTargetReport ? reportDocumentURL : nil,
            fallbackURL: fallbackReportDocumentURL,
            targetRootURL: summary.targetURL,
            startedAt: startedAt,
            finishedAt: finishedAt,
            taskFolder: taskFolder,
            summary: summary,
            destinations: destinations,
            copyFailedFiles: [],
            verificationFailedFiles: [],
            skippedFiles: skippedFiles,
            fileRecords: fileRecords,
            failedFiles: failedFiles,
            interruptionReason: nil,
            verificationSummary: verificationSummary,
            language: language
        )
        let finalVerificationSummary = [verificationSummary, reportDocumentWriteResult.note]
            .compactMap { $0 }
            .joined(separator: " ")
        state.reportSummary = finalVerificationSummary

        let report = TransferReport(
            id: UUID(),
            startedAt: startedAt,
            finishedAt: finishedAt,
            sourceName: summary.sourceVolume.name,
            sourcePath: summary.sourceVolume.url.path,
            sourceRootPath: summary.sourceRootURL.path,
            targetPath: primaryImportFolder.path,
            backupPath: summary.backupURL?.appendingPathComponent(taskFolder, isDirectory: true).path,
            selectedFileCount: summary.selectedItems.count,
            totalBytes: summary.totalSize,
            verificationMode: summary.verificationMode,
            namingRule: summary.namingRule,
            success: false,
            cancelled: false,
            failedFiles: failedFiles,
            copyFailedFiles: [],
            verificationFailedFiles: [],
            skippedFiles: skippedFiles,
            verificationSummary: finalVerificationSummary,
            interruptionReason: nil,
            duration: finishedAt.timeIntervalSince(startedAt),
            reportDocumentPath: reportDocumentWriteResult.targetURL?.path,
            localReportDocumentPath: reportDocumentWriteResult.localURL?.path,
            reportDocumentWriteFailed: reportDocumentWriteResult.hasFailure,
            importedItems: summary.selectedItems.map(\.relativePath),
            fileRecords: fileRecords
        )

        return TransferResult(report: report)
    }

    private func buildDestinations(targetURL: URL, backupURL: URL?) -> [Destination] {
        var destinations = [Destination(rootURL: targetURL, label: "主目标盘")]
        if let backupURL {
            destinations.append(Destination(rootURL: backupURL, label: "备份盘"))
        }
        return destinations
    }

    private func validateProjectStageSeparation(project: CopyProject, stage: ProjectTransferStage) throws {
        let sourceVolumeURL = URL(fileURLWithPath: project.sourceVolumePath, isDirectory: true)

        switch stage {
        case .primary:
            if PathSafety.pathsOverlap(project.sourceRootURL, project.targetRootURL) {
                throw TransferError.pathOverlap("主目标盘不能与源素材目录相同、包含源素材目录，或位于源素材目录内部。")
            }
            if PathSafety.pathsShareVolume(sourceVolumeURL, project.targetRootURL)
                || PathSafety.pathsShareVolume(project.sourceRootURL, project.targetRootURL) {
                throw TransferError.pathOverlap("主目标盘不能位于源设备同一个磁盘卷上，请选择独立工作盘，避免把素材写回源卡。")
            }
        case .backup:
            guard let backupRootURL = project.backupRootURL else {
                throw TransferError.deviceUnavailable(role: "备份盘", path: project.backupRootPath ?? "未配置")
            }
            if PathSafety.pathsOverlap(project.primaryImportURL, backupRootURL)
                || PathSafety.pathsOverlap(project.targetRootURL, backupRootURL) {
                throw TransferError.pathOverlap("备份盘不能与主目标盘相同，也不能互相包含。")
            }
            if PathSafety.pathsShareVolume(project.targetRootURL, backupRootURL) {
                throw TransferError.pathOverlap("备份盘不能与主目标盘位于同一个磁盘卷上，请选择独立备份盘。")
            }
            if PathSafety.pathsOverlap(project.sourceRootURL, backupRootURL)
                || PathSafety.pathsShareVolume(sourceVolumeURL, backupRootURL)
                || PathSafety.pathsShareVolume(project.sourceRootURL, backupRootURL) {
                throw TransferError.pathOverlap("备份盘不能位于源设备同一个磁盘卷上，请选择独立备份盘。")
            }
        }
    }

    private func validateDestinationSeparation(summary: ImportSelectionSummary) throws {
        if PathSafety.pathsOverlap(summary.sourceRootURL, summary.targetURL) {
            throw TransferError.pathOverlap("主目标盘不能与源素材目录相同、包含源素材目录，或位于源素材目录内部。")
        }
        if PathSafety.pathsShareVolume(summary.sourceVolume.url, summary.targetURL)
            || PathSafety.pathsShareVolume(summary.sourceRootURL, summary.targetURL) {
            throw TransferError.pathOverlap("主目标盘不能位于源设备同一个磁盘卷上，请选择独立工作盘，避免把素材写回源卡。")
        }

        guard let backupURL = summary.backupURL else { return }
        if PathSafety.pathsOverlap(summary.sourceRootURL, backupURL) {
            throw TransferError.pathOverlap("备份盘不能与源素材目录相同、包含源素材目录，或位于源素材目录内部。")
        }
        if PathSafety.pathsShareVolume(summary.sourceVolume.url, backupURL)
            || PathSafety.pathsShareVolume(summary.sourceRootURL, backupURL) {
            throw TransferError.pathOverlap("备份盘不能位于源设备同一个磁盘卷上，请选择独立备份盘。")
        }

        if PathSafety.pathsOverlap(summary.targetURL, backupURL) {
            throw TransferError.pathOverlap("主目标盘与备份盘不能相同，也不能互相包含。")
        }
        if PathSafety.pathsShareVolume(summary.targetURL, backupURL) {
            throw TransferError.pathOverlap("主目标盘与备份盘不能位于同一个磁盘卷上，请选择独立备份盘。")
        }
    }

    private func preflightSpace(destinations: [Destination], requiredBytes: Int64) throws {
        for destination in destinations {
            let available = availableCapacity(for: destination.rootURL)
            if let available, available < requiredBytes {
                throw TransferError.insufficientSpace(
                    destination: destination.label,
                    available: available,
                    required: requiredBytes
                )
            }
        }

        let groupedByVolume = Dictionary(grouping: destinations) { destination in
            DiskCapacityResolver.volumeRootPath(for: destination.rootURL) ?? destination.rootURL.path
        }

        for destinationsOnVolume in groupedByVolume.values where destinationsOnVolume.count > 1 {
            let combinedRequired = requiredBytes * Int64(destinationsOnVolume.count)
            guard let firstDestination = destinationsOnVolume.first,
                  let available = availableCapacity(for: firstDestination.rootURL),
                  available < combinedRequired else {
                continue
            }

            let labels = destinationsOnVolume.map(\.label).joined(separator: " + ")
            throw TransferError.insufficientSpace(
                destination: labels,
                available: available,
                required: combinedRequired
            )
        }
    }

    private func appendUnique(_ value: String, to array: inout [String]) {
        if !array.contains(value) {
            array.append(value)
        }
    }

    private func validateRelativePaths(_ items: [ProjectMediaItem]) throws {
        for item in items {
            _ = try SafeRelativePath(item.relativePath)
        }
    }

    private func validateRelativePaths(_ items: [MediaItem]) throws {
        for item in items {
            _ = try SafeRelativePath(item.relativePath)
        }
    }

    private func updateVerificationProgress(logicalBytes: Int64, state: inout TransferState) {
        state.verificationProcessedBytes = min(
            state.verificationProcessedBytes + max(logicalBytes, 0),
            state.verificationTotalBytes
        )

        guard let verificationStartedAt = state.verificationStartedAt else { return }
        let elapsed = Date().timeIntervalSince(verificationStartedAt)
        guard elapsed > 0 else { return }
        state.currentVerificationSpeedBytesPerSecond = Double(state.verificationProcessedBytes) / elapsed
    }

    private func completeVerificationProgress(
        itemStartBytes: Int64,
        itemWorkBytes: Int64,
        state: inout TransferState
    ) {
        let expectedProcessedBytes = min(itemStartBytes + itemWorkBytes, state.verificationTotalBytes)
        guard state.verificationProcessedBytes < expectedProcessedBytes else { return }
        updateVerificationProgress(logicalBytes: expectedProcessedBytes - state.verificationProcessedBytes, state: &state)
    }

    private func verificationBytesForItem(_ item: MediaItem, destinations: [Destination]) -> Int64 {
        item.size * Int64(1 + destinations.count)
    }

    private func verificationWorkBytes(
        for items: [ProjectMediaItem],
        mode: VerificationMode,
        destinationCount: Int,
        prehashedPaths: Set<String> = []
    ) -> Int64 {
        let total = items.reduce(Int64(0)) {
            $0 + verificationWorkBytes(for: $1, mode: mode, destinationCount: destinationCount, prehashedPaths: prehashedPaths)
        }
        return max(total, Int64(items.count))
    }

    private func verificationWorkBytes(
        for item: ProjectMediaItem,
        mode: VerificationMode,
        destinationCount: Int,
        prehashedPaths: Set<String> = []
    ) -> Int64 {
        switch mode {
        case .sha256:
            // 源哈希已在拷贝时内联计算的文件,校验阶段只需读目标。
            let sourcePasses = prehashedPaths.contains(item.relativePath) ? 0 : 1
            return item.size * Int64(sourcePasses + destinationCount)
        case .fastFingerprint:
            return fingerprintLogicalBytes(fileSize: item.size) * Int64(1 + destinationCount)
        case .sizeOnly, .skipped:
            return max(item.size, 1)
        }
    }

    private func fingerprintLogicalBytes(fileSize: Int64) -> Int64 {
        let sampleSize = Int64(16 * 1024 * 1024)
        guard fileSize > sampleSize * 3 else {
            return max(fileSize, 1)
        }
        return sampleSize * 3
    }

    private func cleanupInstalledCopies(_ urls: [URL]) -> String? {
        guard !urls.isEmpty else { return nil }
        var cleanupFailures: [String] = []
        for url in urls {
            do {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            } catch {
                cleanupFailures.append("\(url.path): \(error.localizedDescription)")
            }
        }

        if cleanupFailures.isEmpty {
            return "已清理本文件在其他目标盘上的已写入副本，避免留下未校验素材。"
        }
        return "部分已写入副本清理失败：\(cleanupFailures.joined(separator: "；"))"
    }

    private func checkInterruption(_ token: ImportInterruptionToken?) throws {
        if let reason = token?.reason {
            throw TransferError.transferInterrupted(reason: reason)
        }
        try checkTaskCancellation()
    }

    private func checkTaskCancellation() throws {
        if Task.isCancelled {
            throw TransferError.transferInterrupted(reason: Self.userCancellationReason)
        }
    }

    private func ensureRequiredLocations(summary: ImportSelectionSummary, destinations: [Destination]) throws {
        try ensureAvailable(summary.sourceVolume.url, role: "源设备")
        for destination in destinations {
            try ensureAvailable(destination.rootURL, role: destination.label)
            try ensureWritableDestination(destination.rootURL, role: destination.label)
        }
    }

    private func ensureAvailable(_ url: URL, role: String) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw TransferError.deviceUnavailable(role: role, path: url.path)
        }
    }

    private func ensureWritableDestination(_ url: URL, role: String) throws {
        let values = try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey, .isWritableKey])
        if values?.volumeIsReadOnly == true || values?.isWritable == false || !FileManager.default.isWritableFile(atPath: url.path) {
            throw TransferError.destinationNotWritable(role: role, path: url.path)
        }
    }

    private func ensureEnoughAvailableSpace(_ url: URL, role: String, requiredBytes: Int64) throws {
        guard requiredBytes > 0, let available = availableCapacity(for: url), available < requiredBytes else {
            return
        }
        throw TransferError.insufficientSpace(destination: role, available: available, required: requiredBytes)
    }

    private func fatalInterruptionReason(
        for error: Error,
        summary: ImportSelectionSummary,
        destinations: [Destination]
    ) -> String? {
        if let transferError = error as? TransferError {
            switch transferError {
            case .deviceUnavailable, .transferInterrupted:
                return transferError.localizedDescription
            case .insufficientSpace, .destinationNotWritable, .pathOverlap, .copySizeMismatch:
                break
            }
        }

        if !FileManager.default.fileExists(atPath: summary.sourceVolume.url.path) {
            return TransferError.deviceUnavailable(role: "源设备", path: summary.sourceVolume.url.path).localizedDescription
        }

        for destination in destinations where !FileManager.default.fileExists(atPath: destination.rootURL.path) {
            return TransferError.deviceUnavailable(role: destination.label, path: destination.rootURL.path).localizedDescription
        }

        return nil
    }

    private func fatalInterruptionReason(
        for error: Error,
        sourceURL: URL,
        destinations: [Destination],
        sourceRole: String
    ) -> String? {
        if let transferError = error as? TransferError {
            switch transferError {
            case .deviceUnavailable, .transferInterrupted:
                return transferError.localizedDescription
            case .insufficientSpace, .destinationNotWritable, .pathOverlap, .copySizeMismatch:
                break
            }
        }

        if !FileManager.default.fileExists(atPath: sourceURL.path) {
            return TransferError.deviceUnavailable(role: sourceRole, path: sourceURL.path).localizedDescription
        }

        for destination in destinations where !FileManager.default.fileExists(atPath: destination.rootURL.path) {
            return TransferError.deviceUnavailable(role: destination.label, path: destination.rootURL.path).localizedDescription
        }

        return nil
    }

    private func isPathOverlapError(_ error: Error) -> Bool {
        guard let transferError = error as? TransferError else { return false }
        if case .pathOverlap = transferError {
            return true
        }
        return false
    }

    private func copy(
        item: MediaItem,
        sourceURL: URL,
        to destinationURL: URL,
        destination: Destination,
        sourceRoot: URL,
        interruptionToken: ImportInterruptionToken?,
        state: inout TransferState,
        progress: @escaping @Sendable (TransferState) async -> Void
    ) async throws {
        try await copyFile(
            sourceURL: sourceURL,
            relativePath: item.relativePath,
            expectedSize: item.size,
            to: destinationURL,
            destination: destination,
            sourceRoot: sourceRoot,
            sourceRole: "源设备",
            interruptionToken: interruptionToken,
            state: &state,
            progress: progress
        )
    }

    @discardableResult
    private func copySourceFile(
        sourceURL: URL,
        relativePath: String,
        expectedSize: Int64,
        to destinationURL: URL,
        destination: Destination,
        sourceRoot: URL,
        sourceRole: String,
        computeSourceHash: Bool = false,
        interruptionToken: ImportInterruptionToken?,
        state: inout TransferState,
        progress: @escaping @Sendable (TransferState) async -> Void
    ) async throws -> String? {
        try await copyFile(
            sourceURL: sourceURL,
            relativePath: relativePath,
            expectedSize: expectedSize,
            to: destinationURL,
            destination: destination,
            sourceRoot: sourceRoot,
            sourceRole: sourceRole,
            computeSourceHash: computeSourceHash,
            interruptionToken: interruptionToken,
            state: &state,
            progress: progress
        )
    }

    /// 拷贝单个文件。`computeSourceHash` 为 true 时,在读取源数据的同一遍 IO 里
    /// 同步计算 SHA-256 并返回十六进制摘要 —— 这让 SHA-256 校验模式省掉对源
    /// 文件的第二次全量读取(对 SD 卡等慢速源设备,整体耗时约降一半)。
    /// 返回 nil 表示未启用内联哈希。
    @discardableResult
    private func copyFile(
        sourceURL: URL,
        relativePath: String,
        expectedSize: Int64,
        to destinationURL: URL,
        destination: Destination,
        sourceRoot: URL,
        sourceRole: String,
        computeSourceHash: Bool = false,
        interruptionToken: ImportInterruptionToken?,
        state: inout TransferState,
        progress: @escaping @Sendable (TransferState) async -> Void
    ) async throws -> String? {
        let folder = destinationURL.deletingLastPathComponent()

        try checkInterruption(interruptionToken)
        try ensureAvailable(sourceRoot, role: sourceRole)
        try ensureAvailable(sourceURL, role: "源文件")
        try ensureAvailable(destination.rootURL, role: destination.label)
        try ensureWritableDestination(destination.rootURL, role: destination.label)
        try PathSafety.ensureSafeExistingFileTarget(for: sourceURL, under: sourceRoot)
        try PathSafety.ensureSafeWritableFileTarget(for: destinationURL, under: destination.rootURL)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
        try PathSafety.ensureSafeWritableFileTarget(for: destinationURL, under: destination.rootURL)
        let temporaryURL = try makeTemporaryCopyURL(in: folder)
        try PathSafety.ensureSafeWritableFileTarget(for: temporaryURL, under: destination.rootURL)

        var temporaryFileCreated = false
        do {
            let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
            var destinationHandle: FileHandle?
            var sourceClosed = false
            var destinationClosed = false

            defer {
                if !sourceClosed {
                    try? sourceHandle.close()
                }
                if !destinationClosed {
                    try? destinationHandle?.close()
                }
            }

            destinationHandle = try createExclusiveFileHandle(at: temporaryURL)
            temporaryFileCreated = true

            let chunkSize = 16 * 1024 * 1024
            let minimumUpdateInterval: TimeInterval = 0.5
            let availabilityCheckInterval: TimeInterval = 1.0
            var bytesSinceLastUpdate: Int64 = 0
            var bytesCopiedForFile: Int64 = 0
            var lastUpdateAt = Date()
            var lastAvailabilityCheckAt = Date()
            var sourceHasher = computeSourceHash ? SHA256() : nil

            while true {
                try checkInterruption(interruptionToken)
                let availabilityCheckAt = Date()
                if availabilityCheckAt.timeIntervalSince(lastAvailabilityCheckAt) >= availabilityCheckInterval {
                    try ensureAvailable(sourceRoot, role: sourceRole)
                    try ensureAvailable(destination.rootURL, role: destination.label)
                    let remainingBytes = max(expectedSize - bytesCopiedForFile, 0)
                    try ensureEnoughAvailableSpace(destination.rootURL, role: destination.label, requiredBytes: remainingBytes)
                    lastAvailabilityCheckAt = availabilityCheckAt
                }

                // 读/写/哈希放在 autoreleasepool 内同步完成,只携带字节数出来:
                // FileHandle.read 返回的 NSData 是 autoreleased,异步循环里的
                // 排水点(await)间隔 0.5s,16MB 块不及时排水会让内存峰值飙到数百 MB。
                var chunkBytes: Int64 = 0
                try autoreleasepool {
                    guard let data = try sourceHandle.read(upToCount: chunkSize), !data.isEmpty else {
                        return
                    }
                    try destinationHandle?.write(contentsOf: data)
                    sourceHasher?.update(data: data)
                    chunkBytes = Int64(data.count)
                }
                if chunkBytes == 0 {
                    break
                }

                bytesCopiedForFile += chunkBytes
                state.processedBytes += chunkBytes
                bytesSinceLastUpdate += chunkBytes

                let now = Date()
                let elapsed = now.timeIntervalSince(lastUpdateAt)
                if elapsed >= minimumUpdateInterval || state.processedBytes >= state.totalBytes {
                    state.currentSpeedBytesPerSecond = Double(bytesSinceLastUpdate) / max(elapsed, 0.001)
                    lastUpdateAt = now
                    bytesSinceLastUpdate = 0
                    await progress(state)
                }
            }

            state.phaseTitle = "正在确认写入到\(destination.label)"
            await progress(state)
            try destinationHandle?.synchronize()
            try? sourceHandle.close()
            sourceClosed = true
            try? destinationHandle?.close()
            destinationClosed = true

            // Verify the temp file holds exactly the bytes we read from the source.
            // We compare against bytesCopiedForFile (actual read count) rather than the
            // stale scan-time expectedSize, so files that changed between scan and copy
            // don't produce false failures when the copy itself is byte-complete.
            let actualSize = fileSize(at: temporaryURL) ?? -1
            guard actualSize == bytesCopiedForFile else {
                throw TransferError.copySizeMismatch(file: relativePath, expected: bytesCopiedForFile, actual: actualSize)
            }

            try installCopiedFile(from: temporaryURL, to: destinationURL, under: destination.rootURL)
            await progress(state)
            return sourceHasher.map { hasher in
                hasher.finalize().map { String(format: "%02x", $0) }.joined()
            }
        } catch {
            if temporaryFileCreated {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            throw error
        }
    }

    private func installCopiedFile(from temporaryURL: URL, to destinationURL: URL, under destinationRootURL: URL) throws {
        try PathSafety.ensureSafeWritableFileTarget(for: destinationURL, under: destinationRootURL)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let replacementURL = destinationURL
                .deletingLastPathComponent()
                .appendingPathComponent(".airwang-replacement-\(UUID().uuidString)", isDirectory: false)
            try PathSafety.ensureSafeWritableFileTarget(for: replacementURL, under: destinationRootURL)
            try FileManager.default.moveItem(at: temporaryURL, to: replacementURL)
            do {
                try PathSafety.ensureSafeWritableFileTarget(for: destinationURL, under: destinationRootURL)
                _ = try FileManager.default.replaceItemAt(
                    destinationURL,
                    withItemAt: replacementURL,
                    backupItemName: nil,
                    options: []
                )
            } catch {
                try? FileManager.default.removeItem(at: replacementURL)
                throw error
            }
        } else {
            try PathSafety.ensureSafeWritableFileTarget(for: destinationURL, under: destinationRootURL)
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    private func sweepStaleTempFiles(in folder: URL) {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsSubdirectoryDescendants]
        ) else { return }
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix(".airwang-") && (name.hasSuffix(".part") || name.hasSuffix(".tmp")) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func makeTemporaryCopyURL(in folder: URL) throws -> URL {
        for _ in 0..<10 {
            let candidate = folder.appendingPathComponent(".airwang-\(UUID().uuidString).part", isDirectory: false)
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw CocoaError(.fileWriteFileExists)
    }

    private func createExclusiveFileHandle(at url: URL) throws -> FileHandle {
        let flags = O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW
        let fileDescriptor = Darwin.open(url.path, flags, S_IRUSR | S_IWUSR)
        guard fileDescriptor >= 0 else {
            let code = POSIXErrorCode(rawValue: errno) ?? .EIO
            throw POSIXError(code)
        }
        return FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
    }

    private func checksum(
        for url: URL,
        interruptionToken: ImportInterruptionToken?,
        state: inout TransferState,
        progress: @escaping @Sendable (TransferState) async -> Void
    ) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        // 8MB 块:1MB 块在快速 SSD 上 syscall 频率过高,拖低校验吞吐。
        let chunkSize = 8 * 1024 * 1024
        let minimumUpdateInterval: TimeInterval = 0.15
        var lastUpdateAt = Date()
        while true {
            try checkInterruption(interruptionToken)
            var chunkBytes: Int64 = 0
            try autoreleasepool {
                guard let data = try handle.read(upToCount: chunkSize), !data.isEmpty else { return }
                hasher.update(data: data)
                chunkBytes = Int64(data.count)
            }
            if chunkBytes == 0 { break }

            updateVerificationProgress(logicalBytes: chunkBytes, state: &state)
            let now = Date()
            if now.timeIntervalSince(lastUpdateAt) >= minimumUpdateInterval
                || state.verificationProcessedBytes >= state.verificationTotalBytes {
                lastUpdateAt = now
                await progress(state)
            }
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func verifyProjectFile(
        item: ProjectMediaItem,
        sourceURL: URL,
        targetURL: URL,
        sourceRoot: URL,
        destinationRoot: URL,
        mode: VerificationMode,
        stage: ProjectTransferStage,
        itemStartBytes: Int64,
        itemWorkBytes: Int64,
        precomputedSourceHash: String? = nil,
        interruptionToken: ImportInterruptionToken?,
        state: inout TransferState,
        progress: @escaping @Sendable (TransferState) async -> Void
    ) async throws -> FileVerificationRecord {
        try PathSafety.ensureSafeExistingFileTarget(for: sourceURL, under: sourceRoot)
        try PathSafety.ensureSafeExistingFileTarget(for: targetURL, under: destinationRoot)

        let sourceSize = fileSize(at: sourceURL)
        let targetSize = fileSize(at: targetURL)
        // Compare source and target against each other rather than against the stale
        // scan-time item.size.  item.size is advisory; the live source is the authority.
        guard let sourceSize, let targetSize, sourceSize == targetSize else {
            throw TransferError.copySizeMismatch(
                file: item.relativePath,
                expected: sourceSize ?? -1,
                actual: targetSize ?? -1
            )
        }

        switch mode {
        case .skipped:
            completeVerificationProgress(
                itemStartBytes: itemStartBytes,
                itemWorkBytes: itemWorkBytes,
                state: &state
            )
            return FileVerificationRecord(
                relativePath: item.relativePath,
                size: item.size,
                sourceChecksum: nil,
                targetChecksum: nil,
                backupChecksum: nil,
                status: "跳过校验",
                message: mode.reportWarning
            )
        case .sizeOnly:
            completeVerificationProgress(
                itemStartBytes: itemStartBytes,
                itemWorkBytes: itemWorkBytes,
                state: &state
            )
            return FileVerificationRecord(
                relativePath: item.relativePath,
                size: item.size,
                sourceChecksum: nil,
                targetChecksum: nil,
                backupChecksum: nil,
                status: "通过",
                message: "大小校验通过：源文件与\(stage.destinationLabel)文件大小一致。\(mode.reportWarning)"
            )
        case .sha256:
            // 优先使用拷贝阶段内联计算的源哈希(同一批源字节,免去第二次全量读源);
            // 若该文件没有内联哈希(例如拷贝途中切换过校验模式),回退为重读源文件。
            let sourceHash: String
            if let precomputedSourceHash {
                sourceHash = precomputedSourceHash
            } else {
                sourceHash = try await checksum(
                    for: sourceURL,
                    interruptionToken: interruptionToken,
                    state: &state,
                    progress: progress
                )
            }
            let targetHash = try await checksum(
                for: targetURL,
                interruptionToken: interruptionToken,
                state: &state,
                progress: progress
            )
            guard sourceHash == targetHash else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return FileVerificationRecord(
                relativePath: item.relativePath,
                size: item.size,
                sourceChecksum: sourceHash,
                targetChecksum: stage == .primary ? targetHash : nil,
                backupChecksum: stage == .backup ? targetHash : nil,
                status: "通过",
                message: "SHA-256 全量校验通过：源文件与\(stage.destinationLabel)一致。"
            )
        case .fastFingerprint:
            let sourceFingerprint = try await fingerprint(
                for: sourceURL,
                fileSize: item.size,
                interruptionToken: interruptionToken,
                state: &state,
                progress: progress
            )
            let targetFingerprint = try await fingerprint(
                for: targetURL,
                fileSize: item.size,
                interruptionToken: interruptionToken,
                state: &state,
                progress: progress
            )
            guard sourceFingerprint == targetFingerprint else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return FileVerificationRecord(
                relativePath: item.relativePath,
                size: item.size,
                sourceChecksum: sourceFingerprint,
                targetChecksum: stage == .primary ? targetFingerprint : nil,
                backupChecksum: stage == .backup ? targetFingerprint : nil,
                status: "通过",
                message: "快速指纹校验通过。\(mode.reportWarning)"
            )
        }
    }

    private func fingerprint(
        for url: URL,
        fileSize: Int64,
        interruptionToken: ImportInterruptionToken?,
        state: inout TransferState,
        progress: @escaping @Sendable (TransferState) async -> Void
    ) async throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        let minimumUpdateInterval: TimeInterval = 0.15
        let chunkSize = 1_048_576
        var lastUpdateAt = Date()

        for segment in fingerprintSegments(fileSize: fileSize) {
            try checkInterruption(interruptionToken)
            try handle.seek(toOffset: UInt64(segment.offset))
            hasher.update(data: Data("offset:\(segment.offset)|length:\(segment.length)|".utf8))

            var remaining = segment.length
            while remaining > 0 {
                try checkInterruption(interruptionToken)
                let readCount = Int(min(Int64(chunkSize), remaining))
                let data = try handle.read(upToCount: readCount)
                guard let data, !data.isEmpty else { break }
                hasher.update(data: data)
                remaining -= Int64(data.count)
                updateVerificationProgress(logicalBytes: Int64(data.count), state: &state)

                let now = Date()
                if now.timeIntervalSince(lastUpdateAt) >= minimumUpdateInterval
                    || state.verificationProcessedBytes >= state.verificationTotalBytes {
                    lastUpdateAt = now
                    await progress(state)
                }
            }
        }

        return "fingerprint-" + hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func fingerprintSegments(fileSize: Int64) -> [(offset: Int64, length: Int64)] {
        let sampleSize = Int64(16 * 1024 * 1024)
        let normalizedSize = max(fileSize, 0)
        guard normalizedSize > 0 else { return [(0, 0)] }
        guard normalizedSize > sampleSize * 3 else {
            return [(0, normalizedSize)]
        }

        let middleOffset = max((normalizedSize - sampleSize) / 2, sampleSize)
        return [
            (0, sampleSize),
            (middleOffset, sampleSize),
            (normalizedSize - sampleSize, sampleSize)
        ]
    }

    private func availableCapacity(for url: URL) -> Int64? {
        DiskCapacityResolver.capacity(for: url).availableCapacity
    }

    private func fileSize(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map { Int64($0) }
    }

    private func localReportDocumentURL(taskFolder: String) -> URL {
        AppStorageScope.localReportDocumentURL(taskFolder: taskFolder)
    }

    private func makeTaskFolderName(from date: Date, sourceName: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let cleaned = sanitizedFileNameComponent(sourceName, fallback: "Source")
        return "\(formatter.string(from: date))_\(cleaned)"
    }

    private func sanitizedFileNameComponent(_ value: String, fallback: String) -> String {
        let disallowedCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let replacedScalars = value.unicodeScalars.map { scalar in
            disallowedCharacters.contains(scalar) ? "_" : String(scalar)
        }
        let cleaned = replacedScalars
            .joined()
            .replacingOccurrences(of: " ", with: "_")
            .split(separator: "_", omittingEmptySubsequences: true)
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "._- "))

        let limited = String(cleaned.prefix(80))
        return limited.isEmpty ? fallback : limited
    }

    private func writeReportDocument(
        to url: URL?,
        fallbackURL: URL,
        targetRootURL: URL?,
        startedAt: Date,
        finishedAt: Date,
        taskFolder: String,
        summary: ImportSelectionSummary,
        destinations: [Destination],
        copyFailedFiles: [String],
        verificationFailedFiles: [String],
        skippedFiles: [String],
        fileRecords: [FileVerificationRecord],
        failedFiles: [String],
        interruptionReason: String?,
        verificationSummary: String,
        language: AppLanguage
    ) -> ReportDocumentWriteResult {
        let isEnglish = language == .english
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        byteFormatter.countStyle = .file

        let fileLines = summary.selectedItems.enumerated().map { index, item in
            "\(index + 1). \(item.relativePath) | \(byteFormatter.string(fromByteCount: item.size)) | \(formatter.string(from: item.createdAt))"
        }

        let failedSection = makeNumberedSection(failedFiles, emptyText: isEnglish ? "No issue files" : "无异常文件")
        let copyFailedSection = makeNumberedSection(copyFailedFiles, emptyText: isEnglish ? "No copy failures" : "无拷贝失败文件")
        let verificationFailedSection = makeNumberedSection(verificationFailedFiles, emptyText: isEnglish ? "No verification failures" : "无校验失败文件")
        let skippedSection = makeNumberedSection(skippedFiles, emptyText: isEnglish ? "No skipped files" : "无跳过文件")
        let recordLines = fileRecords.enumerated().map { index, record in
            if isEnglish {
                return """
                \(index + 1). \(record.relativePath)
                   Status: \(record.status)
                   Size: \(byteFormatter.string(fromByteCount: record.size))
                   Source SHA-256: \(record.sourceChecksum ?? "-")
                   Primary SHA-256: \(record.targetChecksum ?? "-")
                   Backup SHA-256: \(record.backupChecksum ?? "-")
                   Note: \(record.message)
                """
            }
            return """
            \(index + 1). \(record.relativePath)
               状态: \(record.status)
               大小: \(byteFormatter.string(fromByteCount: record.size))
               源 SHA-256: \(record.sourceChecksum ?? "-")
               主目标 SHA-256: \(record.targetChecksum ?? "-")
               备份 SHA-256: \(record.backupChecksum ?? "-")
               说明: \(record.message)
            """
        }.joined(separator: "\n")

        let content: String
        if isEnglish {
            content = """
            Airwang DIT for Mac Copy Report
            ========================================

            [Task Summary]
            Copy ID: \(taskFolder)
            Started At: \(formatter.string(from: startedAt))
            Finished At: \(formatter.string(from: finishedAt))
            Duration: \(formatDuration(finishedAt.timeIntervalSince(startedAt)))
            Import Status: \(failedFiles.isEmpty ? "Success" : "Issues Found")
            Bundle ID: \(AppStorageScope.bundleIdentifier)
            Local Storage: \(AppStorageScope.displayName)
            Verification Mode: \(summary.verificationMode)
            Naming Rule: \(summary.namingRule)
            Verification Summary: \(verificationSummary)
            Safety Event: \(interruptionReason ?? "None")

            [Paths]
            Source Device Name: \(summary.sourceVolume.name)
            Source Device Path: \(summary.sourceVolume.url.path)
            Actual Scan Folder: \(summary.sourceRootURL.path)
            Primary Target Path: \(summary.targetURL.appendingPathComponent(taskFolder, isDirectory: true).path)
            Backup Path: \(summary.backupURL?.appendingPathComponent(taskFolder, isDirectory: true).path ?? "Disabled")
            Target Capacity: \(capacityLines(for: destinations, formatter: byteFormatter))

            [Media Stats]
            File Count: \(summary.selectedItems.count)
            Total Size: \(byteFormatter.string(fromByteCount: summary.totalSize))
            Copy Failures: \(copyFailedFiles.count)
            Verification Failures: \(verificationFailedFiles.count)
            Skipped Verification: \(skippedFiles.count)

            [Media List]
            \(fileLines.joined(separator: "\n"))

            [Copy Failures]
            \(copyFailedSection)

            [Verification Failures]
            \(verificationFailedSection)

            [Skipped Files]
            \(skippedSection)

            [Verification Details]
            \(recordLines.isEmpty ? "No verification details" : recordLines)

            [Issue Files]
            \(failedSection)

            [Handoff Confirmation]
            DIT/Media Manager Signature:
            Receiver Signature:
            Notes:
            """
        } else {
            content = """
        Airwang DIT for Mac 拷贝报告
        ========================================

        [任务概要]
        拷贝 ID: \(taskFolder)
        开始时间: \(formatter.string(from: startedAt))
        完成时间: \(formatter.string(from: finishedAt))
        拷贝时长: \(formatDuration(finishedAt.timeIntervalSince(startedAt)))
        导入状态: \(failedFiles.isEmpty ? "成功" : "存在异常")
        应用标识: \(AppStorageScope.bundleIdentifier)
        本地存储: \(AppStorageScope.displayName)
        校验方式: \(summary.verificationMode)
        命名规则: \(summary.namingRule)
        校验结论: \(verificationSummary)
        安全事件: \(interruptionReason ?? "无")

        [路径信息]
        源设备名称: \(summary.sourceVolume.name)
        源设备地址: \(summary.sourceVolume.url.path)
        实际扫描目录: \(summary.sourceRootURL.path)
        主目标地址: \(summary.targetURL.appendingPathComponent(taskFolder, isDirectory: true).path)
        备份地址: \(summary.backupURL?.appendingPathComponent(taskFolder, isDirectory: true).path ?? "未启用")
        目标容量: \(capacityLines(for: destinations, formatter: byteFormatter))

        [素材统计]
        文件数量: \(summary.selectedItems.count)
        总容量: \(byteFormatter.string(fromByteCount: summary.totalSize))
        拷贝失败: \(copyFailedFiles.count)
        校验失败: \(verificationFailedFiles.count)
        跳过校验: \(skippedFiles.count)

        [素材清单]
        \(fileLines.joined(separator: "\n"))

        [拷贝失败文件]
        \(copyFailedSection)

        [校验失败文件]
        \(verificationFailedSection)

        [跳过校验文件]
        \(skippedSection)

        [文件校验明细]
        \(recordLines.isEmpty ? "无校验明细" : recordLines)

        [异常文件]
        \(failedSection)

        [交接确认]
        DIT/素材管理员签名:
        接收方签名:
        备注:
        """
        }

        return writeReportContent(
            content,
            targetURL: url,
            targetRootURL: targetRootURL,
            localURL: fallbackURL
        )
    }

    private func writeProjectReportDocument(
        to url: URL?,
        fallbackURL: URL,
        targetRootURL: URL?,
        startedAt: Date,
        finishedAt: Date,
        project: CopyProject,
        stage: ProjectTransferStage,
        sourceBaseURL: URL,
        destinationFolderURL: URL,
        destination: Destination,
        copyFailedFiles: [String],
        verificationFailedFiles: [String],
        skippedFiles: [String],
        fileRecords: [FileVerificationRecord],
        failedFiles: [String],
        interruptionReason: String?,
        verificationSummary: String,
        language: AppLanguage
    ) -> ReportDocumentWriteResult {
        let isEnglish = language == .english
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        byteFormatter.countStyle = .file

        let fileLines = project.selectedItems.enumerated().map { index, item in
            "\(index + 1). \(item.relativePath) | \(byteFormatter.string(fromByteCount: item.size)) | \(formatter.string(from: item.createdAt))"
        }
        let failedSection = makeNumberedSection(failedFiles, emptyText: isEnglish ? "No issue files" : "无异常文件")
        let copyFailedSection = makeNumberedSection(copyFailedFiles, emptyText: isEnglish ? "No copy failures" : "无拷贝失败文件")
        let verificationFailedSection = makeNumberedSection(verificationFailedFiles, emptyText: isEnglish ? "No verification failures" : "无校验失败文件")
        let skippedSection = makeNumberedSection(skippedFiles, emptyText: isEnglish ? "No skipped files" : "无跳过文件")
        let recordLines = fileRecords.enumerated().map { index, record in
            if isEnglish {
                return """
                \(index + 1). \(record.relativePath)
                   Status: \(record.status)
                   Size: \(byteFormatter.string(fromByteCount: record.size))
                   Source Checksum: \(record.sourceChecksum ?? "-")
                   Primary Checksum: \(record.targetChecksum ?? "-")
                   Backup Checksum: \(record.backupChecksum ?? "-")
                   Note: \(record.message)
                """
            }
            return """
            \(index + 1). \(record.relativePath)
               状态: \(record.status)
               大小: \(byteFormatter.string(fromByteCount: record.size))
               源校验值: \(record.sourceChecksum ?? "-")
               主目标校验值: \(record.targetChecksum ?? "-")
               备份校验值: \(record.backupChecksum ?? "-")
               说明: \(record.message)
            """
        }.joined(separator: "\n")

        let routeLine: String
        switch stage {
        case .primary:
            routeLine = isEnglish ? "Stage Route: original source path -> primary target path" : "本阶段路径: 原始源地址 -> 主目标地址"
        case .backup:
            routeLine = isEnglish ? "Stage Route: primary target path -> backup path. Backup reads from the primary target." : "本阶段路径: 主目标地址 -> 备份地址（备份来源为主目标盘）"
        }

        let content: String
        if isEnglish {
            content = """
            \(stage == .primary ? "Airwang DIT for Mac Primary Copy Report" : "Airwang DIT for Mac Backup Report")
            ========================================

            [Task Summary]
            Copy ID: \(project.taskFolderName)
            Project Name: \(project.name)
            Report Type: \(stage == .primary ? "Primary report" : "Backup report")
            Started At: \(formatter.string(from: startedAt))
            Finished At: \(formatter.string(from: finishedAt))
            Duration: \(formatDuration(finishedAt.timeIntervalSince(startedAt)))
            Stage Status: \(failedFiles.isEmpty ? "Success" : "Issues Found")
            Bundle ID: \(AppStorageScope.bundleIdentifier)
            Local Storage: \(AppStorageScope.displayName)
            Verification Mode: \(project.verificationMode.title)
            Verification Risk Note: \(project.verificationMode.reportWarning)
            Verification Summary: \(verificationSummary)
            Safety Event: \(interruptionReason ?? "None")

            [Paths]
            \(routeLine)
            Original Source Name: \(project.sourceName)
            Original Source Path: \(project.sourceVolumePath)
            Original Scan Folder: \(project.sourceRootPath)
            Stage Read Path: \(sourceBaseURL.path)
            Primary Target Path: \(project.primaryImportURL.path)
            Backup Path: \(project.backupImportURL?.path ?? "Disabled")
            Stage Write Path: \(destinationFolderURL.path)
            Target Capacity: \(capacityLines(for: [destination], formatter: byteFormatter))

            [Media Stats]
            File Count: \(project.selectedItems.count)
            Total Size: \(byteFormatter.string(fromByteCount: project.totalBytes))
            Copy Failures: \(copyFailedFiles.count)
            Verification Failures: \(verificationFailedFiles.count)
            Skipped Verification: \(skippedFiles.count)

            [Media List]
            \(fileLines.joined(separator: "\n"))

            [Copy Failures]
            \(copyFailedSection)

            [Verification Failures]
            \(verificationFailedSection)

            [Skipped Files]
            \(skippedSection)

            [Verification Details]
            \(recordLines.isEmpty ? "No verification details" : recordLines)

            [Issue Files]
            \(failedSection)

            [Handoff Confirmation]
            DIT/Media Manager Signature:
            Receiver Signature:
            Notes:
            """
        } else {
            content = """
        \(stage.reportTitle)
        ========================================

        [任务概要]
        拷贝 ID: \(project.taskFolderName)
        项目名称: \(project.name)
        报告类型: \(stage == .primary ? "第一份主盘报告" : "第二份备份报告")
        开始时间: \(formatter.string(from: startedAt))
        完成时间: \(formatter.string(from: finishedAt))
        拷贝时长: \(formatDuration(finishedAt.timeIntervalSince(startedAt)))
        阶段状态: \(failedFiles.isEmpty ? "成功" : "存在异常")
        应用标识: \(AppStorageScope.bundleIdentifier)
        本地存储: \(AppStorageScope.displayName)
        校验方式: \(project.verificationMode.title)
        校验风险说明: \(project.verificationMode.reportWarning)
        校验结论: \(verificationSummary)
        安全事件: \(interruptionReason ?? "无")

        [路径信息]
        \(routeLine)
        原始源设备名称: \(project.sourceName)
        原始源地址: \(project.sourceVolumePath)
        原始扫描目录: \(project.sourceRootPath)
        本阶段读取地址: \(sourceBaseURL.path)
        主目标地址: \(project.primaryImportURL.path)
        备份地址: \(project.backupImportURL?.path ?? "未启用")
        本阶段写入地址: \(destinationFolderURL.path)
        目标容量: \(capacityLines(for: [destination], formatter: byteFormatter))

        [素材统计]
        文件数量: \(project.selectedItems.count)
        总容量: \(byteFormatter.string(fromByteCount: project.totalBytes))
        拷贝失败: \(copyFailedFiles.count)
        校验失败: \(verificationFailedFiles.count)
        跳过校验: \(skippedFiles.count)

        [素材清单]
        \(fileLines.joined(separator: "\n"))

        [拷贝失败文件]
        \(copyFailedSection)

        [校验失败文件]
        \(verificationFailedSection)

        [跳过校验文件]
        \(skippedSection)

        [文件校验明细]
        \(recordLines.isEmpty ? "无校验明细" : recordLines)

        [异常文件]
        \(failedSection)

        [交接确认]
        DIT/素材管理员签名:
        接收方签名:
        备注:
        """
        }

        return writeReportContent(
            content,
            targetURL: url,
            targetRootURL: targetRootURL,
            localURL: fallbackURL
        )
    }

    private func makeProjectVerificationSummary(
        stage: ProjectTransferStage,
        mode: VerificationMode,
        totalFiles: Int,
        failedFiles: [String],
        preflightFailureMessage: String?,
        fatalStopReason: String?
    ) -> String {
        if let preflightFailureMessage {
            return "\(stage.destinationLabel)阶段未开始：预检失败：\(preflightFailureMessage)"
        }
        if let fatalStopReason {
            if fatalStopReason == Self.userCancellationReason {
                return "\(stage.destinationLabel)阶段已取消：已停止新写入并生成报告。"
            }
            return "\(stage.destinationLabel)阶段已安全停止：\(fatalStopReason)。未完成文件已标记为异常或未校验。"
        }
        if mode == .skipped {
            return "\(stage.destinationLabel)阶段已完成拷贝，但用户主动跳过校验；本报告不代表素材完整性已确认。"
        }
        if failedFiles.isEmpty {
            return "\(stage.destinationLabel)阶段完成：\(totalFiles) 个文件已按“\(mode.title)”通过校验。"
        }
        return "\(stage.destinationLabel)阶段完成但存在异常：发现 \(failedFiles.count) 个异常文件，请复核明细。"
    }

    private func finalProjectPhaseTitle(
        stage: ProjectTransferStage,
        failedFiles: [String],
        cancelled: Bool,
        reportWriteFailed: Bool,
        preflightFailureMessage: String?
    ) -> String {
        if preflightFailureMessage != nil {
            return "预检失败，已生成报告"
        }
        if cancelled {
            return "任务已取消，已生成报告"
        }
        if reportWriteFailed {
            return "\(stage.destinationLabel)完成，报告写入异常"
        }
        return failedFiles.isEmpty ? "\(stage.destinationLabel)阶段完成" : "\(stage.destinationLabel)阶段存在异常"
    }

    private func writeReportContent(
        _ content: String,
        targetURL: URL?,
        targetRootURL: URL?,
        localURL: URL
    ) -> ReportDocumentWriteResult {
        var writtenTargetURL: URL?
        var writtenLocalURL: URL?
        var notes: [String] = []

        if let targetURL {
            if let targetRootURL {
                do {
                    try writeText(content, to: targetURL, under: targetRootURL)
                    writtenTargetURL = targetURL
                } catch {
                    notes.append("目标盘报告写入失败：\(error.localizedDescription)")
                }
            } else {
                notes.append("目标盘报告缺少安全根目录，已拒绝写入。")
            }
        } else {
            notes.append("因预检安全拦截，未向目标盘写入报告，仅保存 App 本地报告。")
        }

        do {
            try writeText(content, to: localURL, under: AppStorageScope.applicationSupportURL)
            writtenLocalURL = localURL
        } catch {
            notes.append("本地备份报告写入失败：\(error.localizedDescription)")
        }

        let note = notes.isEmpty ? nil : notes.joined(separator: "；")
        return ReportDocumentWriteResult(
            requestedTargetURL: targetURL,
            targetURL: writtenTargetURL,
            localURL: writtenLocalURL,
            note: note
        )
    }

    private func writeText(_ content: String, to url: URL, under rootURL: URL) throws {
        try PathSafety.ensureSafeWritableFileTarget(for: url, under: rootURL)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try PathSafety.ensureSafeWritableFileTarget(for: url, under: rootURL)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func formatDuration(_ value: TimeInterval) -> String {
        let totalSeconds = Int(value.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private func makeNumberedSection(_ items: [String], emptyText: String) -> String {
        guard !items.isEmpty else { return emptyText }
        return items.enumerated().map { index, item in "\(index + 1). \(item)" }.joined(separator: "\n")
    }

    private func capacityLines(for destinations: [Destination], formatter: ByteCountFormatter) -> String {
        destinations.map { destination in
            let capacity = DiskCapacityResolver.capacity(for: destination.rootURL)
            let free = capacity.availableCapacity.map { formatter.string(fromByteCount: $0) } ?? "-"
            let total = capacity.totalCapacity.map { formatter.string(fromByteCount: $0) } ?? "-"
            return "\(destination.label) 可用 \(free) / 总计 \(total)"
        }
        .joined(separator: " | ")
    }
}
