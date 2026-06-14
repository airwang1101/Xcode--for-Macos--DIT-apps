import Foundation

struct MediaScanner {
    enum ScanError: LocalizedError {
        case cannotCreateEnumerator(URL)

        var errorDescription: String? {
            switch self {
            case let .cannotCreateEnumerator(url):
                return "无法读取素材目录：\(url.path)"
            }
        }
    }

    func scan(volume: StorageVolume, rootURL: URL? = nil, filter: ScanFilter = .video) throws -> [MediaItem] {
        let scanRoot = rootURL ?? volume.url
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .creationDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .typeIdentifierKey,
            .nameKey,
            .isDirectoryKey,
            .isHiddenKey,
            .isPackageKey,
            .isSymbolicLinkKey
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: scanRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ScanError.cannotCreateEnumerator(scanRoot)
        }

        var items: [MediaItem] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if shouldSkip(url: url, values: values) {
                if values.isDirectory == true || values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard values.isRegularFile == true else { continue }

            let createdAt = values.creationDate ?? values.contentModificationDate ?? Date()
            let size = Int64(values.fileSize ?? 0)
            let relativePath = try PathSafety.relativePath(for: url, under: scanRoot)
            let fileExtension = url.pathExtension.lowercased()
            let mediaKind = mediaKind(for: fileExtension)
            guard filter == .all || mediaKind == filter || isSidecarExtension(fileExtension) else { continue }

            items.append(
                MediaItem(
                    id: url.path,
                    fileURL: url,
                    relativePath: relativePath,
                    displayName: values.name ?? url.lastPathComponent,
                    createdAt: createdAt,
                    size: size,
                    isVideo: mediaKind == .video,
                    mediaKind: mediaKind
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.relativePath < rhs.relativePath
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func makeTimeGroups(items: [MediaItem]) -> [TimeGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.createdAt)
        }

        return grouped
            .map { date, values in
                TimeGroup(
                    id: ISO8601DateFormatter().string(from: date),
                    date: date,
                    items: values,
                    totalSize: values.reduce(0) { $0 + $1.size }
                )
            }
            .sorted { $0.date < $1.date }
    }

    private func shouldSkip(url: URL, values: URLResourceValues) -> Bool {
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

    private func isSidecarExtension(_ fileExtension: String) -> Bool {
        [
            "rmd", "xml", "xmp", "thm", "lrv", "lut", "cube", "cdl",
            "ale", "edl", "json", "srt", "vtt", "md5", "sha1", "sha256"
        ].contains(fileExtension)
    }
}
