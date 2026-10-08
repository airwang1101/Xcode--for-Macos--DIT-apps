import Foundation
import XCTest
@testable import Airwang_DIT_for_Mac

/// 纯逻辑模型/策略层测试：不碰文件系统，毫秒级完成。
final class ModelPolicyTests: XCTestCase {

    func testLegacyUISettingsAdoptPaperWithoutLosingLanguageThemeOrAutoStart() throws {
        let data = Data(#"{"theme":"night","language":"english","autoStartQueuedProjects":true}"#.utf8)
        let settings = try JSONDecoder().decode(AppUISettings.self, from: data)
        XCTAssertEqual(settings.interfaceStyle, .paper)
        XCTAssertEqual(settings.theme, .night)
        XCTAssertEqual(settings.language, .english)
        XCTAssertTrue(settings.autoStartQueuedProjects)
    }

    func testClassicAppearanceRoundTripsWithAllExistingPreferences() throws {
        let original = AppUISettings(theme: .night, language: .english,
                                     autoStartQueuedProjects: true, interfaceStyle: .classic)
        let restored = try JSONDecoder().decode(AppUISettings.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.interfaceStyle, .classic)
        XCTAssertEqual(restored.theme, .night)
        XCTAssertEqual(restored.language, .english)
        XCTAssertTrue(restored.autoStartQueuedProjects)
    }

    @MainActor
    func testChangingAppearancePreservesSavedExistingPreferences() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DIT-Appearance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppViewModel(dataDirectory: root)
        model.setTheme(.night)
        model.setLanguage(.english)
        model.setAutoStartQueuedProjects(true)
        model.setInterfaceStyle(.classic)
        let settings = model.settingsStore.loadUISettings()
        XCTAssertEqual(settings.interfaceStyle, .classic)
        XCTAssertEqual(settings.theme, .night)
        XCTAssertEqual(settings.language, .english)
        XCTAssertTrue(settings.autoStartQueuedProjects)
        model.setInterfaceStyle(.paper)
        XCTAssertEqual(model.settingsStore.loadUISettings().interfaceStyle, .paper)
        XCTAssertEqual(model.selectedTheme, .night)
        XCTAssertEqual(model.selectedLanguage, .english)
        XCTAssertTrue(model.autoStartQueuedProjects)
    }

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

final class ImportSelectionTests: XCTestCase {
    @MainActor
    func testSelectionTracksMutationsAndScanOrder() async throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let model = AppViewModel(dataDirectory: storage)
        let items = makeItems(count: 4)
        model.scannedItems = items
        model.selectedItemIDs = [items[3].id, items[1].id, "missing"]
        XCTAssertEqual(model.selectedItems, [items[1], items[3]])
        XCTAssertEqual(model.selectedTotalBytes, 6)
        XCTAssertEqual(model.scannedTotalBytes, 10)

        // Reordering and replacing an item with the same ID must invalidate the snapshot.
        let replacement = makeItem(path: items[3].relativePath, size: 100)
        model.scannedItems = [replacement, items[1]]
        XCTAssertEqual(model.selectedItems, [replacement, items[1]])
        XCTAssertEqual(model.selectedTotalBytes, 102)
        XCTAssertEqual(model.scannedTotalBytes, 102)
        model.clearScannedSelection()
        XCTAssertTrue(model.selectedItems.isEmpty)
        XCTAssertEqual(model.selectedTotalBytes, 0)
        model.selectAllScannedItems()
        XCTAssertEqual(model.selectedItems, model.scannedItems)
        model.scannedItems = []
        XCTAssertTrue(model.selectedItems.isEmpty)
        XCTAssertEqual(model.selectedTotalBytes, 0)
        XCTAssertEqual(model.scannedTotalBytes, 0)
    }

    @MainActor
    func testSelectionPreservesRelatedSidecarsAndSummary() async throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let model = AppViewModel(dataDirectory: storage)
        let photo = makeItem(path: "DCIM/Caf\u{00e9}.arw", size: 10)
        let sidecar = makeItem(path: "DCIM/CAFE\u{0301}.xmp", size: 2)
        let otherFolder = makeItem(path: "Other/Caf\u{00e9}.arw", size: 20)
        model.scannedItems = [sidecar, otherFolder, photo]
        model.toggle(item: photo)
        XCTAssertEqual(model.selectedItems, [sidecar, photo])
        XCTAssertEqual(model.selectedTotalBytes, 12)
        model.preferences.targetPath = storage.path
        model.pendingImportVolume = StorageVolume(
            id: "/selection-fixture", name: "Card", url: URL(fileURLWithPath: "/selection-fixture"),
            isRemovable: true, isInternal: false, totalCapacity: nil, availableCapacity: nil
        )
        let summary = try XCTUnwrap(model.selectionSummary)
        XCTAssertEqual(summary.selectedItems, [sidecar, photo])
        XCTAssertEqual(summary.totalSize, 12)
        model.toggle(item: sidecar)
        XCTAssertTrue(model.selectedItems.isEmpty)
        XCTAssertNil(model.selectionSummary)
        let group = TimeGroup(id: "group", date: photo.createdAt, items: [photo], totalSize: 10)
        model.toggle(group: group)
        XCTAssertEqual(model.selectedItems, [sidecar, photo])
        model.toggle(group: group)
        XCTAssertTrue(model.selectedItems.isEmpty)
    }

    @MainActor
    func testLargeSelectionReadPerformance() async throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let model = AppViewModel(dataDirectory: storage)
        model.scannedItems = makeItems(count: 10_000)
        model.selectAllScannedItems()
        XCTAssertEqual(model.selectedItems.count, 10_000)
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: options) {
            var checksum: Int64 = 0
            for _ in 0..<30 {
                checksum += Int64(model.selectedItems.count)
                checksum += model.selectedTotalBytes + model.scannedTotalBytes
            }
            XCTAssertEqual(checksum, 3_000_600_000)
        }
    }

    private func makeItems(count: Int) -> [MediaItem] {
        (0..<count).map { makeItem(path: "DCIM/clip_\($0).mov", size: Int64($0 + 1)) }
    }

    private func makeItem(path: String, size: Int64) -> MediaItem {
        let url = URL(fileURLWithPath: "/selection-fixture").appendingPathComponent(path)
        return MediaItem(
            id: url.path, fileURL: url, relativePath: path, displayName: url.lastPathComponent,
            createdAt: Date(timeIntervalSince1970: 0), size: size, isVideo: true, mediaKind: .video
        )
    }
}
