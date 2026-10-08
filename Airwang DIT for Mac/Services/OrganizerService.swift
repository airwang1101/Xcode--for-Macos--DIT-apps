import CoreServices
import Foundation
import Darwin
import ImageIO

struct OrganizerService {
    enum OrganizerError: LocalizedError, Sendable {
        case sourceUnavailable(String)
        case sourceNotWritable(String)
        case destinationUnavailable(String)
        case destinationNotWritable(String)
        case pathOverlap(String)
        case cannotCreateEnumerator(String)
        case noFiles
        case capacityUnavailable(String)
        case insufficientSpace(available: Int64, required: Int64)
        case destinationAlreadyExists(String)
        case copiedSizeMismatch(path: String, expected: Int64, actual: Int64)
        case verificationFailed(String)
        case sourceChanged(String)

        var errorDescription: String? {
            switch self {
            case let .sourceUnavailable(path):
                return "源文件夹不可访问：\(path)"
            case let .sourceNotWritable(path):
                return "移动规整需要可写的源文件夹，但它位于只读卷或没有写入权限：\(path)"
            case let .destinationUnavailable(path):
                return "目标文件夹不可访问：\(path)"
            case let .destinationNotWritable(path):
                return "目标文件夹不可写或位于只读卷：\(path)"
            case let .pathOverlap(message):
                return message
            case let .cannotCreateEnumerator(path):
                return "无法读取待规整目录：\(path)"
            case .noFiles:
                return "没有找到符合当前筛选条件的文件。"
            case let .capacityUnavailable(path):
                return "目标容量不可读，为避免写满或中断，已阻止规整：\(path)"
            case let .insufficientSpace(available, required):
                return "目标剩余空间不足：最低需要 \(ByteDisplayFormatter.string(fromByteCount: required))，当前可用 \(ByteDisplayFormatter.string(fromByteCount: available))。"
            case let .destinationAlreadyExists(path):
                return "目标文件已存在，为避免覆盖素材，已停止写入：\(path)"
            case let .verificationFailed(path):
                return "规整内容校验失败，源文件已保留：\(path)"
            case let .sourceChanged(path):
                return "源文件在规整过程中发生变化，已停止删除源文件：\(path)"
            case let .copiedSizeMismatch(path, expected, actual):
                return "\(path) 写入大小不一致：应为 \(ByteDisplayFormatter.string(fromByteCount: expected))，实际 \(ByteDisplayFormatter.string(fromByteCount: actual))。"
            }
        }
    }

    fileprivate struct SourceFile: Sendable {
        let url: URL
        let relativePath: String
        let displayName: String
        let createdAt: Date
        let modifiedAt: Date
        let size: Int64
        let mediaKind: ScanFilter
        let isSidecar: Bool

        var pairingKey: String {
            url.deletingPathExtension().standardizedFileURL.path
        }
    }

    fileprivate struct FileMetadata: Sendable {
        let capturedAt: Date?
        let deviceName: String?
    }

    func makePlan(
        sourceURL: URL,
        destinationURL: URL,
        rule: OrganizerRule,
        progress: (@Sendable (OrganizerPlanProgress) -> Void)? = nil
    ) async throws -> OrganizerPlan {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try await buildPlan(sourceURL: sourceURL, destinationURL: destinationURL, rule: rule, progress: progress)
        }
        return try await withTaskCancellationHandler {
            let plan = try await worker.value
            try Task.checkCancellation()
            return plan
        } onCancel: {
            worker.cancel()
        }
    }

    func execute(
        plan: OrganizerPlan,
        progress: @escaping @Sendable (OrganizerExecutionState) async -> Void
    ) async throws -> OrganizerRunSummary {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try await executePlan(plan, progress: progress)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

private func buildPlan(
    sourceURL: URL,
    destinationURL: URL,
    rule: OrganizerRule,
    progress: (@Sendable (OrganizerPlanProgress) -> Void)?
) async throws -> OrganizerPlan {
    let source = sourceURL.standardizedFileURL
    let destination = destinationURL.standardizedFileURL
    try validateOrganizerSource(source, requireWritable: rule.operationMode == .move)
    try validateOrganizerDestination(destination)
    try validateOrganizerTopology(source: source, destination: destination)

    let throttle = OrganizerProgressThrottle(progress)
    let files = try scanOrganizerFiles(sourceURL: source, filter: rule.scanFilter, throttle: throttle)
    guard !files.isEmpty else {
        throw OrganizerService.OrganizerError.noFiles
    }

    // 元数据读取（ImageIO/Spotlight）是纯粹的独立 I/O，是生成预览最贵的一步；
    // 之前串行逐个读，万级文件要等几分钟，现在按 CPU 核数并行。
    let metadataByPairingKey = try await readMetadataInParallel(files: files, throttle: throttle)

    // 目标端存在性判定改为每目录一次 readdir 的清单缓存，替代逐文件 stat。
    var destinationIndex = OrganizerDestinationIndex()
    var reservedDestinations: [String: URL] = [:]
    var items: [OrganizerPlanItem] = []
    items.reserveCapacity(files.count)
    for file in files {
        try Task.checkCancellation()
        // 非 sidecar 已在上面预读并写入 metadataByPairingKey；sidecar 命中同 pairingKey
        // 的主文件元数据，没有配对主文件时再回退到自身读取。
        let metadata = metadataByPairingKey[file.pairingKey] ?? readMetadata(for: file)
        let capturedAt = metadata.capturedAt ?? file.createdAt
        let rawDeviceName = metadata.deviceName
            ?? inferredDeviceName(from: source.lastPathComponent + "/" + file.relativePath)
            ?? "unknown-device"
        let deviceFolderName = deviceFolderName(from: rawDeviceName)
        let proposedDestination = makeOrganizerDestinationURL(
            rootURL: destination,
            capturedAt: capturedAt,
            deviceFolderName: deviceFolderName,
            fileName: file.displayName
        )
        let resolved = resolveDestination(
            proposedDestination,
            sourceURL: file.url,
            duplicatePolicy: rule.duplicatePolicy,
            reservedDestinations: &reservedDestinations,
            destinationIndex: &destinationIndex
        )

        let item = OrganizerPlanItem(
            id: file.url.path,
            sourceURL: file.url,
            destinationURL: resolved.url,
            relativePath: file.relativePath,
            displayName: file.displayName,
            capturedAt: capturedAt,
            deviceName: rawDeviceName,
            deviceFolderName: deviceFolderName,
            size: file.size,
            mediaKind: file.mediaKind,
            conflictResolution: resolved.resolution
        )
        items.append(item)
        throttle.send(.resolving(processed: items.count, total: files.count))
    }

    return OrganizerPlan(
        id: UUID(),
        sourceURL: source,
        destinationURL: destination,
        rule: rule,
        createdAt: Date(),
        items: items.sorted {
            if $0.capturedAt == $1.capturedAt {
                return $0.relativePath < $1.relativePath
            }
            return $0.capturedAt < $1.capturedAt
        }
    )
}

private func executePlan(
    _ plan: OrganizerPlan,
    progress: @escaping @Sendable (OrganizerExecutionState) async -> Void
) async throws -> OrganizerRunSummary {
    try validateOrganizerSource(plan.sourceURL, requireWritable: plan.rule.operationMode == .move)
    try validateOrganizerDestination(plan.destinationURL)
    try validateOrganizerTopology(source: plan.sourceURL, destination: plan.destinationURL)
    try validateOrganizerCapacity(plan)

    let startedAt = Date()
    var state = OrganizerExecutionState(
        totalBytes: plan.totalBytes,
        processedBytes: 0,
        totalFiles: plan.totalFiles,
        processedFiles: 0,
        skippedFiles: 0,
        failedFiles: [],
        currentFile: "",
        phaseTitle: plan.rule.operationMode == .copy ? "正在复制规整" : "正在移动规整",
        startedAt: startedAt,
        finishedAt: nil,
        isActive: true
    )
    await progress(state)

    var reservedDestinations = Set<String>()
    // 进度按时间节流：小文件/sidecar 密集时逐文件回调会把 MainActor 刷爆，
    // 失败与终态仍然强制送达。
    var lastProgressAt = Date.distantPast
    for item in plan.items {
        try Task.checkCancellation()
        state.currentFile = item.displayName

        guard item.isExecutable else {
            state.skippedFiles += 1
            state.processedFiles += 1
            if case .duplicate = item.conflictResolution {
                state.duplicateFiles += 1
            }
            if Date().timeIntervalSince(lastProgressAt) >= 0.1 {
                lastProgressAt = Date()
                await progress(state)
            }
            continue
        }

        var forceProgress = false
        do {
            switch try runtimeDestination(
                for: item,
                plan: plan,
                reservedDestinations: &reservedDestinations
            ) {
            case .duplicate:
                // 计划生成后、执行前目标端新落了一份相同内容（多见于重跑），
                // 视为查重命中而不是失败。
                state.skippedFiles += 1
                state.duplicateFiles += 1
                state.processedFiles += 1
            case let .write(destinationURL):
                try performOrganizerOperation(
                    item: item,
                    destinationURL: destinationURL,
                    mode: plan.rule.operationMode,
                    sourceRootURL: plan.sourceURL,
                    destinationRootURL: plan.destinationURL
                )
                state.processedBytes += item.size
                state.processedFiles += 1
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let organizerError as OrganizerService.OrganizerError {
            forceProgress = true
            if case .destinationAlreadyExists = organizerError, plan.rule.duplicatePolicy == .skip {
                state.skippedFiles += 1
                state.processedFiles += 1
            } else {
                state.failedFiles.append("\(item.relativePath)：\(organizerError.localizedDescription)")
                state.processedFiles += 1
            }
        } catch {
            forceProgress = true
            state.failedFiles.append("\(item.relativePath)：\(error.localizedDescription)")
            state.processedFiles += 1
        }
        if forceProgress || Date().timeIntervalSince(lastProgressAt) >= 0.1 {
            lastProgressAt = Date()
            await progress(state)
        }
    }

    state.currentFile = ""
    state.phaseTitle = state.failedFiles.isEmpty ? "规整完成" : "规整完成，有文件失败"
    state.finishedAt = Date()
    state.isActive = false
    await progress(state)

    return OrganizerRunSummary(
        operationMode: plan.rule.operationMode,
        totalFiles: plan.totalFiles,
        completedFiles: max(0, state.processedFiles - state.skippedFiles - state.failedFiles.count),
        skippedFiles: state.skippedFiles,
        duplicateFiles: state.duplicateFiles,
        failedFiles: state.failedFiles,
        totalBytes: state.processedBytes,
        startedAt: startedAt,
        finishedAt: state.finishedAt ?? Date()
    )
}

private func validateOrganizerSource(_ url: URL, requireWritable: Bool = false) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw OrganizerService.OrganizerError.sourceUnavailable(url.path)
    }
    // 移动规整会删除源文件，必须确认源卷可写，避免拿只读卡当源时逐文件失败、
    // 并在目标留下半套副本（移动跨卷会先复制再删源，删源失败时副本已落地）。
    guard requireWritable else { return }
    let values = try? url.resourceValues(forKeys: [.isWritableKey, .volumeIsReadOnlyKey])
    guard values?.volumeIsReadOnly != true,
          values?.isWritable != false,
          FileManager.default.isWritableFile(atPath: url.path) else {
        throw OrganizerService.OrganizerError.sourceNotWritable(url.path)
    }
}

private func validateOrganizerDestination(_ url: URL) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw OrganizerService.OrganizerError.destinationUnavailable(url.path)
    }
    let values = try? url.resourceValues(forKeys: [.isWritableKey, .volumeIsReadOnlyKey])
    guard values?.volumeIsReadOnly != true,
          values?.isWritable != false,
          FileManager.default.isWritableFile(atPath: url.path) else {
        throw OrganizerService.OrganizerError.destinationNotWritable(url.path)
    }
}

private func validateOrganizerTopology(source: URL, destination: URL) throws {
    if PathSafety.pathsOverlap(source, destination) {
        throw OrganizerService.OrganizerError.pathOverlap("规整源文件夹和目标文件夹不能相同，也不能互相包含。请把目标放到另一个安全位置，避免把输出再次扫进来。")
    }
}

private func validateOrganizerCapacity(_ plan: OrganizerPlan) throws {
    let requiresAdditionalSpace = plan.rule.operationMode == .copy
        || !PathSafety.pathsShareVolume(plan.sourceURL, plan.destinationURL)
    guard requiresAdditionalSpace else { return }
    let requirement = SpacePreflightPolicy.requirement(for: plan.totalBytes)
    let capacity = DiskCapacityResolver.capacity(for: plan.destinationURL)
    guard let available = capacity.availableCapacity else {
        throw OrganizerService.OrganizerError.capacityUnavailable(plan.destinationURL.path)
    }
    guard available >= requirement.requiredBytes else {
        throw OrganizerService.OrganizerError.insufficientSpace(
            available: available,
            required: requirement.requiredBytes
        )
    }
}

/// 生成预览的进度节流器：整个计划构建在单个后台任务里串行推进（并行元数据的
/// 汇总也回到这个任务），所以这里不需要加锁；按时间间隔限流，避免几十 Hz 的
/// MainActor 回调把界面刷卡。
private final class OrganizerProgressThrottle {
    private let handler: (@Sendable (OrganizerPlanProgress) -> Void)?
    private var lastSentAt = Date.distantPast

    init(_ handler: (@Sendable (OrganizerPlanProgress) -> Void)?) {
        self.handler = handler
    }

    func send(_ value: OrganizerPlanProgress, force: Bool = false) {
        guard let handler else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSentAt) >= 0.12 else { return }
        lastSentAt = now
        handler(value)
    }
}

/// 目标目录清单缓存：把逐文件的 fileExists(stat) 换成每目录一次 readdir。
/// 精确同名直接判"存在"；只有大小写变体命中时才回退一次真实 fileExists
/// 消歧 —— APFS 默认卷不区分大小写（应判存在），区分大小写的卷则不应
/// 误判，否则 skip 策略会把本该写入的文件漏拷。消歧是罕见路径，
/// 不影响整体 O(每目录一次 readdir) 的收益。
private struct OrganizerDestinationIndex {
    private struct DirectoryListing {
        let exactNames: Set<String>
        let lowercasedNames: Set<String>
    }

    private var listings: [String: DirectoryListing] = [:]

    mutating func fileExists(at url: URL) -> Bool {
        let directory = url.deletingLastPathComponent().path
        let listing: DirectoryListing
        if let cached = listings[directory] {
            listing = cached
        } else {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            listing = DirectoryListing(
                exactNames: Set(entries),
                lowercasedNames: Set(entries.map { $0.lowercased() })
            )
            listings[directory] = listing
        }

        let name = url.lastPathComponent
        if listing.exactNames.contains(name) { return true }
        guard listing.lowercasedNames.contains(name.lowercased()) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

/// 并行读取非 sidecar 文件的拍摄元数据。宽度取 CPU 核数（2...8）：ImageIO 与
/// Spotlight 读取都是短促的独立 I/O，再宽只会互相争抢磁盘。
private func readMetadataInParallel(
    files: [OrganizerService.SourceFile],
    throttle: OrganizerProgressThrottle
) async throws -> [String: OrganizerService.FileMetadata] {
    let mainFiles = files.filter { !$0.isSidecar }
    guard !mainFiles.isEmpty else { return [:] }

    let width = max(2, min(8, ProcessInfo.processInfo.activeProcessorCount))
    var result = [String: OrganizerService.FileMetadata](minimumCapacity: mainFiles.count)
    var processed = 0

    try await withThrowingTaskGroup(of: (String, OrganizerService.FileMetadata).self) { group in
        var iterator = mainFiles.makeIterator()

        @discardableResult
        func addNext() -> Bool {
            guard let file = iterator.next() else { return false }
            group.addTask {
                try Task.checkCancellation()
                return (file.pairingKey, readMetadata(for: file))
            }
            return true
        }

        for _ in 0..<width {
            if !addNext() { break }
        }
        while let (key, metadata) = try await group.next() {
            result[key] = metadata
            processed += 1
            throttle.send(.readingMetadata(processed: processed, total: mainFiles.count))
            addNext()
        }
    }
    return result
}

private func scanOrganizerFiles(
    sourceURL: URL,
    filter: ScanFilter,
    throttle: OrganizerProgressThrottle
) throws -> [OrganizerService.SourceFile] {
    let keys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .creationDateKey,
        .contentModificationDateKey,
        .fileSizeKey,
        .nameKey,
        .isDirectoryKey,
        .isHiddenKey,
        .isPackageKey,
        .isSymbolicLinkKey
    ]

    guard let enumerator = FileManager.default.enumerator(
        at: sourceURL,
        includingPropertiesForKeys: Array(keys),
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
    ) else {
        throw OrganizerService.OrganizerError.cannotCreateEnumerator(sourceURL.path)
    }

    var files: [OrganizerService.SourceFile] = []
    for case let url as URL in enumerator {
        try Task.checkCancellation()
        guard let values = try? url.resourceValues(forKeys: keys) else { continue }
        if shouldSkipOrganizerURL(url, values: values) {
            if values.isDirectory == true || values.isSymbolicLink == true {
                enumerator.skipDescendants()
            }
            continue
        }
        guard values.isRegularFile == true else { continue }

        let fileExtension = url.pathExtension.lowercased()
        let mediaKind = organizerMediaKind(for: fileExtension)
        let isSidecar = organizerSidecarExtensions.contains(fileExtension)
        guard filter == .all || mediaKind == filter || isSidecar else { continue }

        files.append(
            OrganizerService.SourceFile(
                url: url.standardizedFileURL,
                relativePath: try PathSafety.relativePath(for: url, under: sourceURL),
                displayName: values.name ?? url.lastPathComponent,
                createdAt: values.creationDate ?? values.contentModificationDate ?? Date(),
                modifiedAt: values.contentModificationDate ?? values.creationDate ?? Date(),
                size: Int64(values.fileSize ?? 0),
                mediaKind: mediaKind,
                isSidecar: isSidecar
            )
        )
        throttle.send(.scanning(found: files.count))
    }

    return files.sorted {
        if $0.createdAt == $1.createdAt {
            return $0.relativePath < $1.relativePath
        }
        return $0.createdAt < $1.createdAt
    }
}

private func shouldSkipOrganizerURL(_ url: URL, values: URLResourceValues) -> Bool {
    let name = url.lastPathComponent
    if values.isSymbolicLink == true {
        return true
    }
    if values.isHidden == true || name.hasPrefix(".") {
        return true
    }
    if values.isPackage == true {
        return true
    }
    if [
        "__MACOSX",
        ".Trashes",
        ".Spotlight-V100",
        ".fseventsd",
        ".TemporaryItems",
        ".DocumentRevisions-V100",
        ".file",
        ".VolumeIcon.icns"
    ].contains(name) || name.hasPrefix(".com.apple.timemachine") {
        return true
    }
    return false
}

private func readMetadata(for file: OrganizerService.SourceFile) -> OrganizerService.FileMetadata {
    // ImageIO 只认识图片。视频/音频每次都会创建失败再走 Spotlight，
    // 白白付一次打开+嗅探的开销，所以按媒体类型直接分流。
    let imageMetadata = file.mediaKind == .photo
        ? readImageMetadata(url: file.url)
        : OrganizerService.FileMetadata(capturedAt: nil, deviceName: nil)
    if imageMetadata.capturedAt != nil, imageMetadata.deviceName != nil {
        return imageMetadata
    }
    let spotlightMetadata = readSpotlightMetadata(url: file.url)
    return OrganizerService.FileMetadata(
        capturedAt: imageMetadata.capturedAt ?? spotlightMetadata.capturedAt ?? file.createdAt,
        deviceName: imageMetadata.deviceName ?? spotlightMetadata.deviceName
    )
}

private func readImageMetadata(url: URL) -> OrganizerService.FileMetadata {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
        return OrganizerService.FileMetadata(capturedAt: nil, deviceName: nil)
    }

    let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
    let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
    let capturedAt = [
        exif?[kCGImagePropertyExifDateTimeOriginal] as? String,
        exif?[kCGImagePropertyExifDateTimeDigitized] as? String,
        tiff?[kCGImagePropertyTIFFDateTime] as? String
    ]
    .compactMap { $0 }
    .lazy
    .compactMap(parseMetadataDate)
    .first

    let make = (tiff?[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let model = (tiff?[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let device = [make, model]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " ")

    return OrganizerService.FileMetadata(
        capturedAt: capturedAt,
        deviceName: device.isEmpty ? nil : device
    )
}

private func readSpotlightMetadata(url: URL) -> OrganizerService.FileMetadata {
    guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else {
        return OrganizerService.FileMetadata(capturedAt: nil, deviceName: nil)
    }

    let capturedAt = MDItemCopyAttribute(item, kMDItemContentCreationDate) as? Date
    let make = (MDItemCopyAttribute(item, kMDItemAcquisitionMake) as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let model = (MDItemCopyAttribute(item, kMDItemAcquisitionModel) as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let device = [make, model]
        .compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " ")

    return OrganizerService.FileMetadata(
        capturedAt: capturedAt,
        deviceName: device.isEmpty ? nil : device
    )
}

// 每个文件解析日期都重建 DateFormatter 的开销比解析本身还大，改为常量复用。
// DateFormatter / ISO8601DateFormatter 在 macOS 10.9+ 上只读使用是线程安全的，
// 可被并行元数据任务共享。
private let organizerExifDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return formatter
}()

// ISO8601DateFormatter 未标记 Sendable，但苹果文档明确其线程安全；
// 这里初始化后不再修改，只读共享。
nonisolated(unsafe) private let organizerISOFractionalDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

nonisolated(unsafe) private let organizerISODateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()

private func parseMetadataDate(_ rawValue: String) -> Date? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return organizerExifDateFormatter.date(from: trimmed)
        ?? organizerISOFractionalDateFormatter.date(from: trimmed)
        ?? organizerISODateFormatter.date(from: trimmed)
}

private func makeOrganizerDestinationURL(rootURL: URL, capturedAt: Date, deviceFolderName: String, fileName: String) -> URL {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: capturedAt)
    let year = "\(components.year ?? 1970)"
    let month = "\(components.month ?? 1)"
    let day = "\(components.day ?? 1)"
    return rootURL
        .appendingPathComponent(year, isDirectory: true)
        .appendingPathComponent(month, isDirectory: true)
        .appendingPathComponent(day, isDirectory: true)
        .appendingPathComponent(deviceFolderName, isDirectory: true)
        .appendingPathComponent(fileName, isDirectory: false)
}

/// 逐字节流式比对两个文件的内容，任何一块不同立即返回。对"两个具体文件是否
/// 一致"这种一对一判定，它比双方各算一次哈希更快：单遍读取、可提前退出。
/// 任何读取错误都按"内容不同"处理 —— 查重只允许假阴性（多留一份），
/// 绝不允许假阳性（把不一致的文件当重复跳过）。
private func organizerFilesHaveIdenticalContent(_ lhs: URL, _ rhs: URL) -> Bool {
    guard let lhsSize = try? lhs.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          let rhsSize = try? rhs.resourceValues(forKeys: [.fileSizeKey]).fileSize,
          lhsSize == rhsSize else {
        return false
    }
    if lhsSize == 0 { return true }
    guard let lhsHandle = try? FileHandle(forReadingFrom: lhs),
          let rhsHandle = try? FileHandle(forReadingFrom: rhs) else {
        return false
    }
    defer {
        try? lhsHandle.close()
        try? rhsHandle.close()
    }

    let chunkSize = 1 << 20
    while true {
        // 取消时立即放弃比对，按"内容不同"返回：调用方循环顶部的
        // checkCancellation 会随即终止整个计划，不会基于这个结果写盘。
        if Task.isCancelled { return false }
        let lhsChunk: Data
        let rhsChunk: Data
        do {
            lhsChunk = try lhsHandle.read(upToCount: chunkSize) ?? Data()
            rhsChunk = try rhsHandle.read(upToCount: chunkSize) ?? Data()
        } catch {
            return false
        }
        if lhsChunk != rhsChunk { return false }
        if lhsChunk.isEmpty { return true }
    }
}

private func resolveDestination(
    _ proposedURL: URL,
    sourceURL: URL,
    duplicatePolicy: OrganizerDuplicatePolicy,
    reservedDestinations: inout [String: URL],
    destinationIndex: inout OrganizerDestinationIndex
) -> (url: URL, resolution: OrganizerConflictResolution) {
    let normalizedProposed = PathSafety.normalizedPath(proposedURL)
    let existsOnDisk = destinationIndex.fileExists(at: proposedURL)
    let reservedOwner = reservedDestinations[normalizedProposed]

    guard existsOnDisk || reservedOwner != nil else {
        reservedDestinations[normalizedProposed] = sourceURL
        return (proposedURL, .none)
    }

    // 查重：同名先比内容。与目标现有文件一致，或与同批更早规划的源文件一致，
    // 都标记为重复 —— 再写一份副本对素材管理没有价值。
    if existsOnDisk, organizerFilesHaveIdenticalContent(sourceURL, proposedURL) {
        return (proposedURL, .duplicate(existingPath: proposedURL.path))
    }
    if let reservedOwner, organizerFilesHaveIdenticalContent(sourceURL, reservedOwner) {
        return (proposedURL, .duplicate(existingPath: reservedOwner.path))
    }

    if duplicatePolicy == .skip {
        return (proposedURL, .skipped(existingPath: proposedURL.path))
    }

    let uniqueURL = uniqueOrganizerDestinationURL(
        for: proposedURL,
        reservedDestinations: Set(reservedDestinations.keys),
        destinationIndex: &destinationIndex
    )
    reservedDestinations[PathSafety.normalizedPath(uniqueURL)] = sourceURL
    return (uniqueURL, .renamed(originalPath: proposedURL.path))
}

/// 执行期对单个文件的落点判定：目标可能在"生成预览"与"执行"之间被外部改动，
/// 所以这里用实时 fileExists 复核，并对撞名文件再做一次内容比对。
private enum OrganizerRuntimeDestination {
    case write(URL)
    case duplicate(existingPath: String)
}

private func runtimeDestination(
    for item: OrganizerPlanItem,
    plan: OrganizerPlan,
    reservedDestinations: inout Set<String>
) throws -> OrganizerRuntimeDestination {
    let normalized = PathSafety.normalizedPath(item.destinationURL)
    let exists = FileManager.default.fileExists(atPath: item.destinationURL.path)
    let reserved = reservedDestinations.contains(normalized)

    guard exists || reserved else {
        reservedDestinations.insert(normalized)
        return .write(item.destinationURL)
    }

    if exists, organizerFilesHaveIdenticalContent(item.sourceURL, item.destinationURL) {
        return .duplicate(existingPath: item.destinationURL.path)
    }

    if plan.rule.duplicatePolicy == .skip {
        throw OrganizerService.OrganizerError.destinationAlreadyExists(item.destinationURL.path)
    }

    var runtimeIndex = OrganizerDestinationIndex()
    let uniqueURL = uniqueOrganizerDestinationURL(
        for: item.destinationURL,
        reservedDestinations: reservedDestinations,
        destinationIndex: &runtimeIndex
    )
    reservedDestinations.insert(PathSafety.normalizedPath(uniqueURL))
    return .write(uniqueURL)
}

private func uniqueOrganizerDestinationURL(
    for proposedURL: URL,
    reservedDestinations: Set<String>,
    destinationIndex: inout OrganizerDestinationIndex
) -> URL {
    let directory = proposedURL.deletingLastPathComponent()
    let baseName = proposedURL.deletingPathExtension().lastPathComponent
    let ext = proposedURL.pathExtension

    for index in 2...9999 {
        let candidateName = ext.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(ext)"
        let candidate = directory.appendingPathComponent(candidateName, isDirectory: false)
        let normalized = PathSafety.normalizedPath(candidate)
        if !destinationIndex.fileExists(at: candidate),
           !reservedDestinations.contains(normalized) {
            return candidate
        }
    }

    let fallbackName = ext.isEmpty
        ? "\(baseName) \(UUID().uuidString)"
        : "\(baseName) \(UUID().uuidString).\(ext)"
    return directory.appendingPathComponent(fallbackName, isDirectory: false)
}

private func performOrganizerOperation(
    item: OrganizerPlanItem,
    destinationURL: URL,
    mode: OrganizerOperationMode,
    sourceRootURL: URL,
    destinationRootURL: URL
) throws {
    try PathSafety.ensureSafeExistingFileTarget(for: item.sourceURL, under: sourceRootURL)
    try PathSafety.ensureSafeWritableFileTarget(for: destinationURL, under: destinationRootURL)
    guard FileManager.default.fileExists(atPath: item.sourceURL.path) else {
        throw OrganizerService.OrganizerError.sourceUnavailable(item.sourceURL.path)
    }
    guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
        throw OrganizerService.OrganizerError.destinationAlreadyExists(destinationURL.path)
    }

    try Task.checkCancellation()
    let parent = destinationURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    try PathSafety.ensureSafeWritableFileTarget(for: destinationURL, under: destinationRootURL)

    if mode == .move && PathSafety.pathsShareVolume(item.sourceURL, destinationURL) {
        // 同卷使用排他原子重命名，文件内容和扩展属性无需重写。
        try installOrganizerFileExclusively(from: item.sourceURL, to: destinationURL)
    } else {
        try OrganizerVerifiedCopy.perform(
            sourceURL: item.sourceURL,
            destinationURL: destinationURL,
            sourceRootURL: sourceRootURL,
            destinationRootURL: destinationRootURL,
            removeSource: mode == .move
        )
    }
}

/// 跨卷移动先复制、落盘和逐字节校验，再安装目标并删除源文件。
/// Foundation copyItem 保留元数据；临时文件和最终文件都拒绝覆盖。
enum OrganizerVerifiedCopy {
    static func perform(
        sourceURL: URL,
        destinationURL: URL,
        sourceRootURL: URL,
        destinationRootURL: URL,
        removeSource: Bool,
        verifier: ((URL, URL) throws -> Bool)? = nil
    ) throws {
        try Task.checkCancellation()
        try PathSafety.ensureSafeExistingFileTarget(for: sourceURL, under: sourceRootURL)
        try PathSafety.ensureSafeWritableFileTarget(for: destinationURL, under: destinationRootURL)
        let identity = try SourceIdentity(url: sourceURL)
        let stagingURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(".airwang-organize-\(UUID().uuidString).partial", isDirectory: true)
        try PathSafety.ensureSafeWritableFileTarget(for: stagingURL, under: destinationRootURL)
        let manager = FileManager.default
        guard mkdir(stagingURL.path, 0o700) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        // 专属目录即使复制中途抛错也能收回残留，已安装的目标不在其中。
        defer { try? manager.removeItem(at: stagingURL) }
        let temporaryURL = stagingURL.appendingPathComponent(sourceURL.lastPathComponent)
        try manager.copyItem(at: sourceURL, to: temporaryURL)
        try Task.checkCancellation()
        let handle = try FileHandle(forWritingTo: temporaryURL)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        let identical = try verifier?(sourceURL, temporaryURL) ?? organizerFilesHaveIdenticalContent(sourceURL, temporaryURL)
        try Task.checkCancellation()
        guard identical else { throw OrganizerService.OrganizerError.verificationFailed(sourceURL.path) }
        guard try SourceIdentity(url: sourceURL) == identity else {
            throw OrganizerService.OrganizerError.sourceChanged(sourceURL.path)
        }
        try PathSafety.ensureSafeWritableFileTarget(for: destinationURL, under: destinationRootURL)
        try installOrganizerFileExclusively(from: temporaryURL, to: destinationURL)
        if removeSource {
            // 取消、源变更或删除失败时保留已验证的目标副本和仍在的源文件。
            try Task.checkCancellation()
            try PathSafety.ensureSafeExistingFileTarget(for: sourceURL, under: sourceRootURL)
            guard try SourceIdentity(url: sourceURL) == identity else {
                throw OrganizerService.OrganizerError.sourceChanged(sourceURL.path)
            }
            try manager.removeItem(at: sourceURL)
        }
    }

    private struct SourceIdentity: Equatable {
        let inode: UInt64
        let device: UInt64
        let size: UInt64
        let modifiedAt: Date

        init(url: URL) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let inode = attributes[.systemFileNumber] as? NSNumber,
                  let device = attributes[.systemNumber] as? NSNumber,
                  let size = attributes[.size] as? NSNumber,
                  let modifiedAt = attributes[.modificationDate] as? Date else {
                throw OrganizerService.OrganizerError.sourceUnavailable(url.path)
            }
            self.inode = inode.uint64Value
            self.device = device.uint64Value
            self.size = size.uint64Value
            self.modifiedAt = modifiedAt
        }
    }
}

private func installOrganizerFileExclusively(from source: URL, to destination: URL) throws {
    guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
        let code = errno
        if code == EEXIST { throw OrganizerService.OrganizerError.destinationAlreadyExists(destination.path) }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: destination.path])
    }
}

private func organizerMediaKind(for fileExtension: String) -> ScanFilter {
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

private let organizerSidecarExtensions: Set<String> = [
    "rmd", "xml", "xmp", "thm", "lrv", "lut", "cube", "cdl",
    "ale", "edl", "json", "srt", "vtt", "md5", "sha1", "sha256"
]

private func inferredDeviceName(from relativePath: String) -> String? {
    let searchable = relativePath.replacingOccurrences(of: "_", with: " ")
    for alias in knownDeviceAliases {
        if normalizedDeviceToken(searchable).contains(alias.token) {
            return alias.folder
        }
    }
    return nil
}

private func deviceFolderName(from rawValue: String) -> String {
    let normalized = normalizedDeviceToken(rawValue)
    for alias in knownDeviceAliases where normalized.contains(alias.token) {
        return alias.folder
    }
    return FileNameSanitizer.safeComponent(
        rawValue.lowercased().replacingOccurrences(of: " ", with: "-"),
        fallback: "unknown-device",
        maximumLength: 48
    )
}

private func normalizedDeviceToken(_ rawValue: String) -> String {
    rawValue
        .lowercased()
        .filter { $0.isLetter || $0.isNumber }
}

private let knownDeviceAliases: [(token: String, folder: String)] = [
    ("ilce7m3", "a7m3"),
    ("a7m3", "a7m3"),
    ("a7iii", "a7m3"),
    ("ilce7m4", "a7m4"),
    ("a7m4", "a7m4"),
    ("a7iv", "a7m4"),
    ("ilce7sm3", "a7s3"),
    ("a7siii", "a7s3"),
    ("a7s3", "a7s3"),
    ("ilce7rm5", "a7r5"),
    ("a7rv", "a7r5"),
    ("a7r5", "a7r5"),
    ("ilmefx3", "fx3"),
    ("fx3", "fx3"),
    ("ilmefx30", "fx30"),
    ("fx30", "fx30"),
    ("eosr6markii", "eos-r6-ii"),
    ("eosr5", "eos-r5"),
    ("eosr6", "eos-r6"),
    ("bmpcc4k", "bmpcc4k"),
    ("bmpcc6k", "bmpcc6k"),
    ("pocketcinemacamera6k", "bmpcc6k"),
    ("goprohero12", "hero12"),
    ("goprohero11", "hero11"),
    ("iphone15pro", "iphone15pro"),
    ("iphone14pro", "iphone14pro"),
    ("djiosmopocket3", "osmo-pocket-3"),
    ("osmopocket3", "osmo-pocket-3")
]
