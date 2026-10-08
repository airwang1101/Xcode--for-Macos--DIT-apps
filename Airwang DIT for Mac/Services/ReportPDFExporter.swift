import CoreGraphics
import CoreText
import Darwin
import Foundation

/// Exports the complete saved TXT evidence. Compact history JSON is never used
/// to reconstruct a report because it intentionally omits per-file checksums.
enum ReportPDFExporter {
    enum ExportError: LocalizedError {
        case invalidSource
        case sourceChanged
        case invalidDestination
        case destinationExists
        case renderingFailed

        var errorDescription: String? {
            switch self {
            case .invalidSource: "The original UTF-8 TXT report is unavailable or invalid."
            case .sourceChanged: "The original TXT report changed while it was being read."
            case .invalidDestination: "Choose a PDF file in an existing folder."
            case .destinationExists: "The existing file was preserved. Choose a new name."
            case .renderingFailed: "The PDF could not be rendered completely."
            }
        }
    }

    static func defaultFileName(for source: URL) -> String {
        source.deletingPathExtension().lastPathComponent + "-" + UUID().uuidString.prefix(8) + ".pdf"
    }

    @discardableResult
    static func export(sourceURL: URL, to selectedOutput: URL) throws -> Int {
        try Task.checkCancellation()
        guard selectedOutput.isFileURL, selectedOutput.pathExtension.lowercased() == "pdf" else {
            throw ExportError.invalidDestination
        }
        let manager = FileManager.default
        let parent = selectedOutput.deletingLastPathComponent().standardizedFileURL
        let output = parent.appendingPathComponent(selectedOutput.lastPathComponent, isDirectory: false)
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ExportError.invalidDestination
        }
        try PathSafety.ensureSafeWritableFileTarget(for: output, under: parent)
        guard !manager.fileExists(atPath: output.path) else { throw ExportError.destinationExists }
        let text = try readOriginalReport(sourceURL)
        try Task.checkCancellation()
        let replacement = try manager.url(
            for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: output, create: true
        )
        defer { try? manager.removeItem(at: replacement) }
        let staged = replacement.appendingPathComponent("report.pdf")
        let pages = try render(text, to: staged)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staged.path)
        let handle = try FileHandle(forWritingTo: staged)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        try Task.checkCancellation()
        try PathSafety.ensureSafeWritableFileTarget(for: output, under: parent)
        let result = staged.path.withCString { source in
            output.path.withCString { target in renamex_np(source, target, UInt32(RENAME_EXCL)) }
        }
        if result != 0 {
            if errno == EEXIST { throw ExportError.destinationExists }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return pages
    }

    private static func readOriginalReport(_ selectedSource: URL) throws -> String {
        guard selectedSource.isFileURL, selectedSource.pathExtension.lowercased() == "txt" else {
            throw ExportError.invalidSource
        }
        let parent = selectedSource.deletingLastPathComponent().standardizedFileURL
        let source = parent.appendingPathComponent(selectedSource.lastPathComponent)
        try PathSafety.ensureSafeExistingFileTarget(for: source, under: parent)
        let descriptor = source.path.withCString { open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK) }
        guard descriptor >= 0 else { throw ExportError.invalidSource }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(descriptor, &before) == 0, before.st_mode & S_IFMT == S_IFREG else {
            throw ExportError.invalidSource
        }
        let data = try handle.readToEnd() ?? Data()
        var after = stat()
        var current = stat()
        guard fstat(descriptor, &after) == 0,
              source.path.withCString({ lstat($0, &current) }) == 0,
              current.st_mode & S_IFMT == S_IFREG,
              before.st_dev == current.st_dev, before.st_ino == current.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
            throw ExportError.sourceChanged
        }
        guard let text = String(data: data, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExportError.invalidSource
        }
        return text
    }

    private static func render(_ text: String, to url: URL) throws -> Int {
        var page = CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        let metadata: [String: Any] = [
            kCGPDFContextTitle as String: "Airwang DIT Transfer Report",
            kCGPDFContextCreator as String: "Airwang DIT for Mac"
        ]
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &page, metadata as CFDictionary) else {
            throw ExportError.renderingFailed
        }
        defer { context.closePDF() }
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 9.5, nil)
        var lineBreak = CTLineBreakMode.byCharWrapping
        let paragraph = withUnsafePointer(to: &lineBreak) { pointer in
            var setting = CTParagraphStyleSetting(
                spec: .lineBreakMode, valueSize: MemoryLayout<CTLineBreakMode>.size, value: pointer
            )
            return CTParagraphStyleCreate(&setting, 1)
        }
        let content = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.12, alpha: 1),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph
        ])
        let framesetter = CTFramesetterCreateWithAttributedString(content)
        let body = CGRect(x: 42, y: 48, width: page.width - 84, height: page.height - 130)
        let path = CGPath(rect: body, transform: nil)
        var position = 0
        var pages = 0
        while position < content.length {
            try Task.checkCancellation()
            let frame = CTFramesetterCreateFrame(
                framesetter, CFRange(location: position, length: 0), path, nil
            )
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { throw ExportError.renderingFailed }
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(page)
            context.textMatrix = .identity
            drawLine("Airwang DIT", size: 16, x: 42, y: page.height - 42, in: context)
            drawLine("Complete copy of the original TXT report", size: 9, x: 42, y: page.height - 59, in: context)
            context.setStrokeColor(CGColor(gray: 0.8, alpha: 1))
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: 42, y: page.height - 70))
            context.addLine(to: CGPoint(x: page.width - 42, y: page.height - 70))
            context.strokePath()
            // Preserve the exact logical text across wrapped glyph runs. PDF
            // readers otherwise may treat short hash suffixes as a column and
            // move them ahead of their corresponding file record on extraction.
            let pageText = (content.string as NSString).substring(with: NSRange(
                location: visible.location, length: visible.length
            ))
            CGPDFContextBeginTag(context, .paragraph, [
                CGPDFTagProperty.actualText.rawValue as String: pageText
            ] as CFDictionary)
            CTFrameDraw(frame, context)
            CGPDFContextEndTag(context)
            pages += 1
            drawLine("Page \(pages)", size: 9, x: 42, y: 27, in: context)
            context.endPDFPage()
            position += visible.length
        }
        return pages
    }

    private static func drawLine(_ text: String, size: CGFloat, x: CGFloat, y: CGFloat, in context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.2, alpha: 1)
        ]
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
    }
}
