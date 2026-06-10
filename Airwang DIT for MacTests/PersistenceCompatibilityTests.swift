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
    }

    func testUISettingsDecodesLegacyThemeOnlySettings() throws {
        let json = """
        {
          "theme": "night"
        }
        """.data(using: .utf8)!

        let settings = try JSONDecoder().decode(AppUISettings.self, from: json)

        XCTAssertEqual(settings.theme, .night)
        XCTAssertEqual(settings.language, .chinese)
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
}
