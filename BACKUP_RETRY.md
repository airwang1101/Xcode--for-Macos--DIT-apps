# 独立备份重试 / Independent backup retry

## 使用方式

主盘拷贝和校验已完成，并且完成记录含有完整文件明细时，复制队列或备份页会显示“仅重试备份”。原有“重试”继续保留，会从源设备重新执行主盘和备份流程。

1. 连接已完成的主盘与备份盘。原始源卡可以拔出。
2. 点击“仅重试备份”。主盘完成状态、文件夹与原报告保留。
3. 检查主盘和备份路径，再手动执行任务队列。若手动队列已经运行，它会继续处理新加入的项目。
4. 查看本次备份报告，其中引用原主盘报告，记录主盘复核结果、已有文件复用及新增拷贝数量。

重试前按原报告的校验策略重新读取主盘。原报告为 SHA-256 时执行全量校验；快速指纹沿用原抽样策略；大小校验和跳过模式核对文件大小。这些模式原有的完整性限制与警告继续保留。曾通过恢复流程复用的主盘文件，保留其更强的 SHA-256 证据。

已有备份文件通过完整 SHA-256 比对后才能复用。缺失文件补拷，并采用当前项目选择的策略。同名文件内容不一致时保留现有文件并报告异常。主盘在复核、复制或校验期间变化时，任务停止；主盘完成状态保留，本次文件与报告保留供检查。

独立重试排队期间改名只影响显示名称和后续报告标题。取消备份配置会恢复为主盘已完成的项目，不会重新读取源卡。取消正在执行的任务需要等待报告生成和文件操作收尾。

## 完成记录与旧版本

新完成的主盘在项目中保存完整校验记录，应用日志继续使用原有精简存储格式。重启后仍可复核主盘。旧项目缺少完整成功明细时，重新连接原始源设备，使用原有“重试”建立新的完成记录。

项目存储格式升级为 v2。首次保存旧格式前，在同一目录保留独立的 `copy-projects.before-v2-<UUID>.json` 原始备份，后续保存不会替换它。原有滚动 `.bak.json` 机制保留。已具有较新格式保护的旧版本会拒绝读取或覆盖 v2；更早版本的保护能力和跨实际版本回退仍需验收。请先保存应用数据备份，再降级。

完整校验记录含素材相对文件名和校验值，保存在本地项目文件中。诊断导出继续排除这些字段，不会自动上传。

## English

When primary copy and verification have completed with full file evidence, choose **Retry Backup Only** in the copy queue or backup workspace. Connect the completed primary and backup drives, review their paths, and start the queue. The original card may be disconnected. A manual queue already running can continue with the newly queued retry.

The primary is checked against its original report before backup writes begin. Full SHA-256, the original fingerprint sampling policy, and size-based checks retain their existing guarantees and warnings. Files recovered during the primary stage retain their per-file full SHA-256 evidence. Existing backup files require full SHA-256 verification for reuse; missing files use the project's selected mode. Conflicting files are preserved and reported.

The retry retains the completed primary state, folder, and original report. Renaming preserves the physical folder. Removing the backup configuration restores a completed-primary project. Changed, missing, or redirected primary files stop the retry and produce an exception report. Cancellation waits for file operations and reporting to finish.

New primary completions persist full evidence across restarts. Legacy compact logs may lack this evidence; reconnect the original source and use the existing **Retry** action. Project stores now use schema v2 and retain a unique pre-v2 snapshot before migration. Older versions with future-schema protection reject v2. Actual cross-version rollback remains unverified. Back up app data before downgrading.

Local project evidence contains relative filenames and checksums. Support diagnostic exports exclude them and do not upload automatically.
