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

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AirwangTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }
}
