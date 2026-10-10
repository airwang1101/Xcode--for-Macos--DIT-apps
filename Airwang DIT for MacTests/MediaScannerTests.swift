import Foundation
import XCTest
@testable import Airwang_DIT_for_Mac

final class MediaScannerTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testSkipsSymbolicLinksAndSystemFolders() throws {
        let root = try makeTemporaryDirectory()
        let mediaFolder = root.appendingPathComponent("DCIM", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
        try Data("clip".utf8).write(to: mediaFolder.appendingPathComponent("A001.mov"))

        let trashFolder = root.appendingPathComponent(".Trashes", isDirectory: true)
        try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        try Data("hidden".utf8).write(to: trashFolder.appendingPathComponent("ignored.mov"))

        let loopLink = root.appendingPathComponent("Loop")
        try FileManager.default.createSymbolicLink(at: loopLink, withDestinationURL: root)

        let rootLink = root.appendingPathComponent("SystemRoot")
        try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: URL(fileURLWithPath: "/", isDirectory: true))

        let volume = StorageVolume(
            id: root.path,
            name: "TestCard",
            url: root,
            isRemovable: true,
            isInternal: false,
            totalCapacity: nil,
            availableCapacity: nil
        )

        let items = try MediaScanner().scan(volume: volume, rootURL: root, filter: .all)

        XCTAssertEqual(items.map(\.relativePath), ["DCIM/A001.mov"])
    }

    func testFiltersRetainSidecarsAndScannedMetadata() throws {
        let root = try makeTemporaryDirectory().resolvingSymlinksInPath()
        let folder = root.appendingPathComponent("DCIM", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let contents = [
            "A001.MOV": "video",
            "A001.XML": "sidecar",
            "photo.CR3": "photo",
            "sound.WAV": "audio",
            "other.bin": "other"
        ]
        for (name, content) in contents {
            try Data(content.utf8).write(to: folder.appendingPathComponent(name))
        }
        let volume = StorageVolume(
            id: root.path, name: "TestCard", url: root,
            isRemovable: true, isInternal: false,
            totalCapacity: nil, availableCapacity: nil
        )
        let expected: [(ScanFilter, Set<String>)] = [
            (.video, ["A001.MOV", "A001.XML"]),
            (.photo, ["photo.CR3", "A001.XML"]),
            (.audio, ["sound.WAV", "A001.XML"]),
            (.all, Set(contents.keys))
        ]
        let scanner = MediaScanner()
        for (filter, names) in expected {
            let items = try scanner.scan(volume: volume, rootURL: root, filter: filter)
            XCTAssertEqual(Set(items.map(\.displayName)), names, filter.rawValue)
            for item in items {
                let url = folder.appendingPathComponent(item.displayName)
                let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
                XCTAssertEqual(item.id, item.fileURL.path)
                XCTAssertEqual(item.fileURL.resolvingSymlinksInPath(), url.resolvingSymlinksInPath())
                XCTAssertEqual(item.relativePath, "DCIM/\(item.displayName)")
                XCTAssertEqual(item.size, Int64(try XCTUnwrap(contents[item.displayName]).utf8.count))
                XCTAssertEqual(item.createdAt, values.creationDate ?? values.contentModificationDate)
                XCTAssertEqual(item.isVideo, item.displayName == "A001.MOV")
            }
            let groups = scanner.makeTimeGroups(items: items)
            XCTAssertEqual(Set(groups.flatMap(\.items).map(\.id)), Set(items.map(\.id)))
            XCTAssertEqual(groups.reduce(Int64(0)) { $0 + $1.totalSize }, items.reduce(Int64(0)) { $0 + $1.size })
        }
    }

    func testMissingRootDoesNotMasqueradeAsAnEmptyCard() throws {
        let root = try makeTemporaryDirectory().appendingPathComponent("removed-card")
        let volume = StorageVolume(id: root.path, name: "Card", url: root, isRemovable: true, isInternal: false, totalCapacity: nil, availableCapacity: nil)
        XCTAssertThrowsError(try MediaScanner().scan(volume: volume, filter: .all))
    }

    func testFileCannotBeUsedAsAScanDirectory() throws {
        let root = try makeTemporaryDirectory().appendingPathComponent("clip.mov")
        try Data("clip".utf8).write(to: root)
        let volume = StorageVolume(id: root.path, name: "Card", url: root, isRemovable: true, isInternal: false, totalCapacity: nil, availableCapacity: nil)
        XCTAssertThrowsError(try MediaScanner().scan(volume: volume, filter: .all))
    }

    @MainActor
    func testCancelledEmptyScanStillReportsCancellation() async throws {
        let root = try makeTemporaryDirectory()
        let volume = StorageVolume(id: root.path, name: "Card", url: root, isRemovable: true, isInternal: false, totalCapacity: nil, availableCapacity: nil)
        let worker = Task.detached {
            try? await Task.sleep(for: .milliseconds(20))
            return try MediaScanner().scan(volume: volume, filter: .all)
        }
        worker.cancel()
        do {
            _ = try await worker.value
            XCTFail("An empty directory must not hide a cancelled scan")
        } catch is CancellationError {} catch { XCTFail("Unexpected scan error: \(error)") }
    }

    func testEveryExistingExtensionAndSidecarRemainsSelectable() throws {
        let root = try makeTemporaryDirectory().resolvingSymlinksInPath()
        let folder = root.appendingPathComponent("Données_素材_e\u{301}", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let videos = ["mov", "mp4", "mxf", "r3d", "braw", "ari", "crm", "avi", "mkv", "mts", "m2ts"]
        let photos = ["jpg", "jpeg", "png", "heic", "tif", "tiff", "dng", "cr2", "cr3", "nef", "arw", "raf", "rw2"]
        let audio = ["wav", "aif", "aiff", "mp3", "m4a", "flac"]
        let sidecars = ["rmd", "xml", "xmp", "thm", "lrv", "lut", "cube", "cdl", "ale", "edl", "json", "srt", "vtt", "md5", "sha1", "sha256"]
        let all = videos + photos + audio + sidecars + ["bin"]
        for suffix in all { try Data(suffix.utf8).write(to: folder.appendingPathComponent("素材.\(suffix.uppercased())")) }
        let volume = StorageVolume(id: root.path, name: "Card", url: root, isRemovable: true, isInternal: false, totalCapacity: nil, availableCapacity: nil)
        let filters: [(ScanFilter, [String])] = [(.video, videos), (.photo, photos), (.audio, audio), (.all, all)]
        for (filter, included) in filters {
            let items = try MediaScanner().scan(volume: volume, filter: filter)
            XCTAssertEqual(Set(items.map { $0.fileURL.pathExtension.lowercased() }), Set(included + sidecars))
            for item in items {
                XCTAssertEqual(item.relativePath, try PathSafety.relativePath(for: item.fileURL, under: root))
                XCTAssertEqual(item.size, Int64(item.fileURL.pathExtension.utf8.count))
            }
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AirwangTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }
}
