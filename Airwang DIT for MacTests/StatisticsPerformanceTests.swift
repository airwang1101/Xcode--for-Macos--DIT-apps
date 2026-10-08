import Foundation
import XCTest
@testable import Airwang_DIT_for_Mac

final class StatisticsPerformanceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testLargeHistoryIndexMatchesFullSummaryAndHeatmaps() throws {
        let now = try makeDate(year: 2026, month: 6, day: 24, hour: 23)
        let reports = makeStressReports(count: 10_000, now: now, daySpan: 730)

        let fullSummary = CopyStatisticsSummary.make(
            reports: reports,
            projects: [],
            calendar: calendar,
            now: now,
            dayCount: 365
        )
        let index = CopyStatisticsIndex.make(reports: reports, calendar: calendar, now: now)
        let indexedSummary = index.summary(projects: [], calendar: calendar, now: now, dayCount: 365)
        let heatmaps = CopyStatisticsHeatmaps.make(days: indexedSummary.days, calendar: calendar)

        XCTAssertTrue(index.matches(reports: reports, calendar: calendar, now: now))
        XCTAssertEqual(indexedSummary, fullSummary)
        XCTAssertEqual(heatmaps.daily.days.count, 365)
        XCTAssertEqual(heatmaps.weekly.days.count, 365)
        XCTAssertEqual(heatmaps.cumulative.days.count, 365)
        XCTAssertEqual(heatmaps.daily.weeks.flatMap { $0 }.compactMap { $0 }.count, 365)
        XCTAssertEqual(heatmaps.cumulative.days.last?.bytes, indexedSummary.days.reduce(0) { $0 + $1.bytes })
    }

    func testStatisticsIndexAndHeatmapBuildPerformanceForLargeHistory() throws {
        let now = try makeDate(year: 2026, month: 6, day: 24, hour: 23)
        let reports = makeStressReports(count: 10_000, now: now, daySpan: 730)
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(
            metrics: [
                XCTClockMetric(),
                XCTCPUMetric(),
                XCTMemoryMetric()
            ],
            options: options
        ) {
            let index = CopyStatisticsIndex.make(reports: reports, calendar: calendar, now: now)
            let summary = index.summary(projects: [], calendar: calendar, now: now, dayCount: 365)
            let heatmaps = CopyStatisticsHeatmaps.make(days: summary.days, calendar: calendar)

            XCTAssertEqual(summary.days.count, 365)
            XCTAssertEqual(heatmaps.daily.days.count, 365)
            XCTAssertGreaterThan(summary.totalReports, 0)
        }
    }

    func testCachedHeatmapModeSwitchLookupStaysConstantWork() throws {
        let now = try makeDate(year: 2026, month: 6, day: 24, hour: 23)
        let reports = makeStressReports(count: 10_000, now: now, daySpan: 730)
        let index = CopyStatisticsIndex.make(reports: reports, calendar: calendar, now: now)
        let summary = index.summary(projects: [], calendar: calendar, now: now, dayCount: 365)
        let heatmaps = CopyStatisticsHeatmaps.make(days: summary.days, calendar: calendar)
        let modes: [StatisticsActivityMode] = [.daily, .weekly, .cumulative]
        let options = XCTMeasureOptions()
        options.iterationCount = 5

        measure(metrics: [XCTClockMetric(), XCTCPUMetric()], options: options) {
            var totalBytes: Int64 = 0
            for offset in 0..<30_000 {
                let heatmap = heatmaps.heatmap(for: modes[offset % modes.count])
                totalBytes += heatmap.maxBytes
            }
            XCTAssertGreaterThan(totalBytes, 0)
        }
    }

    func testRepeatedStatisticsRefreshInputsProduceStableOutputs() throws {
        let now = try makeDate(year: 2026, month: 6, day: 24, hour: 23)
        let reports = makeStressReports(count: 10_000, now: now, daySpan: 730)
        let index = CopyStatisticsIndex.make(reports: reports, calendar: calendar, now: now)

        let firstSummary = index.summary(projects: [], calendar: calendar, now: now, dayCount: 365)
        let firstHeatmaps = CopyStatisticsHeatmaps.make(days: firstSummary.days, calendar: calendar)
        let secondSummary = index.summary(projects: [], calendar: calendar, now: now, dayCount: 365)
        let secondHeatmaps = CopyStatisticsHeatmaps.make(days: secondSummary.days, calendar: calendar)

        XCTAssertEqual(secondSummary, firstSummary)
        XCTAssertEqual(secondHeatmaps, firstHeatmaps)
    }

    func testHeatmapsPreservePartialWeeksAndCumulativeCounts() throws {
        let start = try makeDate(year: 2026, month: 6, day: 24)
        let days = (0..<9).map { offset in
            CopyActivityDay(
                date: calendar.date(byAdding: .day, value: offset, to: start)!,
                bytes: Int64(offset + 1), files: offset + 1, reportCount: 1,
                successCount: offset % 2
            )
        }
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let heatmaps = CopyStatisticsHeatmaps.make(days: days, calendar: mondayCalendar)
        XCTAssertEqual(heatmaps.daily.days, days)
        XCTAssertEqual(heatmaps.daily.weeks.map { $0.compactMap { $0 }.count }, [4, 5])
        XCTAssertEqual(heatmaps.weekly.days.map(\.bytes), [10, 10, 10, 10, 35, 35, 35, 35, 35])
        XCTAssertEqual(heatmaps.weekly.days.map(\.files), [10, 10, 10, 10, 35, 35, 35, 35, 35])
        XCTAssertEqual(heatmaps.weekly.days.map(\.reportCount), [4, 4, 4, 4, 5, 5, 5, 5, 5])
        XCTAssertEqual(heatmaps.weekly.days.map(\.successCount), Array(repeating: 2, count: 9))
        XCTAssertEqual(heatmaps.cumulative.days.map(\.bytes), [1, 3, 6, 10, 15, 21, 28, 36, 45])
        XCTAssertEqual(heatmaps.cumulative.days.last?.files, 45)
        XCTAssertEqual(heatmaps.cumulative.days.last?.reportCount, 9)
        XCTAssertEqual(heatmaps.cumulative.days.last?.successCount, 4)
        XCTAssertEqual(heatmaps.weekly.peakDay?.date, days.last?.date)
        XCTAssertEqual(heatmaps.weekly.maxBytes, 35)
        let empty = CopyStatisticsHeatmaps.make(days: [], calendar: calendar)
        for mode in StatisticsActivityMode.allCases {
            XCTAssertTrue(empty.heatmap(for: mode).weeks.isEmpty)
            XCTAssertNil(empty.heatmap(for: mode).peakDay)
            XCTAssertEqual(empty.heatmap(for: mode).maxBytes, 1)
        }
        let inactive = CopyStatisticsHeatmap.make(days: [
            CopyActivityDay(date: start, bytes: -1, files: 0, reportCount: 0, successCount: 0)
        ], calendar: calendar)
        XCTAssertNil(inactive.peakDay)
        XCTAssertEqual(inactive.maxBytes, 1)
    }

    func testHeatmapBuildPerformance() throws {
        let now = try makeDate(year: 2026, month: 6, day: 24)
        let reports = makeStressReports(count: 10_000, now: now, daySpan: 730)
        let days = CopyStatisticsIndex.make(reports: reports, calendar: calendar, now: now)
            .summary(projects: [], calendar: calendar, now: now).days
        let options = XCTMeasureOptions()
        options.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: options) {
            var checksum = 0
            for _ in 0..<300 {
                let heatmaps = CopyStatisticsHeatmaps.make(days: days, calendar: calendar)
                checksum += heatmaps.weekly.days.count + heatmaps.cumulative.days.count
            }
            XCTAssertEqual(checksum, 219_000)
        }
    }

    private func makeStressReports(count: Int, now: Date, daySpan: Int) -> [TransferReport] {
        let dayStart = calendar.startOfDay(for: now)
        let sourceNames = ["A7M3 Card", "FX3 Card", "A7S3 Card", "Drone Card"]
        let verificationModes = [
            VerificationMode.sha256.title,
            VerificationMode.fastFingerprint.title,
            VerificationMode.sizeOnly.title
        ]

        return (0..<count).map { index in
            let dayOffset = -(index % daySpan)
            let day = calendar.date(byAdding: .day, value: dayOffset, to: dayStart) ?? dayStart
            let finishedAt = day.addingTimeInterval(TimeInterval(index % 82_800))
            let success = index % 11 != 0
            let cancelled = index % 97 == 0
            let bytes = Int64(64_000_000 + (index % 240) * 8_000_000)
            let selectedFileCount = 1 + (index % 18)
            let sourceName = sourceNames[index % sourceNames.count]
            let taskName = "DIT_Stress_\(index)"

            return TransferReport(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", index + 1)) ?? UUID(),
                startedAt: finishedAt.addingTimeInterval(-TimeInterval(60 + index % 600)),
                finishedAt: finishedAt,
                sourceName: sourceName,
                sourcePath: "/Volumes/\(sourceName)",
                sourceRootPath: "/Volumes/\(sourceName)",
                targetPath: "/Volumes/Work/\(taskName)",
                backupPath: index % 3 == 0 ? "/Volumes/Backup/\(taskName)" : nil,
                selectedFileCount: selectedFileCount,
                totalBytes: bytes,
                verificationMode: verificationModes[index % verificationModes.count],
                namingRule: "Stress",
                success: success && !cancelled,
                cancelled: cancelled,
                failedFiles: success ? [] : ["clip_\(index).mov"],
                copyFailedFiles: [],
                verificationFailedFiles: success ? [] : ["clip_\(index).mov"],
                skippedFiles: [],
                verificationSummary: success ? "ok" : "failed",
                interruptionReason: cancelled ? "cancelled" : nil,
                duration: TimeInterval(30 + index % 1_200),
                reportDocumentPath: nil,
                localReportDocumentPath: nil,
                importedItems: [],
                fileRecords: []
            )
        }
    }

    private func makeDate(year: Int, month: Int, day: Int, hour: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        )))
    }
}
