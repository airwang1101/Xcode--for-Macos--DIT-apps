import Foundation
import XCTest
@testable import Airwang_DIT_for_Mac

/// 纯逻辑模型/策略层测试：不碰文件系统，毫秒级完成。
final class ModelPolicyTests: XCTestCase {

    // MARK: - FileNameSanitizer

    func testSafeComponentReplacesIllegalCharactersAndCollapsesUnderscores() {
        XCTAssertEqual(FileNameSanitizer.safeComponent("A7M3//卡1: 拷贝*?"), "A7M3_卡1_拷贝")
        XCTAssertEqual(FileNameSanitizer.safeComponent("  spaced name  "), "spaced_name")
    }

    func testSafeComponentFallsBackWhenEmptyOrFullyIllegal() {
        XCTAssertEqual(FileNameSanitizer.safeComponent("", fallback: "fallback"), "fallback")
        XCTAssertEqual(FileNameSanitizer.safeComponent("///***", fallback: "fallback"), "fallback")
    }

    func testSafeComponentHonorsMaximumLength() {
        let long = String(repeating: "a", count: 200)
        let result = FileNameSanitizer.safeComponent(long, maximumLength: 48)
        XCTAssertEqual(result.count, 48)
    }

    // MARK: - MainWindowLayoutPolicy

    func testPortraitLayoutTriggersBelowWidthBreakpoint() {
        XCTAssertTrue(MainWindowLayoutPolicy.usesPortraitLayout(width: 700, height: 700))
        XCTAssertFalse(MainWindowLayoutPolicy.usesPortraitLayout(width: 1280, height: 820))
    }

    func testPortraitLayoutTriggersForTallAspectRatio() {
        XCTAssertTrue(MainWindowLayoutPolicy.usesPortraitLayout(width: 800, height: 1000))
        XCTAssertFalse(MainWindowLayoutPolicy.usesPortraitLayout(width: 800, height: 900))
    }

    // MARK: - OrganizerPlan 查重/冲突计数与预览过滤

    private func makePlanItem(
        id: String,
        resolution: OrganizerConflictResolution,
        size: Int64 = 100
    ) -> OrganizerPlanItem {
        OrganizerPlanItem(
            id: id,
            sourceURL: URL(fileURLWithPath: "/src/\(id).mov"),
            destinationURL: URL(fileURLWithPath: "/dst/\(id).mov"),
            relativePath: "\(id).mov",
            displayName: "\(id).mov",
            capturedAt: Date(timeIntervalSince1970: 1_600_000_000),
            deviceName: "ILCE-7M3",
            deviceFolderName: "a7m3",
            size: size,
            mediaKind: .video,
            conflictResolution: resolution
        )
    }

    private func makePlan(items: [OrganizerPlanItem]) -> OrganizerPlan {
        OrganizerPlan(
            id: UUID(),
            sourceURL: URL(fileURLWithPath: "/src"),
            destinationURL: URL(fileURLWithPath: "/dst"),
            rule: OrganizerRule(scanFilter: .all, operationMode: .copy, duplicatePolicy: .rename),
            createdAt: Date(),
            items: items
        )
    }

    func testPlanCountsSeparateDuplicateRenameAndSkip() {
        let plan = makePlan(items: [
            makePlanItem(id: "clean", resolution: .none),
            makePlanItem(id: "renamed", resolution: .renamed(originalPath: "/dst/renamed.mov")),
            makePlanItem(id: "skipped", resolution: .skipped(existingPath: "/dst/skipped.mov")),
            makePlanItem(id: "dupe", resolution: .duplicate(existingPath: "/dst/dupe.mov"), size: 300)
        ])

        XCTAssertEqual(plan.totalFiles, 4)
        XCTAssertEqual(plan.executableFiles, 2)
        XCTAssertEqual(plan.duplicateFiles, 1)
        XCTAssertEqual(plan.renamedFiles, 1)
        XCTAssertEqual(plan.conflictFiles, 3)
        // 重复与跳过的文件不计入待写入容量。
        XCTAssertEqual(plan.totalBytes, 200)
    }

    func testPreviewItemsConflictFilterShowsOnlyConflicts() {
        let plan = makePlan(items: [
            makePlanItem(id: "clean", resolution: .none),
            makePlanItem(id: "dupe", resolution: .duplicate(existingPath: "/dst/dupe.mov")),
            makePlanItem(id: "renamed", resolution: .renamed(originalPath: "/dst/renamed.mov"))
        ])

        XCTAssertEqual(plan.previewItems(filter: .all).count, 3)
        let conflicts = plan.previewItems(filter: .conflicts)
        XCTAssertEqual(conflicts.map(\.id), ["dupe", "renamed"])
    }

    func testDuplicateResolutionIsNotExecutableButRenamedIs() {
        XCTAssertFalse(makePlanItem(id: "d", resolution: .duplicate(existingPath: "/x")).isExecutable)
        XCTAssertFalse(makePlanItem(id: "s", resolution: .skipped(existingPath: "/x")).isExecutable)
        XCTAssertTrue(makePlanItem(id: "r", resolution: .renamed(originalPath: "/x")).isExecutable)
        XCTAssertTrue(makePlanItem(id: "n", resolution: .none).isExecutable)
    }

    func testPlanProgressMessagesDescribeEachPhase() {
        XCTAssertTrue(OrganizerPlanProgress.scanning(found: 12).message.contains("12"))
        XCTAssertTrue(OrganizerPlanProgress.readingMetadata(processed: 3, total: 9).message.contains("3/9"))
        XCTAssertTrue(OrganizerPlanProgress.resolving(processed: 5, total: 9).message.contains("5/9"))
    }
}
