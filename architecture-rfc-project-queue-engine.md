# RFC: ProjectQueueEngine — 把项目队列编排从 AppViewModel 深化为可测试模块

| 字段 | 内容 |
|---|---|
| 状态 | Draft |
| 日期 | 2026-06-10 |
| 作者 | 架构审查(improve-codebase-architecture 流程产出) |
| 前置 | 候选 2(路径语义收口)已落地:`PathSafety.pathsOverlap` / `pathsShareVolume` 为唯一实现,38 处调用点统一,`DiskCapacityResolver.volumeRootPath` 系统卷 nil bug 已修 |

---

## Problem

**哪些模块浅且强耦合:**

[AppViewModel.swift](Airwang DIT for Mac/ViewModels/AppViewModel.swift) 约 600 行队列编排逻辑与 UI 状态、媒体扫描、文件夹导航、偏好设置共居一个 2000+ 行的 `@MainActor ObservableObject`:

- 调度决策:`scheduleQueuedProjects(automaticOnlyAt:)`(槽位分配 + autoStart 过滤)、`canRunAlongsideActiveProjects`(五组卷互斥规则)、`continueQueueAfterStateChange`(手动/自动二分)
- 生命周期:`launchProject` → `runQueuedProject`(主盘→备份两阶段串联,中途 4 处状态分支)→ `finishPrimaryStage` / `finishBackupStage` / `finishProjectTask`
- 定时:`scheduleNextAutoStartCheck`(自管理 `autoStartTask: Task` + 0.5s 下限的 deadline 重排)
- 异常路径:`cancelProject`、`handleUnmountedVolume`、`recoverInterruptedProjects`(冷启动重放)
- 簿记:`projectTasks: [UUID: Task]`、`projectTokens: [UUID: ImportInterruptionToken]`、`activeProjectIDs`、`manualQueueRunActive`

**接缝处的集成风险:**

1. 状态迁移没有收口点 —— 十几个 `updateProject { $0.status = ... }` 散落各处,错误文案(中文)内联在迁移逻辑里。新增一种状态或一条迁移规则时,无法枚举"现在共有哪些合法迁移"。
2. 拔盘竞态(TEST_REPORT #19):`handleUnmountedVolume` 对 token.stop / task.cancel / updateProject 的时序与 `runQueuedProject` 的收尾路径存在最后写入者胜出。
3. `executionMode` 切换只在 `didSet` 里触发一次 `continueQueueAfterStateChange`,与 `manualQueueRunActive` 的交互语义没有任何测试钉住(#91 的修复就在这种盲区里反复横跳)。
4. GA 计划 Phase 3 的两项任务 —— 单阶段重试(Task 3.6)、多源并行调优(Task 3.5)—— 都必须改这块代码,而它**测试覆盖为零**:任何回归只能靠真盘手测发现。

**为什么难以导航、修改、测试:**

- 理解"下一个项目什么时候启动"需要同时打开 4 个函数 + 2 个标志位 + 1 个定时器;
- 测试需要实例化整个 AppViewModel(连带 SettingsStore 读磁盘、VolumeMonitor 订阅通知);
- 进度回调链(TransferService → MainActor.run → applyProgress → updateProject)跨 3 个抽象层。

## Candidate summary

| 字段 | 评估 |
|---|---|
| Dependency category | 编排本身 **in-process**;对 TransferService 为 **local-substitutable**(真实文件 I/O,可用 fake stage runner / 临时目录替代);定时与时钟注入后为 in-process |
| Expected leverage | **最高**。已知 bug #16/#19/#91/#92/#93 全部位于此簇;Phase 3 两项功能直接压在它上面;唯一零测试的核心业务逻辑收口为一个可独立测试的模块 |
| Migration cost / risk | **中高**。唯一调用方是 AppViewModel(利好),但 ContentView 直接绑定 `@Published copyProjects` / `activeProjectIDs`(需要转发或重绑);取消收尾语义微妙,迁移必须"先搬运后重构",分 3 个 PR |
| Confidence | **High** —— 直接调用链追踪 + bug 聚集证据 + 候选 2 热身已验证该区域可安全机械化迁移 |

## 问题域框定

**新接口必须满足的约束:**

1. UI 持续观察项目列表与活跃集合(SwiftUI 绑定,`@Published` 兼容);
2. 阶段执行留在 TransferService(已是深模块)—— 引擎编排,不碰文件;
3. 取消语义保持"优雅收尾":`token.stop(reason:)` 后阶段返回 cancelled 报告,而非中断抛错;`.cancelling` 是可观察的中间态;
4. 状态迁移后必须持久化;持久化失败时队列**拒绝启动新项目**(现有 `hasUnsavedChanges` 门),不允许内存状态与磁盘漂移时继续写盘;
5. autoStart deadline 在任何状态变化后重排定时器;手动执行队列清除所有排队项目的 autoStart;
6. 冷启动恢复:`.running` → `.failed`、`.cancelling` → `.cancelled`(语义区分,#16);
7. 引擎 `@MainActor`(SwiftUI 一致性),阶段任务跑在引擎外的并发上下文;
8. 并发上限来自 `executionMode`,互斥规则基于卷拓扑(源-源、目标-目标、目标-备份、备份-备份);
9. 单飞:同一项目绝不双launch(现有 `projectTasks[id] == nil` 守卫);
10. 拔盘事件强制失败所有触及该卷的活跃/排队项目,且**先等任务退出再定状态**(根治 #19)。

**必须依赖的边界:** TransferService(两个 stage 方法)、持久化(写 projects 数组)、时钟与定时器(autoStart 可测的前提)、PathSafety(卷互斥,纯函数,已测)。

**非目标:** 不动文件拷贝/校验内核;不改 CopyProject 持久化格式;不改 UI 绑定架构(仍是 ObservableObject);本期不实现单阶段重试,但接口必须给它留座位。

**可能的失败模式:** 取消收尾语义漂移(cancelled vs failed 的边界)、定时器泄漏或迟到触发、`finishProjectTask → continueQueue → launchProject` 的重入序列在迁移中被打断、持久化门失效导致漂移写盘。

**草图(仅为约束定锚,非承诺设计):**

```swift
// 事件进 → 迁移出。所有 status 写入收口到一个 transition 函数。
engine.add(project)                  // queued (+autoStart deadline)
engine.startQueue(manual: true)      // 清 autoStart → 按槽位与互斥规则 launch
// stage 完成 → engine 内部: blocked / completed / 进入备份阶段
engine.cancel(projectID)             // running → cancelling → (任务退出) → cancelled
engine.volumeUnmounted(url)          // 触及者 → cancelling → 等退出 → failed(原因:设备拔出)
```

## Proposed interface(推荐设计,含备选对比见附录)

**推荐:设计 A(事件方法 + 最小表面)为骨架,内化设计 B 的迁移收口纪律,只取设计 C 的时钟/定时器注入。**

```swift
/// 项目队列引擎:唯一有权写 CopyProject.status 的地方。
@MainActor
final class ProjectQueueEngine: ObservableObject {

    // MARK: 可观察状态(UI 经 AppViewModel 转发或直接绑定)
    @Published private(set) var projects: [CopyProject]
    @Published private(set) var activeProjectIDs: Set<UUID>

    var executionMode: ProjectExecutionMode { get set }   // didSet 内部自动 continueQueue

    // MARK: 生命周期事件(全部同步返回,内部派生异步工作)
    func add(_ project: CopyProject)
    func startQueue(manual: Bool)
    func cancel(_ projectID: UUID)
    func cancelAutoStart(_ projectID: UUID)
    func remove(_ projectID: UUID)
    func requeue(_ projectID: UUID, resetAllStages: Bool)   // 为 Phase 3 单阶段重试留座位
    func volumeUnmounted(_ volumeURL: URL) async             // 等待受影响任务退出后才返回
    func recoverAfterColdLaunch()

    // MARK: 注入边界
    init(
        stageRunner: any ProjectStageRunning,
        persistence: any ProjectQueuePersisting,
        clock: any QueueClock = SystemQueueClock(),
        configuration: Configuration = .init()
    )
}

/// TransferService 的窄端口 —— 引擎只认识这两个动作。
protocol ProjectStageRunning: Sendable {
    func runPrimaryStage(_ project: CopyProject, token: ImportInterruptionToken,
                         language: AppLanguage,
                         progress: @escaping @Sendable (TransferState) async -> Void
    ) async throws -> TransferService.ProjectStageResult

    func runBackupStage(_ project: CopyProject, token: ImportInterruptionToken,
                        language: AppLanguage,
                        progress: @escaping @Sendable (TransferState) async -> Void
    ) async throws -> TransferService.ProjectStageResult
}

/// 持久化端口:返回是否成功;失败时引擎进入"持久化降级"态,拒绝 launch 新项目。
protocol ProjectQueuePersisting {
    func persist(_ projects: [CopyProject]) -> Bool
}

/// 时钟端口:autoStart 可测的前提。
protocol QueueClock: Sendable {
    var now: Date { get }
    func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> any Cancellable
}

/// 引擎对外的事件流(报告产出、状态迁移、用户可见提示的原因码)。
/// 注意:引擎不产生中文文案 —— 只发原因码,文案由 ViewModel 映射(为 i18n Task 4.1 铺路)。
enum QueueEvent {
    case stageFinished(projectID: UUID, stage: ProjectTransferStage, report: TransferReport)
    case transitioned(projectID: UUID, from: CopyProjectStatus, to: CopyProjectStatus, cause: TransitionCause)
    case persistenceDegraded(Bool)
}
var events: AsyncStream<QueueEvent> { get }

enum TransitionCause: Equatable {
    case userCancelled, volumeUnmounted(path: String), primaryFailed, backupFailed,
         completed, autoStarted, manualStarted, coldLaunchRecovery(wasCancelling: Bool)
}
```

**用法示例(AppViewModel 收敛为门面):**

```swift
@MainActor final class AppViewModel: ObservableObject {
    let queue: ProjectQueueEngine   // ContentView 可经 viewModel.queue.projects 绑定

    init() {
        queue = ProjectQueueEngine(
            stageRunner: transferService,            // TransferService 直接 conform
            persistence: projectStoreAdapter,        // 包装 JSONPersistence.writeProjects
            clock: SystemQueueClock()
        )
        Task { @MainActor [weak self] in
            for await event in self!.queue.events {
                self?.handle(event)                  // 报告入库、本地化提示、Sentry 面包屑
            }
        }
    }
}
```

**接口内部隐藏的复杂度:** 槽位分配与五组卷互斥;autoStart deadline 的定时器重排(0.5s 下限、取消旧任务);`projectTasks`/`projectTokens` 簿记与单飞守卫;两阶段串联中的 cancelled/blocked/failed/completed 四分支;**所有** `status` 写入收口到私有 `transition(_:to:cause:)`(单一迁移函数 = 设计 B 的纪律,不带 B 的 reducer 形式税);拔盘时 await 任务退出的时序(先 `.cancelling` → stop token → await task → 终态,消灭 #19 的竞态窗口);持久化失败的降级门与恢复。

**留在引擎外:** 报告数组的所有权与排序(经 `stageFinished` 事件交给 ViewModel/未来的 ReportController);所有用户可见文案(引擎只发 `TransitionCause`);`isImporting` 全局旗标(ViewModel 从 `activeProjectIDs` 派生);媒体扫描/导入 sheet 状态;偏好设置。

## Dependency strategy

| 依赖 | 类别 | 生产 | 测试 |
|---|---|---|---|
| TransferService | local-substitutable | `TransferService: ProjectStageRunning`(已有方法,签名微调) | `FakeStageRunner`:可编程返回 成功/失败/取消报告,可挂起以测时序 |
| 持久化 | local-substitutable | 适配器包装 `JSONPersistence.writeProjects` | `SpyPersistence`:记录调用、可注入失败 |
| 时钟/定时器 | in-process(注入后) | `SystemQueueClock`(Task.sleep) | `ManualClock`:手动推进时间,deadline 测试确定化 |
| 卷互斥 | in-process | 直接调 `PathSafety.pathsShareVolume`(已测,候选 2 产物) | 真实临时目录(同卷→冲突)即可,不再抽象 |

## Testing strategy

**新边界测试(全部经公共接口断言可观察结果):**

1. 顺序模式:3 个排队项目逐个启动,顺序与 orderIndex 一致;
2. 并行模式:不同卷的项目并行,共卷项目互斥等待;
3. 主盘失败 + 有备份 → `.blocked`,备份阶段从未调用(FakeRunner 断言);
4. 主盘成功无备份 → `.completed`;
5. 执行中取消 → `.cancelling` 可观察 → FakeRunner 返回取消报告 → `.cancelled`;
6. autoStart:ManualClock 推到 deadline 前一刻不启动、到点启动;`cancelAutoStart` 后永不自动启动;
7. 手动 `startQueue` 清除全部排队项的 autoStart 字段;
8. 拔盘:活跃项目先 `.cancelling`、await 退出后 `.failed(cause: volumeUnmounted)`,不存在终态被反向覆盖(#19 回归测试);
9. 持久化失败 → `persistenceDegraded(true)` 事件 + 拒绝 launch;恢复后门重开;
10. 冷启动恢复:`.running` → `.failed`、`.cancelling` → `.cancelled`,cause 区分(#16 回归测试);
11. 单飞:连续两次 `startQueue` 不会对同一项目双 launch;
12. `executionMode` 运行中切换 sequential→parallel:下一槽位立即补位(#91 回归测试)。

**变冗余的旧测试:** 无 —— 这块现在是零覆盖,只有新增没有删除。`PersistenceCompatibilityTests` 中 `isAutoStartReady` 等模型级测试保留(模型谓词仍被引擎使用)。

**需要的替身:** `FakeStageRunner` / `SpyPersistence` / `ManualClock`,共约 120 行,放 `Airwang DIT for MacTests/QueueEngineTestSupport.swift`。

## Migration notes

**引擎应当拥有:** `projects` 数组的写权(含 orderIndex 归一化)、`activeProjectIDs`、任务/令牌表、autoStart 定时器、全部 status 迁移、迁移后持久化触发。

**保持在外:** 报告集合、用户文案、全局 isImporting、扫描/导入流程、偏好。

**迁移路径(3 个 PR,每个独立可回滚):**

1. **PR1 — 垂直搬运(无行为变更):** 新建 `Services/ProjectQueueEngine.swift`,函数级搬运现有逻辑;AppViewModel 持有引擎并转发 `@Published`(`queue.$projects.assign(...)` 或计算属性);TransferService conform `ProjectStageRunning`;落 12 条边界测试。验收:全部测试绿 + 手测一次真盘队列。
2. **PR2 — 收口与原因码:** 内部引入 `transition(_:to:cause:)` 单点;把内联中文文案替换为 `TransitionCause` → ViewModel 映射文案(同时修 #16 的区分语义);拔盘改为 await-退出时序(修 #19)。验收:回归测试 8/10 由红转绿。
3. **PR3 —(可选)直绑与瘦身:** ContentView 改绑 `viewModel.queue.projects`,删除转发层;AppViewModel 预计 -600 行。

**开放问题 / 后续风险:**

- `runQueuedProject` 中"备份阶段读主盘"的前置校验(`validateProjectStageSeparation`)留在 TransferService —— 引擎不重复校验,接受阶段抛错作为失败迁移输入;
- `requeue(_:resetAllStages:)` 本期只实现 `resetAllStages: true`(等价现状),`false` 分支留给 Phase 3 Task 3.6,接口已占位;
- Swift 6 strict concurrency 开启后(GA 计划 Task 1.5),`QueueEvent` 流与 `@MainActor` 边界需复核一次 Sendable;
- 若未来引入多窗口(目前已单窗口化),引擎单例所有权需要重新讨论。

---

## 附录:三个候选设计的完整对比

### 设计 A — 最小表面(事件方法 + ObservableObject)

即上文推荐主体。**取舍:** 接口即方法列表,可发现性最好、与现有代码习语零距离;但状态迁移纪律靠约定(私有 transition 函数)而非类型系统强制。**失败模式:** 后来者绕过 transition 直接改 status —— 用 `private(set)` + code review 检查表防御。**迁移形状:** 函数级搬运,风险最低。

### 设计 B — 显式状态机(纯 reducer + 效果解释器)

```swift
enum QueueReducer {
    static func reduce(_ state: inout QueueState, _ event: QueueEvent, rules: QueueRules) -> [QueueEffect]
}
final class QueueRuntime { /* 解释 [QueueEffect]:起任务、定时、持久化 */ }
```

**隐藏复杂度:** 全部迁移规则成为纯函数,可用穷举表测试,迁移合法性可静态审计。**取舍:** 可测试性天花板,但这套习语(TCA 风格)与代码库完全陌生,进度回调约 10Hz 走事件管道有性能噪声,需要旁路通道 —— 旁路一开,纯度承诺即打折。**失败模式:** reducer 与 runtime 的边界谈判变成新的复杂度来源。**迁移形状:** 重写而非搬运,成本最高,回滚困难。**结论:不取其形,取其神**(单一迁移收口点 + cause 枚举)。

### 设计 C — 端口与适配器(闭包端口包)

```swift
struct Ports {
    var runStage: (CopyProject, ProjectTransferStage, ...) async throws -> ProjectStageResult
    var persist: ([CopyProject]) -> Bool
    var now: () -> Date
    var scheduleTimer: (TimeInterval, @escaping () -> Void) -> Cancellable
    var conflicts: (CopyProject, CopyProject) -> Bool
}
```

**隐藏复杂度:** 同 A,外加一切 I/O 可在测试中零协议替换。**取舍:** 端口包易膨胀为杂物抽屉;`conflicts` 端口属于过度抽象(PathSafety 已是纯函数,直接调用即可测);闭包捕获列表在 @MainActor 边界上易踩 Sendable 雷。**失败模式:** Ports 结构成为没有语义的参数巨兽。**迁移形状:** 与 A 相近。**结论:只取时钟/定时器注入**(这是测试确实无法用真实现的唯一依赖),其余用协议。

### 对比结论

A 与 C 的迁移成本相近且都贴近现有习语,差异在替身机制:协议(A)对两个有名有姓的依赖(stage runner、持久化)更易发现和文档化;闭包(C)只该用于"小而无名"的依赖(时钟)。B 的纯 reducer 在这个 10Hz 进度流 + SwiftUI 绑定的场景里形式税过高,但它指出的核心病灶 —— 迁移无收口点 —— 是三个设计都必须解决的,A 用最低成本的方式(私有单点函数 + cause 枚举)解决它。故推荐 **A 骨架 + B 纪律 + C 时钟注入** 的混合体。
