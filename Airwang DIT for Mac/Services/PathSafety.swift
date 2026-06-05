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

        if basePath == "/" {
            let raw = String(filePath.dropFirst())
            return try validatedRelativePath(raw)
        }
        guard canonicalComparisonPath(filePath).hasPrefix(canonicalComparisonPath(basePath + "/")) else {
            throw Error.pathEscapesBase(relativePath: fileURL.path, basePath: basePath)
        }
        let startIndex = filePath.index(filePath.startIndex, offsetBy: basePath.count + 1)
        return try validatedRelativePath(String(filePath[startIndex...]))
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

    static func ensureSafeExistingFileTarget(for candidateURL: URL, under baseURL: URL) throws {
        guard isContained(candidateURL, in: baseURL) else {
            throw Error.pathEscapesBase(relativePath: candidateURL.path, basePath: normalizedPath(baseURL))
        }
        try ensureNoSymlinkAncestors(for: candidateURL, under: baseURL)
        if isSymbolicLink(candidateURL) {
            throw Error.symlinkTarget(candidateURL)
        }
    }

    static func ensureSafeWritableFileTarget(for candidateURL: URL, under baseURL: URL) throws {
        guard isContained(candidateURL, in: baseURL) else {
            throw Error.pathEscapesBase(relativePath: candidateURL.path, basePath: normalizedPath(baseURL))
        }
        try ensureNoSymlinkAncestors(for: candidateURL, under: baseURL)
        if isSymbolicLink(candidateURL) {
            throw Error.symlinkTarget(candidateURL)
        }
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
