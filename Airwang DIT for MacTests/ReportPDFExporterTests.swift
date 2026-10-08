import Foundation
import PDFKit
import XCTest
@testable import Airwang_DIT_for_Mac

final class ReportPDFExporterTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DIT-PDF-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func source(in root: URL, text: String = "SHA-256 verified\nOriginal evidence\n") throws -> URL {
        let url = root.appendingPathComponent("original.txt")
        try Data(text.utf8).write(to: url)
        return url
    }

    func testMultiPageExportRetainsUnicodeHashesAndFinalRecordWithoutChangingOriginal() throws {
        let root = try directory()
        let hash = String(repeating: "0123456789abcdef", count: 4)
        let lines = (0..<180).map { "Record \($0) 素材拍摄/文件_\($0).mov SHA-256 \(hash)" }
        let text = "START-EVIDENCE\n" + lines.joined(separator: "\n") + "\nEND-EVIDENCE"
        let original = try source(in: root, text: text)
        let before = try Data(contentsOf: original)
        let output = root.appendingPathComponent("report.pdf")
        let count = try ReportPDFExporter.export(sourceURL: original, to: output)
        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertEqual(document.pageCount, count)
        XCTAssertGreaterThan(count, 1)
        // Page decorations are separate from original evidence. Join each
        // page's body so a record wrapping across a page remains comparable.
        let extracted = try (0..<document.pageCount).map { index in
            let page = try XCTUnwrap(document.page(at: index))
            return try XCTUnwrap(page.string).filter { !$0.isWhitespace }
                .replacingOccurrences(of: "AirwangDITCompletecopyoftheoriginalTXTreport", with: "")
                .replacingOccurrences(of: "Page\(index + 1)", with: "")
        }.joined()
        for line in lines { XCTAssertTrue(extracted.contains(line.filter { !$0.isWhitespace }), line) }
        XCTAssertTrue(extracted.contains("START-EVIDENCE"))
        XCTAssertTrue(extracted.contains("END-EVIDENCE"))
        XCTAssertEqual(try Data(contentsOf: original), before)
        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testExistingDestinationIsPreserved() throws {
        let root = try directory()
        let original = try source(in: root)
        let output = root.appendingPathComponent("existing.pdf")
        let data = Data("existing customer file".utf8)
        try data.write(to: output)
        XCTAssertThrowsError(try ReportPDFExporter.export(sourceURL: original, to: output))
        XCTAssertEqual(try Data(contentsOf: output), data)
    }

    func testSymlinkDestinationAndItsTargetArePreserved() throws {
        let root = try directory()
        let original = try source(in: root)
        let target = root.appendingPathComponent("customer.pdf")
        let output = root.appendingPathComponent("link.pdf")
        let data = Data("customer original".utf8)
        try data.write(to: target)
        try FileManager.default.createSymbolicLink(at: output, withDestinationURL: target)
        XCTAssertThrowsError(try ReportPDFExporter.export(sourceURL: original, to: output))
        XCTAssertEqual(try Data(contentsOf: target), data)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: output.path), target.path)
    }

    func testDanglingSymlinkDestinationIsPreserved() throws {
        let root = try directory()
        let original = try source(in: root)
        let output = root.appendingPathComponent("dangling.pdf")
        let missing = root.appendingPathComponent("missing.pdf")
        try FileManager.default.createSymbolicLink(at: output, withDestinationURL: missing)
        XCTAssertThrowsError(try ReportPDFExporter.export(sourceURL: original, to: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: output.path), missing.path)
    }

    func testSymlinkOriginalDoesNotProduceAnExport() throws {
        let root = try directory()
        let original = try source(in: root)
        let link = root.appendingPathComponent("source-link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let output = root.appendingPathComponent("report.pdf")
        XCTAssertThrowsError(try ReportPDFExporter.export(sourceURL: link, to: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    func testSourceDirectoryAndMissingOriginalDoNotProduceAnExport() throws {
        let root = try directory()
        let output = root.appendingPathComponent("report.pdf")
        let folder = root.appendingPathComponent("folder.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for original in [folder, root.appendingPathComponent("missing.txt")] {
            XCTAssertThrowsError(try ReportPDFExporter.export(sourceURL: original, to: output))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testInvalidUTF8AndEmptyOriginalDoNotProduceAnExport() throws {
        let root = try directory()
        let original = root.appendingPathComponent("original.txt")
        let output = root.appendingPathComponent("report.pdf")
        for data in [Data([0xff, 0xfe]), Data(" \n\t".utf8)] {
            try data.write(to: original)
            XCTAssertThrowsError(try ReportPDFExporter.export(sourceURL: original, to: output))
            XCTAssertEqual(try Data(contentsOf: original), data)
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testInvalidExtensionAndMissingParentDoNotCreateFiles() throws {
        let root = try directory()
        let original = try source(in: root)
        for output in [root.appendingPathComponent("report.txt"), root.appendingPathComponent("missing/report.pdf")] {
            XCTAssertThrowsError(try ReportPDFExporter.export(sourceURL: original, to: output))
            XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        }
    }

    func testCancellationPreservesOriginalAndDoesNotPublishPDF() async throws {
        let root = try directory()
        let original = try source(in: root)
        let before = try Data(contentsOf: original)
        let output = root.appendingPathComponent("report.pdf")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ReportPDFExporter.export(sourceURL: original, to: output)
        }
        do { _ = try await task.value; XCTFail("Cancelled export must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try Data(contentsOf: original), before)
    }

    func testConcurrentExportsPublishOneCompleteDocument() async throws {
        let root = try directory()
        let original = try source(in: root, text: "COMPLETE-EVIDENCE\n" + String(repeating: "SHA-256\n", count: 150))
        let output = root.appendingPathComponent("report.pdf")
        let successCount = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<2 {
                group.addTask {
                    do { try ReportPDFExporter.export(sourceURL: original, to: output); return true }
                    catch { return false }
                }
            }
            var total = 0
            for await success in group { if success { total += 1 } }
            return total
        }
        XCTAssertEqual(successCount, 1)
        let document = try XCTUnwrap(PDFDocument(url: output))
        XCTAssertTrue(document.string?.contains("COMPLETE-EVIDENCE") == true)
        XCTAssertGreaterThan(document.pageCount, 1)
    }

    @MainActor
    func testViewModelExportProtectsQuitUntilSuccessAndClearsBusyState() async throws {
        let root = try directory()
        let original = try source(in: root)
        let output = root.appendingPathComponent("report.pdf")
        let vm = AppViewModel(dataDirectory: root)
        let id = UUID()
        vm.beginPDFReportExport(sourceURL: original, to: output, reportID: id)
        XCTAssertTrue(vm.isExportingPDFReport)
        XCTAssertTrue(vm.hasActiveFileOperations)
        XCTAssertEqual(vm.pdfReportExportID, id)
        let deadline = Date().addingTimeInterval(10)
        while vm.isExportingPDFReport && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(vm.isExportingPDFReport)
        XCTAssertFalse(vm.hasActiveFileOperations)
        XCTAssertTrue(vm.pdfReportExportStatus?.contains("1") == true)
        XCTAssertNotNil(PDFDocument(url: output))
        XCTAssertTrue(vm.copyProjects.isEmpty)
        XCTAssertTrue(vm.reports.isEmpty)
    }

    @MainActor
    func testViewModelFailurePreservesOutputAndAllowsAnotherExport() async throws {
        let root = try directory()
        let original = try source(in: root)
        let output = root.appendingPathComponent("existing.pdf")
        let before = Data("existing evidence".utf8)
        try before.write(to: output)
        let vm = AppViewModel(dataDirectory: root)
        vm.beginPDFReportExport(sourceURL: original, to: output, reportID: UUID())
        let deadline = Date().addingTimeInterval(10)
        while vm.isExportingPDFReport && Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(vm.isExportingPDFReport)
        XCTAssertEqual(vm.pdfReportExportStatus, vm.localized("已有文件已保留，请选择新名称。"))
        XCTAssertEqual(try Data(contentsOf: output), before)
        let next = root.appendingPathComponent("new.pdf")
        vm.beginPDFReportExport(sourceURL: original, to: next, reportID: UUID())
        let retryDeadline = Date().addingTimeInterval(10)
        while vm.isExportingPDFReport && Date() < retryDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(vm.isExportingPDFReport)
        XCTAssertNotNil(PDFDocument(url: next))
    }
}
