import CoreServices
import Foundation
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
        rule: OrganizerRule
    ) async throws -> OrganizerPlan {
        try await Task.detached(priority: .userInitiated) {
            try buildPlan(sourceURL: sourceURL, destinationURL: destinationURL, rule: rule)
        }.value
    }

    func execute(
        plan: OrganizerPlan,
        progress: @escaping @Sendable (OrganizerExecutionState) async -> Void
    ) async throws -> OrganizerRunSummary {
        try await Task.detached(priority: .userInitiated) {
            try await executePlan(plan, progress: progress)
        }.value
    }
}

private func buildPlan(sourceURL: URL, destinationURL: URL, rule: OrganizerRule) throws -> OrganizerPlan {
    let source = sourceURL.standardizedFileURL
    let destination = destinationURL.standardizedFileURL
    try validateOrganizerSource(source, requireWritable: rule.operationMode == .move)
    try validateOrganizerDestination(destination)
    try validateOrganizerTopology(source: source, destination: destination)

    let files = try scanOrganizerFiles(sourceURL: source, filter: rule.scanFilter)
    guard !files.isEmpty else {
        throw OrganizerService.OrganizerError.noFiles
    }

    var metadataByPairingKey: [String: OrganizerService.FileMetadata] = [:]
    for file in files where !file.isSidecar {
        metadataByPairingKey[file.pairingKey] = readMetadata(for: file)
    }

    var reservedDestinations = Set<String>()
    var items: [OrganizerPlanItem] = []
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
            duplicatePolicy: rule.duplicatePolicy,
            reservedDestinations: &reservedDestinations
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
    for item in plan.items {
        try Task.checkCancellation()
        state.currentFile = item.displayName

        guard item.isExecutable else {
            state.skippedFiles += 1
            state.processedFiles += 1
            await progress(state)
            continue
        }

        do {
            let runtimeDestination = try runtimeDestinationURL(
                for: item,
                plan: plan,
                reservedDestinations: &reservedDestinations
            )
            try performOrganizerOperation(
                item: item,
                destinationURL: runtimeDestination,
                mode: plan.rule.operationMode,
                sourceRootURL: plan.sourceURL,
                destinationRootURL: plan.destinationURL
            )
            state.processedBytes += item.size
            state.processedFiles += 1
        } catch let organizerError as OrganizerService.OrganizerError {
            if case .destinationAlreadyExists = organizerError, plan.rule.duplicatePolicy == .skip {
                state.skippedFiles += 1
                state.processedFiles += 1
            } else {
                state.failedFiles.append("\(item.relativePath)：\(organizerError.localizedDescription)")
                state.processedFiles += 1
            }
        } catch {
            state.failedFiles.append("\(item.relativePath)：\(error.localizedDescription)")
            state.processedFiles += 1
        }
        await progress(state)
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

private func scanOrganizerFiles(sourceURL: URL, filter: ScanFilter) throws -> [OrganizerService.SourceFile] {
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
    let imageMetadata = readImageMetadata(url: file.url)
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

private func parseMetadataDate(_ rawValue: String) -> Date? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let exifFormatter = DateFormatter()
    exifFormatter.locale = Locale(identifier: "en_US_POSIX")
    exifFormatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    if let date = exifFormatter.date(from: trimmed) {
        return date
    }
    let isoFormatter = ISO8601DateFormatter()
    isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = isoFormatter.date(from: trimmed) {
        return date
    }
    isoFormatter.formatOptions = [.withInternetDateTime]
    return isoFormatter.date(from: trimmed)
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

private func resolveDestination(
    _ proposedURL: URL,
    duplicatePolicy: OrganizerDuplicatePolicy,
    reservedDestinations: inout Set<String>
) -> (url: URL, resolution: OrganizerConflictResolution) {
    let normalizedProposed = PathSafety.normalizedPath(proposedURL)
    let exists = FileManager.default.fileExists(atPath: proposedURL.path)
    let reserved = reservedDestinations.contains(normalizedProposed)

    guard exists || reserved else {
        reservedDestinations.insert(normalizedProposed)
        return (proposedURL, .none)
    }

    if duplicatePolicy == .skip {
        return (proposedURL, .skipped(existingPath: proposedURL.path))
    }

    let uniqueURL = uniqueOrganizerDestinationURL(for: proposedURL, reservedDestinations: reservedDestinations)
    reservedDestinations.insert(PathSafety.normalizedPath(uniqueURL))
    return (uniqueURL, .renamed(originalPath: proposedURL.path))
}

private func runtimeDestinationURL(
    for item: OrganizerPlanItem,
    plan: OrganizerPlan,
    reservedDestinations: inout Set<String>
) throws -> URL {
    let normalized = PathSafety.normalizedPath(item.destinationURL)
    let exists = FileManager.default.fileExists(atPath: item.destinationURL.path)
    let reserved = reservedDestinations.contains(normalized)

    guard exists || reserved else {
        reservedDestinations.insert(normalized)
        return item.destinationURL
    }

    if plan.rule.duplicatePolicy == .skip {
        throw OrganizerService.OrganizerError.destinationAlreadyExists(item.destinationURL.path)
    }

    let uniqueURL = uniqueOrganizerDestinationURL(for: item.destinationURL, reservedDestinations: reservedDestinations)
    reservedDestinations.insert(PathSafety.normalizedPath(uniqueURL))
    return uniqueURL
}

private func uniqueOrganizerDestinationURL(for proposedURL: URL, reservedDestinations: Set<String>) -> URL {
    let directory = proposedURL.deletingLastPathComponent()
    let baseName = proposedURL.deletingPathExtension().lastPathComponent
    let ext = proposedURL.pathExtension

    for index in 2...9999 {
        let candidateName = ext.isEmpty ? "\(baseName) \(index)" : "\(baseName) \(index).\(ext)"
        let candidate = directory.appendingPathComponent(candidateName, isDirectory: false)
        let normalized = PathSafety.normalizedPath(candidate)
        if !FileManager.default.fileExists(atPath: candidate.path),
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

    // 以执行期源文件的真实大小做基准，而不是计划期可能已过时的 item.size：
    // 文件在扫描后仍在落盘/被改动时，旧值会把一次字节完整的复制/移动误判为失败。
    let expectedSize = (try? item.sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? item.size

    let parent = destinationURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

    switch mode {
    case .copy:
        try FileManager.default.copyItem(at: item.sourceURL, to: destinationURL)
    case .move:
        try FileManager.default.moveItem(at: item.sourceURL, to: destinationURL)
    }

    let actualSize = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? -1
    guard actualSize == expectedSize else {
        // 复制模式下源仍在，删掉写坏的目标，避免残留半套文件污染重跑；
        // 移动模式下源已被系统删除、无法回滚，只能如实上报。
        if mode == .copy {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        throw OrganizerService.OrganizerError.copiedSizeMismatch(
            path: destinationURL.path,
            expected: expectedSize,
            actual: actualSize
        )
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
