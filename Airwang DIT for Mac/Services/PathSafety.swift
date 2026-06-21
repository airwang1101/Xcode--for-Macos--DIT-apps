import Foundation

struct SafeRelativePath: Codable, Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) throws {
        self.rawValue = try PathSafety.validatedRelativePath(rawValue)
    }
}

enum PathSafety {
    enum Error: LocalizedError, Equatable {
        case emptyRelativePath
        case absoluteRelativePath(String)
        case invalidRelativePathComponent(String)
        case pathEscapesBase(relativePath: String, basePath: String)
        case symlinkAncestor(URL)
        case symlinkTarget(URL)

        var errorDescription: String? {
            switch self {
            case .emptyRelativePath:
                return "相对路径为空，已拒绝执行。"
            case let .absoluteRelativePath(path):
                return "相对路径不能是绝对路径：\(path)"
            case let .invalidRelativePathComponent(component):
                return "相对路径包含不安全片段：\(component)"
            case let .pathEscapesBase(relativePath, basePath):
                return "路径“\(relativePath)”会逃出允许目录：\(basePath)"
            case let .symlinkAncestor(url):
                return "目标路径包含符号链接目录，已拒绝写入：\(url.path)"
            case let .symlinkTarget(url):
                return "目标文件是符号链接，已拒绝处理：\(url.path)"
            }
        }
    }

    static func validatedRelativePath(_ rawPath: String) throws -> String {
        guard !rawPath.isEmpty else {
            throw Error.emptyRelativePath
        }
        guard !rawPath.contains("\0") else {
            throw Error.invalidRelativePathComponent("\\0")
        }
        guard !rawPath.hasPrefix("/") else {
            throw Error.absoluteRelativePath(rawPath)
        }

        let components = rawPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty else {
            throw Error.emptyRelativePath
        }
        for component in components {
            if component.isEmpty || component == "." || component == ".." {
                throw Error.invalidRelativePathComponent(component.isEmpty ? "/" : component)
            }
        }
        return components.joined(separator: "/")
    }

    static func resolvedURL(for rawRelativePath: String, under baseURL: URL, isDirectory: Bool = false) throws -> URL {
        let relativePath = try validatedRelativePath(rawRelativePath)
        var candidate = normalizedBaseURL(baseURL)
        for component in relativePath.split(separator: "/").map(String.init) {
            candidate.appendPathComponent(component, isDirectory: false)
        }

        let resolved = candidate.standardizedFileURL
        guard isContained(resolved, in: baseURL) else {
            throw Error.pathEscapesBase(relativePath: relativePath, basePath: normalizedPath(baseURL))
        }
        if isDirectory {
            return URL(fileURLWithPath: resolved.path, isDirectory: true)
        }
        return resolved
    }

    static func relativePath(for fileURL: URL, under baseURL: URL) throws -> String {
        let basePath = normalizedPath(baseURL)
        let filePath = normalizedPath(fileURL)
        let canonicalBase = canonicalComparisonPath(basePath)
        let canonicalFile = canonicalComparisonPath(filePath)

        if basePath == "/" {
            let raw = String(canonicalFile.dropFirst())
            return try validatedRelativePath(raw)
        }
        let prefix = canonicalBase + "/"
        guard canonicalFile.hasPrefix(prefix) else {
            throw Error.pathEscapesBase(relativePath: fileURL.path, basePath: basePath)
        }
        // Slice from the canonical string so multibyte/combining characters don't misalign the offset.
        let raw = String(canonicalFile[canonicalFile.index(canonicalFile.startIndex, offsetBy: prefix.count)...])
        return try validatedRelativePath(raw)
    }

    static func isContained(_ candidateURL: URL, in baseURL: URL) -> Bool {
        let basePath = normalizedPath(baseURL)
        let candidatePath = normalizedPath(candidateURL)
        let canonicalBase = canonicalComparisonPath(basePath)
        let canonicalCandidate = canonicalComparisonPath(candidatePath)
        if canonicalCandidate == canonicalBase {
            return true
        }
        guard canonicalBase != "/" else {
            return canonicalCandidate.hasPrefix("/")
        }
        return canonicalCandidate.hasPrefix(canonicalBase + "/")
    }

    static func ensureNoSymlinkAncestors(for candidateURL: URL, under baseURL: URL) throws {
        let basePath = normalizedPath(baseURL)
        let candidateParent = candidateURL.deletingLastPathComponent()
        guard isContained(candidateParent, in: baseURL) else {
            throw Error.pathEscapesBase(relativePath: candidateURL.path, basePath: basePath)
        }

        if basePath != "/", isSymbolicLink(URL(fileURLWithPath: basePath, isDirectory: true)) {
            throw Error.symlinkAncestor(URL(fileURLWithPath: basePath, isDirectory: true))
        }

        if canonicalComparisonPath(normalizedPath(candidateParent)) == canonicalComparisonPath(basePath) {
            return
        }
        var current = normalizedBaseURL(baseURL)
        let relative = try relativePath(for: candidateParent, under: baseURL)
        for component in relative.split(separator: "/").map(String.init) {
            current.appendPathComponent(component, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirectory) else {
                continue
            }
            let values = try? current.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                throw Error.symlinkAncestor(current)
            }
        }
    }

    /// 源(读)文件的安全约束入口。语义化命名便于调用点阅读。
    static func ensureSafeExistingFileTarget(for candidateURL: URL, under baseURL: URL) throws {
        try ensureSafeFileTarget(for: candidateURL, under: baseURL)
    }

    /// 目标(写)文件的安全约束入口。语义化命名便于调用点阅读。
    static func ensureSafeWritableFileTarget(for candidateURL: URL, under baseURL: URL) throws {
        try ensureSafeFileTarget(for: candidateURL, under: baseURL)
    }

    /// 源(读)与目标(写)目前共享同一套硬约束:必须包含在 baseURL 内、祖先链无符号
    /// 链接、目标自身不是符号链接。两个语义化入口委托到这里,避免将来单边修改某条
    /// 路径的规则时,读/写两侧的判断静默失同步。
    private static func ensureSafeFileTarget(for candidateURL: URL, under baseURL: URL) throws {
        guard isContained(candidateURL, in: baseURL) else {
            throw Error.pathEscapesBase(relativePath: candidateURL.path, basePath: normalizedPath(baseURL))
        }
        try ensureNoSymlinkAncestors(for: candidateURL, under: baseURL)
        if isSymbolicLink(candidateURL) {
            throw Error.symlinkTarget(candidateURL)
        }
    }

    // MARK: - 卷与目录拓扑

    /// 两个目录相同或互相包含。
    ///
    /// 这是"源/目标/备份盘不允许嵌套"规则的唯一实现:AppViewModel 在创建项目时
    /// 用它做预检,TransferService 在执行阶段用它做硬校验。此前两边各持一份
    /// 私有副本且都不做 NFC 规范化,与 `isContained` 的判断存在 NFD/NFC 分叉
    /// 风险(TEST_REPORT #113);现在统一走 canonical comparison。
    static func pathsOverlap(_ lhs: URL, _ rhs: URL) -> Bool {
        // Resolve symlinks before comparing so /Volumes/B -> /Volumes/A is detected as overlap.
        let lhsPath = canonicalComparisonPath(resolvedNormalizedPath(lhs))
        let rhsPath = canonicalComparisonPath(resolvedNormalizedPath(rhs))
        if lhsPath == rhsPath {
            return true
        }
        return isPath(lhsPath, inside: rhsPath) || isPath(rhsPath, inside: lhsPath)
    }

    /// 两个 URL 是否落在同一个物理卷上(按卷根路径比对)。
    /// 卷根解析失败(典型场景:设备已拔出)时返回 `false`,
    /// 调用方应将"无法判断"视为"不共卷"并依赖后续执行期校验兜底。
    static func pathsShareVolume(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhsRoot = DiskCapacityResolver.volumeRootPath(for: lhs),
              let rhsRoot = DiskCapacityResolver.volumeRootPath(for: rhs) else {
            return false
        }
        return canonicalComparisonPath(normalizedPath(lhsRoot))
            == canonicalComparisonPath(normalizedPath(rhsRoot))
    }

    private static func isPath(_ childPath: String, inside parentPath: String) -> Bool {
        guard parentPath != "/" else { return childPath != "/" }
        return childPath.hasPrefix(parentPath + "/")
    }

    static func normalizedPath(_ url: URL) -> String {
        normalizedPath(url.standardizedFileURL.path)
    }

    static func normalizedPath(_ path: String) -> String {
        var normalized = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        while normalized.count > 1 && normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        return normalized
    }

    /// Like `normalizedPath` but also resolves symlinks (used for overlap/containment checks).
    private static func resolvedNormalizedPath(_ url: URL) -> String {
        normalizedPath(url.standardizedFileURL.resolvingSymlinksInPath().path)
    }

    private static func normalizedBaseURL(_ url: URL) -> URL {
        URL(fileURLWithPath: normalizedPath(url), isDirectory: true)
    }

    private static func canonicalComparisonPath(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }
}
