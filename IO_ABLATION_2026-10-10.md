# 读写消融与稳定性核查，2026-10-10

当前本地实现已整合扫描优化、目录取消修复和无调用旧代码清理。扫描筛选有稳定收益，核心拷贝、备份、任务保存暂未确认提速。实验中的缓冲区候选已撤回。

## 基线与保留范围

- 工作分支 `codex/dit-paper-workbench`，提交 `c45c66b9151d4da84e0317e06d61bb351f610e15`，基线同时包含已完成但尚未提交的新手引导。
- 改动前完整保存 59 个构建输入及哈希，见 `artifacts/io-ablation-2026-10-10/baseline/` 与 `baseline-input-hashes.json`。
- 本轮修改 4 个生产 Swift 文件，新增 8 项回归测试。其余 33 个应用文件与本轮基线逐字节一致，包含全部视图、字体、资源和数据模型。新手引导、Paper/Classic 选择、已有选项均保留。
- 本轮没有提交、推送、修改 GitHub、替换已安装应用或对用户真实任务数据执行测试读写。

## 实验设计

同一台 arm64 Mac，macOS 27.2（26B5101f），Xcode 27.0（27A266a）。各候选串行运行，计时使用单调时钟 DispatchTime。计时排除编译、造测试文件、挂载磁盘映像和夹具准备；拷贝计时包含实际任务阶段及报告写入。

夹具包含 10,000 个混合扩展名文件、5,001 个目录浏览条目、300 个 8 KiB 小文件、2 个 64 MiB 视频、500 个各含 3 项的任务。目标与备份为临时 HFS+ 磁盘映像，与来源构成独立逻辑卷，底层仍为同一台机器的内部存储。缓存为热缓存，没有强制清空系统缓存。

候选：

| 候选 | 单独验证的改动 | Debug 回归与工作负载 |
| --- | --- | --- |
| control | 本轮基线 | 65/65 通过 |
| scan | 提前筛选媒体类型、复用根路径解析、严格报告扫描错误 | 65/65 通过 |
| directory | 目录浅层枚举、取消传播与结果发布保护 | 65/65 通过 |
| buffer | 自适应拷贝缓冲区 | 65/65 通过，收益不足，撤回 |
| cleanup | 删除不可达旧导入及专用助手 | 65/65 通过 |
| combined | 上述候选组合，含缓冲区实验 | 65/65 通过 |
| control-repeat | 同基线再次运行 | 65/65 通过 |
| accepted | 最终采用 scan + directory + cleanup，使用原缓冲区 | 完整 176/176 通过 |

Release 先执行 control、accepted、control-repeat，又执行 accepted-repeat。最后复用已编译的两份 XCTest 包连续运行 control-paired 与 accepted-paired，避免在两者之间插入编译。两份测试包均实际执行 1 项工作负载测试并通过。全套原始样本与中位数汇总保留，包含慢于基线的结果。

## Release 实测

下表采用最后一组相邻配对实验的中位数，单位毫秒。每轮扫描 5 次、目录列举 7 次、小文件拷贝 5 次、大文件与备份各 3 次、保存和读取各 5 次。

| 工作负载 | 基线 | 最终版本 | 判断 |
| --- | ---: | ---: | --- |
| 扫描 10,000 个条目，仅视频 | 491.691 | 288.184 | 耗时减少 41.4% |
| 扫描 10,000 个条目，仅照片 | 473.237 | 215.860 | 耗时减少 54.4% |
| 扫描 10,000 个条目，仅音频 | 482.333 | 206.387 | 耗时减少 57.2% |
| 扫描 10,000 个条目，全部类型 | 531.534 | 456.360 | 耗时减少 14.1% |
| 列出 5,001 个直接条目中的 2,000 个目录 | 222.189 | 191.345 | 本轮减少 13.9%，Debug 未复现提速 |
| 拷贝 300 个 8 KiB 文件，完整 SHA-256 | 515.475 | 633.364 | 跨轮波动，未确认提速 |
| 拷贝 128 MiB，完整 SHA-256 | 279.534 | 325.243 | 跨轮波动，未确认提速 |
| 拷贝 128 MiB，快速指纹 | 253.147 | 292.299 | 跨轮波动，未确认提速 |
| 拷贝 128 MiB，仅大小 | 133.698 | 144.363 | 跨轮波动，未确认提速 |
| 拷贝 128 MiB，跳过校验 | 133.714 | 137.016 | 跨轮波动，未确认提速 |
| 备份 128 MiB，完整 SHA-256 | 282.620 | 332.628 | 跨轮波动，未确认提速 |
| 保存 500 个项目 | 73.755 | 87.962 | 跨轮波动，未确认提速 |
| 读取 500 个项目 | 24.745 | 30.273 | 跨轮波动，未确认提速 |
| 10,000 条媒体时间分组 | 10.114 | 9.801 | 跨轮波动，未确认提速 |

视频筛选在 Debug 组合实验中由约 705 ms 降至 390 ms，耗时减少约 44.7%；Release 最终配对由 491.691 ms 降至 288.184 ms，减少约 41.4%。照片、音频筛选和全部类型扫描也在复测中保持同方向收益。

拷贝与保存出现明显轮次波动，最后配对中的部分结果变慢，早期轮次又更快。没有足够证据归因于代码改动。缓冲区候选在小文件与大文件校验场景都未产生可信收益，最终保留原来的 16 MiB 拷贝缓冲区与 8 MiB 校验缓冲区。

所有扫描候选的条目、顺序、路径、大小、时间及类型清单哈希一致：`822c37974ce008add03abc559bbf0a99dbc6bb12a010f1f03ec5f2df00306d6a`。拷贝与备份均使用另行计算的来源/目标完整 SHA-256 验证，全部通过。

这些结果适用于本机合成夹具和热缓存。实体 SD/CFexpress 卡、读卡器、外接盘、冷缓存、持续大规模写入及交互界面尚未实机验收，不能用表中数值承诺实体卡速度。

## 已修复的稳定性问题

新增回归在旧代码上运行：22 项中出现 5 个预期失败，在最终代码上全部通过。

1. 已取消的空目录扫描仍返回成功。
2. 已消失的来源目录被当作扫描成功、内容为空。
3. 普通文件被作为扫描根目录接受。
4. 关闭目录选择窗口后，后台旧结果仍回写。
5. 关闭来源浏览窗口后，后台旧结果仍回写。

目录取消在旧配对实验中仍返回 2,000 项并工作约 236.5 ms；最终版本返回 0 项并在约 0.006 ms 结束。取消处理会传递到分离的后台任务；结果发布同时检查取消状态与导航版本。

扫描现在显式报告枚举、元数据读取错误，避免把未完整读取的来源当作成功。隐藏项、包、符号链接处理、扩展名与侧车文件规则、排序、Unicode 路径安全规则均保留。新测试覆盖可见直接子目录、快速导航、全部既有侧车类型和 Unicode 路径。

## 删除范围与可达性依据

`TransferService.runImport` 在应用与测试中没有调用入口。当前导入窗口经 `startImport()` 创建队列项目，执行路径为 `runPrimaryStage` 与 `runBackupStage`。旧入口及只被旧入口调用的类型、私有助手、重复报告写入重载已删除。删除前保存完整实现，删除后独立 cleanup 候选和最终完整回归通过。

以下同名方法可能还有供当前队列使用的重载；删除范围只包含旧流程的专用版本。精确代码见 `selected-changes.patch`。

| 删除的旧声明或重载 | 原声明行数 |
| --- | ---: |
| `TransferResult` | 3 |
| `runImport` | 422 |
| `makePreflightFailureResult` | 94 |
| `buildDestinations` | 7 |
| `validateDestinationSeparation` | 25 |
| `validateRelativePaths` | 5 |
| `verificationBytesForItem` | 3 |
| `cleanupInstalledCopies` | 18 |
| `ensureRequiredLocations` | 7 |
| `ensureDestinationFilesDoNotExist` | 10 |
| `fatalInterruptionReason` | 38 |
| `isPathOverlapError` | 7 |
| `copy` | 23 |
| `makeTaskFolderName` | 7 |
| `sanitizedFileNameComponent` | 22 |
| `writeReportDocument` | 174 |
| `writeReportContent` | 45 |
| `writeText` | 10 |

另删除所有活跃调用中始终为 false 或空集合的内联来源哈希分支与参数，将单层拷贝包装并入现用私有函数。来源和目标仍独立完整读取并校验 SHA-256。

`TransferService.swift` 由 3,272 行减至 2,314 行，净减少 958 行。扫描与取消修复增加 38 行，4 个生产文件合计净减少 920 行。测试新增 115 行。符号名引用扫描仅用于寻找候选，Codable、SwiftUI 回调、构建资源和模型字段没有因低文本引用次数被删除。

保留同步写入、原子安装、拒绝覆盖、路径/卷身份检查、取消、恢复重试、独立备份、全部校验模式与报告证据，存储 schema 未改变。

## 验证与证据

- 原基线完整 168 项单元测试通过；最终完整 176 项通过，0 失败、0 跳过。
- 发布工具 17 项测试通过。
- 原生 Release 编译通过，Swift/GCC warnings-as-errors；原生 Debug 的应用、单元测试及 UI 测试目标编译通过。
- Xcode 保留未依赖 AppIntents.framework 时的元数据提取提示，编译完成。UI 测试没有实际启动，未打开前台应用。
- 最终测试输入逐文件哈希记录在 `final-tested-inputs.json`，与交付生产 Swift 文件一致。
- 日志位于 `artifacts/io-ablation-2026-10-10/logs/`；全部原始计时位于 `measurements/`，中位数位于 `median-summary.json`。
- 回滚依据为本轮 `baseline/` 与 `selected-changes.patch`，包含本轮开始前的新手引导，避免覆盖已有未提交工作。

## 复现与测试隔离

`script/headless_tests.py` 准备无窗口 Swift 测试库，仅在暂存库中移除应用的 @main 声明。基准额外在暂存库暴露私有目录快照方法；Release 暂存库将 AppStorageScope 的 DEBUG 条件扩展为 DEBUG 或 SWIFT_PACKAGE，以隔离到 `/tmp/airwang-dit-unit-tests`。这些测试改写没有进入原生应用源码。

生成、Debug 消融、Release 和最后配对脚本分别为 `make_variants.py`、`run_ablation.py`、`run_release_benchmark.py`、`run_paired_benchmark.py`。它们保留本机路径，运行前应核对输出目录；配对脚本依赖先前准备的 control Release 测试包。后续基准启动环境仅保留 PATH、HOME、TMPDIR、SDKROOT、LANG、LC_ALL、DEVELOPER_DIR 及专用测试变量，避免把其他全局凭据传入测试进程。

## 可运行试用包

`Dist/io-stability-preview-0.1.1-2026101003/Airwang-DIT-IO-Stability-0.1.1-2026101003-AppleSilicon.zip` 为 Apple Silicon、macOS 14+ 原生 Release 内部试用包，版本 0.1.1，构建 2026101003。使用原 Bundle ID `com.airwang.ditformac`，沿用既有本地数据路径。

包采用临时签名，尚未完成 Developer ID 签名、公证与商业发布验收。没有自动替换已安装应用，首次启动由用户执行。包内签名、ZIP 解压回读、逐文件内容和构建输入指纹另存 package-manifest.json。
