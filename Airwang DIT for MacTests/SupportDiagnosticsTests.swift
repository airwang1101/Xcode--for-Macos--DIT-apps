import Foundation
import XCTest
@testable import Airwang_DIT_for_Mac

final class SupportDiagnosticsTests: XCTestCase {
    private let secret = "PRIVATE_CLIENT_FILM_UNRELEASED_82733"

    func testEncodedDiagnosticsExcludePrivateModelFieldsAndIdentifiers() throws {
        var project = makeProject()
        project.primaryCopyState.currentFile = secret + ".mov"
        project.primaryCopyState.title = secret
        project.primaryCopyState.detail = "/private/" + secret
        project.primaryCopyState.failedFiles = [secret]
        project.errorMessage = "Failure at /Users/client/\(secret)"
        project.sourceVolumeIdentifier = secret + "-SOURCE-DEVICE"
        project.targetVolumeIdentifier = secret + "-TARGET-DEVICE"
        let report = makeReport()
        project.primaryCompletionReference = PrimaryCompletionReference(report: report)
        project.backupOnlyRetry = true
        var activity = SupportDiagnosticsSnapshot.Activity()
        activity.errorCategory = .classify(project.errorMessage)
        let snapshot = SupportDiagnosticsSnapshot.capture(projects: [project], reports: [report], activity: activity)
        let data = try snapshot.encoded()
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(text.contains(secret))
        XCTAssertFalse(text.contains(project.id.uuidString))
        XCTAssertFalse(text.contains(report.id.uuidString))
        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertFalse(text.contains("/Volumes/"))
        XCTAssertFalse(text.contains("/private/"))
        XCTAssertEqual(snapshot.projects.stages["primaryCopy"]?.withFailures, 1)
        XCTAssertEqual(snapshot.reports.withCopyFailures, 1)
        XCTAssertTrue(snapshot.privacy.redacted)
        XCTAssertFalse(snapshot.privacy.automaticallyUploaded)
        XCTAssertFalse(snapshot.privacy.includesRawErrors)
        XCTAssertFalse(snapshot.privacy.includesEnvironmentVariables)
    }

    func testTaskStatesAndFailureKindsRemainUsefulWithoutRawText() {
        var project = makeProject()
        project.status = .failed
        project.prepareForRetry()
        project.primaryVerifyState.isBlocked = true
        project.backupCopyState.isActive = true
        project.backupRootPath = "/Volumes/\(secret)/Backup"
        let snapshot = SupportDiagnosticsSnapshot.capture(
            projects: [project], reports: [makeReport()], activity: .init()
        )

        XCTAssertEqual(snapshot.projects.statusCounts["queued"], 1)
        XCTAssertEqual(snapshot.projects.recoveryEnabled, 1)
        XCTAssertEqual(snapshot.projects.withBackup, 1)
        XCTAssertEqual(snapshot.projects.stages["primaryVerify"]?.blocked, 1)
        XCTAssertEqual(snapshot.projects.stages["backupCopy"]?.active, 1)
        XCTAssertEqual(snapshot.reports.interrupted, 1)
        XCTAssertEqual(snapshot.reports.reportWriteFailures, 1)
        XCTAssertEqual(snapshot.recentReports[0].verificationFailureCount, 1)
        XCTAssertEqual(snapshot.recentReports[0].resumedFileCount, 1)
    }

    func testBuiltSourceProvenanceIsIncludedWithoutLocalPaths() {
        let revision = String(repeating: "a", count: 40)
        let fingerprint = String(repeating: "b", count: 64)
        let application = SupportDiagnosticsSnapshot.Application.fromMetadata([
            "CFBundleShortVersionString": "0.1.1", "CFBundleVersion": "2026093001",
            "AirwangSourceRevision": revision, "AirwangBuildInputSHA256": fingerprint,
            "AirwangSourceState": "working-tree"
        ], developmentBuild: false, isolatedDevelopmentData: false)
        XCTAssertEqual(application.sourceRevision, revision)
        XCTAssertEqual(application.buildInputSHA256, fingerprint)
        XCTAssertEqual(application.sourceState, "working-tree")
        XCTAssertEqual(application.build, "2026093001")
    }

    func testMissingOrInvalidProvenanceIsUnknownAndNeverEchoed() throws {
        for metadata in [[:], ["AirwangSourceRevision": secret, "AirwangBuildInputSHA256": secret,
                              "AirwangSourceState": secret]] {
            let application = SupportDiagnosticsSnapshot.Application.fromMetadata(
                metadata, developmentBuild: true, isolatedDevelopmentData: true
            )
            XCTAssertEqual(application.sourceRevision, "unknown")
            XCTAssertEqual(application.buildInputSHA256, "unknown")
            XCTAssertEqual(application.sourceState, "unknown")
            let snapshot = SupportDiagnosticsSnapshot.capture(
                projects: [], reports: [], activity: .init(), application: application
            )
            XCTAssertFalse(try XCTUnwrap(String(data: snapshot.encoded(), encoding: .utf8)).contains(secret))
        }
    }

    func testSamplingIsBoundedWhileTotalsIncludeAllReports() {
        let snapshot = SupportDiagnosticsSnapshot.capture(
            projects: [], reports: (0..<100).map { _ in makeReport() }, activity: .init()
        )
        XCTAssertEqual(snapshot.reports.total, 100)
        XCTAssertEqual(snapshot.reports.withCopyFailures, 100)
        XCTAssertEqual(snapshot.recentReports.count, 25)
        XCTAssertEqual(snapshot.recentReports.map(\.reference), Array(1...25))
    }

    func testKnownEnglishChineseAndRawVerificationLabelsAreNormalized() throws {
        for mode in VerificationMode.allCases {
            for label in [mode.rawValue, mode.title, AppLocalization.text(mode.title, language: .english)] {
                let snapshot = SupportDiagnosticsSnapshot.capture(
                    projects: [], reports: [makeReport(mode: label)], activity: .init()
                )
                XCTAssertEqual(snapshot.reports.verificationModeCounts[mode.rawValue], 1)
            }
        }
        let snapshot = SupportDiagnosticsSnapshot.capture(
            projects: [], reports: [makeReport(mode: secret)], activity: .init()
        )
        XCTAssertEqual(snapshot.recentReports[0].verificationMode, "unknown")
        XCTAssertFalse(try XCTUnwrap(String(data: snapshot.encoded(), encoding: .utf8)).contains(secret))
    }

    func testPublicationProducesValidJSONWithPrivateFilePermissions() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("diagnostics.json")
            let snapshot = makeSnapshot()
            try SupportDiagnosticsExporter.write(snapshot, to: url)

            XCTAssertEqual(try Data(contentsOf: url), try snapshot.encoded())
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            XCTAssertEqual(object["format"] as? String, SupportDiagnosticsSnapshot.formatIdentifier)
            let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.intValue, 0o600)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["diagnostics.json"])
        }
    }

    func testExistingOutputIsPreserved() throws {
        try withDirectory { directory in
            let output = directory.appendingPathComponent("existing.json")
            let original = Data(secret.utf8)
            try original.write(to: output)
            XCTAssertThrowsError(try SupportDiagnosticsExporter.write(makeSnapshot(), to: output))
            XCTAssertEqual(try Data(contentsOf: output), original)
        }
    }

    func testSavePanelPrivateTemporaryDirectoryAliasPublishesSafely() throws {
        let directory = URL(fileURLWithPath: "/private/tmp/AirwangDiagnosticsAlias-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("diagnostics.json", isDirectory: false)
        let snapshot = makeSnapshot()
        try SupportDiagnosticsExporter.write(snapshot, to: output)
        XCTAssertEqual(try Data(contentsOf: output), try snapshot.encoded())
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["diagnostics.json"])
    }

    func testSymlinkTargetAndParentArePreservedAndRefused() throws {
        try withDirectory { directory in
            let original = directory.appendingPathComponent("original.json")
            let data = Data(secret.utf8)
            try data.write(to: original)
            let link = directory.appendingPathComponent("linked.json")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
            XCTAssertThrowsError(try SupportDiagnosticsExporter.write(makeSnapshot(), to: link))
            XCTAssertEqual(try Data(contentsOf: original), data)
            XCTAssertTrue(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)

            let parentLink = directory.appendingPathComponent("parent-link", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: parentLink, withDestinationURL: directory)
            XCTAssertThrowsError(try SupportDiagnosticsExporter.write(makeSnapshot(), to: parentLink.appendingPathComponent("new.json")))
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("new.json").path))
        }
    }

    func testMissingParentAndWrongExtensionDoNotCreateFiles() throws {
        try withDirectory { directory in
            XCTAssertThrowsError(try SupportDiagnosticsExporter.write(makeSnapshot(), to: directory.appendingPathComponent("missing/new.json")))
            XCTAssertThrowsError(try SupportDiagnosticsExporter.write(makeSnapshot(), to: directory.appendingPathComponent("clip.mov")))
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
    }

    func testCancellationDoesNotPublishAnOutput() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("cancelled.json")
        let snapshot = makeSnapshot()
        let gate = DiagnosticsAsyncGate()
        let task = Task.detached {
            await gate.wait()
            try SupportDiagnosticsExporter.write(snapshot, to: output)
        }
        task.cancel()
        await gate.open()
        do {
            try await task.value
            XCTFail("Cancelled export was published")
        } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testConcurrentExportsCannotReplaceEachOther() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("race.json")
        let snapshot = makeSnapshot()
        let successes = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do { try SupportDiagnosticsExporter.write(snapshot, to: output); return true }
                    catch { return false }
                }
            }
            var successCount = 0
            for await success in group { successCount += success ? 1 : 0 }
            return successCount
        }
        XCTAssertEqual(successes, 1)
        XCTAssertEqual(try Data(contentsOf: output), try snapshot.encoded())
    }

    func testDefaultFileNameIsUniqueAndUTCRegardlessOfSystemLocale() {
        let date = Date(timeIntervalSince1970: 0)
        let first = SupportDiagnosticsExporter.defaultFileName(at: date)
        XCTAssertTrue(first.hasPrefix("Airwang-DIT-Diagnostics-19700101T000000Z-"))
        XCTAssertTrue(first.hasSuffix(".json"))
        XCTAssertNotEqual(first, SupportDiagnosticsExporter.defaultFileName(at: date))
    }

    private func makeSnapshot() -> SupportDiagnosticsSnapshot {
        .capture(projects: [makeProject()], reports: [makeReport()], activity: .init(), now: Date(timeIntervalSince1970: 0))
    }

    private func makeProject() -> CopyProject {
        CopyProject(
            name: secret, taskFolderName: secret, createdAt: .distantPast, updatedAt: .distantPast,
            sourceName: secret, sourceVolumePath: "/Volumes/\(secret)", sourceRootPath: "/Volumes/\(secret)/DCIM",
            targetRootPath: "/Volumes/\(secret)/Work", backupRootPath: nil, selectedItems: [],
            totalBytes: 123, verificationMode: .sha256, orderIndex: 0
        )
    }

    private func makeReport(mode: String = "sha256") -> TransferReport {
        TransferReport(
            id: UUID(), startedAt: .distantPast, finishedAt: Date(timeIntervalSince1970: 0),
            sourceName: secret, sourcePath: "/Volumes/\(secret)", sourceRootPath: "/Volumes/\(secret)/DCIM",
            targetPath: "/Volumes/\(secret)/Work", backupPath: "/Volumes/\(secret)/Backup",
            selectedFileCount: 2, totalBytes: 123, verificationMode: mode, namingRule: secret,
            success: false, cancelled: false, failedFiles: [secret], copyFailedFiles: [secret],
            verificationFailedFiles: [secret], skippedFiles: [secret], verificationSummary: secret,
            interruptionReason: "source missing at /private/\(secret)", duration: 1,
            reportDocumentPath: "/private/\(secret).txt", localReportDocumentPath: "/Users/\(secret).txt",
            reportDocumentWriteFailed: true, importedItems: [secret],
            fileRecords: [.init(relativePath: secret, size: 123, sourceChecksum: secret,
                                targetChecksum: secret, backupChecksum: secret, status: secret, message: secret)],
            resumedFiles: [secret]
        )
    }

    private func makeDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AirwangDiagnostics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }
}

private actor DiagnosticsAsyncGate {
    private var opened = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if opened { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        opened = true
        continuation?.resume()
        continuation = nil
    }
}
