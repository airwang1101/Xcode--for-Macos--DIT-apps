import Foundation
import XCTest
@testable import Airwang_DIT_for_Mac

final class PersistenceCompatibilityTests: XCTestCase {
    func testCopyProjectDecodesWhenNewerFieldsAreMissing() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "name": "Legacy",
          "taskFolderName": "Legacy",
          "createdAt": 0,
          "updatedAt": 0,
          "sourceName": "Card",
          "sourceVolumePath": "/Volumes/Card",
          "sourceRootPath": "/Volumes/Card",
          "targetRootPath": "/Volumes/Work",
          "backupRootPath": null,
          "selectedItems": [],
          "totalBytes": 0,
          "verificationMode": "sha256",
          "status": "queued",
          "orderIndex": 0
        }
        """.data(using: .utf8)!

        let project = try JSONDecoder().decode(CopyProject.self, from: json)

        XCTAssertEqual(project.name, "Legacy")
        XCTAssertEqual(project.primaryCopyState.title, ProjectStageKind.primaryCopy.title)
        XCTAssertEqual(project.backupCopyState.detail, "未配置备份盘")
        XCTAssertNil(project.primaryReportID)
        XCTAssertEqual(project.skipVerificationConfirmations, 0)
        XCTAssertFalse(project.autoStartEnabled)
        XCTAssertNil(project.autoStartDeadline)
        XCTAssertFalse(project.resumeExistingFiles)
        XCTAssertFalse(project.backupOnlyRetry)
        XCTAssertNil(project.primaryCompletionReference)
        XCTAssertNil(project.sourceVolumeIdentifier)
        XCTAssertNil(project.targetVolumeIdentifier)
        XCTAssertNil(project.backupVolumeIdentifier)
    }

    func testRetryStateRoundTripsWithoutChangingPathsOrVerificationPolicy() throws {
        var project = makeProject(autoStartEnabled: true, autoStartDeadline: Date(timeIntervalSince1970: 300))
        project.status = .failed
        project.verificationMode = .fastFingerprint
        project.sourceVolumeIdentifier = "original-volume-id"
        project.targetVolumeIdentifier = "original-primary-volume-id"
        project.backupVolumeIdentifier = "original-backup-volume-id"
        project.primaryReportID = UUID()
        project.primaryCopyState.isComplete = true
        project.primaryVerifyState.isActive = true
        project.skipVerificationConfirmations = 2
        project.errorMessage = "interrupted"
        let projectID = project.id
        let outputURL = project.primaryImportURL

        project.prepareForRetry()
        let restored = try JSONDecoder().decode(CopyProject.self, from: JSONEncoder().encode(project))

        XCTAssertEqual(restored.id, projectID)
        XCTAssertEqual(restored.primaryImportURL, outputURL)
        XCTAssertEqual(restored.sourceRootPath, project.sourceRootPath)
        XCTAssertEqual(restored.verificationMode, .fastFingerprint)
        XCTAssertEqual(restored.sourceVolumeIdentifier, "original-volume-id")
        XCTAssertEqual(restored.targetVolumeIdentifier, "original-primary-volume-id")
        XCTAssertEqual(restored.backupVolumeIdentifier, "original-backup-volume-id")
        XCTAssertTrue(restored.resumeExistingFiles)
        XCTAssertEqual(restored.status, .queued)
        XCTAssertFalse(restored.autoStartEnabled)
        XCTAssertNil(restored.autoStartDeadline)
        XCTAssertNil(restored.primaryReportID)
        XCTAssertNil(restored.errorMessage)
        XCTAssertFalse(restored.primaryCopyState.isComplete)
        XCTAssertFalse(restored.primaryVerifyState.isActive)
        XCTAssertEqual(restored.skipVerificationConfirmations, 0)
        XCTAssertEqual(restored.backupCopyState.detail, "未配置备份盘")
    }

    func testRetryRetainsBackupConfigurationAndResetsAllStageProgress() {
        var project = makeProject()
        project.backupRootPath = "/Volumes/Backup"
        project.backupReportID = UUID()
        project.backupCopyState.completedFiles = 4
        project.backupVerifyState.isComplete = true

        project.prepareForRetry()

        XCTAssertEqual(project.backupRootPath, "/Volumes/Backup")
        XCTAssertNil(project.backupReportID)
        XCTAssertEqual(project.backupCopyState.completedFiles, 0)
        XCTAssertFalse(project.backupVerifyState.isComplete)
        XCTAssertEqual(project.backupCopyState.detail, "等待主盘完成")
    }

    func testDefaultUISettingsDisableAutoStart() {
        XCTAssertFalse(AppUISettings.default.autoStartQueuedProjects)
    }

    func testDecodedMissingAutoStartDefaultsToFalse() throws {
        let json = """
        {
          "theme": "night"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppUISettings.self, from: json)

        XCTAssertEqual(settings.theme, .night)
        XCTAssertEqual(settings.language, .chinese)
        XCTAssertFalse(settings.autoStartQueuedProjects)
    }

    func testDecodedExplicitAutoStartTrueRemainsTrue() throws {
        let json = """
        {
          "theme": "night",
          "autoStartQueuedProjects": true
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppUISettings.self, from: json)

        XCTAssertTrue(settings.autoStartQueuedProjects)
    }

    func testCopyProjectStoresAutoStartDeadlineForNewProjects() throws {
        let deadline = Date(timeIntervalSince1970: 300)
        let project = makeProject(autoStartEnabled: true, autoStartDeadline: deadline)

        XCTAssertTrue(project.autoStartEnabled)
        XCTAssertEqual(project.autoStartDeadline, deadline)
    }

    func testAutoStartReadinessRequiresQueuedEnabledAndElapsedDeadline() throws {
        let deadline = Date(timeIntervalSince1970: 300)
        var project = makeProject(autoStartEnabled: true, autoStartDeadline: deadline)

        XCTAssertFalse(project.isAutoStartReady(at: Date(timeIntervalSince1970: 299)))
        XCTAssertTrue(project.isAutoStartReady(at: Date(timeIntervalSince1970: 300)))

        project.autoStartEnabled = false
        XCTAssertFalse(project.isAutoStartReady(at: Date(timeIntervalSince1970: 301)))

        project.autoStartEnabled = true
        project.status = .running
        XCTAssertFalse(project.isAutoStartReady(at: Date(timeIntervalSince1970: 301)))
    }

    func testCopyStatisticsKeepsCumulativeTotalsOutsideHeatmapWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_767_916_800)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let oldDay = calendar.date(byAdding: .day, value: -8, to: today)!
        let reports = [
            makeReport(finishedAt: yesterday, totalBytes: 100, selectedFileCount: 3, success: true),
            makeReport(finishedAt: today, totalBytes: 200, selectedFileCount: 2, success: false),
            makeReport(finishedAt: oldDay, totalBytes: 900, selectedFileCount: 9, success: true)
        ]

        let summary = CopyStatisticsSummary.make(
            reports: reports,
            projects: [],
            calendar: calendar,
            now: now,
            dayCount: 7
        )

        XCTAssertEqual(summary.days.count, 7)
        XCTAssertEqual(summary.totalBytes, 1200)
        XCTAssertEqual(summary.recent7Bytes, 300)
        XCTAssertEqual(summary.totalFiles, 14)
        XCTAssertEqual(summary.totalReports, 3)
        XCTAssertEqual(summary.successfulReports, 2)
        XCTAssertEqual(summary.peakDayBytes, 900)
        XCTAssertEqual(summary.peakDay?.date, oldDay)
        XCTAssertFalse(summary.days.contains { $0.date == oldDay && $0.hasActivity })
    }

    func testCopyStatisticsHeatmapsCacheDailyWeeklyAndCumulativeModes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2024,
            month: 1,
            day: 7
        )))
        let days = (0..<7).map { offset in
            CopyActivityDay(
                date: calendar.date(byAdding: .day, value: offset, to: sunday)!,
                bytes: Int64((offset + 1) * 10),
                files: offset + 1,
                reportCount: 1,
                successCount: 1
            )
        }

        let heatmaps = CopyStatisticsHeatmaps.make(days: days, calendar: calendar)

        XCTAssertEqual(heatmaps.daily.days.map(\.bytes), [10, 20, 30, 40, 50, 60, 70])
        XCTAssertEqual(heatmaps.weekly.days.map(\.bytes), Array(repeating: 280, count: 7))
        XCTAssertEqual(heatmaps.cumulative.days.map(\.bytes), [10, 30, 60, 100, 150, 210, 280])
        XCTAssertEqual(heatmaps.daily.weeks.count, 1)
        XCTAssertEqual(heatmaps.daily.peakDay?.date, days.last?.date)
    }

    func testCopyStatisticsIndexMatchesFullSummaryAndSupportsIncrementalMerge() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_767_916_800)
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let reports = [
            makeReport(finishedAt: yesterday, totalBytes: 100, selectedFileCount: 3, success: true),
            makeReport(finishedAt: today, totalBytes: 200, selectedFileCount: 2, success: false)
        ]

        let fullSummary = CopyStatisticsSummary.make(
            reports: reports,
            projects: [],
            calendar: calendar,
            now: now,
            dayCount: 7
        )
        var index = CopyStatisticsIndex.make(
            reports: [reports[0]],
            calendar: calendar,
            now: now
        )
        index.add(reports[1], calendar: calendar, now: now)
        let indexedSummary = index.summary(
            projects: [],
            calendar: calendar,
            now: now,
            dayCount: 7
        )

        XCTAssertTrue(index.matches(reports: reports, calendar: calendar, now: now))
        XCTAssertEqual(indexedSummary.totalBytes, fullSummary.totalBytes)
        XCTAssertEqual(indexedSummary.totalFiles, fullSummary.totalFiles)
        XCTAssertEqual(indexedSummary.totalReports, fullSummary.totalReports)
        XCTAssertEqual(indexedSummary.successfulReports, fullSummary.successfulReports)
        XCTAssertEqual(indexedSummary.days, fullSummary.days)
    }

    func testCopyStatisticsIndexInvalidatesAcrossTimeZoneChanges() throws {
        let now = Date()
        var foreignCalendar = Calendar(identifier: .gregorian)
        let currentOffset = TimeZone.current.secondsFromGMT(for: now)
        foreignCalendar.timeZone = try XCTUnwrap(
            TimeZone(secondsFromGMT: currentOffset == 0 ? 3_600 : 0)
        )
        let report = makeReport(
            finishedAt: now,
            totalBytes: 100,
            selectedFileCount: 1,
            success: true
        )

        let index = CopyStatisticsIndex.make(
            reports: [report],
            calendar: foreignCalendar,
            now: now
        )

        XCTAssertFalse(index.matches(reports: [report]))
    }

    func testCopyStatisticsIndexMatchesUsingSameFutureReportCutoffAsBuild() throws {
        let now = Date()
        let futureReport = makeReport(
            finishedAt: now.addingTimeInterval(2 * 24 * 60 * 60),
            totalBytes: 100,
            selectedFileCount: 1,
            success: true
        )

        let index = CopyStatisticsIndex.make(
            reports: [futureReport],
            calendar: .current,
            now: now
        )

        XCTAssertTrue(index.matches(reports: [futureReport]))
    }

    func testCopyStatisticsIndexSummaryMergesDuplicateDayBuckets() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_767_916_800)
        let today = calendar.startOfDay(for: now)
        let index = CopyStatisticsIndex(
            dayBuckets: [
                CopyStatisticsIndexDay(date: today, bytes: 100, files: 1, reportCount: 1, successCount: 1),
                CopyStatisticsIndexDay(date: today, bytes: 200, files: 2, reportCount: 1, successCount: 0)
            ],
            totalBytes: 300,
            totalFiles: 3,
            totalReports: 2,
            successfulReports: 1
        )

        let summary = index.summary(
            projects: [],
            calendar: calendar,
            now: now,
            dayCount: 7
        )

        let todaySummary = try XCTUnwrap(summary.days.first { $0.date == today })
        XCTAssertEqual(todaySummary.bytes, 300)
        XCTAssertEqual(todaySummary.files, 3)
        XCTAssertEqual(todaySummary.reportCount, 2)
        XCTAssertEqual(todaySummary.successCount, 1)
    }

    func testReportStoreWritesCompactAppLogWithoutSuccessfulFileRecords() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AirwangCompactReports-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("import-reports.json")
        let finishedAt = Date(timeIntervalSince1970: 1_767_916_800)
        let report = makeReport(
            finishedAt: finishedAt,
            totalBytes: 300,
            selectedFileCount: 2,
            success: false,
            failedFiles: ["bad.mov"],
            importedItems: ["good.mov", "bad.mov"],
            fileRecords: [
                FileVerificationRecord(
                    relativePath: "good.mov",
                    size: 100,
                    sourceChecksum: "source",
                    targetChecksum: "target",
                    backupChecksum: nil,
                    status: "通过",
                    message: "ok"
                ),
                FileVerificationRecord(
                    relativePath: "bad.mov",
                    size: 200,
                    sourceChecksum: nil,
                    targetChecksum: nil,
                    backupChecksum: nil,
                    status: "异常",
                    message: "failed"
                )
            ]
        )

        try JSONPersistence.writeReports([report], to: url)
        let json = try String(contentsOf: url, encoding: .utf8)
        let loaded = JSONPersistence.loadReports(from: url).value

        XCTAssertFalse(json.contains("good.mov"))
        XCTAssertTrue(json.contains("bad.mov"))
        XCTAssertEqual(loaded.first?.importedItems, [])
        XCTAssertEqual(loaded.first?.fileRecords.map(\.relativePath), ["bad.mov"])
    }

    func testByteDisplayFormatterSwitchesToTerabytesAtThousandGigabytes() throws {
        XCTAssertTrue(ByteDisplayFormatter.string(fromByteCount: 999_999_999_999).contains("GB"))
        XCTAssertEqual(ByteDisplayFormatter.string(fromByteCount: 1_000_000_000_000), "1 TB")
        XCTAssertEqual(ByteDisplayFormatter.string(fromByteCount: 2_500_000_000_000), "2.5 TB")
    }

    func testSpacePreflightRequiresAtLeastOneGBMargin() {
        let requirement = SpacePreflightPolicy.requirement(for: 10_000_000_000)

        XCTAssertEqual(requirement.payloadBytes, 10_000_000_000)
        XCTAssertEqual(requirement.safetyMarginBytes, 1_000_000_000)
        XCTAssertEqual(requirement.requiredBytes, 11_000_000_000)
    }

    func testSpacePreflightUsesFivePercentForLargeTransfers() {
        let requirement = SpacePreflightPolicy.requirement(for: 100_000_000_000)

        XCTAssertEqual(requirement.safetyMarginBytes, 5_000_000_000)
        XCTAssertEqual(requirement.requiredBytes, 105_000_000_000)
    }

    func testSpacePreflightFailsWhenAvailableOnlyEqualsRawTotalBytes() {
        let result = SpacePreflightPolicy.evaluate(
            destinationLabel: "主目标盘",
            destinationPath: "/Volumes/Target",
            payloadBytes: 10_000_000_000,
            availableBytes: 10_000_000_000
        )

        XCTAssertEqual(result.status, .insufficient)
        XCTAssertFalse(result.isAllowed)
    }

    func testSpacePreflightFailsWhenCapacityUnreadable() {
        let result = SpacePreflightPolicy.evaluate(
            destinationLabel: "主目标盘",
            destinationPath: "/Volumes/Target",
            payloadBytes: 10_000_000_000,
            availableBytes: nil
        )

        XCTAssertEqual(result.status, .capacityUnavailable)
        XCTAssertFalse(result.isAllowed)
    }

    func testSpacePreflightAllowsAvailableEqualToMinimumRequirement() {
        let result = SpacePreflightPolicy.evaluate(
            destinationLabel: "主目标盘",
            destinationPath: "/Volumes/Target",
            payloadBytes: 10_000_000_000,
            availableBytes: 11_000_000_000
        )

        XCTAssertEqual(result.status, .passed)
        XCTAssertTrue(result.isAllowed)
    }

    func testMainWindowLayoutPolicyUsesPortraitLayoutForNarrowAndRotatedWindows() {
        XCTAssertTrue(MainWindowLayoutPolicy.usesPortraitLayout(width: 700, height: 900))
        XCTAssertTrue(MainWindowLayoutPolicy.usesPortraitLayout(width: 900, height: 1_300))
        XCTAssertFalse(MainWindowLayoutPolicy.usesPortraitLayout(width: 1_280, height: 800))
    }

    func testMainWindowLayoutPolicyAllowsNarrowMacWindows() {
        XCTAssertEqual(MainWindowLayoutPolicy.minimumWidth, 640)
        XCTAssertEqual(MainWindowLayoutPolicy.minimumHeight, 560)
    }

    func testStoreFileDecodesLegacyProjectArray() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AirwangStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("copy-projects.json")
        try "[]".write(to: url, atomically: true, encoding: .utf8)

        let result = JSONPersistence.loadProjects(from: url)

        XCTAssertEqual(result.value.count, 0)
        XCTAssertNil(result.warning)
    }

    func testCorruptProjectFileIsBackedUp() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AirwangCorrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("copy-projects.json")
        try "{".write(to: url, atomically: true, encoding: .utf8)

        let result = JSONPersistence.loadProjects(from: url)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains(".corrupt-") }

        XCTAssertEqual(result.value.count, 0)
        XCTAssertNotNil(result.warning)
        XCTAssertEqual(backups.count, 1)
    }

    func testFutureProjectSchemaIsProtectedOnLoadAndSave() throws {
        try withStoreFile("{\"schemaVersion\":999,\"projects\":[]}") { url, original in
            XCTAssertNotNil(JSONPersistence.loadProjects(from: url).warning)
            XCTAssertThrowsError(try JSONPersistence.writeProjects([makeProject()], to: url))
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("bak.json").path))
        }
    }

    func testFutureReportSchemaIsProtectedOnLoadAndSave() throws {
        try withStoreFile("{\"schemaVersion\":999,\"reports\":[]}") { url, original in
            XCTAssertNotNil(JSONPersistence.loadReports(from: url).warning)
            XCTAssertThrowsError(try JSONPersistence.writeReports([], to: url))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testUnrecognizedValidProjectJSONIsNotOverwritten() throws {
        for json in ["{\"unrecognized\":[1,2]}", "{\"schemaVersion\":1}", "{\"schemaVersion\":1,\"projects\":null}", "null", "42"] {
            try withStoreFile(json) { url, original in
                XCTAssertNotNil(JSONPersistence.loadProjects(from: url).warning)
                XCTAssertThrowsError(try JSONPersistence.writeProjects([], to: url))
                XCTAssertEqual(try Data(contentsOf: url), original)
            }
        }
    }

    func testLegacyProjectStoreCanBeMigratedAndPreservesBackup() throws {
        try withStoreFile("[]") { url, original in
            try JSONPersistence.writeProjects([makeProject()], to: url)
            XCTAssertEqual(JSONPersistence.loadProjects(from: url).value.count, 1)
            let backup = url.deletingPathExtension().appendingPathExtension("bak.json")
            XCTAssertEqual(try Data(contentsOf: backup), original)
        }
    }

    func testRepeatedCorruptLoadsKeepEachBackup() throws {
        try withStoreFile("{") { url, original in
            _ = JSONPersistence.loadProjects(from: url)
            _ = JSONPersistence.loadProjects(from: url)
            let backups = try FileManager.default.contentsOfDirectory(
                at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.contains(".corrupt-") }
            XCTAssertEqual(backups.count, 2)
            for backup in backups { XCTAssertEqual(try Data(contentsOf: backup), original) }
        }
    }

    func testCorruptProjectCanBeSavedAfterPreservingOriginalBytes() throws {
        try withStoreFile("{") { url, original in
            try JSONPersistence.writeProjects([makeProject()], to: url)
            XCTAssertEqual(JSONPersistence.loadProjects(from: url).value.count, 1)
            let backups = try FileManager.default.contentsOfDirectory(
                at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.contains(".corrupt-") }
            XCTAssertFalse(backups.isEmpty)
            for backup in backups { XCTAssertEqual(try Data(contentsOf: backup), original) }
        }
    }

    func testFutureStatisticsSchemaIsProtectedOnSave() throws {
        try withStoreFile("{\"schemaVersion\":999,\"indexedReportIDs\":[]}") { url, original in
            XCTAssertNotNil(JSONPersistence.loadStatisticsIndex(from: url).warning)
            XCTAssertThrowsError(try JSONPersistence.writeStatisticsIndex(CopyStatisticsIndex(), to: url))
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
    }

    func testUnrecognizedSettingsAreProtectedOnSave() throws {
        for json in ["{\"theme\":\"future-theme\"}", "{\"schemaVersion\":999,\"theme\":\"day\"}"] {
            try withStoreFile(json) { url, original in
                let store = SettingsStore(preferencesURL: url, uiSettingsURL: url)
                _ = store.loadUISettings()
                XCTAssertNotNil(store.lastLoadWarning)
                XCTAssertThrowsError(try store.saveUISettings(.default))
                XCTAssertEqual(try Data(contentsOf: url), original)
            }
        }
    }

    func testSettingsSavePreservesUnknownKeysAndClearsKnownOptionalValues() throws {
        try withStoreFile("{\"targetPath\":\"/Volumes/Old\",\"backupEnabled\":false,\"futureOption\":{\"value\":42}}") { url, original in
            let store = SettingsStore(preferencesURL: url, uiSettingsURL: url)
            try store.save(.default)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            XCTAssertEqual((object["futureOption"] as? [String: Int])?["value"], 42)
            XCTAssertNil(store.load().targetPath)
            XCTAssertEqual(try Data(contentsOf: url.deletingPathExtension().appendingPathExtension("bak.json")), original)
        }
    }

    func testSaveRechecksFileReplacedByNewerAppSinceLoad() throws {
        try withStoreFile("[]") { url, _ in
            XCTAssertNil(JSONPersistence.loadProjects(from: url).warning)
            let replacement = Data("{\"schemaVersion\":999,\"projects\":[]}".utf8)
            try replacement.write(to: url, options: .atomic)
            XCTAssertThrowsError(try JSONPersistence.writeProjects([makeProject()], to: url))
            XCTAssertEqual(try Data(contentsOf: url), replacement)
        }
    }


    func testIndependentBackupStatePreservesPrimaryAndRoundTrips() throws {
        var project = makeProject(autoStartEnabled: true, autoStartDeadline: Date())
        project.backupRootPath = "/Volumes/Backup"
        project.status = .failed
        project.verificationMode = .fastFingerprint
        let report = makeReport(finishedAt: Date(), totalBytes: 42, selectedFileCount: 1, success: true,
            importedItems: ["a.mov"], fileRecords: [FileVerificationRecord(relativePath: "a.mov", size: 42, sourceChecksum: "proof", targetChecksum: "proof", backupChecksum: nil, status: "通过", message: "ok")])
        project.primaryReportID = report.id
        project.primaryCompletionReference = PrimaryCompletionReference(report: report)
        project.backupReportID = UUID()
        project.primaryCopyState.isComplete = true
        project.primaryVerifyState.isComplete = true
        project.primaryCopyState.reportDocumentPath = "/original/report.txt"
        project.backupCopyState.completedFiles = 5
        let previousPrimary = try encodedStage(project.primaryCopyState)
        let previousBackupReport = project.backupReportID
        XCTAssertTrue(project.prepareForBackupRetry())
        let restored = try JSONDecoder().decode(CopyProject.self, from: JSONEncoder().encode(project))
        XCTAssertTrue(restored.backupOnlyRetry)
        XCTAssertTrue(restored.resumeExistingFiles)
        XCTAssertEqual(restored.status, .queued)
        XCTAssertEqual(restored.primaryReportID, report.id)
        XCTAssertEqual(restored.backupReportID, previousBackupReport)
        XCTAssertEqual(restored.primaryCompletionReference?.report.fileRecords.count, 1)
        XCTAssertEqual(restored.primaryCompletionReference?.report.importedItems, ["a.mov"])
        XCTAssertEqual(try encodedStage(restored.primaryCopyState), previousPrimary)
        XCTAssertEqual(restored.primaryImportURL, project.primaryImportURL)
        XCTAssertEqual(restored.verificationMode, .fastFingerprint)
        XCTAssertFalse(restored.autoStartEnabled)
        XCTAssertNil(restored.autoStartDeadline)
        XCTAssertEqual(restored.backupCopyState.completedFiles, 0)
        project.prepareForRetry()
        XCTAssertFalse(project.backupOnlyRetry)
        XCTAssertNil(project.primaryCompletionReference)
    }

    func testIndependentBackupPreparationRejectsUnsafeStatesWithoutMutation() throws {
        var eligible = makeProject()
        eligible.backupRootPath = "/Volumes/Backup"
        eligible.primaryReportID = UUID()
        eligible.primaryCopyState.isComplete = true
        eligible.primaryVerifyState.isComplete = true
        for index in 0..<5 {
            var project = eligible
            switch index {
            case 0: project.backupRootPath = nil
            case 1: project.primaryReportID = nil
            case 2: project.primaryVerifyState.isComplete = false
            case 3: project.status = .running
            default: project.status = .cancelling
            }
            let before = project
            XCTAssertFalse(project.prepareForBackupRetry())
            XCTAssertEqual(project.status, before.status)
            XCTAssertEqual(project.primaryReportID, before.primaryReportID)
            XCTAssertEqual(project.backupRootPath, before.backupRootPath)
            XCTAssertFalse(project.backupOnlyRetry)
        }
    }

    func testProjectV2MigrationRetainsOriginalBeyondRollingBackups() throws {
        for json in ["[]", "{\"schemaVersion\":1,\"projects\":[]}"] {
            try withStoreFile(json) { url, original in
                try JSONPersistence.writeProjects([makeProject()], to: url)
                let first = try Data(contentsOf: url)
                XCTAssertEqual((try JSONSerialization.jsonObject(with: first) as? [String: Any])?["schemaVersion"] as? Int, 2)
                XCTAssertThrowsError(try PersistentSchema.validateDataVersion(first, supported: 1))
                try JSONPersistence.writeProjects([], to: url)
                let backups = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent.contains(".before-v2-") }
                XCTAssertEqual(backups.count, 1)
                XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), original)
                XCTAssertEqual(try Data(contentsOf: url.deletingPathExtension().appendingPathExtension("bak.json")), first)
                XCTAssertNil(JSONPersistence.loadProjects(from: url).warning)
            }
        }
    }

    private func encodedStage(_ state: ProjectStageState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }

    private func withStoreFile(_ json: String, body: (URL, Data) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirwangUpgrade-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store.json")
        let original = Data(json.utf8)
        try original.write(to: url)
        try body(url, original)
    }

    private func makeProject(
        autoStartEnabled: Bool = false,
        autoStartDeadline: Date? = nil
    ) -> CopyProject {
        CopyProject(
            name: "Test",
            taskFolderName: "Test",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            sourceName: "Card",
            sourceVolumePath: "/Volumes/Card",
            sourceRootPath: "/Volumes/Card",
            targetRootPath: "/Volumes/Work",
            backupRootPath: nil,
            selectedItems: [],
            totalBytes: 0,
            verificationMode: .sha256,
            orderIndex: 0,
            autoStartEnabled: autoStartEnabled,
            autoStartDeadline: autoStartDeadline
        )
    }

    private func makeReport(
        finishedAt: Date,
        totalBytes: Int64,
        selectedFileCount: Int,
        success: Bool,
        failedFiles: [String] = [],
        importedItems: [String] = [],
        fileRecords: [FileVerificationRecord] = []
    ) -> TransferReport {
        TransferReport(
            id: UUID(),
            startedAt: finishedAt.addingTimeInterval(-60),
            finishedAt: finishedAt,
            sourceName: "Card",
            sourcePath: "/Volumes/Card",
            sourceRootPath: "/Volumes/Card",
            targetPath: "/Volumes/Work/Test",
            backupPath: nil,
            selectedFileCount: selectedFileCount,
            totalBytes: totalBytes,
            verificationMode: VerificationMode.sha256.title,
            namingRule: "Test",
            success: success,
            cancelled: false,
            failedFiles: failedFiles,
            copyFailedFiles: [],
            verificationFailedFiles: [],
            skippedFiles: [],
            verificationSummary: "",
            interruptionReason: nil,
            duration: 60,
            reportDocumentPath: nil,
            localReportDocumentPath: nil,
            importedItems: importedItems,
            fileRecords: fileRecords
        )
    }
}
