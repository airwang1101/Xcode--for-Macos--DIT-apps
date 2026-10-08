import XCTest

@MainActor
final class StatisticsUITests: XCTestCase {
    private var app: XCUIApplication!
    private var appSupportURL: URL!

    override func setUp() async throws {
        continueAfterFailure = false

        appSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirwangDITUITests-\(UUID().uuidString)", isDirectory: true)
        try seedConfiguredAppData(at: appSupportURL)

        app = XCUIApplication()
        app.launchEnvironment["AIRWANG_DIT_UI_TESTING"] = "1"
        app.launchEnvironment["AIRWANG_DIT_APP_SUPPORT_DIR"] = appSupportURL.path
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), app.debugDescription)
    }

    override func tearDown() async throws {
        if app?.state == .runningForeground || app?.state == .runningBackground {
            app.terminate()
        }
        if let appSupportURL {
            try? FileManager.default.removeItem(at: appSupportURL)
        }
        app = nil
        appSupportURL = nil
    }

    func testStatisticsSectionShowsStablePerformanceTestAnchors() throws {
        requireElement("main-dashboard", timeout: 8)

        tapBottomTab("statistics")

        requireElement("workspace-statistics")
        requireElement("statistics-workspace")
        requireElement("statistics-profile-card")
        requireElement("statistics-activity-heatmap-card")
        requireElement("statistics-activity-mode-picker")
        requireElement("statistics-refresh-button")
        requireElement("statistics-recent-reports-card")
    }

    func testStatisticsSectionSurvivesModeSwitchAndRefreshWithoutLosingLayoutAnchors() throws {
        tapBottomTab("statistics", timeout: 8)

        requireElement("statistics-activity-mode-picker")
        requireElement("statistics-activity-heatmap-card")

        let weeklyButton = app.buttons["近 7 日"]
        if weeklyButton.waitForExistence(timeout: 2) {
            weeklyButton.click()
        }
        let cumulativeButton = app.buttons["累计"]
        if cumulativeButton.waitForExistence(timeout: 2) {
            cumulativeButton.click()
        }
        let dailyButton = app.buttons["每日"]
        if dailyButton.waitForExistence(timeout: 2) {
            dailyButton.click()
        }

        requireElement("statistics-refresh-button").click()

        XCTAssertTrue(app.descendants(matching: .any)["workspace-statistics"].exists, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["statistics-activity-heatmap-card"].exists, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["statistics-activity-mode-picker"].exists, app.debugDescription)
        XCTAssertTrue(app.descendants(matching: .any)["statistics-recent-reports-card"].exists, app.debugDescription)
    }

    @discardableResult
    private func requireElement(
        _ identifier: String,
        timeout: TimeInterval = 4,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let element = app.descendants(matching: .any)[identifier]
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Missing \(identifier)\n\(app.debugDescription)", file: file, line: line)
        return element
    }

    private func tapBottomTab(
        _ rawValue: String,
        timeout: TimeInterval = 4,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let button = app.buttons["bottom-tab-\(rawValue)"]
        if button.waitForExistence(timeout: timeout) {
            button.click()
            return
        }

        let label = app.descendants(matching: .any)["bottom-tab-label-\(rawValue)"]
        XCTAssertTrue(label.waitForExistence(timeout: 1), "Missing bottom-tab-\(rawValue)\n\(app.debugDescription)", file: file, line: line)
        label.click()
    }

    private func seedConfiguredAppData(at rootURL: URL) throws {
        let dataURL = rootURL.appendingPathComponent("Data", isDirectory: true)
        let targetURL = rootURL.appendingPathComponent("Target", isDirectory: true)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)

        try writeJSON([
            "targetPath": targetURL.path,
            "backupEnabled": false
        ], to: dataURL.appendingPathComponent("preferences.json"))

        try writeJSON([
            "theme": "day",
            "language": "chinese",
            "autoStartQueuedProjects": false
        ], to: dataURL.appendingPathComponent("ui-settings.json"))

        try writeJSON([
            "schemaVersion": 1,
            "reports": makeReports()
        ], to: dataURL.appendingPathComponent("import-reports.json"))
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func makeReports() -> [[String: Any]] {
        let now = Date()
        return (0..<12).map { index in
            let finishedAt = now.addingTimeInterval(TimeInterval(-index * 86_400))
            let startedAt = finishedAt.addingTimeInterval(-120)
            return [
                "id": UUID().uuidString,
                "startedAt": startedAt.timeIntervalSinceReferenceDate,
                "finishedAt": finishedAt.timeIntervalSinceReferenceDate,
                "sourceName": index % 2 == 0 ? "A7M3 Card" : "FX3 Card",
                "sourcePath": "/Volumes/TestCard",
                "sourceRootPath": "/Volumes/TestCard",
                "targetPath": "/tmp/AirwangDITUITests/Task-\(index)",
                "selectedFileCount": 2 + index,
                "totalBytes": 64_000_000 + index * 12_000_000,
                "verificationMode": "SHA-256 全量校验",
                "namingRule": "UITest",
                "success": index % 5 != 0,
                "cancelled": false,
                "failedFiles": [],
                "copyFailedFiles": [],
                "verificationFailedFiles": [],
                "skippedFiles": [],
                "verificationSummary": "ok",
                "duration": 120,
                "reportDocumentWriteFailed": false,
                "importedItems": [],
                "fileRecords": []
            ]
        }
    }
}
