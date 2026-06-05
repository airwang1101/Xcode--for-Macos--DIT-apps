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
}
