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

    func testPlanMarksContentIdenticalDestinationAsDuplicate() async throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("Source_A7M3", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let clip = source.appendingPathComponent("A001.mov")
        try Data("same-bytes".utf8).write(to: clip)
        try setDates(for: clip, year: 2020, month: 6, day: 20)
        let existing = destination
            .appendingPathComponent("2020/6/20/a7m3", isDirectory: true)
            .appendingPathComponent("A001.mov")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("same-bytes".utf8).write(to: existing)

        let plan = try await OrganizerService().makePlan(
            sourceURL: source,
            destinationURL: destination,
            rule: OrganizerRule(scanFilter: .all, operationMode: .copy, duplicatePolicy: .rename)
        )

        let item = try XCTUnwrap(plan.items.first)
        guard case .duplicate = item.conflictResolution else {
            return XCTFail("Expected duplicate resolution, got \(item.conflictResolution)")
        }
        XCTAssertFalse(item.isExecutable)
        XCTAssertEqual(plan.duplicateFiles, 1)
        XCTAssertEqual(plan.executableFiles, 0)
    }

    func testPlanDetectsInBatchContentDuplicates() async throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("Source_A7M3", isDirectory: true)
        let nested = source.appendingPathComponent("CARD_B", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let first = source.appendingPathComponent("A001.mov")
        let second = nested.appendingPathComponent("A001.mov")
        try Data("same-bytes".utf8).write(to: first)
        try Data("same-bytes".utf8).write(to: second)
        try setDates(for: first, year: 2020, month: 6, day: 20)
        try setDates(for: second, year: 2020, month: 6, day: 20)

        let plan = try await OrganizerService().makePlan(
            sourceURL: source,
            destinationURL: destination,
            rule: OrganizerRule(scanFilter: .all, operationMode: .copy, duplicatePolicy: .rename)
        )

        XCTAssertEqual(plan.totalFiles, 2)
        XCTAssertEqual(plan.duplicateFiles, 1)
        XCTAssertEqual(plan.executableFiles, 1)
    }

    func testPlanRenamesInBatchNameCollisionWithDifferentContent() async throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("Source_A7M3", isDirectory: true)
        let nested = source.appendingPathComponent("CARD_B", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let first = source.appendingPathComponent("A001.mov")
        let second = nested.appendingPathComponent("A001.mov")
        try Data("first-bytes".utf8).write(to: first)
        try Data("second-bytes-different".utf8).write(to: second)
        try setDates(for: first, year: 2020, month: 6, day: 20)
        try setDates(for: second, year: 2020, month: 6, day: 20)

        let plan = try await OrganizerService().makePlan(
            sourceURL: source,
            destinationURL: destination,
            rule: OrganizerRule(scanFilter: .all, operationMode: .copy, duplicatePolicy: .rename)
        )

        XCTAssertEqual(plan.duplicateFiles, 0)
        XCTAssertEqual(plan.renamedFiles, 1)
        XCTAssertEqual(plan.executableFiles, 2)
        let names = Set(plan.items.map { $0.destinationURL.lastPathComponent })
        XCTAssertEqual(names, ["A001.mov", "A001 2.mov"])
    }

    func testExecuteSkipsRuntimeContentDuplicateInsteadOfFailing() async throws {
        let root = try makeTemporaryDirectory()
        let source = root.appendingPathComponent("Source_A7M3", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let clip = source.appendingPathComponent("A001.mov")
        try Data("same-bytes".utf8).write(to: clip)
        try setDates(for: clip, year: 2020, month: 6, day: 20)

        let service = OrganizerService()
        let plan = try await service.makePlan(
            sourceURL: source,
            destinationURL: destination,
            rule: OrganizerRule(scanFilter: .all, operationMode: .move, duplicatePolicy: .rename)
        )

        // 预览之后、执行之前，目标端被外部写入了一份内容相同的文件。
        let landed = try XCTUnwrap(plan.items.first).destinationURL
        try FileManager.default.createDirectory(at: landed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("same-bytes".utf8).write(to: landed)

        let summary = try await service.execute(plan: plan) { _ in }

        XCTAssertTrue(summary.success)
        XCTAssertEqual(summary.duplicateFiles, 1)
        XCTAssertEqual(summary.skippedFiles, 1)
        // 查重跳过不算完成写入，移动模式下源文件必须原地保留。
        XCTAssertEqual(summary.completedFiles, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: clip.path))
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

    func testOrganizerStatisticsSnapshotCombinesPreviewAndLastRun() throws {
        let root = URL(fileURLWithPath: "/tmp/AirwangOrganizerStats", isDirectory: true)
        let source = root.appendingPathComponent("Source", isDirectory: true)
        let destination = root.appendingPathComponent("Destination", isDirectory: true)
        let firstDate = try makeDate(year: 2020, month: 6, day: 20)
        let secondDate = try makeDate(year: 2020, month: 6, day: 21)
        let plan = OrganizerPlan(
            id: UUID(),
            sourceURL: source,
            destinationURL: destination,
            rule: OrganizerRule(scanFilter: .all, operationMode: .copy, duplicatePolicy: .rename),
            createdAt: firstDate,
            items: [
                OrganizerPlanItem(
                    id: "one",
                    sourceURL: source.appendingPathComponent("A001.mov"),
                    destinationURL: destination.appendingPathComponent("2020/6/20/a7m3/A001.mov"),
                    relativePath: "A001.mov",
                    displayName: "A001.mov",
                    capturedAt: firstDate,
                    deviceName: "ILCE-7M3",
                    deviceFolderName: "a7m3",
                    size: 120,
                    mediaKind: .video,
                    conflictResolution: .none
                ),
                OrganizerPlanItem(
                    id: "two",
                    sourceURL: source.appendingPathComponent("B001.mov"),
                    destinationURL: destination.appendingPathComponent("2020/6/21/fx3/B001 2.mov"),
                    relativePath: "B001.mov",
                    displayName: "B001.mov",
                    capturedAt: secondDate,
                    deviceName: "ILME-FX3",
                    deviceFolderName: "fx3",
                    size: 240,
                    mediaKind: .video,
                    conflictResolution: .renamed(originalPath: "2020/6/21/fx3/B001.mov")
                ),
                OrganizerPlanItem(
                    id: "three",
                    sourceURL: source.appendingPathComponent("C001.mov"),
                    destinationURL: destination.appendingPathComponent("2020/6/21/fx3/C001.mov"),
                    relativePath: "C001.mov",
                    displayName: "C001.mov",
                    capturedAt: secondDate,
                    deviceName: "ILME-FX3",
                    deviceFolderName: "fx3",
                    size: 480,
                    mediaKind: .video,
                    conflictResolution: .skipped(existingPath: "2020/6/21/fx3/C001.mov")
                )
            ]
        )
        let summary = OrganizerRunSummary(
            operationMode: .move,
            totalFiles: 3,
            completedFiles: 2,
            skippedFiles: 1,
            failedFiles: ["C001.mov"],
            totalBytes: 360,
            startedAt: firstDate,
            finishedAt: firstDate.addingTimeInterval(90)
        )

        let snapshot = OrganizerStatisticsSnapshot.make(plan: plan, lastSummary: summary)

        XCTAssertTrue(snapshot.hasAnyData)
        XCTAssertEqual(snapshot.plannedFiles, 3)
        XCTAssertEqual(snapshot.executableFiles, 2)
        XCTAssertEqual(snapshot.previewSkippedFiles, 1)
        XCTAssertEqual(snapshot.plannedBytes, 360)
        XCTAssertEqual(snapshot.dayCount, 2)
        XCTAssertEqual(snapshot.deviceCount, 2)
        XCTAssertEqual(snapshot.renamedFiles, 1)
        XCTAssertEqual(snapshot.lastOperationMode, .move)
        XCTAssertEqual(snapshot.lastCompletedFiles, 2)
        XCTAssertEqual(snapshot.lastSkippedFiles, 1)
        XCTAssertEqual(snapshot.lastFailedFiles, 1)
        XCTAssertEqual(snapshot.lastBytes, 360)
        XCTAssertEqual(snapshot.lastDuration, 90)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AirwangOrganizerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        temporaryDirectories.append(url)
        return url
    }

    private func makeDate(year: Int, month: Int, day: Int) throws -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return try XCTUnwrap(components.date)
    }

    private func setDates(for url: URL, year: Int, month: Int, day: Int) throws {
        let date = try makeDate(year: year, month: month, day: day)
        try FileManager.default.setAttributes(
            [.creationDate: date, .modificationDate: date],
            ofItemAtPath: url.path
        )
    }
}
