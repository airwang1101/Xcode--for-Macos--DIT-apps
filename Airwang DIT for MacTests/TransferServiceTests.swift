import Foundation
import XCTest
@testable import Airwang_DIT_for_Mac

/// 针对核心拷贝/校验引擎 `TransferService` 的端到端测试。
///
/// 这是产品的命根子：拷贝绝不能丢/不能损坏。测试通过公开接口
/// (`runPrimaryStage` / `runBackupStage`) 在真实文件系统上验证拷贝、各校验模式、
/// 缺源文件、路径穿越防护与备份镜像。私有方法 (copyFile/checksum/verifyProjectFile)
/// 通过公开接口间接覆盖。
///
/// 关键约束：引擎的安全预检会**拒绝源盘与目标盘同处一个磁盘卷**(避免把素材写回源卡)，
/// 因此凡是要真正触发拷贝的用例，目标盘必须是一个独立卷。这里用 `hdiutil` 临时挂载
/// 一个磁盘镜像作为独立目标/备份卷；环境不支持时 (`XCTSkip`) 跳过而非误判失败。
final class TransferServiceTests: XCTestCase {

    // MARK: - 正常路径（需要独立目标卷）

    func testPrimaryStageCopiesAndVerifiesWithSHA256() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷（hdiutil 不可用），跳过端到端拷贝测试。")
        }
        defer { volume.detach() }

        let dataA = Data((0..<4096).map { UInt8($0 % 251) })
        let dataB = Data("hello dit".utf8)
        try writeFile(dataA, to: source.appendingPathComponent("clipA.mov"))
        try writeFile(dataB, to: source.appendingPathComponent("day1/clipB.mov"))

        let items = [
            mediaItem(sourceRoot: source, relativePath: "clipA.mov", data: dataA),
            mediaItem(sourceRoot: source, relativePath: "day1/clipB.mov", data: dataB)
        ]
        let project = makeProject(source: source, target: volume.mount, backup: nil, items: items, mode: .sha256)

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertTrue(result.report.success, "SHA-256 正常路径应成功：\(result.report.verificationSummary)")
        XCTAssertEqual(result.finalState.copiedFiles, 2)
        XCTAssertTrue(result.report.copyFailedFiles.isEmpty)
        XCTAssertTrue(result.report.verificationFailedFiles.isEmpty)
        XCTAssertEqual(result.report.selectedFileCount, 2)

        let targetA = project.primaryImportURL.appendingPathComponent("clipA.mov")
        let targetB = project.primaryImportURL.appendingPathComponent("day1/clipB.mov")
        XCTAssertEqual(try Data(contentsOf: targetA), dataA, "主盘文件内容应与源一致")
        XCTAssertEqual(try Data(contentsOf: targetB), dataB, "子目录文件应保留相对路径并内容一致")
    }

    func testSizeOnlyAndFingerprintSucceedOnGoodCopy() async throws {
        for mode in [VerificationMode.sizeOnly, .fastFingerprint] {
            let source = try makeTempDir(); defer { cleanup(source) }
            guard let volume = try makeSeparateVolume() else {
                throw XCTSkip("无法创建独立测试卷，跳过。")
            }
            defer { volume.detach() }

            let data = Data((0..<200_000).map { UInt8($0 % 255) })
            try writeFile(data, to: source.appendingPathComponent("a.mov"))
            let items = [mediaItem(sourceRoot: source, relativePath: "a.mov", data: data)]
            let project = makeProject(source: source, target: volume.mount, backup: nil, items: items, mode: mode)

            let result = try await TransferService().runPrimaryStage(project: project) { _ in }

            XCTAssertTrue(result.report.success, "\(mode.rawValue) 在正常拷贝下应成功")
            XCTAssertEqual(
                try Data(contentsOf: project.primaryImportURL.appendingPathComponent("a.mov")),
                data
            )
        }
    }

    func testSkippedVerificationStillCopiesFiles() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let data = Data("skip me".utf8)
        try writeFile(data, to: source.appendingPathComponent("a.mov"))
        let items = [mediaItem(sourceRoot: source, relativePath: "a.mov", data: data)]
        let project = makeProject(source: source, target: volume.mount, backup: nil, items: items, mode: .skipped)

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertEqual(result.finalState.copiedFiles, 1, "跳过校验仍应完成拷贝")
        XCTAssertTrue(result.report.copyFailedFiles.isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: project.primaryImportURL.appendingPathComponent("a.mov")),
            data
        )
    }

    // MARK: - 失败与安全

    func testMissingSourceFileIsReportedAsFailure() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        // 声明了一个项目素材，但故意不在源盘创建它。
        let ghost = ProjectMediaItem(
            id: "ghost",
            filePath: source.appendingPathComponent("ghost.mov").path,
            relativePath: "ghost.mov",
            displayName: "ghost.mov",
            createdAt: Date(timeIntervalSince1970: 0),
            size: 1024,
            mediaKindRawValue: ScanFilter.video.rawValue
        )
        let project = makeProject(source: source, target: volume.mount, backup: nil, items: [ghost], mode: .sha256)

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertFalse(result.report.success, "缺失源文件不应被判为成功")
        XCTAssertTrue(result.report.failedFiles.contains("ghost.mov"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: project.primaryImportURL.appendingPathComponent("ghost.mov").path),
            "失败的文件不应在目标盘留下产物"
        )
    }

    func testPathTraversalRelativePathIsRejected() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let data = Data("evil".utf8)
        try writeFile(data, to: source.appendingPathComponent("real.mov"))

        // relativePath 试图用 "../" 逃逸出任务文件夹。
        let evil = ProjectMediaItem(
            id: "evil",
            filePath: source.appendingPathComponent("real.mov").path,
            relativePath: "../escape.mov",
            displayName: "escape.mov",
            createdAt: Date(timeIntervalSince1970: 0),
            size: Int64(data.count),
            mediaKindRawValue: ScanFilter.video.rawValue
        )
        let project = makeProject(source: source, target: volume.mount, backup: nil, items: [evil], mode: .sha256)

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertFalse(result.report.success, "路径穿越必须被拒绝，不能判为成功")
        // "../escape.mov" 相对任务文件夹 (volume/Task) 会指向 volume/escape.mov。
        let escapeURL = volume.mount.appendingPathComponent("escape.mov")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: escapeURL.path),
            "不能在任务文件夹之外写入任何文件"
        )
    }

    /// 安全预检：源盘与目标盘同处一个磁盘卷必须被拒绝（避免把素材写回源卡/同盘）。
    /// 此用例不需要独立卷——同卷正是它要触发的条件，因此确定性强、运行快。
    func testSameVolumeSourceAndTargetIsRejected() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        let target = try makeTempDir(); defer { cleanup(target) }  // 与 source 同卷（都在临时目录）

        let data = Data("same volume".utf8)
        try writeFile(data, to: source.appendingPathComponent("a.mov"))
        let items = [mediaItem(sourceRoot: source, relativePath: "a.mov", data: data)]
        let project = makeProject(source: source, target: target, backup: nil, items: items, mode: .sha256)

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertFalse(result.report.success, "源盘与目标盘同卷必须被安全预检拒绝")
        XCTAssertEqual(result.finalState.copiedFiles, 0, "被拒绝时不应发生任何拷贝")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: project.primaryImportURL.appendingPathComponent("a.mov").path)
        )
    }

    // MARK: - 备份阶段（需要两个互相独立、且独立于源的卷）

    func testBackupStageMirrorsPrimary() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let primaryVolume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { primaryVolume.detach() }
        guard let backupVolume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建第二个独立测试卷，跳过。")
        }
        defer { backupVolume.detach() }

        let data = Data((0..<10_000).map { UInt8($0 % 200) })
        try writeFile(data, to: source.appendingPathComponent("a.mov"))
        let items = [mediaItem(sourceRoot: source, relativePath: "a.mov", data: data)]
        let project = makeProject(
            source: source,
            target: primaryVolume.mount,
            backup: backupVolume.mount,
            items: items,
            mode: .sha256
        )

        let service = TransferService()
        let primary = try await service.runPrimaryStage(project: project) { _ in }
        XCTAssertTrue(primary.report.success, "主盘阶段应先成功：\(primary.report.verificationSummary)")

        let backupResult = try await service.runBackupStage(project: project) { _ in }
        XCTAssertTrue(backupResult.report.success, "备份阶段应通过校验：\(backupResult.report.verificationSummary)")

        let backupFile = try XCTUnwrap(project.backupImportURL).appendingPathComponent("a.mov")
        XCTAssertEqual(try Data(contentsOf: backupFile), data, "备份盘文件应与源一致")
    }

    // MARK: - 中断 / 鲁棒性 / 混合结果

    /// 安全：携带"已停止"中断令牌时，拷贝必须在写盘前中止，不留下半成品。
    func testInterruptionTokenAbortsCopy() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let data = Data((0..<8192).map { UInt8($0 % 233) })
        try writeFile(data, to: source.appendingPathComponent("a.mov"))
        let items = [mediaItem(sourceRoot: source, relativePath: "a.mov", data: data)]
        let project = makeProject(source: source, target: volume.mount, backup: nil, items: items, mode: .sha256)

        let token = ImportInterruptionToken()
        token.stop(reason: "测试触发的中断")

        let result = try await TransferService().runPrimaryStage(project: project, interruptionToken: token) { _ in }

        XCTAssertFalse(result.report.success, "已中断的任务不应判为成功")
        XCTAssertEqual(result.finalState.copiedFiles, 0, "中断后不应有文件被计入已拷贝")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: project.primaryImportURL.appendingPathComponent("a.mov").path),
            "中断不应在目标盘留下半成品"
        )
    }

    func testInterruptedPartialCopyRollsBackProcessedBytes() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let data = Data(repeating: 0xA5, count: 32 * 1024 * 1024)
        try writeFile(data, to: source.appendingPathComponent("large.mov"))
        let project = makeProject(
            source: source,
            target: volume.mount,
            backup: nil,
            items: [mediaItem(sourceRoot: source, relativePath: "large.mov", data: data)],
            mode: .sha256
        )
        let token = ImportInterruptionToken()

        let result = try await TransferService().runPrimaryStage(
            project: project,
            interruptionToken: token
        ) { state in
            if state.processedBytes > 0, state.copiedFiles == 0 {
                token.stop(reason: "测试中断部分文件")
            }
        }

        XCTAssertFalse(result.report.success)
        XCTAssertEqual(result.finalState.copiedFiles, 0)
        XCTAssertEqual(result.finalState.processedBytes, 0, "已删除的临时文件字节不应保留在完成进度中")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: project.primaryImportURL.appendingPathComponent("large.mov").path)
        )
    }

    /// 锁定行为：扫描时记录的 size 与拷贝时实际不一致（文件在扫描后被改动）时，
    /// 引擎应按实际字节完整拷贝并通过校验，不因 size 陈旧而误报失败。
    /// 对应 `copyFile` 中"对比实际读取字节数而非 expectedSize"的设计。
    func testStaleScanSizeStillCopiesByteComplete() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let data = Data((0..<4096).map { UInt8($0 % 251) })
        let fileURL = source.appendingPathComponent("a.mov")
        try writeFile(data, to: fileURL)
        // 故意把声明 size 设得远大于真实大小（模拟扫描后文件变小）；仍需 < 卷可用空间。
        let staleItem = ProjectMediaItem(
            id: fileURL.path,
            filePath: fileURL.path,
            relativePath: "a.mov",
            displayName: "a.mov",
            createdAt: Date(timeIntervalSince1970: 0),
            size: 1_000_000,
            mediaKindRawValue: ScanFilter.video.rawValue
        )
        let project = makeProject(source: source, target: volume.mount, backup: nil, items: [staleItem], mode: .sha256)

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertTrue(result.report.success, "实际字节完整拷贝应成功，不应因陈旧 size 误报：\(result.report.verificationSummary)")
        XCTAssertEqual(
            try Data(contentsOf: project.primaryImportURL.appendingPathComponent("a.mov")),
            data,
            "目标内容应与源实际内容一致"
        )
    }

    func testSpacePreflightUsesLiveSourceSizeWhenScanSizeIsSmaller() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume(size: "1200m") else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let available = try XCTUnwrap(DiskCapacityResolver.capacity(for: volume.mount).availableCapacity)
        guard available > SpacePreflightPolicy.minimumSafetyMarginBytes + 20_000_000 else {
            throw XCTSkip("测试卷可用空间不足以构造扫描大小陈旧场景。")
        }
        let liveSize = available - SpacePreflightPolicy.minimumSafetyMarginBytes + 50_000_000
        let sourceURL = source.appendingPathComponent("grown.mov")
        try writeSparseFile(size: liveSize, to: sourceURL)
        let staleItem = ProjectMediaItem(
            id: sourceURL.path,
            filePath: sourceURL.path,
            relativePath: "grown.mov",
            displayName: "grown.mov",
            createdAt: Date(timeIntervalSince1970: 0),
            size: 1,
            mediaKindRawValue: ScanFilter.video.rawValue
        )
        let project = makeProject(
            source: source,
            target: volume.mount,
            backup: nil,
            items: [staleItem],
            mode: .sizeOnly,
            taskFolder: "LiveSize-\(UUID().uuidString.prefix(8))"
        )

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertFalse(result.report.success)
        XCTAssertEqual(result.finalState.copiedFiles, 0)
        XCTAssertTrue(result.report.verificationSummary.contains("空间不足"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: project.primaryImportURL.appendingPathComponent("grown.mov").path)
        )
    }

    /// 锁定「当前真实行为」（存在产品决策待定，见下）：批量拷贝遇到**缺失的源文件**时，
    /// 引擎把它当作「源文件断开」按**致命中断**处理（`ensureAvailable` 抛 `deviceUnavailable`
    /// → `fatalInterruptionReason` 判致命），从而中止本批后续、整体判失败，并把缺失文件
    /// 之前**已成功拷贝**的文件标记为「未校验」。关键保证：已落盘的数据**不回滚**，仍完整。
    ///
    /// ⚠️ 待产品确认：单个文件缺失是否应等同于「整卡掉线」中止整批？对大批量离线，
    /// 这意味着可能因 1 个坏/缺文件停在第 3/5000。若决定改为「逐文件失败并继续」，
    /// 需同步更新本测试与 `ensureAvailable`/`fatalInterruptionReason` 的分类。
    /// M5：源根仍在、单个源文件缺失 → 记为单文件失败并继续，不中断整批。
    func testMissingSingleSourceFileRecordsFailureAndContinues() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let dataA = Data((0..<5000).map { UInt8($0 % 200) })
        let dataB = Data((0..<5000).map { UInt8(($0 + 7) % 200) })
        try writeFile(dataA, to: source.appendingPathComponent("good.mov"))
        try writeFile(dataB, to: source.appendingPathComponent("good2.mov"))
        let good = mediaItem(sourceRoot: source, relativePath: "good.mov", data: dataA)
        // ghost 夹在两个正常文件中间，且故意不在源盘创建。
        let ghost = ProjectMediaItem(
            id: "ghost",
            filePath: source.appendingPathComponent("ghost.mov").path,
            relativePath: "ghost.mov",
            displayName: "ghost.mov",
            createdAt: Date(timeIntervalSince1970: 0),
            size: 5000,
            mediaKindRawValue: ScanFilter.video.rawValue
        )
        let good2 = mediaItem(sourceRoot: source, relativePath: "good2.mov", data: dataB)
        let project = makeProject(source: source, target: volume.mount, backup: nil, items: [good, ghost, good2], mode: .sha256)

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertFalse(result.report.success, "存在缺失文件时整体应判失败")
        XCTAssertNil(result.report.interruptionReason, "单文件缺失（源根仍在）不应被当作致命中断")
        XCTAssertTrue(result.report.copyFailedFiles.contains("ghost.mov"), "缺失文件应记为拷贝失败")

        // 关键：ghost 之后的 good2 仍应被继续处理并完整落盘。
        let goodTarget = project.primaryImportURL.appendingPathComponent("good.mov")
        let good2Target = project.primaryImportURL.appendingPathComponent("good2.mov")
        XCTAssertEqual(try Data(contentsOf: goodTarget), dataA, "缺失文件之前的文件应完整")
        XCTAssertEqual(try Data(contentsOf: good2Target), dataB, "缺失文件之后的文件应继续拷贝并完整")
        XCTAssertEqual(result.finalState.copiedFiles, 2, "应有 2 个文件成功拷贝")
    }

    /// M5：源根（源设备）丢失 → 立即致命中断整阶段。这里用进度回调模拟“拷到一半拔卡”。
    func testMissingSourceRootInterruptsWholeStage() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let dataA = Data((0..<5000).map { UInt8($0 % 200) })
        let dataB = Data((0..<5000).map { UInt8(($0 + 7) % 200) })
        try writeFile(dataA, to: source.appendingPathComponent("a.mov"))
        try writeFile(dataB, to: source.appendingPathComponent("b.mov"))
        let items = [
            mediaItem(sourceRoot: source, relativePath: "a.mov", data: dataA),
            mediaItem(sourceRoot: source, relativePath: "b.mov", data: dataB)
        ]
        let project = makeProject(source: source, target: volume.mount, backup: nil, items: items, mode: .sha256)

        let sourcePath = source.path
        let result = try await TransferService().runPrimaryStage(project: project) { state in
            // 第一个文件拷完后，模拟源盘被整体拔出：删除源根目录。
            if state.copiedFiles >= 1 {
                try? FileManager.default.removeItem(atPath: sourcePath)
            }
        }

        XCTAssertFalse(result.report.success, "源根丢失整体应判失败")
        XCTAssertNotNil(result.report.interruptionReason, "源根（源设备）丢失必须触发致命中断")
    }

    func testDestinationCollisionAfterPreflightStopsRemainingFiles() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let firstData = Data("first".utf8)
        let secondData = Data("second".utf8)
        let thirdData = Data("third".utf8)
        try writeFile(firstData, to: source.appendingPathComponent("a.mov"))
        try writeFile(secondData, to: source.appendingPathComponent("b.mov"))
        try writeFile(thirdData, to: source.appendingPathComponent("c.mov"))
        let items = [
            mediaItem(sourceRoot: source, relativePath: "a.mov", data: firstData),
            mediaItem(sourceRoot: source, relativePath: "b.mov", data: secondData),
            mediaItem(sourceRoot: source, relativePath: "c.mov", data: thirdData)
        ]
        let project = makeProject(
            source: source,
            target: volume.mount,
            backup: nil,
            items: items,
            mode: .sizeOnly,
            taskFolder: "RuntimeCollision-\(UUID().uuidString.prefix(8))"
        )
        let collisionURL = project.primaryImportURL.appendingPathComponent("b.mov")
        let thirdTargetURL = project.primaryImportURL.appendingPathComponent("c.mov")

        let result = try await TransferService().runPrimaryStage(project: project) { state in
            if state.copiedFiles == 1,
               !FileManager.default.fileExists(atPath: collisionURL.path) {
                _ = FileManager.default.createFile(
                    atPath: collisionURL.path,
                    contents: Data("external payload".utf8)
                )
            }
        }

        XCTAssertFalse(result.report.success)
        XCTAssertNotNil(result.report.interruptionReason, "运行期目标冲突必须停止阶段")
        XCTAssertTrue(result.report.copyFailedFiles.contains("b.mov"))
        XCTAssertTrue(result.report.skippedFiles.contains("c.mov"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thirdTargetURL.path))
    }

    func testPathSafetyFailureAfterPreflightStopsRemainingFiles() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        let external = try makeTempDir(); defer { cleanup(external) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let firstData = Data("first".utf8)
        let secondData = Data("second".utf8)
        let thirdData = Data("third".utf8)
        try writeFile(firstData, to: source.appendingPathComponent("a.mov"))
        try writeFile(secondData, to: source.appendingPathComponent("redirected/b.mov"))
        try writeFile(thirdData, to: source.appendingPathComponent("c.mov"))
        let items = [
            mediaItem(sourceRoot: source, relativePath: "a.mov", data: firstData),
            mediaItem(sourceRoot: source, relativePath: "redirected/b.mov", data: secondData),
            mediaItem(sourceRoot: source, relativePath: "c.mov", data: thirdData)
        ]
        let project = makeProject(
            source: source,
            target: volume.mount,
            backup: nil,
            items: items,
            mode: .sizeOnly,
            taskFolder: "RuntimeSymlink-\(UUID().uuidString.prefix(8))"
        )
        let symlinkURL = project.primaryImportURL.appendingPathComponent("redirected", isDirectory: true)
        let thirdTargetURL = project.primaryImportURL.appendingPathComponent("c.mov")

        let result = try await TransferService().runPrimaryStage(project: project) { state in
            if state.copiedFiles == 1,
               !FileManager.default.fileExists(atPath: symlinkURL.path) {
                try? FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: external)
            }
        }

        XCTAssertFalse(result.report.success)
        XCTAssertNotNil(result.report.interruptionReason, "运行期路径安全失败必须停止阶段")
        XCTAssertTrue(result.report.skippedFiles.contains("c.mov"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: thirdTargetURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: external.appendingPathComponent("b.mov").path))
    }

    /// M5：非缺失的单文件读失败（源根仍在）也应记为单文件失败并继续。
    /// 用“目录冒充文件”制造可靠的读失败：路径存在但无法作为普通文件读取。
    func testReadErrorRecordsSingleFileFailureWhenRootStillAvailable() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let goodData = Data((0..<5000).map { UInt8($0 % 200) })
        try writeFile(goodData, to: source.appendingPathComponent("good.mov"))
        // bad.mov 是一个目录：它“存在”，但作为文件读取会失败（EISDIR）。
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("bad.mov", isDirectory: true),
            withIntermediateDirectories: true
        )
        let bad = ProjectMediaItem(
            id: "bad",
            filePath: source.appendingPathComponent("bad.mov").path,
            relativePath: "bad.mov",
            displayName: "bad.mov",
            createdAt: Date(timeIntervalSince1970: 0),
            size: 5000,
            mediaKindRawValue: ScanFilter.video.rawValue
        )
        let good = mediaItem(sourceRoot: source, relativePath: "good.mov", data: goodData)
        // bad 在前失败，good 在后仍应完成。
        let project = makeProject(source: source, target: volume.mount, backup: nil, items: [bad, good], mode: .sha256)

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertFalse(result.report.success)
        XCTAssertNil(result.report.interruptionReason, "单文件读失败（源根仍在）不应致命中断")
        XCTAssertTrue(result.report.copyFailedFiles.contains("bad.mov"), "读失败文件应记为拷贝失败")
        XCTAssertEqual(
            try Data(contentsOf: project.primaryImportURL.appendingPathComponent("good.mov")),
            goodData,
            "读失败文件之后的文件应继续拷贝并完整"
        )
    }

    func testPrimaryStageFailsWhenDestinationFileAlreadyExists() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let sourceData = Data("new source payload".utf8)
        let existingData = Data("existing destination payload".utf8)
        try writeFile(sourceData, to: source.appendingPathComponent("a.mov"))
        let taskFolder = "ExistingPrimary-\(UUID().uuidString.prefix(8))"
        let project = makeProject(
            source: source,
            target: volume.mount,
            backup: nil,
            items: [mediaItem(sourceRoot: source, relativePath: "a.mov", data: sourceData)],
            mode: .sha256,
            taskFolder: taskFolder
        )
        let destination = project.primaryImportURL.appendingPathComponent("a.mov")
        try writeFile(existingData, to: destination)

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertFalse(result.report.success)
        XCTAssertEqual(try Data(contentsOf: destination), existingData, "既有目标文件必须保持原内容")
        XCTAssertTrue(result.report.verificationSummary.contains("目标文件已存在"))
        let localReportPath = try XCTUnwrap(result.report.localReportDocumentPath)
        let localReport = try String(contentsOfFile: localReportPath, encoding: .utf8)
        XCTAssertTrue(localReport.contains("失败类型: 目标文件已存在"))
        XCTAssertTrue(localReport.contains("处理建议: 改项目名、更换目标目录或人工确认后重试"))
    }

    func testBackupStageFailsWhenDestinationFileAlreadyExists() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let primaryVolume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建主目标测试卷，跳过。")
        }
        defer { primaryVolume.detach() }
        guard let backupVolume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建备份测试卷，跳过。")
        }
        defer { backupVolume.detach() }

        let sourceData = Data("primary payload".utf8)
        let existingData = Data("existing backup payload".utf8)
        try writeFile(sourceData, to: source.appendingPathComponent("a.mov"))
        let project = makeProject(
            source: source,
            target: primaryVolume.mount,
            backup: backupVolume.mount,
            items: [mediaItem(sourceRoot: source, relativePath: "a.mov", data: sourceData)],
            mode: .sha256,
            taskFolder: "ExistingBackup-\(UUID().uuidString.prefix(8))"
        )
        let primaryResult = try await TransferService().runPrimaryStage(project: project) { _ in }
        XCTAssertTrue(primaryResult.report.success)

        let backupDestination = try XCTUnwrap(project.backupImportURL).appendingPathComponent("a.mov")
        try writeFile(existingData, to: backupDestination)

        let result = try await TransferService().runBackupStage(project: project) { _ in }

        XCTAssertFalse(result.report.success)
        XCTAssertEqual(try Data(contentsOf: backupDestination), existingData, "既有备份文件必须保持原内容")
        XCTAssertTrue(result.report.verificationSummary.contains("目标文件已存在"))
    }

    func testRejectExistingDestinationSymlink() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        let external = try makeTempDir(); defer { cleanup(external) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let sourceData = Data("source payload".utf8)
        let protectedData = Data("protected payload".utf8)
        try writeFile(sourceData, to: source.appendingPathComponent("a.mov"))
        let protectedURL = external.appendingPathComponent("protected.mov")
        try writeFile(protectedData, to: protectedURL)
        let project = makeProject(
            source: source,
            target: volume.mount,
            backup: nil,
            items: [mediaItem(sourceRoot: source, relativePath: "a.mov", data: sourceData)],
            mode: .sha256,
            taskFolder: "SymlinkFile-\(UUID().uuidString.prefix(8))"
        )
        try FileManager.default.createDirectory(at: project.primaryImportURL, withIntermediateDirectories: true)
        let destination = project.primaryImportURL.appendingPathComponent("a.mov")
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: protectedURL)

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertFalse(result.report.success)
        XCTAssertEqual(try Data(contentsOf: protectedURL), protectedData)
        let localReportPath = try XCTUnwrap(result.report.localReportDocumentPath)
        let localReport = try String(contentsOfFile: localReportPath, encoding: .utf8)
        XCTAssertTrue(localReport.contains("失败类型: 路径安全检查失败"))
        XCTAssertFalse(localReport.contains("[预检]\n结果: 通过"))
    }

    func testRejectDestinationInsideSymlinkAncestor() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let sourceData = Data("nested payload".utf8)
        try writeFile(sourceData, to: source.appendingPathComponent("day1/a.mov"))
        let project = makeProject(
            source: source,
            target: volume.mount,
            backup: nil,
            items: [mediaItem(sourceRoot: source, relativePath: "day1/a.mov", data: sourceData)],
            mode: .sha256,
            taskFolder: "SymlinkAncestor-\(UUID().uuidString.prefix(8))"
        )
        let redirectDirectory = volume.mount.appendingPathComponent("redirect", isDirectory: true)
        try FileManager.default.createDirectory(at: redirectDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project.primaryImportURL, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: project.primaryImportURL.appendingPathComponent("day1", isDirectory: true),
            withDestinationURL: redirectDirectory
        )

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertFalse(result.report.success)
        XCTAssertFalse(FileManager.default.fileExists(atPath: redirectDirectory.appendingPathComponent("a.mov").path))
    }

    func testRejectExistingDestinationDirectory() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let sourceData = Data("source payload".utf8)
        try writeFile(sourceData, to: source.appendingPathComponent("a.mov"))
        let project = makeProject(
            source: source,
            target: volume.mount,
            backup: nil,
            items: [mediaItem(sourceRoot: source, relativePath: "a.mov", data: sourceData)],
            mode: .sha256,
            taskFolder: "ExistingDirectory-\(UUID().uuidString.prefix(8))"
        )
        let destination = project.primaryImportURL.appendingPathComponent("a.mov", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertFalse(result.report.success)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testReportWriterDoesNotOverwriteExistingReport() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let sourceData = Data("report collision payload".utf8)
        try writeFile(sourceData, to: source.appendingPathComponent("a.mov"))
        let taskFolder = "ReportCollision-\(UUID().uuidString.prefix(8))"
        let project = makeProject(
            source: source,
            target: volume.mount,
            backup: nil,
            items: [mediaItem(sourceRoot: source, relativePath: "a.mov", data: sourceData)],
            mode: .sha256,
            taskFolder: taskFolder
        )
        let existingReport = project.primaryImportURL
            .appendingPathComponent("Airwang_Primary_Copy_Report_\(taskFolder).txt")
        let originalReportData = Data("existing report must remain unchanged".utf8)
        try writeFile(originalReportData, to: existingReport)

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertTrue(result.report.success)
        XCTAssertEqual(try Data(contentsOf: existingReport), originalReportData)
        XCTAssertNotEqual(result.report.reportDocumentPath, existingReport.path)
        XCTAssertNotNil(result.report.reportDocumentPath)
    }

    func testTextReportContainsSpacePreflightDetails() async throws {
        let source = try makeTempDir(); defer { cleanup(source) }
        guard let volume = try makeSeparateVolume() else {
            throw XCTSkip("无法创建独立测试卷，跳过。")
        }
        defer { volume.detach() }

        let sourceData = Data("space report payload".utf8)
        try writeFile(sourceData, to: source.appendingPathComponent("a.mov"))
        let project = makeProject(
            source: source,
            target: volume.mount,
            backup: nil,
            items: [mediaItem(sourceRoot: source, relativePath: "a.mov", data: sourceData)],
            mode: .sizeOnly,
            taskFolder: "SpaceReport-\(UUID().uuidString.prefix(8))"
        )

        let result = try await TransferService().runPrimaryStage(project: project) { _ in }

        XCTAssertTrue(result.report.success)
        let reportPath = try XCTUnwrap(result.report.reportDocumentPath)
        let report = try String(contentsOfFile: reportPath, encoding: .utf8)
        XCTAssertTrue(report.contains("[空间预检]"))
        XCTAssertTrue(report.contains("素材总量:"))
        XCTAssertTrue(report.contains("安全冗余:"))
        XCTAssertTrue(report.contains("最低需求:"))
        XCTAssertTrue(report.contains("可用空间:"))
        XCTAssertTrue(report.contains("预检结果: 通过"))
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("AirwangXfer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func writeFile(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }

    private func writeSparseFile(size: Int64, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(size))
    }

    private func mediaItem(sourceRoot: URL, relativePath: String, data: Data) -> ProjectMediaItem {
        let fileURL = sourceRoot.appendingPathComponent(relativePath)
        return ProjectMediaItem(
            id: fileURL.path,
            filePath: fileURL.path,
            relativePath: relativePath,
            displayName: fileURL.lastPathComponent,
            createdAt: Date(timeIntervalSince1970: 0),
            size: Int64(data.count),
            mediaKindRawValue: ScanFilter.video.rawValue
        )
    }

    private func makeProject(
        source: URL,
        target: URL,
        backup: URL?,
        items: [ProjectMediaItem],
        mode: VerificationMode,
        taskFolder: String = "Task"
    ) -> CopyProject {
        CopyProject(
            name: "Test",
            taskFolderName: taskFolder,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            sourceName: "Card",
            sourceVolumePath: source.path,
            sourceRootPath: source.path,
            targetRootPath: target.path,
            backupRootPath: backup?.path,
            selectedItems: items,
            totalBytes: items.reduce(Int64(0)) { $0 + $1.size },
            verificationMode: mode,
            orderIndex: 0
        )
    }

    /// 用 hdiutil 创建并挂载一个独立的临时磁盘卷，作为目标/备份盘，
    /// 以满足「目标盘必须与源盘不同卷」的安全预检。
    /// 返回挂载点与一个 detach 闭包；环境不支持时返回 nil（调用方应 XCTSkip）。
    private func makeSeparateVolume(size: String = "2g") throws -> (mount: URL, detach: () -> Void)? {
        let fileManager = FileManager.default
        let token = String(UUID().uuidString.prefix(8))
        let dmgPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("AirwangVol-\(token).sparseimage")
        let mountPath = (NSTemporaryDirectory() as NSString).appendingPathComponent("AirwangMnt-\(token)")

        func hdiutil(_ arguments: [String]) -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                return false
            }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }

        guard hdiutil(["create", "-size", size, "-type", "SPARSE", "-fs", "HFS+", "-volname", "Airwang\(token)", "-quiet", dmgPath]) else {
            return nil
        }
        try? fileManager.createDirectory(atPath: mountPath, withIntermediateDirectories: true)
        guard hdiutil(["attach", dmgPath, "-mountpoint", mountPath, "-nobrowse", "-quiet"]) else {
            try? fileManager.removeItem(atPath: dmgPath)
            try? fileManager.removeItem(atPath: mountPath)
            return nil
        }

        let detach: () -> Void = {
            _ = hdiutil(["detach", mountPath, "-force", "-quiet"])
            try? fileManager.removeItem(atPath: dmgPath)
            try? fileManager.removeItem(atPath: mountPath)
        }
        return (URL(fileURLWithPath: mountPath, isDirectory: true), detach)
    }
}
