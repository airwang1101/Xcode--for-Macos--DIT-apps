import Foundation
import XCTest
@testable import Airwang_DIT_for_Mac

final class OrganizerServiceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        temporaryDirectories.removeAll()
    }

    func testPlanBuildsDateDeviceFolderHierarchy() async throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("Messy_A7M3", isDirectory: true)
        let destination = root.appendingPathComponent("Organized", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let clip = source.appendingPathComponent("A001.mov")
        try Data("clip".utf8).write(to: clip)
        try setDates(for: clip, year: 2020, month: 6, day: 20)

        let plan = try await OrganizerService().makePlan(
            sourceURL: source,
            destinationURL: destination,
            rule: OrganizerRule(scanFilter: .all, operationMode: .copy, duplicatePolicy: .rename)
        )

        XCTAssertEqual(plan.totalFiles, 1)
        XCTAssertEqual(plan.items.first?.deviceFolderName, "a7m3")
        XCTAssertEqual(
            try PathSafety.relativePath(for: XCTUnwrap(plan.items.first).destinationURL, under: destination),
            "2020/6/20/a7m3/A001.mov"
        )
    }

    func testPlanRenamesDuplicateDestinationsWithoutOverwriting() async throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("Source_A7M3", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let clip = source.appendingPathComponent("A001.mov")
        try Data("clip".utf8).write(to: clip)
        try setDates(for: clip, year: 2020, month: 6, day: 20)
        let existing = destination
            .appendingPathComponent("2020", isDirectory: true)
            .appendingPathComponent("6", isDirectory: true)
            .appendingPathComponent("20", isDirectory: true)
            .appendingPathComponent("a7m3", isDirectory: true)
            .appendingPathComponent("A001.mov")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: existing)

        let plan = try await OrganizerService().makePlan(
            sourceURL: source,
            destinationURL: destination,
            rule: OrganizerRule(scanFilter: .all, operationMode: .copy, duplicatePolicy: .rename)
        )

        XCTAssertEqual(
            try PathSafety.relativePath(for: XCTUnwrap(plan.items.first).destinationURL, under: destination),
            "2020/6/20/a7m3/A001 2.mov"
        )
    }

    func testPlanRejectsOverlappingSourceAndDestination() async throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = source.appendingPathComponent("Organized", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        do {
            _ = try await OrganizerService().makePlan(
                sourceURL: source,
                destinationURL: destination,
                rule: OrganizerRule(scanFilter: .all, operationMode: .copy, duplicatePolicy: .rename)
            )
            XCTFail("Expected overlapping paths to be rejected")
        } catch let error as OrganizerService.OrganizerError {
            guard case .pathOverlap = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testExecuteCopyKeepsSourceAndWritesDestination() async throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("Source_A7M3", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let clip = source.appendingPathComponent("A001.mov")
        try Data("clip".utf8).write(to: clip)
        try setDates(for: clip, year: 2020, month: 6, day: 20)

        let service = OrganizerService()
        let plan = try await service.makePlan(
            sourceURL: source,
            destinationURL: destination,
            rule: OrganizerRule(scanFilter: .all, operationMode: .copy, duplicatePolicy: .rename)
        )
        let summary = try await service.execute(plan: plan) { _ in }
        let output = try XCTUnwrap(plan.items.first).destinationURL

        XCTAssertTrue(summary.success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AirwangOrganizerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func setDates(for url: URL, year: Int, month: Int, day: Int) throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        components.minute = 0
        components.second = 0
        let date = try XCTUnwrap(components.date)
        try FileManager.default.setAttributes(
            [.creationDate: date, .modificationDate: date],
            ofItemAtPath: url.path
        )
    }
}
