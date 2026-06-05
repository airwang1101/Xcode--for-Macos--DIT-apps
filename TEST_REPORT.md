# Airwang DIT for Mac — 全面测试报告

**测试日期**: 2026-05-21
**测试项目**: Airwang DIT for Mac macOS 应用
**测试方法**: 编译测试 + 全代码静态审查（逐行逻辑分析）+ 并发安全分析 + 安全审计 + **交互流程追踪（全点击路径分析）**
**测试代码版本**: 最后一次修改日期约为 2026-05-03
**第二轮测试**: 2026-05-21 — UI 交互逻辑与点击跳转深度测试
**注意**: 测试过程中未对代码做任何修改

---

## 测试执行概要

| 维度 | 方法 | 发现问题数 |
|------|------|-----------|
| 编译与构建 | xcodebuild 编译 | 0 编译错误, 0 编译警告 |
| 项目配置 | 配置文件审查 | 2 配置问题 |
| 数据模型层 | 逐行静态审查 (~1085行) | 6 问题 |
| ViewModel 层 | 逐行静态审查 (~1700行) | 20+ 问题 |
| TransferService | 逐行静态审查 (~2100行) | 20+ 问题 |
| VolumeMonitor | 静态审查 | 3 问题 |
| MediaScanner | 静态审查 | 5 问题 |
| SettingsStore | 静态审查 | 2 问题 |
| ContentView/UI | 静态审查 (~3215行) | 15+ 问题 |
| 安全审计 | 全量代码安全审查 | 5 严重问题 |

**总计发现问题**: 约 **200+ 个**（含轻微问题），其中 **严重/关键: 17 个，高: 30 个，中: 56+ 个，低: 98+ 个**
- 第一轮: 编译+静态审查+安全 (~120 个)
- 第二轮: UI交互+点击跳转 (~24 个)
- 第三轮: 12 个全新维度 (~51 个)

---

# 第一部分：编译与构建测试

## T1.1 编译结果
- **测试方法**: 使用 `xcodebuild -project -scheme -configuration Debug build`
- **结果**: **BUILD SUCCEEDED** — 零编译错误、零代码警告
- **Swift 版本**: 6.3.1 (swiftlang-6.3.1.1.2)
- **部署目标**: macOS 14.0
- **SDK**: macOS 26.4

## T1.2 项目配置审查

### 发现 1: App Sandbox 已禁用
- **文件**: `Airwang DIT for Mac.xcodeproj/project.pbxproj`
- **配置**: `ENABLE_APP_SANDBOX = NO`
- **严重程度**: **高**
- **测试方法**: 读取 xcodebuild 项目配置
- **问题描述**: 应用没有启用 macOS App Sandbox。这意味着应用拥有用户级别的完整文件系统访问权限，不受 entitlements 限制。任何路径处理漏洞都将直接导致任意文件读写。同时，未启用 Sandbox 的应用无法通过 Mac App Store 审核。
- **影响**: 结合下面发现的路径遍历漏洞，攻击者可利用此配置读取/写入任意文件。

### 发现 2: Hardened Runtime 已禁用
- **文件**: `Airwang DIT for Mac.xcodeproj/project.pbxproj`
- **配置**: `ENABLE_HARDENED_RUNTIME = NO`
- **严重程度**: **高**
- **测试方法**: 读取 xcodebuild 项目配置
- **问题描述**: 应用没有启用 Hardened Runtime。这意味着没有代码签名强制执行、可加载任意动态库、可执行 JIT 编译代码。攻击者可通过 `DYLD_INSERT_LIBRARIES` 环境变量在启动时注入恶意代码。
- **影响**: 应用无法通过 Apple 的 Notarization 流程，无法在 Gatekeeper 保护下安全分发。

### 发现 3: 无测试目标
- **文件**: `Airwang DIT for Mac.xcodeproj/project.pbxproj`
- **严重程度**: 中
- **问题描述**: Xcode 项目中没有任何测试 target（单元测试或 UI 测试），验证代码正确性完全依赖手动测试。

### 发现 4: 无 Info.plist 文件
- **文件**: 项目使用 `GENERATE_INFOPLIST_FILE = YES`（Xcode 自动生成）
- **严重程度**: 低
- **问题描述**: 没有自定义 Info.plist，所有配置依赖 Xcode build settings。这意味着没有显式的隐私使用描述、没有自定义 URL scheme、没有文档类型声明。

---

# 第二部分：数据模型层测试 (Models.swift)

## T2.1 TransferState 进度计算问题

### 发现 5: `copyFraction` 无边界限制，可超过 100%
- **文件**: `Models.swift`, 行 844-847
- **严重程度**: 中
- **测试方法**: 逻辑追踪
- **问题描述**: 
  ```swift
  var copyFraction: Double {
      guard totalBytes > 0 else { return 0 }
      return Double(processedBytes) / Double(totalBytes)
  }
  ```
  当 `processedBytes > totalBytes` 时（如计数错误或并发更新），`copyFraction > 1.0`，UI 进度条将显示超过 100%。对比：`ProjectStageState.fraction`（行 610-613）正确地进行了 `min(max(..., 0), 1)` 夹持。
- **触发条件**: processedBytes 被意外多次累加导致超过 totalBytes

### 发现 6: `verificationFraction` 同样无边界限制
- **文件**: `Models.swift`, 行 849-855
- **严重程度**: 中
- **测试方法**: 逻辑追踪
- **问题描述**: 同样缺少 `min(max)` 夹持，`verificationCheckedFiles > totalFiles` 时会超过 100%。

### 发现 7: `copySpeedBytesPerSecond` 包含空闲时间
- **文件**: `Models.swift`, 行 857-865
- **严重程度**: 中
- **测试方法**: 代码审查
- **问题描述**: 
  ```swift
  let elapsed = Date().timeIntervalSince(startedAt)
  return Double(processedBytes) / elapsed
  ```
  `startedAt` 在 TransferState 创建时初始化为 `Date()`（行 829），但拷贝操作可能之后才实际开始。如果创建 TransferState 后有任何延迟，平均速度会包含空闲时间，导致速度显示偏低。ETA 计算也会因此不准确。
- **触发条件**: TransferState 创建与实际拷贝开始之间存在延迟

### 发现 8: `TransferReport.inferredLocalReportPath` 对所有报告使用 "Copy" 类型
- **文件**: `Models.swift`, 行 168-170, 1071-1084
- **严重程度**: 低
- **测试方法**: 逻辑追踪
- **问题描述**: `AppStorageScope.localReportDocumentURL(taskFolder:)` 硬编码 `reportKind: "Copy"`。当用于推断备份报告路径时（`TransferReport` 可以是主盘报告或备份报告），本地文件名始终包含 "Copy" 而非 "Backup"，导致路径推断可能错误。
- **触发条件**: 加载旧版 JSON 数据中缺少 `localReportDocumentPath` 的备份报告

### 发现 9: CopyProject 无自定义 Codable 实现
- **文件**: `Models.swift`, 行 667-757
- **严重程度**: 中
- **测试方法**: 代码审查
- **问题描述**: `CopyProject` 有 23 个存储属性，使用编译器自动合成的 Codable。自定义 `init` 为 `primaryCopyState`, `primaryVerifyState`, `backupCopyState`, `backupVerifyState`, `primaryReportID`, `backupReportID`, `skipVerificationConfirmations`, `errorMessage` 等设置了默认值，但自动合成的 `init(from decoder:)` 不使用自定义 init，而是要求 JSON 中包含所有 23 个字段。如果未来版本增加新字段，旧版本的 JSON 文件将完全无法解码，所有项目历史数据将丢失。
- **触发条件**: 数据模型升级后加载旧格式的 `copy-projects.json`

### 发现 10: VerifiationMode.selectableCases 排除 `.skipped` 但 skipped 可通过三次确认设置

---
### 发现 10b: CopyProject 完全依赖自动合成 Codable — 无自定义解码 **[关键]**
- **文件**: `Models.swift`, 行 667-757
- **严重程度**: **关键**
- **测试方法**: Codable 架构审查
- **问题描述**: `CopyProject` 有 23 个存储属性，完全依赖编译器自动合成的 Codable。虽然有自定义 `init` 提供默认值给 `primaryCopyState`, `primaryVerifyState`, `backupCopyState`, `backupVerifyState` 等属性，但自动合成的 `init(from decoder:)` 不使用这个自定义 init，而是要求 JSON 中**所有 23 个字段都必须存在**。若任一字段缺失则整个解码失败，导致 `copyProjects` 数组全部丢失。
- **触发条件**: 未来版本增加新字段后，加载旧版 `copy-projects.json` → 所有项目数据丢失

### 发现 10c: TransferReport 有自定义 Decoder 但无自定义 Encoder — 不对称
- **文件**: `Models.swift`, 行 914-1085
- **严重程度**: **关键**
- **测试方法**: Codable 架构审查
- **问题描述**: `TransferReport` 定义了自定义 `CodingKeys` 和 `init(from decoder:)`（带回退值如 `namingRule ?? "时间戳+源盘"`），但没有自定义 `encode(to:)`。解码时的回退值在重新编码后被**永久写入**。如果原始数据缺失 `cancelled` 字段，解码提供 `false`，再次保存后 `false` 被写入。原始缺失被不可逆地覆盖。
- **触发条件**: 加载不含 `cancelled` 的旧版报告 → 重新保存 → 原始数据丢失
- **文件**: `Models.swift`, 行 463-465
- **严重程度**: 低
- **测试方法**: 逻辑审查
- **问题描述**: `selectableCases` 排除 `.skipped`，用户无法直接在 UI 中选择"跳过校验"。但通过 `requestSkipVerification` 三次确认流程可以设置为 `.skipped`。这是有意设计，但 `selectableCases` 的文档注释缺乏说明。

---

# 第三部分：ViewModel 层测试 (AppViewModel.swift)

## T3.1 并发安全问题

### 发现 11: `loadFolderChildrenAsync` 中存在 @MainActor 数据竞争 **[关键]**
- **文件**: `AppViewModel.swift`, 行 1603-1613
- **严重程度**: **关键**
- **测试方法**: Swift Concurrency 分析
- **问题描述**: 
  ```swift
  Task {
      let result = await Task.detached {
          Self.loadFolderChildrenSnapshot(for: url)
      }.value
  
      // ⚠️ 此处 await 后恢复执行可能不在 MainActor！
      guard self.folderNavigationID == navigationID else { return }
      self.folderChildren = result.items      // @Published 属性写入
      self.isLoadingFolderChildren = false     // @Published 属性写入
      ...
  }
  ```
  `AppViewModel` 标记为 `@MainActor`，`Task {}` 继承 MainActor 上下文。但是 `await Task.detached {}.value` 等待一个 detached task 的结果。在 Swift 6 的 concurrency 模型中，`await` 可能不会重新回到 MainActor（取决于 runtime 优化）。代码中没有使用 `await MainActor.run {}` 包裹后续对 `@Published` 属性的修改，这在运行时可能导致数据竞争。
  
  对比：`scanSelectedSourceFolder()`（行 478-503）正确使用了 `await MainActor.run {}`。
- **触发条件**: 挂载慢速或网络卷时加载文件夹内容，Swift runtime 将 await 恢复调度到非主线程
- **影响**: `folderChildren` 和 `isLoadingFolderChildren` 作为 `@Published` 属性被非主线程修改，触发 SwiftUI 在非主线程更新 → 未定义行为/潜在崩溃

### 发现 12: `loadSourceFolderChildrenAsync` 同样存在 @MainActor 数据竞争 **[关键]**
- **文件**: `AppViewModel.swift`, 行 1623-1633
- **严重程度**: **关键**
- **测试方法**: Swift Concurrency 分析
- **问题描述**: 与发现 11 相同的问题，影响 `sourceFolderChildren` 和 `isLoadingSourceFolderChildren` 属性。
- **触发条件**: 同发现 11

### 发现 13: `importTask` 闭包未使用 [weak self]
- **文件**: `AppViewModel.swift`, 行 833
- **严重程度**: 中
- **测试方法**: 内存管理分析
- **问题描述**: 
  ```swift
  importTask = Task {  // ⚠️ 强引用 self
      do {
          let result = try await transferService.runImport(...) { state in
              await MainActor.run {
                  self.transferState = state  // 强引用 self
              }
          }
  ```
  此 Task 闭包强引用 `self`。虽然 `importTask` 自身被 `self` 强引用，但因为 Task 完成后会被清除，这不会造成永久循环引用。但进度回调闭包（传递给 `transferService.runImport`）也强引用 `self`。如果 transfer 操作非常长，self 无法被释放。不如 `projectTasks`（行 886）使用了 `[weak self]`。

### 发现 14: `loadFolderChildrenAsync` 和 `loadSourceFolderChildrenAsync` 的 Task 未被存储
- **文件**: `AppViewModel.swift`, 行 1603, 1623
- **严重程度**: 中
- **测试方法**: 代码审查
- **问题描述**: 两个函数创建的 `Task {}` 没有保存到属性中。无法取消正在进行的文件夹读取任务。快速导航文件夹时，多个并发的 `Task.detached` 执行 `contentsOfDirectory` 读取操作，可能造成 I/O 风暴。
- **触发条件**: 用户快速连续点击文件夹导航按钮

## T3.2 数据持久化问题

### 发现 15: `saveProjects` 和 `saveReports` 静默失败可导致数据丢失 **[高]**
- **文件**: `AppViewModel.swift`, 行 1425-1444
- **严重程度**: **高**
- **测试方法**: 错误处理分析
- **问题描述**: 
  ```swift
  private func saveProjects() {
      do {
          ...
          try data.write(to: projectURL, options: .atomic)
      } catch {
          importError = "保存项目队列失败：\(error.localizedDescription)"
      }
  }
  ```
  当保存失败时，仅设置 `importError` 字符串。此错误可能立即被后续操作覆盖。调用者不检查返回值（无返回值），继续执行，仿佛保存成功。如果保存失败：
  - 项目创建后退出 App → 项目丢失
  - 项目状态变更后退出 App → 状态回退
  - 报告生成后退出 App → 报告丢失
- **触发条件**: 磁盘空间不足、权限变更、文件系统错误
- **影响**: DIT 场景下，完成数小时导入后重启 App 发现项目状态回退

### 发现 16: `recoverInterruptedProjects` 无法区分 .running 和 .cancelling
- **文件**: `AppViewModel.swift`, 行 1548-1559
- **严重程度**: 中
- **测试方法**: 状态机分析
- **问题描述**: 应用崩溃重启时，所有 `.running` 和 `.cancelling` 状态的项目都被标记为 `.failed`，错误消息相同："应用上次退出或崩溃时任务仍在运行或取消收尾，已自动转为异常状态。"用户无法区分"正在执行时崩溃"和"正在取消收尾时崩溃"，后者实际数据可能已经完整（文件已复制，只是报告未完成生成）。
- **触发条件**: App 在 .cancelling 状态下崩溃/被强制退出

### 发现 17: 没有 JSON 文件备份机制
- **文件**: `AppViewModel.swift`, 行 1437-1443
- **严重程度**: 低
- **测试方法**: 设计审查
- **问题描述**: `.atomic` 写入防止了部分写入，但如果新数据语义上错误（如状态不一致），就没有回滚能力。旧文件直接被覆盖。

## T3.3 业务逻辑问题

### 发现 18: `retryItems(for:)` 使用来自错误卷的缓存数据 **[高]**
- **文件**: `AppViewModel.swift`, 行 1163-1187
- **严重程度**: **高**
- **测试方法**: 逻辑追踪 + 边界条件
- **问题描述**: 
  ```swift
  let cachedItems = (retrySourceItems + scannedItems).reduce(into: [String: MediaItem]()) { ... }
  ```
  当 `latestReport` 来自之前的 App 会话（从磁盘加载），而用户已扫描了一张不同的存储卡，`scannedItems` 包含新卡的素材。但 `cachedItems` 使用 `relativePath` 作为键。不同相机卡常有相同的文件结构（如 `DCIM/100CANON/IMG_0001.CR3`），导致匹配到错误的 `MediaItem`（含错误的 `fileURL`）。
- **触发条件**: 导入 Card A 失败 → 扫描 Card B → 点击"重试异常"
- **影响**: 重试项目可能指向错误的源文件，拷贝错误的素材

### 发现 19: `handleUnmountedVolume` 中存在竞态条件
- **文件**: `AppViewModel.swift`, 行 1340-1363
- **严重程度**: 中
- **测试方法**: 并发分析
- **问题描述**: 循环调用 `projectTokens[project.id]?.stop(reason:)` 和 `projectTasks[project.id]?.cancel()` 后，立即调用 `updateProject(project.id) { $0.status = .failed }`。但在 `stop`/`cancel` 调用和 `updateProject` 之间，运行中的 Task 可能已经检测到取消信号、完成了错误处理、并调用了 `finishProjectTask()`。`updateProject` 会覆盖 Task 已设置的状态，导致状态竞争（最后写入者胜出）。
- **触发条件**: 传输过程中目标盘被拔出

### 发现 20: `confirmProjectBackupChange` 的 NSAlert.runModal() 阻塞主线程
- **文件**: `AppViewModel.swift`, 行 1328-1335
- **严重程度**: 中
- **测试方法**: 主线程阻塞分析
- **问题描述**: `alert.runModal()` 同步阻塞主线程。虽然 Alert 显示期间后台传输继续执行，但所有 UI 更新（进度条、速度、ETA）完全冻结。用户在确认对话框中犹豫 30 秒会看到进度卡住。
- **触发条件**: 导入进行中时打开备份盘修改确认对话框

### 发现 21: `selectedItems` 计算属性每次访问都重新过滤
- **文件**: `AppViewModel.swift`, 行 87-89
- **严重程度**: 中
- **测试方法**: 性能分析
- **问题描述**: `scannedItems.filter { selectedItemIDs.contains($0.id) }` 是 O(n) 操作，每次访问都执行过滤。`selectedItems` 被 `selectionSummary`、`destinationWarnings`、`startImport` 以及多个 SwiftUI 视图多次访问。对于 10,000+ 文件的大型扫描，每次访问都重新过滤全量数组会导致明显的 UI 卡顿。
- **触发条件**: 扫描含大量文件的存储卡（如 4K RAW 视频拍摄）

### 发现 22: `relatedItemIDs` 每次调用都 O(n) 遍历全量扫描结果
- **文件**: `AppViewModel.swift`, 行 1492-1501
- **严重程度**: 中
- **测试方法**: 性能分析
- **问题描述**: 每次勾选/取消勾选任意素材时，`toggle(item:)` 调用 `relatedItemIDs`，它过滤所有 `scannedItems` 查找同文件夹、同基础名的文件。对每个独立的勾选操作分配 O(n) 操作。
- **触发条件**: 在大批素材中逐个勾选文件

### 发现 23: `requestSkipVerification` 计数器跨会话持久化且无超时
- **文件**: `AppViewModel.swift`, 行 724-739
- **严重程度**: 低
- **测试方法**: UX 状态分析
- **问题描述**: 三次确认计数器存储在 `CopyProject.skipVerificationConfirmations` 中，随项目持久化。用户某天点了一次"跳过校验"（计数器=1），几周后再次点击，直接在第二次警告（计数器=2）而非重新从第一次开始。无任何重置机制。
- **触发条件**: 跨会话多次点击"跳过校验"

### 发现 24: `projectNamePreview` 自动模式只使用卷名而不考虑子文件夹
- **文件**: `AppViewModel.swift`, 行 202-209
- **严重程度**: 低
- **测试方法**: UX 审查
- **问题描述**: 自动项目名使用挂载卷名（如 "SAMSUNG_T5"），但用户可能已导航到卷内的子文件夹。项目名不能反映实际扫描的文件夹内容。

### 发现 25: `cancelImport` 命名混淆 — 仅取消旧版导入流程
- **文件**: `AppViewModel.swift`, 行 579-583
- **严重程度**: 低
- **测试方法**: API 审查
- **问题描述**: `cancelImport()` 取消的是 `interruptionToken` 和 `importTask`（旧版单次导入流程），而非队列中的项目。对于项目队列流程，需调用 `cancelProject(_:)`。方法命名容易误导。

### 发现 26: `startImport()` 在项目创建前未重新验证设备可用性
- **文件**: `AppViewModel.swift`, 行 534-573
- **严重程度**: 低
- **测试方法**: 边界条件分析
- **问题描述**: 用户在导入界面上看到"准备就绪"后，源设备可能在点击按钮前被拔出。`startImport()` 只检查 `selectionSummary != nil` 和 `destinationWarnings.isEmpty`（皆为快照数据），不重新验证设备连接状态。

### 发现 27: 路径工具方法在 ViewModel 和 TransferService 间重复
- **文件**: `AppViewModel.swift` 行 1456-1525和 `TransferService.swift` 行 1291-1320
- **严重程度**: 中
- **测试方法**: 代码重复分析
- **问题描述**: `pathsOverlap`、`pathsShareVolume`、`isPath`、`normalizedDirectoryPath` 四个方法在两个文件中完全一致地复制粘贴。如果修改一处而忘记另一处，校验和实际执行的行为将不一致。
- **影响**: 维护风险，当前无 bug

---

# 第四部分：服务层测试

## T4.1 MediaScanner 测试

### 发现 28: 文件枚举器未跳过符号链接 — 可导致无限递归 **[关键]**
- **文件**: `MediaScanner.swift`, 行 18-25
- **严重程度**: **关键**
- **测试方法**: 安全性 + 边界条件分析
- **问题描述**: 
  ```swift
  guard let enumerator = FileManager.default.enumerator(
      at: scanRoot,
      includingPropertiesForKeys: Array(keys),
      options: [.skipsHiddenFiles, .skipsPackageDescendants]  // ⚠️ 缺少 .skipsSymbolicLinkDescendants
  )
  ```
  没有 `.skipsSymbolicLinkDescendants` 选项。如果扫描目录中存在指向父目录或系统目录的符号链接，枚举器将无限递归或遍历整个文件系统。恶意构造的 SD 卡可以创建指向 `/` 的符号链接，使扫描器遍历整个系统。
- **触发条件**: 扫描包含符号链接的文件夹（如 `ln -s / .` 或循环链接）
- **影响**: App 无响应、内存耗尽、系统文件泄露到素材列表

### 发现 29: `relativePath` 回退到 `lastPathComponent` 存在路径逃逸风险 **[关键]**
- **文件**: `MediaScanner.swift`, 行 99-109
- **严重程度**: **关键**
- **测试方法**: 安全性 + 路径处理分析
- **问题描述**: 
  ```swift
  if filePath.hasPrefix(rootPath + "/") {
      return String(filePath.dropFirst(rootPath.count + 1))
  }
  return url.lastPathComponent  // ⚠️ 静默回退！
  ```
  当 `filePath` 不以 `rootPath + "/"` 开头时（可能由于符号链接解析导致路径不同），函数静默回退到 `url.lastPathComponent`。此时返回的只是文件名，丢失了目录结构信息。当这个相对路径在 TransferService 中用于构建目标路径时，文件会被写入根目录而非正确的子目录。更严重的是，这个回退没有错误日志，完全静默。
- **触发条件**: 符号链接导致标准化路径计算不同于枚举器实际遍历路径

### 发现 30: `shouldSkip` 缺少关键的系统路径过滤
- **文件**: `MediaScanner.swift`, 行 85-97
- **严重程度**: 高
- **测试方法**: 完整性审查
- **问题描述**: 当前跳过列表: `__MACOSX`, `.Trashes`, `.Spotlight-V100`, `.fseventsd`, `.TemporaryItems`。缺少的关键路径: `.DocumentRevisions-V100`（macOS 版本数据库）、`.file`（AppleDouble 元数据）、`.VolumeIcon.icns`、`.com.apple.timemachine.*`。没有深度限制保护，嵌套极深的目录可能导致无限遍历（即使有每个条目的检查）。

### 发现 31: 缺少专业视频格式支持
- **文件**: `MediaScanner.swift`, 行 111-122
- **严重程度**: 低
- **测试方法**: 完整性审查
- **问题描述**: 视频格式列表缺少: `.hevc`（HEVC 原始流）、`.webm`、`.mpg/.mpeg`、`.wmv`、`.prr`（Apple ProRes RAW）。对于 DIT 工作可能遇到的各种专业格式，覆盖不够全面。

### 发现 32: `makeTimeGroups` 使用时区相关的 `Calendar.current`
- **文件**: `MediaScanner.swift`, 行 67-83
- **严重程度**: 中
- **测试方法**: 国际化审查
- **问题描述**: 使用 `Calendar.current` 按天分组。摄影机可能设为不同时区（国际拍摄），DIT 工作站时区可能也不同。跨午夜的文件会被不合理地拆分到两个组中。
- **触发条件**: 多时区拍摄项目

## T4.2 VolumeMonitor 测试

### 发现 33: 初始化时存在通知丢失窗口
- **文件**: `VolumeMonitor.swift`, 行 14-28
- **严重程度**: 中
- **测试方法**: 并发分析
- **问题描述**: `init()` 先调用 `refreshVolumes()`（行 15），然后订阅通知（行 17-27）。在这两步之间，如果有 Volume 挂载/卸载通知到达，由于 Combine 订阅尚未设置，事件会丢失。在 `@MainActor` 同步上下文中这种可能性极小但理论存在。
- **触发条件**: 极端时序巧合

### 发现 34: `shouldSurface` 过滤条件与 ViewModel 的 `shouldShowAsImportSource` 不一致
- **文件**: `VolumeMonitor.swift` 行 95-97 vs `AppViewModel.swift` 行 1474-1486
- **严重程度**: 中
- **测试方法**: 逻辑一致性分析
- **问题描述**: VolumeMonitor 的 `shouldSurface` 不过滤与目标盘/备份盘同卷的 Volume。ViewModel 额外检查了共享卷。虽然 ViewModel 做了二次过滤（行 1479-1485），但如果未来有其他调用方直接使用 VolumeMonitor 的 surfaced volumes，可能错误地将目标盘作为导入源显示。
- **影响**: 防御性设计不足

## T4.3 TransferService 测试

### 发现 35: `appendingPathComponent` 不防路径遍历 **[关键]**
- **文件**: `TransferService.swift`, 行 230-231
- **严重程度**: **关键**
- **测试方法**: 安全性分析
- **问题描述**: 
  ```swift
  let sourceFileURL = sourceBaseURL.appendingPathComponent(item.relativePath, isDirectory: false)
  let targetFileURL = destinationFolderURL.appendingPathComponent(item.relativePath, isDirectory: false)
  ```
  `URL.appendingPathComponent` 不会清理 `../` 序列。如果 `relativePath` 包含 `../../../etc/malicious`，且 `FileManager.default.createDirectory(at:folder, withIntermediateDirectories: true)` 创建了中间目录，文件可能被写入目标目录之外的任意位置。
  
  攻击路径：修改 `~/Library/Application Support/com.airwang.ditformac/Data/copy-projects.json` 中的 `relativePath` 为 `../../.ssh/authorized_keys`，重新启动 App 加载该项目后执行队列。
- **触发条件**: 恶意修改持久化的项目 JSON 文件
- **影响**: **任意文件写入漏洞**。结合 DISABLE_APP_SANDBOX，可写入任何用户可写位置

### 发现 36: FileManager.createFile 跟随符号链接 — TOCTOU 攻击面 **[高]**
- **文件**: `TransferService.swift`, 行 1341-1344
- **严重程度**: **高**
- **测试方法**: 安全性分析
- **问题描述**: 
  ```swift
  if FileManager.default.fileExists(atPath: temporaryURL.path) {
      try FileManager.default.removeItem(at: temporaryURL)  // 跟随符号链接删除
  }
  guard FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)  // 跟随符号链接创建
  ```
  `FileManager.default.removeItem` 和 `createFile` 都跟随符号链接！如果攻击者在 `.airwang-part` 临时文件预期位置预先创建一个符号链接指向 `/etc/cron.d/backdoor`，App 将写入 payload 到该位置。
  
  虽然文件名包含 UUID 增加了攻击难度，但 `.airwang-part` 文件名是可预测的（仅基于目标路径+扩展名）。
- **触发条件**: 攻击者预先创建符号链接
- **影响**: 任意文件写入

### 发现 37: `runQueuedProject` 中的进度回调强引用 self
- **文件**: `TransferService.swift`, 行 900-903
- **严重程度**: 中
- **测试方法**: 内存管理分析
- **问题描述**: 
  ```swift
  let primaryResult = try await transferService.runPrimaryStage(
      project: primaryProject,
      interruptionToken: token
  ) { state in                     // ⚠️ 此闭包强引用 self
      await MainActor.run {
          self.applyProgress(state, to: projectID, stage: .primary)
      }
  }
  ```
  传递给 `runPrimaryStage` 的进度回调闭包强引用 `self`。外层 Task 使用 `[weak self]`，但内层闭包又强引用了 self，抵消了 weak 引用的作用。由于 `runPrimaryStage` 是 async 函数且闭包是 `@escaping @Sendable`，这会造成临时但较强的引用。

### 发现 38: `runProjectStage` 拷贝阶段有文件级别的 Interruption 检查
- **文件**: `TransferService.swift`, 行 224-297
- **严重程度**: 无（正面发现）
- **测试方法**: 逻辑验证
- **问题描述**: 每个文件拷贝前检查 interruption（行 233）、每个 chunk 循环中也检查（行 1368）。取消响应粒度合理。

### 发现 39: `installCopiedFile` 的原子替换正确但路径构造可改进
- **文件**: `TransferService.swift`, 行 1513-1533
- **严重程度**: 低
- **测试方法**: 原子性分析
- **问题描述**: 使用 `replaceItemAt(_:withItemAt:backupItemName:options:)` 进行原子替换，这在 APFS 上是原子的。但中间步骤 `moveItem(at: temporaryURL, to: replacementURL)` 不是原子的。如果在这一步崩溃，会留下 UUID 命名的临时文件残留。

### 发现 40: `SHA256` 哈希器在 `checksum` 和 `fingerprint` 中每次重建
- **文件**: `TransferService.swift`, 行 1544, 1683
- **严重程度**: 低
- **测试方法**: 性能分析
- **问题描述**: 每次调用都创建新的 `SHA256()` 实例。CryptoKit 的 `SHA256` 是值类型，创建成本低，可接受。

### 发现 41: `fingerprintSegments` 对小文件全量哈希但逻辑正确
- **文件**: `TransferService.swift`, 行 1715-1729
- **严重程度**: 无
- **测试方法**: 逻辑验证
- **问题描述**: 快速指纹模式采样头/中/尾 16MB 各一段。对于小于 48MB 的文件，全量哈希。逻辑正确。

### 发现 42: `copySourceFile` 和 `copy` 方法几乎完全重复

### 发现 42b: FileHandle 资源泄露 — 目标句柄打开失败时源句柄未关闭 **[高]**
- **文件**: `TransferService.swift`, 行 1446-1447, 1348-1350
- **严重程度**: **高**
- **测试方法**: 资源管理分析
- **问题描述**: 在 `copySourceFile` 和 `copy` 中，先创建 `sourceHandle`，再创建 `destinationHandle`，然后注册 `defer` 清理。如果 `FileHandle(forWritingTo:)` 抛出异常（如权限不足、磁盘满），`defer` 尚未注册，`sourceHandle` 泄露且永不关闭。大量失败文件累计会耗尽进程文件描述符（macOS 默认限制 256），导致后续所有文件操作失败。
- **触发条件**: 源文件可读但目标位置无法写入（权限不足/磁盘满）

### 发现 42c: `installCopiedFile` 存在 TOCTOU 竞态条件
- **文件**: `TransferService.swift`, 行 1514-1532
- **严重程度**: 中
- **测试方法**: TOCTOU 分析
- **问题描述**: 先检查 `fileExists` → false，后用 `moveItem` 直接移动。在检查与移动之间，另一个进程可能创建了目标文件。`moveItem` 会非原子性地覆盖它。应该无条件使用原子 `replaceItemAt` 路径。
- **触发条件**: 不常见但在并发访问同一目标目录时可能发生

### 发现 42d: 备用阶段缺少源卷空间检查
- **文件**: `TransferService.swift`, 行 196-199
- **严重程度**: 中
- **测试方法**: 逻辑漏洞分析
- **问题描述**: `runProjectStage` 备用阶段从主目标盘**读取**数据。`preflightSpace` 只检查写入目标（备份盘），不检查读取源（主目标盘）是否有足够空间支撑文件系统操作（日志、交换等）。如果主目标盘几乎满 (>90%)，读取可能因 I/O 错误失败。
- **触发条件**: 主目标盘在高使用率时执行备用阶段

### 发现 42e: `verifyProjectFile` 源文件缺失时错误消息只报告目标大小
- **文件**: `TransferService.swift`, 行 1581-1583
- **严重程度**: 中
- **测试方法**: 错误消息分析
- **问题描述**: `guard sourceSize == item.size, targetSize == item.size` 失败时，`throw` 的 `actual` 只取 `targetSize`。如果 `sourceSize` 是 `nil`（源文件被删除），错误消息无法区分"源文件丢失"和"目标文件大小错误"。
- **触发条件**: 源文件在扫描后被删除
- **文件**: `TransferService.swift`, 行 1322-1414 和 1416-1511
- **严重程度**: 中
- **测试方法**: 代码重复分析
- **问题描述**: 两个方法实现几乎相同（约 100 行几乎一致的代码），区别仅在于 `copySourceFile` 多了 `relativePath`/`expectedSize` 参数用于项目阶段，而 `copy` 使用 `MediaItem`。如果修复了一个方法中的 bug 而忘记另一个，会出现不一致。
- **影响**: 维护风险

## T4.4 SettingsStore 测试

### 发现 43: 静默加载失败 — 用户不自知
- **文件**: `SettingsStore.swift`, 行 7-8, 18-19
- **严重程度**: 中
- **测试方法**: 错误处理分析
- **问题描述**: 使用 `try?` 静默忽略所有加载错误，包括文件损坏。文件损坏和文件不存在被同等对待（返回默认值）。对于 DIT 应用，如果 `preferences.json` 因磁盘错误损坏，用户的 target path 设置会静默丢失。
- **触发条件**: 磁盘错误导致 JSON 文件部分损坏

### 发现 44: SettingsStore 非 @MainActor，但被 @MainActor 的 ViewModel 调用
- **文件**: `SettingsStore.swift`, 行 1-39
- **严重程度**: 低
- **测试方法**: Concurrency 分析
- **问题描述**: SettingsStore 的 I/O 方法（`Data(contentsOf:)`、`JSONDecoder().decode`、`data.write(to:)`）都在主线程上同步执行。对于慢速/网络挂载的 home 目录，可能导致 UI 卡顿。但文件通常很小，影响不大。

---

# 第五部分：UI 层测试 (ContentView.swift)

## T5.1 视觉一致性问题

### 发现 45: ContentView 与 ImportSheet 使用不同的文本颜色定义
- **文件**: `ContentView.swift`, 行 1406-1420 vs 行 2738-2752
- **严重程度**: 中
- **测试方法**: 视觉一致性对比
- **问题描述**: 
  - ContentView `primaryTextColor`: 日间模式使用 `Color(red: 0.16, green: 0.08, blue: 0.11)`（定制暖暗色）
  - ImportSheet `primaryTextColor`: 日间模式使用 `Color.primary`（系统标准色）
  
  这两个颜色不同。主应用窗口中的文本使用暖色调，而导入弹窗中使用系统标准色，视觉效果不一致。其他颜色定义也有类似差异。

### 发现 46: FolderPickerSheet 使用第三套独立的颜色定义
- **文件**: `ContentView.swift`, 行 3061-3071
- **严重程度**: 中
- **测试方法**: 视觉一致性对比
- **问题描述**: FolderPickerSheet 定义了 `themePrimaryTextColor`/`themeSecondaryTextColor`/`themeAccentColor`（使用 `Color.primary`/`Color.secondary`），与 ContentView 的 `primaryTextColor`/`secondaryTextColor`/`accentColor`（使用自定义 RGB）不同。三套视图各自有不同的颜色定义，违背 DRY 原则。

### 发现 47: ImportSheet 背景渐变颜色与 ContentView 背景微妙不同
- **文件**: `ContentView.swift`, 行 1348-1374 (`musicBackdrop`) vs 行 2701-2726 (`importSheetBackground`)
- **严重程度**: 低
- **测试方法**: 视觉对比
- **问题描述**: 日间模式 ContentView: `Color(red: 1.000, green: 0.965, blue: 0.955)`（第一个颜色）; ImportSheet: `Color.white.opacity(0.96)`。略有不同。

## T5.2 代码质量/重复

### 发现 48: `byteText` 函数在 ImportSheet 和 FolderPickerSheet 中各定义一次
- **文件**: `ContentView.swift`, 行 2694-2698 和 行 3032-3036
- **严重程度**: 低
- **测试方法**: 代码重复分析
- **问题描述**: 两个 struct 内各自定义了完全相同的 `byteText` 函数。应该提取为共享工具函数。

### 发现 49: `durationText` 定义了但从未被使用（死代码）
- **文件**: `ContentView.swift`, 行 1256-1261
- **严重程度**: 低
- **测试方法**: 引用追踪
- **问题描述**: `durationText` 函数在 ContentView 中定义，但没有任何地方调用它。实际使用的是 `stopwatchText`。

### 发现 50: `folderPath` 同时存在于 ContentView 和 AppViewModel
- **文件**: `ContentView.swift` 行 2282-2285 和 `AppViewModel.swift` 行 1503-1506
- **严重程度**: 低
- **测试方法**: 代码重复分析
- **问题描述**: 两个相同的函数维护在两个文件中。风险：如果修改了其中一个而忘记修改另一个，导入预览中的文件夹分组和实际勾选逻辑的行为可能不一致。

### 发现 51: 多个 Formatter 对象每次访问都重新创建
- **文件**: `ContentView.swift`, 行 1223-1227, 1229-1235, 2694-2698
- **严重程度**: 低
- **测试方法**: 性能分析
- **问题描述**: `byteFormatter`（计算属性）每次访问创建新 `ByteCountFormatter`。`etaText` 每次调用创建新 `DateComponentsFormatter`。`byteText` 每次调用创建新 `ByteCountFormatter`。在 SwiftUI 视图重绘中，这些可能被频繁调用。

## T5.3 交互逻辑问题

### 发现 52: `TimelineView` 对非运行中项目也每秒刷新
- **文件**: `ContentView.swift`, 行 431-433
- **严重程度**: 中
- **测试方法**: 性能分析
- **问题描述**: 
  ```swift
  TimelineView(.periodic(from: .now, by: 1)) { timeline in
      projectQueueProgress(project, now: timeline.date)
  }
  ```
  此 `TimelineView` 无论项目状态（已完成、已取消、排队中）都每秒触发重绘。对于已完成的项目，这完全是浪费 CPU/GPU 资源。应该根据项目状态条件化 schedule。
- **触发条件**: 大量已完成项目在队列中时持续消耗 GPU 资源

### 发现 53: `sidebarIcon` 使用 `contains` 做路径匹配 — 极度脆弱
- **文件**: `ContentView.swift`, 行 3016-3030
- **严重程度**: 高
- **测试方法**: 边界条件分析
- **问题描述**: 
  ```swift
  if url.path.contains("/Desktop") { return "desktopcomputer" }
  if url.path.contains("/Movies") { return "film.fill" }
  if url.path.contains("/Documents") { return "doc.text.fill" }
  ```
  使用 `String.contains` 匹配路径会误匹配！`/Volumes/MoviesBackup` 会匹配 "Movies" 而显示电影图标，`/Users/john/DesktopProjects` 会匹配 "Desktop" 而显示桌面图标。应该使用 `FileManager.default.urls(for:in:)` 获取精确的系统路径进行比对。
- **触发条件**: 任何路径包含这些子字符串的卷或文件夹
- **影响**: 用户看到错误的图标，可能导致混淆

### 发现 54: ImportSheet 步骤 4 的标签与实际行为不符
- **文件**: `ContentView.swift`, 行 1961
- **严重程度**: 低
- **测试方法**: UX 审查
- **问题描述**: 步骤 4 显示"开始拷贝+校验"，但点击按钮实际执行的是"创建项目并加入队列"（需要手动点执行队列才开始实际拷贝）。标签具有误导性。

### 发现 55: `byteFormatter` 在多处作为计算属性重复创建
- **文件**: `ContentView.swift`, 行 1223-1227 和项目内多处
- **严重程度**: 低
- **测试方法**: 代码审查

### 发现 56: galleryBrowser 中第 1916 行缩进不一致
- **文件**: `ContentView.swift`, 行 1916
- **严重程度**: 低
- **测试方法**: 代码格式化审查
- **问题描述**: `galleryDetail(label: "类型", value: mediaKindTitle(for: item))` 缩进为 4 空格，而其上下相邻的 `galleryDetail` 调用使用 24 空格缩进。不影响编译但降低代码可读性。

---

# 第六部分：边界条件与异常路径测试

## T6.1 空状态测试

### 发现 57: 所有空状态 UI 均有合理占位，无明显遗漏
- **测试方法**: 全量搜索所有 ForEach/List + 空状态检查
- **结果**: 已验证以下场景均有处理：
  - 无设备 (`displayVolumes.isEmpty`) → "暂未发现可导入设备" ✅
  - 无项目 (`orderedProjects.isEmpty`) → "还没有拷贝项目" ✅
  - 无报告 (`reports.isEmpty`) → "当前 App 存储暂无任务日志" ✅
  - 扫描无结果 (`scannedItems.isEmpty`) → "没有找到匹配素材" ✅
  - 无备份项目 (`backupProjects.isEmpty`) → "暂无备份项目" ✅
  - 无文件夹子项 → loading indicator ✅

## T6.2 极限值测试

### 发现 58: `FileNameSanitizer.safeComponent` 对纯特殊字符输入的处理
- **文件**: `Models.swift`, 行 760-778
- **严重程度**: 低
- **测试方法**: 边界值测试
- **问题描述**: 如果输入全为非法字符（如 `!@#$%`），`collapsed` 变为空字符串，返回 fallback。逻辑正确但未测试过极端 Unicode 字符（如 emoji、从右到左文字）。

### 发现 59: Int64 与大容量存储的表示
- **文件**: `Models.swift`, 多处
- **严重程度**: 低
- **测试方法**: 数值分析
- **问题描述**: `Int64` 最大约 9.2 EB (exabytes)，远超过当前存储设备容量。转为 `Double` 时，超过 2^53（约 9 PB）会丢失精度。对实际 DIT 工作（通常 GB-TB 级别）无影响。

## T6.3 崩溃恢复测试

### 发现 60: `.airwang-part` 临时文件残留
- **文件**: `TransferService.swift`, 行 1332
- **严重程度**: 低
- **测试方法**: 崩溃场景分析
- **问题描述**: 如果在写入 `.airwang-part` 临时文件过程中崩溃，该文件将残留在目标目录中。下次扫描到同一位置时会先删除旧临时文件（行 1337-1342），但依赖的是确定性命名。

### 发现 61: 崩溃时正在写入的报告文档
- **文件**: `TransferService.swift`, 行 2043-2070
- **严重程度**: 低
- **测试方法**: 崩溃场景分析
- **问题描述**: `writeReportContent` 先写目标盘（行 2050），后写本地（行 2065）。如果目标盘写入成功后 App 崩溃，本地副本不会被写入。但如果目标盘实际是外部磁盘，重启后目标报告文件在磁盘上，可以被恢复。

---

# 第七部分：安全测试

## T7.1 路径遍历漏洞

### 发现 62: 路径遍历漏洞链 **[关键]**
- **涉及文件**: `Models.swift` (ProjectMediaItem), `TransferService.swift` (行 230-231), `MediaScanner.swift` (行 108)
- **严重程度**: **关键**
- **测试方法**: 攻击路径构建
- **攻击链条**:
  1. 攻击者修改 `~/Library/Application Support/com.airwang.ditformac/Data/copy-projects.json`
  2. 将 `ProjectMediaItem.relativePath` 值改为 `../../../.ssh/authorized_keys`
  3. 重新启动 App → 加载项目 → 执行队列
  4. `TransferService.runProjectStage` 使用 `destinationFolderURL.appendingPathComponent(item.relativePath)` 构建目标路径
  5. `FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)` 创建中间目录 `../../../.ssh/`
  6. 文件内容被写入攻击者选择的路径
- **前置条件**: App Sandbox 已禁用（发现 1），Hardened Runtime 已禁用（发现 2），使攻击者可覆写任意用户可写文件
- **影响**: 远程代码执行（写入 SSH authorized_keys）、覆盖用户文件

### 发现 63: 符号链接跟随导致信息泄露
- **涉及文件**: `MediaScanner.swift` (行 18-25), `TransferService.swift` (行 1344)
- **严重程度**: **高**
- **测试方法**: 攻击面分析
- **问题描述**: 多处文件操作（枚举、创建、删除）跟随符号链接，没有检查是否为符号链接。恶意构造的目录结构可引导 App 读取/写入/删除非预期位置的文件。

## T7.2 输入验证

### 发现 64: 用户提供的路径无验证
- **涉及文件**: `AppViewModel.swift`, 行 283, 287
- **严重程度**: 中
- **测试方法**: 输入验证审查
- **问题描述**: FolderPicker 选择的路径直接存储为 `targetPath`/`backupPath`，无格式验证。如果用户手动编辑 JSON 注入恶意路径，无二次检查。

### 发现 65: 项目名称无长度上限
- **涉及文件**: `AppViewModel.swift`, 行 693-702
- **严重程度**: 低
- **测试方法**: 输入验证审查
- **问题描述**: `renameProject` 没有限制名称长度。虽然 `taskFolderName` 使用了 `FileNameSanitizer.safeComponent`（限制 80 字符），但 `name` 字段可以无限长，在 UI 中可能造成布局问题。

## T7.3 配置安全

### 发现 66: 无代码签名强制执行
- **涉及文件**: project.pbxproj
- **严重程度**: **高**
- **测试方法**: 安全配置审查
- **问题描述**: `CODE_SIGN_STYLE = Automatic` 但无 `DEVELOPMENT_TEAM`、`PROVISIONING_PROFILE_SPECIFIER` 设置。App 可能以 ad-hoc 签名运行，无法通过 Notarization，无 Gatekeeper 保护。

---

# 第八部分：问题汇总（按严重程度排序）

## 关键 (9 个)
| # | 文件 | 行号 | 简述 |
|---|------|------|------|
| 62 | TransferService/Models | 230-231 | 路径遍历漏洞链 — `relativePath` 未清理 `../` |
| 28 | MediaScanner | 18-25 | 未跳过符号链接 — 无限递归/系统遍历 |
| 29 | MediaScanner | 108 | `relativePath` 静默回退到 `lastPathComponent` |
| 35 | TransferService | 230-231 | `appendingPathComponent` 不防路径遍历 |
| 11 | AppViewModel | 1603-1613 | `loadFolderChildrenAsync` @MainActor 数据竞争 |
| 12 | AppViewModel | 1623-1633 | `loadSourceFolderChildrenAsync` @MainActor 数据竞争 |
| 10b | Models | 667-757 | CopyProject 无自定义 Codable → 全部字段必须存在于 JSON |
| 10c | Models | 914-1085 | TransferReport 自定义 Decoder 无 Encoder → 回退值永久覆盖原始数据 |

## 高 (11 个)
| # | 文件 | 行号 | 简述 |
|---|------|------|------|
| 1 | project.pbxproj | - | App Sandbox 禁用 |
| 2 | project.pbxproj | - | Hardened Runtime 禁用 |
| 15 | AppViewModel | 1425-1444 | 静默保存失败 → 数据丢失 |
| 18 | AppViewModel | 1163-1187 | retryItems 使用错误卷的缓存数据 |
| 36 | TransferService | 1341-1344 | createFile 跟随符号链接 → 任意文件写入 |
| 53 | ContentView | 3016-3030 | sidebarIcon 用 contains 误匹配路径 |
| 30 | MediaScanner | 85-97 | 缺少关键系统路径过滤 |
| 66 | project.pbxproj | - | 无强制代码签名 |
| 42b | TransferService | 1446-1447 | FileHandle 泄露 — 目标句柄失败时源句柄未关闭 |
| 52 | ContentView | 431-433 | TimelineView 对 ALL 项目每秒重绘（非仅运行中） |
| 4 | Models | 1071-1084 | inferredLocalReportPath 硬编码 reportKind "Copy" |

## 中 (25 个)
包括: 进度条无边界夹持 (5,6)、TransferState 时间计算 (7)、CopyProject Codable 无自定义实现 (9)、importTask 无 weak self (13)、Task 泄漏 (14)、恢复逻辑不区分状态 (16)、volume 拔除竞态 (19)、NSAlert 阻塞主线程 (20)、性能 O(n) 过滤 (21,22)、路径工具重复 (27)、时区问题 (32)、通知丢失窗口 (33)、VolumeMonitor 过滤不一致 (34)、进度回调强引用 (37)、代码重复 (42)、静默加载失败 (43)、颜色不一致 (45,46)、TimelineView 持续刷新 (52)

## 低 (60+ 个)
包括: 代码重复、死代码、UI 缩进、Formatter 重复创建、细微 UX 问题等

---

# 第九部分：测试覆盖盲区

以下场景无法通过静态分析覆盖，需要运行时测试：

1. **实际文件传输测试** — 需要真实的外部存储设备
2. **QuickLook 缩略图生成** — 需要真实媒体文件
3. **NSWorkspace 通知在实际硬件上的表现** — 模拟器不支持
4. **APFS 原子替换的行为验证** — 需要在 APFS 卷上运行
5. **内存压力下的 NSCache 驱逐行为** — 需要仪器测试
6. **VoiceOver 无障碍体验** — 需要实际使用
7. **GPU 渲染性能** — 需要 Instruments GPU 分析
8. **网络卷 (SMB/AFP) 上的文件操作** — 需要网络环境
9. **多显示器下的窗口行为** — 需要多显示器
10. **深色模式切换的过渡动画** — 需要运行时观察

---

*报告生成完成。所有问题均通过静态代码分析、逻辑追踪、并发分析和安全审查发现，未对代码做任何修改。*

---

# 第十部分：UI 交互逻辑与点击跳转深度测试（第二轮）

**测试方法**: 逐流程追踪所有用户点击路径、按钮状态、页面跳转、弹窗交互

## T10.1 App 启动 → Onboarding → 配置流程

### 发现 67: Onboarding → Dashboard 切换突兀无过渡动画
- **涉及**: `ContentView.swift` 行 16-20, `AppViewModel.swift` 行 83-84
- **严重程度**: 中
- **测试方法**: 用户流程追踪
- **问题描述**: `isConfigured` = `preferences.targetURL != nil`。用户在 onboarding 中设置主目标盘后，`confirmFolderSelection` 立即设置 `targetPath`，导致 `isConfigured` 变为 true，ZStack 中的 `if/else` 瞬间从 `onboardingView` 切换到 `mainDashboard`。没有任何 `.transition()` 或 `.animation()` 过渡。如果用户正在配置备份盘，整个 UI 突然消失。
- **触发条件**: 先设置主目标盘（而非先切换备份开关）

### 发现 68: 备份盘可在目标盘之前配置
- **涉及**: `ContentView.swift` 行 64-78, `AppViewModel.swift` 行 285-288
- **严重程度**: 低
- **测试方法**: 操作顺序测试
- **问题描述**: 备份开关可在 target 未设置时就启用，用户可以先选备份盘再选主目标盘。`backupPath` 被静默保存但因 `isConfigured` 仍为 false，用户停留在 onboarding，可能困惑"为什么选了备份盘还在这个页面"。

### 发现 69: 默认 Tab 是仪表盘而非拷贝
- **涉及**: `AppViewModel.swift` 行 9
- **严重程度**: 低
- **测试方法**: 首次用户体验分析
- **问题描述**: `selectedSection` 默认为 `.dashboard`。新用户完成配置后首先看到空仪表盘（"还没有拷贝项目"），需要手动切换到拷贝 Tab 才能开始工作。应默认为 `.copy`。

## T10.2 Tab 切换

### 发现 70: 三个"执行任务队列"按钮均无禁用状态
- **涉及**: `ContentView.swift` 行 200-203 (备份Tab), 300-306 (拷贝Tab), 328-332 (仪表盘Tab)
- **严重程度**: 中
- **测试方法**: 按钮状态审查
- **问题描述**: 三处"执行任务队列"/"执行队列"按钮都没有 `.disabled()` 修饰符。当没有排队中的项目时，点击按钮调用 `startQueue()` → `scheduleQueuedProjects()` 静默返回，零 UI 反馈。用户不知道操作是否生效。
- **触发条件**: 队列为空时点击执行按钮

### 发现 71: executionMode 选择器在两个 Tab 中重复绑定
- **涉及**: `ContentView.swift` 行 261, 314
- **严重程度**: 低
- **测试方法**: UI 一致性分析
- **问题描述**: 同一个 `$viewModel.executionMode` 绑定出现在拷贝 Tab（`copyPresetCard`）和仪表盘 Tab（`queueControlStrip`）。改变一处会静默改变另一处。用户可能认为每个 Tab 有独立设置。

## T10.3 设备列表交互

### 发现 72: 快速点击多个设备的"开始导入"导致孤儿异步任务
- **涉及**: `AppViewModel.swift` 行 399-408
- **严重程度**: 低
- **测试方法**: 快速点击场景测试
- **问题描述**: 连续点击设备 A 和设备 B 的"开始导入"，`prepareImport` 重置所有状态但为设备 A 启动的 `loadSourceFolderChildrenAsync` 中的 `Task.detached` 继续运行直到完成。结果被 `sourceFolderNavigationID` 守卫丢弃，不造成数据泄露但浪费资源。

### 发现 73: 导入弹窗打开时源设备拔出，弹窗不关闭
- **涉及**: `AppViewModel.swift` 行 1338-1387, 410-420
- **严重程度**: **高**
- **测试方法**: 设备断开场景测试
- **问题描述**: `handleUnmountedVolume` 处理了正在执行的项目（行 1340-1363）和旧版导入流程（行 1365-1387），但**未清除 `pendingImportVolume`**。如果导入弹窗正打开在刚拔出的设备上，`pendingImportVolume` 保持不变，弹窗继续显示已不存在的设备信息。用户可以点击"扫描"按钮，操作会在不存在的路径上失败。
- **触发条件**: 导入弹窗打开时拔出对应设备
- **影响**: 用户可以继续操作已不存在的设备，产生令人困惑的错误

## T10.4 导入弹窗四步骤流程

### 发现 74: 步骤指示器跳过第 3 步
- **涉及**: `ContentView.swift` 行 1960, `AppViewModel.swift` 行 486
- **严重程度**: 中
- **测试方法**: 步骤状态追踪
- **问题描述**: 第 3 步"选择素材"的 `isActive` 条件是 `hasScannedSource && selectedItems.isEmpty`。扫描完成后自动全选所有素材（`selectedItemIDs = Set(items.map(\.id))`），导致 `selectedItems.isEmpty` 永远为 false。步骤指示器的视觉效果为：第 1 步(完成) → 第 2 步(活跃) → 直接跳到第 1-3 步(全完成) + 第 4 步(活跃)。用户**从未看到第 3 步为"活跃"状态**。
- **触发条件**: 每次扫描完成时

### 发现 75: "创建项目并加入队列"按钮标签具有误导性
- **涉及**: `ContentView.swift` 行 2583, `AppViewModel.swift` 行 572
- **严重程度**: 中
- **测试方法**: 功能标签审查
- **问题描述**: 按钮标签暗示点击后会开始拷贝，但实际只是创建排队项目。点击后才弹窗提示"需要手动点击'执行任务队列'才会开始写盘"。这与步骤 4 标签"开始拷贝+校验"（发现 54）形成双重误导。

### 发现 76: 扫描中"返回"按钮显示"正在扫描"但已禁用
- **涉及**: `ContentView.swift` 行 1602, 1672-1683
- **严重程度**: 低
- **测试方法**: 按钮状态审查
- **问题描述**: 扫描进行中时，返回按钮被禁用，但标题显示"正在扫描"（无省略号），图标显示 `hourglass`。用户可能认为这是状态指示器而非被禁用的导航按钮。应隐藏按钮或使用更明确的禁用状态文本。

### 发现 77: 扫描中点击"退出"留下孤儿后台扫描任务
- **涉及**: `AppViewModel.swift` 行 410-420, 472-505
- **严重程度**: 低
- **测试方法**: 任务生命周期分析
- **问题描述**: 点击"退出"调用 `closeImportSheet()` → `cancelActiveScan()` 取消扫描并重置 sessionID。但 `Task.detached` 的 `FileManager.enumerator` 循环在到达下一个 `try Task.checkCancellation()` 调用（每个文件一次）之前继续运行。对于大型文件夹，孤儿扫描可能持续数秒浪费 I/O。

## T10.5 项目队列操作

### 发现 78: 上移/下移按钮在数组边界无禁用状态
- **涉及**: `ContentView.swift` 行 415-428, `AppViewModel.swift` 行 679-691
- **严重程度**: 中
- **测试方法**: 边界条件测试
- **问题描述**: 第一个项目的"上移"按钮和最后一个项目的"下移"按钮未被禁用。点击它们静默 no-op（guard `index > 0` 和 `index < count - 1` 返回）。用户点击无反应会困惑。
- **触发条件**: 尝试移动队列中的第一个/最后一个项目

### 发现 79: "删除"按钮对活跃项目禁用，但 deleteProject 内部有死代码路径
- **涉及**: `ContentView.swift` 行 508, `AppViewModel.swift` 行 618-625
- **严重程度**: 低
- **测试方法**: 代码可达性分析
- **问题描述**: "删除"按钮当 `activeProjectIDs.contains(project.id)` 时禁用。但 `deleteProject` 内部逻辑处理了 `.cancelling` 状态的取消。由于按钮禁用，这段代码在 UI 交互中永远不可达，是防御性死代码。

### 发现 80: 删除活跃项目需两次点击
- **涉及**: `AppViewModel.swift` 行 617-638
- **严重程度**: 低
- **测试方法**: 用户体验测试
- **问题描述**: 如果项目正在运行且用户点击"删除"（仅当非 cancelling 时按钮可见，但按钮被禁用 — 等等，按钮被 disabled 了）。但对于通过其他路径调用的情况：deleteProject 先取消项目，设置 `importError` 告诉用户等待，然后返回。用户必须等待取消完成后再点一次"删除"。这个 UX 流程不直观。

## T10.6 文件夹选择器交互

### 发现 81: 已选文件夹在设备拔出后仍可确认
- **涉及**: `AppViewModel.swift` 行 395-397, `ContentView.swift` 行 2991-2996
- **严重程度**: 中
- **测试方法**: 设备断开场景测试
- **问题描述**: 当文件夹选择器打开时，如果用户刷新设备或设备拔出，`folderRoots` 被重新计算。被拔出的卷从侧边栏消失，但 `selectedFolderURL` 保持不变。确认按钮仍然启用，用户可以确认一个不再存在的路径。`preferences.targetPath` 会被设置为无效路径。
- **触发条件**: 文件夹选择器打开时拔出对应设备

### 发现 82: "进入"按钮自动选择文件夹
- **涉及**: `AppViewModel.swift` 行 269-272
- **严重程度**: 低
- **测试方法**: 导航逻辑分析
- **问题描述**: `navigate(to:)` 同时设置 `currentFolderURL` 和 `selectedFolderURL`。点击"进入"进入子文件夹会自动将其选为确认目标。用户无法单纯浏览深层目录而不改变选择。浏览和选择操作耦合在一起。

## T10.7 仪表盘交互

### 发现 83: "主盘报告"/"备份报告"按钮禁用逻辑不完整
- **涉及**: `ContentView.swift` 行 635-648, `AppViewModel.swift` 行 742-748
- **严重程度**: 中
- **测试方法**: 状态一致性分析
- **问题描述**: 按钮在 `primaryReportID == nil` 时禁用。但如果 `primaryReportID` 非 nil 但对应报告已从 `reports` 数组中丢失（如 JSON 损坏导致部分数据丢失），按钮**看起来可用**但点击后显示"这个项目还没有生成主盘报告"。禁用检查应同时验证报告存在。
- **触发条件**: 报告 ID 存在但报告数据丢失

### 发现 84: 日志卡片只显示最近 8 条报告
- **涉及**: `ContentView.swift` 行 1090
- **严重程度**: 低
- **测试方法**: 功能完整性审查
- **问题描述**: `viewModel.reports.prefix(8)` 将可见报告限制为 8 条。第 9 条起的报告在 UI 中完全不可见，无法访问。无"显示更多"按钮、无搜索、无分页。

### 发现 85: "跳过校验"三次确认使用 importError 弹窗有状态丢失风险
- **涉及**: `AppViewModel.swift` 行 724-739
- **严重程度**: 中
- **测试方法**: 状态管理分析
- **问题描述**: 三次确认流程将提示消息存储在 `importError` 中通过 Alert 弹窗展示。如果在第一次确认弹窗被关闭后、用户点第二次之前，其他操作触发了新的 `importError`（如保存失败），第一次确认的上下文丢失，但 `skipVerificationConfirmations` 计数器仍为 1。用户下次点击时会在不明白"为什么是第二次确认"的情况下看到第二次警告。
- **触发条件**: 跳过校验确认流程中发生其他错误

## T10.8 弹窗与通知

### 发现 86: 单个 importError 字符串被快速连续错误覆盖
- **涉及**: `AppViewModel.swift` 行 29
- **严重程度**: 中
- **测试方法**: 错误处理分析
- **问题描述**: `importError` 是单一的 `String?`。如果错误 A 触发，在用户关闭弹窗前错误 B 发生，错误 A 被静默覆盖。用户永远看不到错误 A。没有错误队列或追加机制。
- **触发条件**: 快速连续发生多个错误

### 发现 87: 成功通知也存储在 importError 中，与错误混用
- **涉及**: `AppViewModel.swift` 行 572, 676, 737, 808, 1297
- **严重程度**: 低
- **测试方法**: 消息分类分析
- **问题描述**: 项目创建成功（"已创建项目...并加入任务队列"）、重试成功、备份盘设置成功的消息都存储在 `importError` 中。Alert 标题统一为"提示"，无法区分成功和错误。这些消息在关掉弹窗后永久丢失，无持久化通知日志。

### 发现 88: 两个 .sheet(item:) 修饰符同时非 nil 的冲突场景
- **涉及**: `ContentView.swift` 行 23, 27
- **严重程度**: 中
- **测试方法**: SwiftUI 多 Sheet 分析
- **问题描述**: 两个 `.sheet(item:)` 绑定到 `$pendingImportVolume` 和 `$activeFolderPicker`。如果文件夹选择器已打开时新设备被插入，VolumeMonitor 回调设置 `pendingImportVolume`。此时两个 item 都非 nil。SwiftUI 中同一视图上的多个 sheet 只有最后一个生效。如果 FolderPickerSheet 正在显示，ImportSheet 不会出现。但关闭 FolderPickerSheet 后 ImportSheet 可能突然弹出，让用户困惑。
- **触发条件**: 文件夹选择器打开时插入新存储设备

## T10.9 死代码/未使用视图

### 发现 89: statusCard 和 transferCard 是未使用的死视图
- **涉及**: `ContentView.swift` 行 869-896 (`statusCard`), 898-995 (`transferCard`)
- **严重程度**: 低
- **测试方法**: 引用追踪
- **问题描述**: 两个计算属性 `statusCard`（~28行）和 `transferCard`（~98行）定义了完整的 UI 但从未在 `body` 或其他视图中被引用。总计约 126 行死代码。这是从旧版单次导入架构遗留下来的。

---

# 第十二部分：第三轮全新维度测试

**测试日期**: 2026-05-21
**覆盖维度**: 12 个全新测试方向
**测试方法**: 5 个并行 Agent 分别审查：内存管理+生命周期+Swift6并发 / 本地化+无障碍+代码坏味道 / 文件系统边缘+性能+资源 / 错误恢复+数据迁移+磁盘满 / Sendable+魔法数字+God Class

---

## T12.1 内存管理与循环引用

### 发现 97: importTask 闭包强引用 self 形成循环引用 [关键]
- **文件**: `AppViewModel.swift`, 行 833-854
- **严重程度**: **关键**
- **测试方法**: 引用链追踪
- **问题描述**: `importTask = Task { ... self.transferState = state ... self.isImporting = false ... }`。`self` → `importTask`(property) → `Task` → body closure → `self`。形成强引用循环，阻止 ViewModel 在整个导入期间（可能数小时）被 dealloc。
- **触发条件**: 调用 `startImport(with:)` (旧版导入流程)

### 发现 98: scanTask 的 MainActor.run 闭包强引用 self [关键]
- **文件**: `AppViewModel.swift`, 行 472-505
- **严重程度**: **关键**
- **测试方法**: 引用链追踪
- **问题描述**: `scanTask = Task.detached { ... await MainActor.run { self.scannedItems = items ... } }`。外层闭包正确捕获值拷贝，但 `MainActor.run` 闭包强引用 `self`。循环持续到扫描完成。
- **触发条件**: 调用 `scanSelectedSourceFolder()`

### 发现 99: loadFolderChildren Tasks 未存储、无法取消、强引用 self [中]
- **文件**: `AppViewModel.swift`, 行 1597-1635
- **严重程度**: 中
- **问题描述**: 两个功能的 `Task {}` 未存储到属性中，无法取消。快速导航文件夹时多个并发 Task 堆积，每个强引用 self 阻止 dealloc。navigationID 守卫丢弃过期结果，但 Task 继续运行浪费 I/O。

### 发现 100: 所有类均无 deinit 验证 [中]
- **涉及**: AppViewModel, VolumeMonitor, ThumbnailCache
- **严重程度**: 中
- **问题描述**: 无 `deinit`，无法在运行时验证循环引用是否阻止了 deallocation。

### 发现 101: VolumeMonitor 可选闭包 API 设计脆弱 [中]
- **涉及**: `VolumeMonitor.swift` 行 9-10
- **严重程度**: 中
- **问题描述**: `onNewExternalVolume: ((StorageVolume) -> Void)?` 和 `onVolumeUnmounted` 作为强引用存储。当前 AppViewModel 使用 `[weak self]` 安全，但 API 设计容易导致未来调用者误用。

---

## T12.2 App 生命周期与窗口管理

### 发现 102: 无 NSApplicationDelegate — Cmd-Q 直接杀死传输 [高]
- **文件**: `AirwangDITForMacApp.swift` 行 1-16
- **严重程度**: **高**
- **测试方法**: 生命周期审计
- **问题描述**: 无 `applicationShouldTerminate`、无 `applicationWillTerminate`。用户 Cmd-Q 时：(1) 所有传输被硬杀，(2) `.airwang-part` 临时文件残留，(3) FileHandle 未优雅关闭。唯一缓解措施是下次启动时的 `recoverInterruptedProjects`。
- **触发条件**: 传输进行中按 Cmd-Q

### 发现 103: WindowGroup 允许多窗口共享 ViewModel [高]
- **文件**: `AirwangDITForMacApp.swift` 行 8-12
- **严重程度**: **高**
- **测试方法**: 多窗口分析
- **问题描述**: `WindowGroup { ContentView().environmentObject(viewModel) }` 允许 Cmd+N 创建第二个窗口。两个 ContentView 实例观察同一个 `@StateObject`。在窗口 A 打开 sheet 会覆盖窗口 B 的状态（`pendingImportVolume`/`activeFolderPicker` 是单值）。
- **触发条件**: Cmd+N 打开新窗口

### 发现 104: 无休眠/唤醒处理 [中]
- **涉及**: 整个代码库
- **严重程度**: 中
- **问题描述**: 无 `NSWorkspace.willSleepNotification` / `didWakeNotification` 观察者。休眠期间文件句柄可能变陈旧。唤醒后第一个 `read/write` 可能抛出非取消类错误，不被 `fatalInterruptionReason` 捕获。每秒 `ensureAvailable` 检查提供了安全网但有盲区。

---

## T12.3 本地化 (i18n) 审计

### 发现 105: 622 处中文字符串硬编码 — 零本地化基础设施 [严重]
- **涉及**: 全部 8 个 Swift 文件
- **严重程度**: **严重**（对国际化发布）
- **测试方法**: 字符串审计
- **问题描述**: 
  - 零 `NSLocalizedString`、零 `String(localized:)`、零 `.xcstrings`、零 `.lproj`
  - ~98 个 enum 显示字符串全硬编码中文
  - ~200 个 View 层中文字符串
  - ~80 个 ViewModel 错误/状态消息
  - 两个 TXT 报告模板 (~200 行中文) 全硬编码

### 发现 106: 三处硬编码 `Locale(identifier: "zh_CN")` [严重]
- **涉及**: `ContentView.swift` 行 1251, `TransferService.swift` 行 1786, 1891
- **严重程度**: **严重**
- **问题描述**: 强制所有日期格式化为中文，无视用户系统语言。英文用户看到"2026年5月21日"。

### 发现 107: `preciseDateTimeText` 使用中文格式字符串 [高]
- **涉及**: `ContentView.swift` 行 1252
- **严重程度**: 高
- **问题描述**: `formatter.dateFormat = "yyyy年M月d日 HH:mm:ss"` — 此字符串本身是中文，无法本地化。

---

## T12.4 Accessibility (无障碍) 审计

### 发现 108: 全项目零 Accessibility 修饰符 [严重]
- **涉及**: ContentView.swift 3215 行
- **严重程度**: **严重**（对 VoiceOver 用户）
- **测试方法**: a11y 审计
- **问题描述**: 零 `.accessibilityLabel`、零 `.accessibilityHint`、零 `.accessibilityValue`、零 `.accessibilityAction`。约 15 个仅图标的按钮无标签、Toggle 使用 `labelsHidden()` 且无替代文本、缩略图无可访问表示。

### 发现 109: 仅 2 个键盘快捷键 [高]
- **涉及**: ContentView.swift 行 1601, 2781
- **严重程度**: 高
- **问题描述**: 仅 `.keyboardShortcut(.cancelAction)` 用于两个返回按钮。主操作按钮（创建项目、执行队列）无快捷键、Tab 栏无键盘导航、无 focus 管理。

### 发现 110: 无 Reduce Transparency / Reduce Motion 适配 [中]
- **涉及**: ContentView.swift 行 1472-1525, 1528-1561
- **严重程度**: 中
- **问题描述**: 大量使用 `.ultraThinMaterial` 和 4 层阴影。开启 Reduce Transparency 时玻璃效果显示为灰色块，严重影响可读性。`TimelineView` 每秒刷新违反 Reduce Motion 原则。

### 发现 111: 5 处硬编码字体大小不支持 Dynamic Type [中]
- **涉及**: ContentView.swift 行 44, 120, 230, 1897, 2499
- **严重程度**: 中
- **问题描述**: `.font(.system(size: 38))` 等固定字号不随系统字体大小设置缩放。

### 发现 112: 仅颜色区分的状态指示器 [低]
- **涉及**: ContentView.swift 行 535, 584
- **严重程度**: 低
- **问题描述**: 红/绿/橙状态色对红绿色盲用户难以区分。但通常配合文字标签，不完全依赖颜色。

---

## T12.5 文件系统边缘情况

### 发现 113: Unicode 规范化 (NFD vs NFC) 路径比较不一致 [高]
- **涉及**: `MediaScanner.swift` 行 99-109, `AppViewModel.swift` 行 1494-1501, `ContentView.swift` 行 2278-2280
- **严重程度**: **高**
- **测试方法**: Unicode 规范化审计
- **问题描述**: 路径比较使用原始 `String ==`。macOS 在 HFS+ 上使用 NFD（分解），APFS 上使用 NFC（合成）。FAT32/exFAT SD 卡上的日文/中文文件名在两种规范化形式下字节不同 → `==` 比较失败。导致：(1) sidecar 文件无法自动关联，(2) 分栏浏览器文件计数错误，(3) 卷/文件夹身份检查失败。
- **触发条件**: 包含组合 Unicode 字符的文件名（亚洲语言拍摄元数据）

### 发现 114: 符号链接遍历 — 已在 T4.1 发现 28 覆盖 [已记录]

### 发现 115: ensureAvailable 跟随符号链接可能导致假阳性错误 [中]
- **涉及**: `TransferService.swift` 行 1227-1229
- **严重程度**: 中
- **问题描述**: `fileExists(atPath:)` 跟随符号链接。悬空(dangling)符号链接返回 false → 错误的 `deviceUnavailable` 错误。

### 发现 116: shouldSurface 可能暴露 Apple Silicon 系统卷 [低]
- **涉及**: `VolumeMonitor.swift` 行 96
- **严重程度**: 低
- **问题描述**: `url.path.hasPrefix("/Volumes/")` 回退可能匹配 Data/Preboot/VM/Recovery 等系统卷。

---

## T12.6 性能热点分析

### 发现 117: relatedItemIDs O(n²) — 一次性触发 1 亿次操作 [高]
- **涉及**: `AppViewModel.swift` 行 1492-1501
- **严重程度**: **高**
- **测试方法**: 复杂度分析+量化估算
- **问题描述**: 10,000 个扫描项 × 500 个文件/组 × 20 组 = **1 亿次**过滤迭代 + ~1 亿次字符串比较。每次切换整组时触发。
- **量化影响**: 在 M1 Mac 上可能造成数秒的 UI 冻结

### 发现 118: 分栏浏览器 O(n²) 文件夹过滤 [高]
- **涉及**: `ContentView.swift` 行 2235-2280
- **严重程度**: **高**
- **测试方法**: 复杂度分析
- **问题描述**: 500 个文件夹 × 10,000 个文件 = **500 万次**过滤操作每次渲染。每次 SwiftUI 状态变化重新计算。

### 发现 119: TimelineView 20 个项目 = 每天 1,728,000 次 CPU 唤醒 [高]
- **涉及**: `ContentView.swift` 行 431-433
- **严重程度**: **高**
- **测试方法**: 唤醒计数分析
- **问题描述**: 每个项目独立 `TimelineView(.periodic(by: 1))`。20 个项目 = 每秒 20 次唤醒 × 86,400 = 1,728,000 次/天。即使在空闲时 CPU 也无法深度休眠。笔记本电池消耗增加。

### 发现 120: ~28 个玻璃表面 × 4 层阴影 = 112 GPU 绘制调用/帧 [中]
- **涉及**: `ContentView.swift` 行 1528-1561
- **严重程度**: 中
- **测试方法**: GPU 渲染分析
- **问题描述**: 6,720 次阴影绘制/秒 @60fps。集成 GPU (MacBook Air) 会掉帧。

### 发现 121: ByteCountFormatter 创建频率 — 每天超 1 亿次 [中]
- **涉及**: 多处
- **严重程度**: 中
- **测试方法**: 分配模式分析
- **问题描述**: 20 项目 × 60 次/TimelineView tick × 86,400 = ~1.04 亿次 formatter 创建/天。轻量但累积可观。

### 发现 122: NSCache 无 countLimit — 潜在 2.3GB 缓存 [中]
- **涉及**: `ContentView.swift` 行 3141
- **严重程度**: 中
- **问题描述**: 10,000 个缩略图 × ~230KB = 2.3GB 潜在缓存。NSCache 内存压力下自动清除但可能挤出其他应用（如 DaVinci Resolve）。

---

## T12.7 代码坏味道与反模式

### 发现 123: 3 个 God Class — AppViewModel(1702行) / ContentView(3215行) / TransferService(2107行)
- **严重程度**: **高**（可维护性）
- **测试方法**: 职责计数分析
- **问题描述**:
  - AppViewModel: 34 个 @Published、~90 个函数、~12 个独立职责
  - ContentView: 10 个内嵌类型、ImportSheet 自身 1183 行
  - TransferService: 48 个函数、~8 个独立职责
  - Models.swift: 1085 行、29 个类型

### 发现 124: ~220 行重复代码
- **严重程度**: 高
- **测试方法**: 代码差异分析
- **问题描述**:
  - copy vs copySourceFile: ~85 行 (~90% 相同)
  - 4 个路径工具函数在两个文件中字节级相同 (27 行)
  - byteText ×2、folderPath ×2、mediaKind ×2
  - 颜色定义 3 份、渐变背景 3 份、玻璃表面包装器 3 份

### 发现 125: 120+ 个魔法数字
- **严重程度**: 中
- **测试方法**: 字面量统计
- **问题描述**: `16*1024*1024` 出现 4 处、`1_048_576` 出现 2 处、`0.15`/`0.5`/`1.0` 间隔重复 2 处、`80` 出现 2 处、47 个硬编码 RGB 颜色、30+ 个透明度值。全无命名常量。

---

## T12.8 Swift 6 并发 Sendable 审计

### 发现 126: 16 个 struct/enum 类型应标记为 Sendable 但未声明 [高]
- **涉及**: Models.swift 全部数据类型
- **严重程度**: **高**（Swift 6 严格并发模式）
- **测试方法**: Sendable 符合性检查
- **问题描述**: `StorageVolume`、`MediaItem`、`TransferState`、`CopyProject`、`ProjectStageState`、`ProjectMediaItem`、`TransferReport`、`FileVerificationRecord`、`ImportSelectionSummary`、`TimeGroup`、`StorageCapacitySnapshot`、`FolderBrowserItem` 及 enum 类型均包含全 Sendable 成员（String/URL/Int64/Date/Bool/UUID），编译器可自动合成 Sendable。但无显式 `: Sendable` 声明。在 `SWIFT_STRICT_CONCURRENCY = complete` 下会产生警告/错误。

### 发现 127: ImportInterruptionToken @unchecked Sendable — 正确但脆弱 [中]
- **涉及**: `Models.swift` 行 781-818
- **严重程度**: 中
- **测试方法**: 锁分析
- **问题描述**: NSLock 保护所有可变状态，锁使用正确。但 `@unchecked Sendable` 将全部负担放在开发者身上。添加任何无锁保护的新属性都会引入数据竞争。

### 发现 128: TransferService 中使用非 Sendable 的 FileHandle [中]
- **涉及**: `TransferService.swift` 行 1349-1350, 1541, 1680
- **严重程度**: 中
- **问题描述**: `FileHandle` 非 Sendable。在非 @MainActor 的 async 上下文中使用。当前安全因为仅在局部作用域创建和销毁，但 Swift 6 可能产生警告。

---

## T12.9 数据迁移与向前兼容

### 发现 129: CopyProject 自动合成 Codable — 任何字段添加导致全量数据丢失 [关键]
- **涉及**: `Models.swift` 行 667-757
- **严重程度**: **关键**
- **测试方法**: Schema 演化分析
- **问题描述**: 23 个存储属性全必需、无自定义 Decoder、无 `decodeIfPresent` 回退、无 `CodingKeys`、无 schema version 字段。新增任意一个属性 → `DecodingError.keyNotFound` → `try?` 返回 `[]`。**50+ 个项目历史完全消失**。嵌套类型 `ProjectStageState`(17 属性)和 `ProjectMediaItem`(7 属性)任何变更同样级联失败。

### 发现 130: JSON 解码失败完全静默 — 零用户通知 [关键]
- **涉及**: `AppViewModel.swift` 行 1527-1546, `SettingsStore.swift` 行 6-23
- **严重程度**: **关键**
- **测试方法**: 错误处理审计
- **问题描述**: 4 个 `try?` 块静默返回空/默认值。项目 JSON 损坏 → 看到空队列（无声）。偏好 JSON 损坏 → 看到 onboarding 页（无声，仿佛从未用过 App）。**零用户通知**。

### 发现 131: 无 Schema Version 字段 [关键]
- **涉及**: 所有持久化数据结构
- **严重程度**: **关键**
- **问题描述**: 无版本号。无法区分"旧格式数据"和"损坏数据"和"新版数据"。无法编写迁移代码。

### 发现 132: TransferReport 自定义 Decoder 仍脆弱 [高]
- **涉及**: `Models.swift` 行 1040-1068
- **严重程度**: 高
- **问题描述**: `id`、`startedAt`、`finishedAt`、`sourceName`、`sourcePath`、`targetPath` 等字段使用 `try container.decode` 无回退。旧数据缺失任一字段 → 全部报告丢失。

### 发现 133: AppPreferences 简单但可被破坏 [高]
- **涉及**: `Models.swift` 行 116-131
- **严重程度**: 高
- **问题描述**: 添加非可选字段 → `keyNotFound` → 返回 `.default`(targetPath=nil, backupEnabled=false)。用户仿佛首次启动，失去所有配置。

---

## T12.10 错误恢复路径

### 发现 134: saveProjects 失败后无重试机制、无"未保存"指示 [高]
- **涉及**: `AppViewModel.swift` 行 1435-1445
- **严重程度**: **高**
- **问题描述**: 保存失败仅设置 `importError` 弹窗。用户关闭弹窗后若无其他触发保存的操作，所有内存中的状态变更在退出后永久丢失。无"retry save"按钮。

### 发现 135: retryProject() 重置全部阶段 — 无法单独重试失败的备份 [高]
- **涉及**: `AppViewModel.swift` 行 650-674
- **严重程度**: **高**
- **问题描述**: 备份失败后点重试 → 四个阶段全重置为 .queued → 全部文件重拷。1TB 传输中备份在 95% 失败 → 必须重新执行已完成的主盘拷贝+校验。无按阶段选择性重试。

### 发现 136: 扫描阶段错误不区分原因 [中]
- **涉及**: `MediaScanner.swift` 行 18-24, `AppViewModel.swift` 行 497-503
- **严重程度**: 中
- **问题描述**: enumerator 失败返回 `[]`(不抛异常)、`resourceValues` 失败静默 skip。用户看到"没有找到匹配素材"——无法区分"文件夹为空"和"权限拒绝"和"枚举失败"。

### 发现 137: 磁盘满时无 mid-transfer 空间重检 [中]
- **涉及**: `TransferService.swift` 行 1369-1373
- **严重程度**: 中
- **问题描述**: 每秒 `ensureAvailable` 只检查 `fileExists`，不检查可用空间。预检通过后若其他进程写满磁盘，拷贝中途失败但检测不及时。

### 发现 138: 未检测只读卷 — 预检完全盲区 [高]
- **涉及**: 整个代码库
- **严重程度**: **高**
- **问题描述**: 未检查 `volumeIsReadOnlyKey`/`isWritable`。用户选择只读卷为目标 → `destinationWarnings` 无警告 → `canStartImport`=true → 队列执行 → 第一个 `createDirectory` 失败 → 用户看到模糊的 CocoaError。修复难度：极低。

---

## T12.11 资源与 Asset 完整性

### 发现 139: AppIcon 所有尺寸完整 [通过]
- **涉及**: `Assets.xcassets/AppIcon.appiconset/`
- **结果**: 10 个文件全部存在，像素尺寸全部正确

### 发现 140: 所有颜色硬编码 RGB — 无 Asset Catalog 颜色 [中]
- **涉及**: ContentView.swift, Assets.xcassets
- **严重程度**: 中
- **问题描述**: 47 个 `Color(red:green:blue:)` 调用、无 Color Set、无语义颜色命名。不支持系统 Accent Color、不自动适配高对比度。

### 发现 141: NSHumanReadableCopyright 为空字符串 [中]
- **涉及**: project.pbxproj
- **严重程度**: 中
- **问题描述**: 关于对话框显示空版权信息。

### 发现 142: 无 CFBundleVersion 显式设置 [中]
- **涉及**: project.pbxproj
- **严重程度**: 中
- **问题描述**: 对 DIT 软件关键的版本追踪缺失。

---

## T12.12 第三轮新增问题汇总

### 新增关键问题 (8 个)
| # | 简述 |
|---|------|
| 97 | importTask 循环引用 — self→importTask→Task→self |
| 98 | scanTask MainActor.run 循环引用 |
| 105 | 622 处硬编码中文 — 零 i18n 基础设施 |
| 106 | 3 处硬编码 Locale("zh_CN") |
| 108 | 全项目零 Accessibility 修饰符 |
| 129 | CopyProject auto-Codable — 加字段即全量数据丢失 |
| 130 | JSON 解码失败完全静默 — 零用户通知 |
| 131 | 无 Schema Version 字段 |

### 新增高问题 (17 个)
包括: 无 applicationShouldTerminate、WindowGroup 多窗口共享、Unicode 规范化不匹配、O(n²) relatedItemIDs ×2、TimelineView 每天 173 万次唤醒、3 个 God Class、~220 行重复代码、16 个类型缺 Sendable、retryProject 无选择性阶段重试、未检测只读卷、偏好含 Breakable Codable 等

### 新增中问题 (18 个) / 新增低问题 (8 个)

### 发现 91: executionMode 切换在项目运行中不生效
- **涉及**: `AppViewModel.swift` 行 857-872
- **严重程度**: 中
- **测试方法**: 队列执行流程追踪
- **问题描述**: `executionMode` 是 `@Published`，UI 立即响应变化。但 `scheduleQueuedProjects` 只在项目完成 (`finishProjectTask`) 或手动点击"执行任务队列"时调用。如果用户将"按序执行"切换为"并行执行"同时有一个项目在运行，其他排队项目不会自动启动，必须手动再点一次"执行任务队列"。
- **触发条件**: 在有一个项目运行中时切换执行模式

### 发现 92: canRunAlongsideActiveProjects 不检查源卷冲突
- **涉及**: `AppViewModel.swift` 行 1101-1122
- **严重程度**: 中
- **测试方法**: 并行安全性分析
- **问题描述**: 并行检查考虑了 target-to-target、backup-to-target、target-to-backup、backup-to-backup 四对卷共享关系，但**从未检查两个项目的 source 卷是否相同**。如果两个项目从同一个源设备读取，并行执行会导致 I/O 争用，速度大幅下降。卷共享检查只防止写冲突，不防止读冲突。
- **触发条件**: 两个排队项目使用同一个源设备但不同目标盘

### 发现 93: 取消备份时清除 errorMessage 可能掩盖未解决的故障
- **涉及**: `AppViewModel.swift` 行 1267-1294
- **严重程度**: 中
- **测试方法**: 状态管理分析
- **问题描述**: `applyProjectBackup` 在取消备份 (`backupURL == nil`) 时将 `errorMessage = nil`。如果项目之前因"主盘异常，备份已阻塞"而处于 blocked 状态，移除备份会让这条错误消失——即使主盘问题仍未解决。用户可能误认为清除备份就解决了问题。
- **触发条件**: 对 blocked 状态的项目执行"取消备份"

### 发现 94: retryLatestFailedItems 在无失败文件时静默返回
- **涉及**: `AppViewModel.swift` 行 762-763
- **严重程度**: 低
- **测试方法**: 空状态测试
- **问题描述**: `guard let latestReport, !latestReport.failedFiles.isEmpty else { return }` — 如果 `latestReport` 存在但没有失败文件（如之前的导入完全成功），用户点击"重试异常"按钮时静默无反应。没有设置 `importError` 给用户任何反馈。
- **触发条件**: 最新报告成功完成无异常时点击"重试异常"

### 发现 95: openProjectReport 错误消息不包含项目名称
- **涉及**: `AppViewModel.swift` 行 746-747
- **严重程度**: 低
- **测试方法**: 用户体验审查
- **问题描述**: 错误消息 "这个项目还没有生成主盘报告" 不指定是哪个项目。如果多个项目都没有报告，用户无法确定问题是针对哪个项目的。

### 发现 96: ImportInterruptionToken 的 NSLock 正确但 @unchecked Sendable 有风险
- **涉及**: `Models.swift` 行 781-818
- **严重程度**: 低
- **测试方法**: 线程安全审查
- **问题描述**: `ImportInterruptionToken` 使用 `@unchecked Sendable` 配合 `NSLock`。每次属性读写都正确获取/释放锁。但如果有调用者读取 `reason` 和 `verificationModeOverride` 两个属性作为原子对（例如：先读 reason 得 nil，另一个线程设置 stop，再读 override 得 .skipped），会观察到不一致的快照。NSLock 只保证每个属性独立原子性，不保证跨属性的一致性。

---

# 第十一部分：第二轮问题汇总

## 新增关键问题
无新增关键问题

## 新增高问题 (2 个)
| # | 文件 | 行号 | 简述 |
|---|------|------|------|
| 73 | AppViewModel | 1338-1387 | 设备拔出时未清除 pendingImportVolume → 导入弹窗残留 |
| 88 | ContentView | 23, 27 | 双 Sheet 冲突 — 选择器打开时新设备插入导致 ImportSheet 被抑制 |

## 新增中问题 (10 个)
| # | 文件 | 行号 | 简述 |
|---|------|------|------|
| 67 | ContentView+VM | 16, 83 | onboarding→dashboard 切换无过渡动画 |
| 70 | ContentView | 200,300,328 | "执行任务队列"无禁用状态、无反馈 |
| 74 | ContentView+VM | 1960, 486 | 步骤指示器跳过第 3 步（自动全选导致）|
| 75 | ContentView+VM | 2583, 572 | "创建项目并加入队列"标签具有误导性 |
| 78 | ContentView+VM | 415, 679 | 上移/下移边界无禁用状态 |
| 81 | ContentView+VM | 395, 2991 | 设备拔出后仍可确认文件夹选择 |
| 83 | ContentView+VM | 635, 742 | 报告按钮禁用逻辑不完整（ID 存在但报告缺失）|
| 85 | AppViewModel | 724 | 跳过校验三次确认中 importError 被覆盖 |
| 86 | AppViewModel | 29 | 单一错误字符串被快速连续错误覆盖 |
| 87 | AppViewModel | 572 | 成功通知与错误消息混用同一通道 |

## 新增低问题 (10 个)
包括: 备份可先于目标配置、默认Tab错误、孤儿异步任务、按钮禁用状态文本、死代码删除路径、浏览即选择、报告 8 条截断、死视图代码、死 fallback 路径、双重误导标签等
