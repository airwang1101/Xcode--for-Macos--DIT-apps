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

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AirwangTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }
}
