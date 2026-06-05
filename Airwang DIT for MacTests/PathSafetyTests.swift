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

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AirwangPathSafety-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
