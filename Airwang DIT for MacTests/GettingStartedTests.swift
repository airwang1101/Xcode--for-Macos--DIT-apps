import Foundation
import XCTest
@testable import Airwang_DIT_for_Mac

@MainActor
final class GettingStartedTests: XCTestCase {
    private func withStorage(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DIT-Guide-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    func testFirstLaunchResumesSavedStepWithoutCompletingGuide() throws {
        try withStorage { root in
            let first = AppViewModel(dataDirectory: root)
            first.presentGettingStartedIfNeeded()
            XCTAssertTrue(first.isShowingGettingStarted)
            first.visitGettingStartedStep(.verification)

            let reopened = AppViewModel(dataDirectory: root)
            reopened.presentGettingStartedIfNeeded()
            XCTAssertTrue(reopened.isShowingGettingStarted)
            XCTAssertEqual(reopened.gettingStartedProgress.step, .verification)
            XCTAssertFalse(reopened.isConfigured)
            XCTAssertFalse(reopened.autoStartQueuedProjects)
            XCTAssertTrue(reopened.copyProjects.isEmpty)
            XCTAssertTrue(reopened.reports.isEmpty)
        }
    }

    func testSkippingPersistsAcrossRelaunchAndOtherPreferenceChanges() throws {
        try withStorage { root in
            let first = AppViewModel(dataDirectory: root)
            first.presentGettingStartedIfNeeded()
            first.visitGettingStartedStep(.source)
            first.dismissGettingStarted()
            first.setTheme(.night)
            first.setLanguage(.english)
            first.setInterfaceStyle(.classic)
            first.setAutoStartQueuedProjects(true)

            let reopened = AppViewModel(dataDirectory: root)
            reopened.presentGettingStartedIfNeeded()
            XCTAssertFalse(reopened.isShowingGettingStarted)
            XCTAssertEqual(reopened.gettingStartedProgress.completedVersion, 1)
            XCTAssertEqual(reopened.selectedTheme, .night)
            XCTAssertEqual(reopened.selectedLanguage, .english)
            XCTAssertEqual(reopened.interfaceStyle, .classic)
            XCTAssertTrue(reopened.autoStartQueuedProjects)
        }
    }

    func testLegacySettingsDoNotForceGuideAndManualReplayPreservesUnknownFields() throws {
        try withStorage { root in
            let url = root.appendingPathComponent("ui-settings.json")
            try Data(#"{"theme":"night","language":"english","autoStartQueuedProjects":true,"interfaceStyle":"classic","futureSetting":"keep"}"#.utf8).write(to: url)
            let model = AppViewModel(dataDirectory: root)
            model.presentGettingStartedIfNeeded()
            XCTAssertFalse(model.isShowingGettingStarted)
            model.reopenGettingStarted()
            XCTAssertTrue(model.isShowingGettingStarted)
            XCTAssertEqual(model.gettingStartedProgress.step, .welcome)
            model.visitGettingStartedStep(.history)
            model.dismissGettingStarted()
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            XCTAssertEqual(fields["futureSetting"] as? String, "keep")
            XCTAssertEqual(fields["theme"] as? String, "night")
            XCTAssertEqual(fields["language"] as? String, "english")
            XCTAssertEqual(fields["interfaceStyle"] as? String, "classic")
            XCTAssertEqual(fields["autoStartQueuedProjects"] as? Bool, true)
        }
    }

    func testExistingTargetDoesNotForceGuide() throws {
        try withStorage { root in
            let store = SettingsStore(preferencesURL: root.appendingPathComponent("preferences.json"),
                                      uiSettingsURL: root.appendingPathComponent("ui-settings.json"))
            try store.save(AppPreferences(targetPath: root.path, backupEnabled: false, backupPath: nil))
            let model = AppViewModel(dataDirectory: root)
            model.presentGettingStartedIfNeeded()
            XCTAssertFalse(model.isShowingGettingStarted)
            XCTAssertEqual(model.preferences.targetPath, root.path)
        }
    }

    func testExistingProjectIsLoadedAndNotRewrittenByGuide() throws {
        try withStorage { root in
            let url = root.appendingPathComponent("copy-projects.json")
            let original = Data("""
            [{"id":"\(UUID().uuidString)","name":"Existing","taskFolderName":"Existing",
            "createdAt":0,"updatedAt":0,"sourceName":"Card","sourceVolumePath":"/source",
            "sourceRootPath":"/source","targetRootPath":"/target","selectedItems":[],
            "totalBytes":0,"verificationMode":"sha256","status":"queued","orderIndex":0}]
            """.utf8)
            try original.write(to: url)
            let model = AppViewModel(dataDirectory: root)
            model.presentGettingStartedIfNeeded()
            XCTAssertFalse(model.isShowingGettingStarted)
            XCTAssertEqual(model.copyProjects.count, 1)
            model.reopenGettingStarted()
            model.visitGettingStartedStep(.queue)
            model.dismissGettingStarted()
            XCTAssertEqual(try Data(contentsOf: url), original)
            XCTAssertEqual(model.copyProjects.first?.status, .queued)
            XCTAssertTrue(model.reports.isEmpty)
        }
    }

    func testGuideDefersWhileExistingFolderPickerOrErrorIsVisible() throws {
        try withStorage { root in
            let model = AppViewModel(dataDirectory: root)
            model.activeFolderPicker = .target
            model.presentGettingStartedIfNeeded()
            XCTAssertFalse(model.isShowingGettingStarted)
            model.activeFolderPicker = nil
            model.importError = "existing warning"
            model.presentGettingStartedIfNeeded()
            XCTAssertFalse(model.isShowingGettingStarted)
            XCTAssertEqual(model.importError, "existing warning")
            model.importError = nil
            model.presentGettingStartedIfNeeded()
            XCTAssertTrue(model.isShowingGettingStarted)
        }
    }

    func testGuideDefersWhilePendingMediaIsRetained() throws {
        try withStorage { root in
            let model = AppViewModel(dataDirectory: root)
            let volume = StorageVolume(id: "guide-card", name: "Card", url: root,
                                       isRemovable: true, isInternal: false,
                                       totalCapacity: nil, availableCapacity: nil)
            model.pendingImportVolume = volume
            model.presentGettingStartedIfNeeded()
            XCTAssertFalse(model.isShowingGettingStarted)
            XCTAssertEqual(model.pendingImportVolume?.id, volume.id)
            model.pendingImportVolume = nil
            model.presentGettingStartedIfNeeded()
            model.pendingImportVolume = volume
            model.dismissGettingStarted()
            XCTAssertEqual(model.pendingImportVolume?.id, volume.id)
        }
    }

    func testManualGuideResumesAfterFolderPickerWithoutReopeningOnNextLaunch() throws {
        try withStorage { root in
            let model = AppViewModel(dataDirectory: root)
            model.dismissGettingStarted()
            model.reopenGettingStarted()
            model.visitGettingStartedStep(.destinations)
            model.chooseGettingStartedDestination(backup: false)
            XCTAssertFalse(model.isShowingGettingStarted)
            XCTAssertNotNil(model.activeFolderPicker)
            model.closeFolderPicker()
            model.presentGettingStartedIfNeeded()
            XCTAssertTrue(model.isShowingGettingStarted)
            XCTAssertEqual(model.gettingStartedProgress.step, .destinations)
            model.dismissGettingStarted()
            let reopened = AppViewModel(dataDirectory: root)
            reopened.presentGettingStartedIfNeeded()
            XCTAssertFalse(reopened.isShowingGettingStarted)
        }
    }

    func testChoosingBackupUsesExistingPreferencesWithoutChangingPrimaryOrVerification() throws {
        try withStorage { root in
            let model = AppViewModel(dataDirectory: root)
            model.preferences.targetPath = "/existing-primary"
            model.selectedVerificationMode = .fastFingerprint
            model.reopenGettingStarted()
            model.chooseGettingStartedDestination(backup: true)
            XCTAssertTrue(model.preferences.backupEnabled)
            XCTAssertEqual(model.preferences.targetPath, "/existing-primary")
            XCTAssertEqual(model.selectedVerificationMode, .fastFingerprint)
            model.closeFolderPicker()
            model.presentGettingStartedIfNeeded()
            XCTAssertTrue(model.isShowingGettingStarted)
        }
    }

    func testPrimarySelectionPersistsAndReturnsToGuide() throws {
        try withStorage { root in
            let target = root.appendingPathComponent("Primary", isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let model = AppViewModel(dataDirectory: root)
            model.presentGettingStartedIfNeeded()
            model.visitGettingStartedStep(.destinations)
            model.chooseGettingStartedDestination(backup: false)
            model.selectFolder(target)
            model.confirmFolderSelection()
            XCTAssertNil(model.activeFolderPicker)
            XCTAssertEqual(model.preferences.targetPath, target.path)
            XCTAssertEqual(model.settingsStore.load().targetPath, target.path)
            model.presentGettingStartedIfNeeded()
            XCTAssertTrue(model.isShowingGettingStarted)
            XCTAssertEqual(model.gettingStartedProgress.step, .destinations)
            XCTAssertTrue(model.copyProjects.isEmpty)
            XCTAssertTrue(model.reports.isEmpty)
        }
    }

    func testFutureCompletionMarkerIsRespectedAndRetained() throws {
        try withStorage { root in
            let url = root.appendingPathComponent("ui-settings.json")
            try Data(#"{"theme":"day","gettingStarted":{"completedVersion":99,"lastVisitedStep":999}}"#.utf8).write(to: url)
            let model = AppViewModel(dataDirectory: root)
            model.presentGettingStartedIfNeeded()
            XCTAssertFalse(model.isShowingGettingStarted)
            XCTAssertEqual(model.gettingStartedProgress.step, .ready)
            model.reopenGettingStarted()
            model.dismissGettingStarted()
            XCTAssertEqual(model.settingsStore.loadUISettings().gettingStarted?.completedVersion, 99)
        }
    }

    func testMissingProgressFieldsAndOutOfRangeStepsDecodeSafely() throws {
        let progress = try JSONDecoder().decode(GettingStartedProgress.self, from: Data(#"{"lastVisitedStep":-50}"#.utf8))
        XCTAssertEqual(progress.step, .welcome)
        XCTAssertTrue(progress.shouldPresentAutomatically)
        let settings = try JSONDecoder().decode(AppUISettings.self, from: Data(#"{"theme":"night"}"#.utf8))
        XCTAssertNil(settings.gettingStarted)
        XCTAssertEqual(settings.interfaceStyle, .paper)
    }

    func testProtectedFutureSettingsAreNotOverwrittenByGuide() throws {
        try withStorage { root in
            let url = root.appendingPathComponent("ui-settings.json")
            let bytes = Data(#"{"schemaVersion":999,"theme":"night"}"#.utf8)
            try bytes.write(to: url)
            let model = AppViewModel(dataDirectory: root)
            model.reopenGettingStarted()
            XCTAssertFalse(model.isShowingGettingStarted)
            XCTAssertNotNil(model.importError)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
    }
}
