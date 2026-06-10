import Foundation
import XCTest
@testable import Airwang_DIT_for_Mac

final class PathSafetyTests: XCTestCase {
    func testRejectsUnsafeRelativePaths() {
        XCTAssertThrowsError(try SafeRelativePath(""))
        XCTAssertThrowsError(try SafeRelativePath("/absolute.mov"))
        XCTAssertThrowsError(try SafeRelativePath("../escape.mov"))
        XCTAssertThrowsError(try SafeRelativePath("A/../escape.mov"))
        XCTAssertThrowsError(try SafeRelativePath("A//escape.mov"))
        XCTAssertThrowsError(try SafeRelativePath("A/\0/escape.mov"))
    }

    func testResolvesValidNestedPathInsideBase() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resolved = try PathSafety.resolvedURL(for: "DCIM/100A/clip.mov", under: base)

        XCTAssertTrue(PathSafety.isContained(resolved, in: base))
        XCTAssertTrue(resolved.path.hasSuffix("DCIM/100A/clip.mov"))
    }

    func testUnicodeComparisonDoesNotRewriteFilename() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let filename = "素材_e\u{301}.mov"
        let resolved = try PathSafety.resolvedURL(for: filename, under: base)

        XCTAssertTrue(PathSafety.isContained(resolved, in: base))
        XCTAssertEqual(resolved.lastPathComponent, filename)
    }

    func testRejectsSymlinkAncestorForWritableTargets() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let realFolder = base.appendingPathComponent("Real", isDirectory: true)
        try FileManager.default.createDirectory(at: realFolder, withIntermediateDirectories: true)
        let linkFolder = base.appendingPathComponent("Link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkFolder, withDestinationURL: realFolder)

        XCTAssertThrowsError(
            try PathSafety.ensureSafeWritableFileTarget(
                for: linkFolder.appendingPathComponent("clip.mov"),
                under: base
            )
        )
    }

    func testRejectsSymlinkFileTargets() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }

        let realFile = base.appendingPathComponent("real.mov")
        try Data("clip".utf8).write(to: realFile)
        let linkFile = base.appendingPathComponent("link.mov")
        try FileManager.default.createSymbolicLink(at: linkFile, withDestinationURL: realFile)

        XCTAssertThrowsError(try PathSafety.ensureSafeExistingFileTarget(for: linkFile, under: base))
        XCTAssertThrowsError(try PathSafety.ensureSafeWritableFileTarget(for: linkFile, under: base))
    }

    func testPathsOverlapDetectsEqualNestedAndDisjoint() {
        let parent = URL(fileURLWithPath: "/Volumes/Work/ProjectA", isDirectory: true)
        let child = URL(fileURLWithPath: "/Volumes/Work/ProjectA/Day01", isDirectory: true)
        let sibling = URL(fileURLWithPath: "/Volumes/Work/ProjectB", isDirectory: true)

        XCTAssertTrue(PathSafety.pathsOverlap(parent, parent))
        XCTAssertTrue(PathSafety.pathsOverlap(parent, child))
        XCTAssertTrue(PathSafety.pathsOverlap(child, parent))
        XCTAssertFalse(PathSafety.pathsOverlap(parent, sibling))
    }

    func testPathsOverlapDoesNotMatchPrefixSiblingNames() {
        // "/Volumes/Work" 与 "/Volumes/Workspace" 是前缀相似的兄弟目录,不重叠。
        let lhs = URL(fileURLWithPath: "/Volumes/Work", isDirectory: true)
        let rhs = URL(fileURLWithPath: "/Volumes/Workspace", isDirectory: true)

        XCTAssertFalse(PathSafety.pathsOverlap(lhs, rhs))
    }

    func testPathsOverlapTreatsNFCAndNFDAsSamePath() {
        // NFD("é" = e + U+0301)与 NFC("é" = U+00E9)指同一目录。
        // 此前 AppViewModel / TransferService 的私有副本不做规范化,
        // 预检与执行期判断会在此分叉(TEST_REPORT #113)。
        let nfd = URL(fileURLWithPath: "/Volumes/素材盘/Day01_e\u{301}", isDirectory: true)
        let nfc = URL(fileURLWithPath: "/Volumes/素材盘/Day01_\u{00E9}", isDirectory: true)

        XCTAssertTrue(PathSafety.pathsOverlap(nfd, nfc))
        XCTAssertTrue(PathSafety.pathsOverlap(nfc, nfd.appendingPathComponent("Sub", isDirectory: true)))
    }

    func testPathsShareVolumeForSameVolumePaths() throws {
        let base = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let nested = base.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        XCTAssertTrue(PathSafety.pathsShareVolume(base, nested))
    }

    func testPathsShareVolumeReturnsFalseWhenVolumeUnresolvable() {
        let real = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let ghost = URL(fileURLWithPath: "/Volumes/AirwangGhost-\(UUID().uuidString)/Sub", isDirectory: true)

        XCTAssertFalse(PathSafety.pathsShareVolume(real, ghost))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AirwangPathSafety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
