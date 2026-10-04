import Foundation

enum ImportMode: String, CaseIterable, Identifiable {
    case time
    case free

    var id: String { rawValue }

    var title: String {
        switch self {
        case .time: "时间模式"
        case .free: "自由模式"
        }
    }

    var subtitle: String {
        switch self {
        case .time: "按日期自动分组，适合快速按拍摄批次整理"
        case .free: "缩略图浏览与手动多选，适合精细挑选素材"
        }
    }
}

enum AssetBrowserMode: String, CaseIterable, Identifiable {
    case icon
    case list
    case column
    case gallery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: "图标"
        case .list: "列表"
        case .column: "分栏"
        case .gallery: "画廊"
        }
    }

    var systemImage: String {
        switch self {
        case .icon: "square.grid.2x2"
        case .list: "list.bullet"
        case .column: "rectangle.split.3x1"
        case .gallery: "rectangle.on.rectangle"
        }
    }

    var subtitle: String {
        switch self {
        case .icon: "缩略图快速扫片"
        case .list: "按名称、路径、大小、时间精确核对"
        case .column: "按文件夹结构理解卡内素材"
        case .gallery: "大预览配合胶片条精挑"
        }
    }
}

enum MainSection: String, CaseIterable, Identifiable {
    case copy
    case dashboard
    case backup
    case organize
    case statistics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .copy: "拷贝"
        case .dashboard: "仪表盘"
        case .backup: "备份"
        case .organize: "规整"
        case .statistics: "统计"
        }
    }

    var systemImage: String {
        switch self {
        case .copy: "square.and.arrow.down.on.square"
        case .dashboard: "gauge.with.dots.needle.67percent"
        case .backup: "externaldrive.badge.timemachine"
        case .organize: "folder.badge.gearshape"
        case .statistics: "chart.xyaxis.line"
        }
    }
}

enum StatisticsActivityMode: String, CaseIterable, Identifiable {
    case daily
    case weekly
    case cumulative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "每日"
        case .weekly: "每周"
        case .cumulative: "累计"
        }
    }
}

enum AppTheme: String, CaseIterable, Identifiable, Codable {
    case day
    case night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "白天"
        case .night: "夜晚"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case chinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chinese: "中文"
        case .english: "English"
        }
    }

    var shortTitle: String {
        switch self {
        case .chinese: "中"
        case .english: "EN"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .chinese: "zh_CN"
        case .english: "en_US"
        }
    }
}

enum AppLocalization {
    static func text(_ key: String, language: AppLanguage) -> String {
        guard language == .english else { return key }
        return english[key] ?? key
    }

    private static let english: [String: String] = [
        "主题": "Theme",
        "白天": "Day",
        "夜晚": "Night",
        "语言": "Language",
        "中文": "Chinese",
        "界面设置": "Interface Settings",
        "自动执行": "Auto Start",
        "支持与诊断": "Support and Diagnostics",
        "导出诊断": "Export Diagnostics",
        "导出 PDF 报告": "Export PDF Report",
        "取消 PDF 导出": "Cancel PDF Export",
        "找不到原始 TXT 报告，无法导出完整 PDF。": "The original TXT report is missing. A complete PDF cannot be exported.",
        "PDF 包含原始 TXT 的完整明细，请选择新名称以保留已有文件。": "The PDF contains all original TXT evidence. Choose a new name to preserve existing files.",
        "正在导出 PDF 报告…": "Exporting PDF report…",
        "PDF 报告已导出（%d 页）。": "PDF report exported (%d pages).",
        "PDF 导出已取消。": "PDF export cancelled.",
        "请选择可写文件夹中的 PDF 文件。": "Choose a PDF file in a writable folder.",
        "找不到有效的原始 TXT 报告。": "The original TXT report is unavailable or invalid.",
        "原始 TXT 报告在读取期间发生变化，导出已停止。": "The original TXT report changed while being read. Export stopped.",
        "无法完整生成 PDF 报告。": "The complete PDF report could not be generated.",
        "PDF 报告正在导出。请先取消并等待导出收尾后再退出。": "A PDF report is being exported. Cancel it and wait for cleanup before quitting.",
        "取消导出": "Cancel Export",
        "导出版本、系统环境和任务状态。诊断不包含素材、文件名、路径或原始错误文本。": "Export the app version, system information, and task status. Media, filenames, paths, and raw error text are excluded.",
        "请选择新名称以保留已有诊断文件。": "Choose a new name to preserve existing diagnostic files.",
        "正在导出诊断…": "Exporting diagnostics…",
        "已导出诊断，可先检查文件再提供给支持人员。": "Diagnostics exported. Review the file before sharing it with support.",
        "诊断导出已取消": "Diagnostics export cancelled",
        "诊断导出失败": "Diagnostics export failed",
        "已有文件已保留，请选择新名称。": "The existing file was preserved. Choose a new name.",
        "请选择可写文件夹中的 JSON 文件。": "Choose a JSON file in a writable folder.",
        "仍有导入、校验、规整或诊断导出正在执行。请先取消并等待文件操作收尾后再退出。": "Import, verification, organization, or diagnostics export is still running. Cancel it and wait for file operations to finish before quitting.",
        "新建任务默认 5 分钟后自动执行": "Auto-start new queued projects after 5 minutes",
        "关闭后，新建项目只加入队列，需要手动执行。": "When off, new projects only enter the queue and require manual start.",
        "当前执行方式": "Current Run Policy",
        "加入队列，等待手动执行": "Queue and wait for manual start",
        "加入队列，5 分钟后自动执行": "Queue and auto-start after 5 minutes",
        "任务将在 5 分钟后开始写入目标盘，请确认源盘、主盘、备份盘路径无误。": "The task will start writing in 5 minutes. Confirm the source, primary, and backup paths first.",
        "拷贝": "Copy",
        "仪表盘": "Dashboard",
        "备份": "Backup",
        "规整": "Organize",
        "统计": "Stats",
        "多项目拷贝队列、主盘校验、串行备份与可追溯报告": "Multi-project copy queue, primary verification, serial backup, and traceable reports",
        "选择主目标盘": "Choose Primary Target",
        "刷新设备": "Refresh Devices",
        "执行队列": "Run Queue",
        "执行任务队列": "Run Task Queue",
        "拷贝项目创建": "Copy Project Setup",
        "执行方式": "Run Mode",
        "主目标盘": "Primary Target",
        "备份盘": "Backup Drive",
        "项目数": "Projects",
        "运行中": "Running",
        "默认校验": "Default Verify",
        "已检测设备": "Detected Devices",
        "任务队列": "Task Queue",
        "任务日志": "Task Log",
        "备份工作台": "Backup Workspace",
        "暂无备份项目": "No Backup Projects",
        "暂无任务": "No Tasks",
        "队列为空": "Queue Empty",
        "还没有拷贝项目": "No Copy Projects Yet",
        "暂未发现可导入设备": "No Importable Devices Detected",
        "当前 App 存储暂无任务日志": "No task logs in app storage",
        "点击选择": "Choose",
        "开始导入": "Start Import",
        "开始": "Start",
        "完成": "Finished",
        "成功": "Success",
        "异常": "Issue",
        "在访达中打开": "Reveal in Finder",
        "查看拷贝报告": "Open Copy Report",
        "查看备份报告": "Open Backup Report",
        "打开主盘": "Open Primary",
        "主盘报告": "Primary Report",
        "备份报告": "Backup Report",
        "取消": "Cancel",
        "重试": "Retry",
        "仅重试备份": "Retry Backup Only",
        "等待独立备份重试": "Waiting for independent backup retry",
        "按原主盘报告复核后补备份，可拔出原始源卡。": "Check the primary against its original report, then complete the backup. The original card can be disconnected.",
        "此次执行从主盘读取，主盘完成状态和原报告已保留。": "This run reads from the primary. Its completed state and original report are retained.",
        "主盘完成记录不足，或项目仍在执行，无法独立重试备份。": "The completed primary record is unavailable, or the project is still running. Independent backup retry is unavailable.",
        "无法独立重试备份": "Independent backup retry unavailable",
        "当前手动队列会继续执行此项目。": "The current manual queue will continue with this project.",
        "请手动执行任务队列。": "Start the task queue manually.",
        "项目“%@”已加入独立备份重试队列。主盘完成状态和原报告已保留，已有备份文件会完整复核 SHA-256。": "Project \"%@\" has been queued for independent backup retry. The completed primary and original report are retained. Existing backup files will receive full SHA-256 verification.",
        "独立备份重试只修改显示名称与后续报告标题，已有主盘文件夹保持不变。": "Renaming an independent backup retry changes its display name and future report titles. The existing primary folder is retained.",
        "独立备份重试已取消，主盘完成状态已保留。": "Independent backup retry cancelled. The completed primary state is retained.",
        "改名": "Rename",
        "删除": "Delete",
        "更换备份": "Change Backup",
        "添加备份": "Add Backup",
        "取消备份": "Remove Backup",
        "更换备份盘": "Change Backup Drive",
        "添加备份盘": "Add Backup Drive",
        "取消自动执行": "Cancel Auto Start",
        "跳过校验": "Skip Verify",
        "排队中": "Queued",
        "执行中": "Running",
        "取消中": "Cancelling",
        "已完成": "Completed",
        "已阻塞": "Blocked",
        "已取消": "Cancelled",
        "仅主盘": "Primary Only",
        "含备份": "With Backup",
        "未启用": "Disabled",
        "未设置": "Not Set",
        "尚未设置": "Not Set",
        "未配置备份盘": "No Backup Drive",
        "等待主盘完成": "Waiting for primary",
        "等待备份完成": "Waiting for backup",
        "外部设备": "External Device",
        "可用卷": "Available Volume",
        "容量暂不可读": "Capacity unavailable",
        "素材总量": "Payload Size",
        "安全冗余": "Safety Margin",
        "最低需求": "Minimum Required",
        "可用空间": "Available Space",
        "预检状态": "Preflight Status",
        "可执行": "Ready",
        "空间不足": "Insufficient Space",
        "容量不可读，已阻止执行": "Capacity unavailable, execution blocked",
        "存储": "Storage",
        "源设备": "Source Device",
        "目标": "Target",
        "导入状态": "Import Status",
        "进行中": "Running",
        "已拷贝": "Copied",
        "已校验": "Verified",
        "实时速度": "Speed",
        "预估剩余": "ETA",
        "导入进度": "Import Progress",
        "校验进度": "Verify Progress",
        "当前文件": "Current File",
        "安全事件": "Safety Event",
        "校验报告": "Verification Report",
        "取消任务": "Cancel Task",
        "打开目标": "Open Target",
        "查看报告": "Open Report",
        "重试异常": "Retry Failed Items",
        "新存储设备已接入": "New Storage Device Connected",
        "模式": "Mode",
        "退出": "Close",
        "自由浏览": "Free Browse",
        "浏览方式": "Browse Mode",
        "名称": "Name",
        "类型": "Type",
        "大小": "Size",
        "创建时间": "Created",
        "文件夹": "Folder",
        "扫描根目录": "Scan Root",
        "根目录文件": "Root Files",
        "预览详情": "Preview Details",
        "没有可预览的素材": "No Preview Available",
        "选择素材": "Select Media",
        "开始拷贝+校验": "Start Copy + Verify",
        "正在扫描素材...": "Scanning media...",
        "全选": "Select All",
        "清空选择": "Clear Selection",
        "整组已选": "Group Selected",
        "点击圆圈选择整组": "Click the circle to select the group",
        "收起": "Collapse",
        "从导入中移除": "Remove from Import",
        "加入导入选择": "Add to Import",
        "选择源文件夹": "Choose Source Folder",
        "上一级": "Up",
        "扫描类型": "Scan Type",
        "进入并设为当前": "Enter and Set Current",
        "当前准备扫描": "Ready to Scan",
        "只扫描这个目录": "Scan This Folder Only",
        "扫描此文件夹": "Scan This Folder",
        "导入摘要": "Import Summary",
        "已扫描": "Scanned",
        "待扫描": "Waiting to Scan",
        "项目名称": "Project Name",
        "当前名称": "Current Name",
        "校验方式": "Verification Mode",
        "创建项目并加入队列": "Create Project and Queue",
        "返回": "Back",
        "位置": "Location",
        "进入": "Enter",
        "已选目录": "Selected Folder",
        "请选择一个目录": "Choose a folder",
        "设为主目标盘": "Set as Primary Target",
        "设为备份盘": "Set as Backup Drive",
        "数据正在保存中，请稍后再试": "Saving data, please try again shortly",
        "当前没有排队中的项目，请先创建拷贝任务": "No queued projects. Create a copy task first",
        "当前无法执行队列": "Queue cannot run right now",
        "开始执行排队中的拷贝项目": "Start running queued copy projects",
        "写入总量": "Written",
        "近 7 天": "Last 7 Days",
        "报告数": "Reports",
        "最近 16 周写入热力图": "Last 16 Weeks Activity",
        "颜色越深，当天写入量越大。统计来自 App 本地任务报告，主盘与备份阶段都会计入写入总量。": "Darker cells mean more data written that day. Stats come from local task reports and include primary and backup stages.",
        "暂无统计数据": "No Stats Yet",
        "完成一次拷贝后，这里会显示每日写入热力图、最近数据量和报告数量。": "After a copy finishes, daily activity, recent data volume, and report counts appear here.",
        "最近报告": "Recent Reports",
        "峰值日": "Peak Day",
        "等效容量": "Equivalent",
        "活跃项目": "Active Projects",
        "个人资料": "Profile",
        "分享": "Share",
        "私有": "Private",
        "编辑": "Edit",
        "累计拷贝量": "Total Copied",
        "峰值拷贝量": "Peak Copied",
        "最长任务": "Longest Task",
        "当前连续天数": "Current Streak",
        "最长连续天数": "Longest Streak",
        "拷贝活动": "Copy Activity",
        "每日": "Daily",
        "每周": "Weekly",
        "累计": "Cumulative",
        "活动洞察": "Activity Insights",
        "备份覆盖率": "Backup Coverage",
        "成功率": "Success Rate",
        "活跃天数": "Active Days",
        "文件总数": "Files Copied",
        "报告总数": "Reports",
        "最常用的校验": "Most Used Verification",
        "常用源设备": "Common Sources",
        "次任务": "runs",
        "刷新统计": "Refresh Stats"
    ]
}

enum ByteDisplayFormatter {
    private static let bytesPerTerabyte = 1_000_000_000_000.0

    static func string(fromByteCount byteCount: Int64) -> String {
        if abs(Double(byteCount)) >= bytesPerTerabyte {
            return terabyteString(fromByteCount: byteCount)
        }

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }

    private static func terabyteString(fromByteCount byteCount: Int64) -> String {
        let terabytes = Double(byteCount) / bytesPerTerabyte
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = abs(terabytes) < 10 ? 2 : 1
        let value = formatter.string(from: NSNumber(value: terabytes)) ?? String(format: "%.1f", terabytes)
        return "\(value) TB"
    }
}

enum ScanFilter: String, CaseIterable, Identifiable, Sendable {
    case video
    case photo
    case audio
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .video: "视频"
        case .photo: "照片"
        case .audio: "音频"
        case .all: "全部"
        }
    }

    /// 全工程统一的媒体类型图标（导入表单与规整预览共用）。
    var systemImageName: String {
        switch self {
        case .video: "film.fill"
        case .photo: "photo.fill"
        case .audio: "waveform"
        case .all: "doc.fill"
        }
    }
}

struct AppPreferences: Codable {
    var targetPath: String?
    var backupEnabled: Bool
    var backupPath: String?

    static let `default` = AppPreferences(targetPath: nil, backupEnabled: false, backupPath: nil)

    enum CodingKeys: String, CodingKey {
        case targetPath
        case backupEnabled
        case backupPath
    }

    init(targetPath: String?, backupEnabled: Bool, backupPath: String?) {
        self.targetPath = targetPath
        self.backupEnabled = backupEnabled
        self.backupPath = backupPath
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetPath = try container.decodeIfPresent(String.self, forKey: .targetPath)
        backupEnabled = try container.decodeIfPresent(Bool.self, forKey: .backupEnabled) ?? false
        backupPath = try container.decodeIfPresent(String.self, forKey: .backupPath)
    }

    var targetURL: URL? {
        targetPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var backupURL: URL? {
        guard backupEnabled, let backupPath else { return nil }
        return URL(fileURLWithPath: backupPath, isDirectory: true)
    }
}

enum MainWindowLayoutPolicy {
    static let minimumWidth: CGFloat = 640
    static let minimumHeight: CGFloat = 560
    static let portraitWidthBreakpoint: CGFloat = 760

    static func usesPortraitLayout(width: CGFloat, height: CGFloat) -> Bool {
        width < portraitWidthBreakpoint || height > width * 1.2
    }
}

enum AppStorageScope {
    static var displayName: String { "App 专属存储" }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.airwang.ditformac"
    }

    static var applicationSupportURL: URL {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if (environment["AIRWANG_DIT_UI_TESTING"] == "1" || environment["AIRWANG_DIT_UNIT_TESTING"] == "1"),
           let overridePath = environment["AIRWANG_DIT_APP_SUPPORT_DIR"],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }
        #endif

        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    static var dataURL: URL {
        applicationSupportURL.appendingPathComponent("Data", isDirectory: true)
    }

    static var preferencesURL: URL {
        dataURL.appendingPathComponent("preferences.json")
    }

    static var uiSettingsURL: URL {
        dataURL.appendingPathComponent("ui-settings.json")
    }

    static var taskLogURL: URL {
        dataURL
            .appendingPathComponent("import-reports.json")
    }

    static var statisticsIndexURL: URL {
        dataURL
            .appendingPathComponent("statistics-index.json")
    }

    static var copyProjectsURL: URL {
        dataURL
            .appendingPathComponent("copy-projects.json")
    }

    static func localReportDocumentURL(taskFolder: String) -> URL {
        localReportDocumentURL(taskFolder: taskFolder, reportKind: "Copy")
    }

    static func localReportDocumentURL(taskFolder: String, reportKind: String) -> URL {
        applicationSupportURL
            .appendingPathComponent("Reports", isDirectory: true)
            .appendingPathComponent("Airwang_\(FileNameSanitizer.safeComponent(reportKind, fallback: "Copy"))_Report_\(FileNameSanitizer.safeComponent(taskFolder)).txt")
    }
}

struct AppUISettings: Codable {
    var theme: AppTheme
    var language: AppLanguage
    var autoStartQueuedProjects: Bool

    static let `default` = AppUISettings(theme: .day, language: .chinese, autoStartQueuedProjects: false)

    enum CodingKeys: String, CodingKey {
        case theme
        case language
        case autoStartQueuedProjects
    }

    init(
        theme: AppTheme,
        language: AppLanguage = .chinese,
        autoStartQueuedProjects: Bool = false
    ) {
        self.theme = theme
        self.language = language
        self.autoStartQueuedProjects = autoStartQueuedProjects
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .day
        language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .chinese
        autoStartQueuedProjects = try container.decodeIfPresent(Bool.self, forKey: .autoStartQueuedProjects) ?? false
    }
}

enum FolderPickerPurpose: Identifiable {
    case target
    case backup
    case projectBackup(UUID)
    case organizerSource
    case organizerDestination

    var id: String {
        switch self {
        case .target:
            return "target"
        case .backup:
            return "backup"
        case let .projectBackup(id):
            return "projectBackup-\(id.uuidString)"
        case .organizerSource:
            return "organizerSource"
        case .organizerDestination:
            return "organizerDestination"
        }
    }

    var title: String {
        switch self {
        case .target: "选择主目标盘"
        case .backup: "选择备份盘"
        case .projectBackup: "选择项目备份盘"
        case .organizerSource: "选择待规整文件夹"
        case .organizerDestination: "选择规整目标文件夹"
        }
    }

    var confirmTitle: String {
        switch self {
        case .target: "设为主目标盘"
        case .backup: "设为备份盘"
        case .projectBackup: "应用到此项目"
        case .organizerSource: "设为规整源"
        case .organizerDestination: "设为规整目标"
        }
    }
}

struct StorageCapacitySnapshot: Equatable, Hashable {
    let totalCapacity: Int64?
    let availableCapacity: Int64?
    let source: String

    var isReadable: Bool {
        totalCapacity != nil || availableCapacity != nil
    }

    var usageFraction: Double? {
        guard let totalCapacity, totalCapacity > 0, let availableCapacity else { return nil }
        return min(max(1 - (Double(availableCapacity) / Double(totalCapacity)), 0), 1)
    }

    var capacityLine: String {
        guard isReadable else { return "容量暂不可读" }
        let free = availableCapacity.map { ByteDisplayFormatter.string(fromByteCount: $0) } ?? "-"
        let total = totalCapacity.map { ByteDisplayFormatter.string(fromByteCount: $0) } ?? "-"
        return "可用 \(free) / 总计 \(total)"
    }

    var shortAvailableText: String {
        availableCapacity.map { ByteDisplayFormatter.string(fromByteCount: $0) } ?? "未知"
    }
}

struct SpaceRequirement: Equatable {
    let payloadBytes: Int64
    let safetyMarginBytes: Int64
    let requiredBytes: Int64
}

struct DestinationSpacePreflight: Equatable {
    enum Status: Equatable {
        case passed
        case insufficient
        case capacityUnavailable
    }

    let destinationLabel: String
    let destinationPath: String
    let requirement: SpaceRequirement
    let availableBytes: Int64?
    let status: Status

    var isAllowed: Bool {
        status == .passed
    }
}

enum SpacePreflightPolicy {
    static let minimumSafetyMarginBytes: Int64 = 1_000_000_000

    static func requirement(for payloadBytes: Int64) -> SpaceRequirement {
        let payload = max(payloadBytes, 0)
        let quotient = payload / 20
        let remainder = payload % 20
        let fivePercentMargin = quotient + (remainder == 0 ? 0 : 1)
        let safetyMargin = max(fivePercentMargin, minimumSafetyMarginBytes)
        let (required, overflowed) = payload.addingReportingOverflow(safetyMargin)

        return SpaceRequirement(
            payloadBytes: payload,
            safetyMarginBytes: safetyMargin,
            requiredBytes: overflowed ? Int64.max : required
        )
    }

    static func evaluate(
        destinationLabel: String,
        destinationPath: String,
        payloadBytes: Int64,
        availableBytes: Int64?
    ) -> DestinationSpacePreflight {
        let requirement = requirement(for: payloadBytes)
        let status: DestinationSpacePreflight.Status

        if let availableBytes {
            status = availableBytes >= requirement.requiredBytes ? .passed : .insufficient
        } else {
            status = .capacityUnavailable
        }

        return DestinationSpacePreflight(
            destinationLabel: destinationLabel,
            destinationPath: destinationPath,
            requirement: requirement,
            availableBytes: availableBytes,
            status: status
        )
    }
}

enum DiskCapacityResolver {
    static func capacity(for url: URL) -> StorageCapacitySnapshot {
        let normalizedURL = url.standardizedFileURL

        // `resourceValues` can report nil or APFS "important usage" values that do not
        // match what users see in Finder. File-system attributes are the safer primary
        // source for DIT preflight checks on SD cards and external SSDs.
        if let filesystemCapacity = capacityFromFilesystemAttributes(for: normalizedURL) {
            return filesystemCapacity
        }

        if let resourceCapacity = capacityFromResourceValues(for: normalizedURL) {
            return resourceCapacity
        }

        return StorageCapacitySnapshot(
            totalCapacity: nil,
            availableCapacity: nil,
            source: "unreadable"
        )
    }

    static func volumeRootPath(for url: URL) -> String? {
        let standardized = url.standardizedFileURL

        // 存在的路径直接询问文件系统所属卷:自动处理 /var → /private/var、
        // APFS firmlink(/Users 实际在 /System/Volumes/Data)等情况。
        // 旧实现只做挂载点前缀匹配且对 "/" 不做前缀兜底,导致系统盘上的
        // 普通路径(/Users/...、/var/...)一律返回 nil →
        // pathsShareVolume(内置盘A, 内置盘B) 恒为 false,
        // "目标盘与备份盘共卷"预检在内置盘场景从不命中。
        if let volumeURL = try? standardized.resourceValues(forKeys: [.volumeURLKey]).volume {
            return volumeURL.standardizedFileURL.path
        }

        // 路径不存在(典型:设备已拔出)→ 退回挂载点前缀匹配。
        // 此时不把 "/" 当兜底:未挂载的 /Volumes/XXX 不属于根卷。
        let candidatePath = standardized.path
        let mountedVolumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: []) ?? []
        let roots = mountedVolumes
            .map { $0.standardizedFileURL.path }
            .sorted { $0.count > $1.count }

        for root in roots {
            if candidatePath == root {
                return root
            }
            if root != "/" && candidatePath.hasPrefix(root + "/") {
                return root
            }
        }

        return nil
    }

    private static func capacityFromFilesystemAttributes(for url: URL) -> StorageCapacitySnapshot? {
        let path = nearestExistingPath(for: url)
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: path) else {
            return nil
        }

        let total = int64Value(from: attributes[.systemSize])
        let free = int64Value(from: attributes[.systemFreeSize])
        guard total != nil || free != nil else { return nil }

        return StorageCapacitySnapshot(
            totalCapacity: total,
            availableCapacity: free,
            source: "filesystem"
        )
    }

    private static func capacityFromResourceValues(for url: URL) -> StorageCapacitySnapshot? {
        let keys: Set<URLResourceKey> = [
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }

        let total = values.volumeTotalCapacity.map { Int64($0) }
        let available = values.volumeAvailableCapacity.map { Int64($0) }
            ?? values.volumeAvailableCapacityForImportantUsage.map { Int64($0) }
        guard total != nil || available != nil else { return nil }

        return StorageCapacitySnapshot(
            totalCapacity: total,
            availableCapacity: available,
            source: "resourceValues"
        )
    }

    private static func nearestExistingPath(for url: URL) -> String {
        let fileManager = FileManager.default
        var candidate = url

        while !fileManager.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent()
            guard parent.path != candidate.path else { break }
            candidate = parent
        }

        return candidate.path
    }

    private static func int64Value(from value: Any?) -> Int64? {
        if let number = value as? NSNumber {
            return number.int64Value
        }
        if let int = value as? Int {
            return Int64(int)
        }
        if let int64 = value as? Int64 {
            return int64
        }
        return nil
    }
}

struct StorageVolume: Identifiable, Equatable {
    let id: String
    let name: String
    let url: URL
    let isRemovable: Bool
    let isInternal: Bool
    let totalCapacity: Int64?
    let availableCapacity: Int64?

    var capacityDescription: String {
        StorageCapacitySnapshot(
            totalCapacity: totalCapacity,
            availableCapacity: availableCapacity,
            source: "stored"
        )
        .capacityLine
    }
}

struct FolderBrowserItem: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let subtitle: String
    let totalCapacity: Int64?
    let availableCapacity: Int64?

    var capacityLine: String {
        StorageCapacitySnapshot(
            totalCapacity: totalCapacity,
            availableCapacity: availableCapacity,
            source: "stored"
        )
        .capacityLine
    }
}

struct MediaItem: Identifiable, Hashable {
    let id: String
    let fileURL: URL
    let relativePath: String
    let displayName: String
    let createdAt: Date
    let size: Int64
    let isVideo: Bool
    let mediaKind: ScanFilter
}

struct TimeGroup: Identifiable {
    let id: String
    let date: Date
    let items: [MediaItem]
    let totalSize: Int64
}

struct ImportSelectionSummary {
    let sourceVolume: StorageVolume
    let sourceRootURL: URL
    let selectedItems: [MediaItem]
    let totalSize: Int64
    let targetURL: URL
    let backupURL: URL?
    let verificationMode: String
    let namingRule: String
}

enum ProjectExecutionMode: String, CaseIterable, Identifiable, Codable {
    case sequential
    case parallel

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sequential: "按序执行"
        case .parallel: "并行执行"
        }
    }

    var subtitle: String {
        switch self {
        case .sequential: "默认最稳妥，一次只跑一个项目"
        case .parallel: "最多 3 个项目同时跑，单项目内部仍严格先主盘后备份"
        }
    }

    var maximumConcurrentProjects: Int {
        switch self {
        case .sequential: 1
        case .parallel: 3
        }
    }
}

enum VerificationMode: String, CaseIterable, Identifiable, Codable {
    case sha256
    case fastFingerprint
    case sizeOnly
    case skipped

    var id: String { rawValue }

    static var selectableCases: [VerificationMode] {
        [.sha256, .fastFingerprint, .sizeOnly]
    }

    var title: String {
        switch self {
        case .sha256: "SHA-256 全量校验"
        case .fastFingerprint: "快速指纹校验"
        case .sizeOnly: "大小校验"
        case .skipped: "跳过校验"
        }
    }

    var shortTitle: String {
        switch self {
        case .sha256: "SHA-256"
        case .fastFingerprint: "快速指纹"
        case .sizeOnly: "大小"
        case .skipped: "已跳过"
        }
    }

    var detail: String {
        switch self {
        case .sha256: "完整读取源/目标/备份并比对 SHA-256，最安全，速度最慢。"
        case .fastFingerprint: "比对大小，并抽样读取头部/中部/尾部生成指纹，速度快但不能保证发现所有损坏。"
        case .sizeOnly: "只确认文件存在和大小一致，最快，但不能发现内容损坏。"
        case .skipped: "用户主动跳过校验，报告会明确标记，不代表素材完整性已确认。"
        }
    }

    var reportWarning: String {
        switch self {
        case .sha256: "完整性校验：已执行 SHA-256 全量比对。"
        case .fastFingerprint: "风险提示：快速指纹校验为性能优先方案，不能替代 SHA-256 全量校验。"
        case .sizeOnly: "风险提示：大小校验只能证明文件大小一致，不能证明内容完全一致。"
        case .skipped: "高风险提示：用户主动跳过校验，本报告不代表素材完整性已确认。"
        }
    }
}

enum ProjectNameMode: String, CaseIterable, Identifiable, Codable {
    case automatic
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "按创建时间自动生成"
        case .custom: "自定义项目名称"
        }
    }
}

enum CopyProjectStatus: String, Codable {
    case queued
    case running
    case cancelling
    case completed
    case failed
    case blocked
    case cancelled

    var title: String {
        switch self {
        case .queued: "排队中"
        case .running: "执行中"
        case .cancelling: "取消中"
        case .completed: "已完成"
        case .failed: "异常"
        case .blocked: "已阻塞"
        case .cancelled: "已取消"
        }
    }
}

enum ProjectStageKind: String, CaseIterable, Codable {
    case primaryCopy
    case primaryVerify
    case backupCopy
    case backupVerify

    var title: String {
        switch self {
        case .primaryCopy: "主盘拷贝"
        case .primaryVerify: "主盘校验"
        case .backupCopy: "备份拷贝"
        case .backupVerify: "备份校验"
        }
    }
}

struct ProjectStageState: Codable, Equatable {
    var title: String
    var detail: String
    var totalBytes: Int64
    var processedBytes: Int64
    var completedFiles: Int
    var totalFiles: Int
    var currentFile: String
    var speedBytesPerSecond: Double
    var startedAt: Date?
    var finishedAt: Date?
    var failedFiles: [String]
    var reportDocumentPath: String?
    var localReportDocumentPath: String?
    var isActive: Bool
    var isComplete: Bool
    var isBlocked: Bool

    enum CodingKeys: String, CodingKey {
        case title
        case detail
        case totalBytes
        case processedBytes
        case completedFiles
        case totalFiles
        case currentFile
        case speedBytesPerSecond
        case startedAt
        case finishedAt
        case failedFiles
        case reportDocumentPath
        case localReportDocumentPath
        case isActive
        case isComplete
        case isBlocked
    }

    init(
        title: String = "等待",
        detail: String = "尚未开始",
        totalBytes: Int64 = 0,
        processedBytes: Int64 = 0,
        completedFiles: Int = 0,
        totalFiles: Int = 0,
        currentFile: String = "",
        speedBytesPerSecond: Double = 0,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        failedFiles: [String] = [],
        reportDocumentPath: String? = nil,
        localReportDocumentPath: String? = nil,
        isActive: Bool = false,
        isComplete: Bool = false,
        isBlocked: Bool = false
    ) {
        self.title = title
        self.detail = detail
        self.totalBytes = totalBytes
        self.processedBytes = processedBytes
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
        self.currentFile = currentFile
        self.speedBytesPerSecond = speedBytesPerSecond
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.failedFiles = failedFiles
        self.reportDocumentPath = reportDocumentPath
        self.localReportDocumentPath = localReportDocumentPath
        self.isActive = isActive
        self.isComplete = isComplete
        self.isBlocked = isBlocked
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "等待"
        detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? "尚未开始"
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        processedBytes = try container.decodeIfPresent(Int64.self, forKey: .processedBytes) ?? 0
        completedFiles = try container.decodeIfPresent(Int.self, forKey: .completedFiles) ?? 0
        totalFiles = try container.decodeIfPresent(Int.self, forKey: .totalFiles) ?? 0
        currentFile = try container.decodeIfPresent(String.self, forKey: .currentFile) ?? ""
        speedBytesPerSecond = try container.decodeIfPresent(Double.self, forKey: .speedBytesPerSecond) ?? 0
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        failedFiles = try container.decodeIfPresent([String].self, forKey: .failedFiles) ?? []
        reportDocumentPath = try container.decodeIfPresent(String.self, forKey: .reportDocumentPath)
        localReportDocumentPath = try container.decodeIfPresent(String.self, forKey: .localReportDocumentPath)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        isComplete = try container.decodeIfPresent(Bool.self, forKey: .isComplete) ?? false
        isBlocked = try container.decodeIfPresent(Bool.self, forKey: .isBlocked) ?? false
    }

    var fraction: Double {
        guard totalBytes > 0 else { return isComplete ? 1 : 0 }
        return min(max(Double(processedBytes) / Double(totalBytes), 0), 1)
    }

    var eta: TimeInterval? {
        guard speedBytesPerSecond > 0, totalBytes > processedBytes else { return nil }
        return Double(totalBytes - processedBytes) / speedBytesPerSecond
    }
}

struct ProjectMediaItem: Codable, Identifiable, Hashable {
    let id: String
    let filePath: String
    let relativePath: String
    let displayName: String
    let createdAt: Date
    let size: Int64
    let mediaKindRawValue: String

    enum CodingKeys: String, CodingKey {
        case id
        case filePath
        case relativePath
        case displayName
        case createdAt
        case size
        case mediaKindRawValue
    }

    init(
        id: String,
        filePath: String,
        relativePath: String,
        displayName: String,
        createdAt: Date,
        size: Int64,
        mediaKindRawValue: String
    ) {
        self.id = id
        self.filePath = filePath
        self.relativePath = relativePath
        self.displayName = displayName
        self.createdAt = createdAt
        self.size = size
        self.mediaKindRawValue = mediaKindRawValue
    }

    init(mediaItem: MediaItem) {
        id = mediaItem.id
        filePath = mediaItem.fileURL.path
        relativePath = mediaItem.relativePath
        displayName = mediaItem.displayName
        createdAt = mediaItem.createdAt
        size = mediaItem.size
        mediaKindRawValue = mediaItem.mediaKind.rawValue
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedRelativePath = try container.decodeIfPresent(String.self, forKey: .relativePath)
        let decodedFilePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        let fallbackName = decodedFilePath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Unknown"

        relativePath = decodedRelativePath ?? fallbackName
        filePath = decodedFilePath ?? relativePath
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
            ?? URL(fileURLWithPath: relativePath).lastPathComponent
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? relativePath
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        size = try container.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        mediaKindRawValue = try container.decodeIfPresent(String.self, forKey: .mediaKindRawValue) ?? ScanFilter.all.rawValue
    }

    var fileURL: URL {
        URL(fileURLWithPath: filePath, isDirectory: false)
    }

    var mediaKind: ScanFilter {
        ScanFilter(rawValue: mediaKindRawValue) ?? .all
    }
}

struct CopyProject: Codable, Identifiable {
    let id: UUID
    var name: String
    var taskFolderName: String
    var createdAt: Date
    var updatedAt: Date
    var sourceName: String
    var sourceVolumePath: String
    var sourceRootPath: String
    var targetRootPath: String
    var backupRootPath: String?
    var selectedItems: [ProjectMediaItem]
    var totalBytes: Int64
    var verificationMode: VerificationMode
    var status: CopyProjectStatus
    var orderIndex: Int
    var primaryCopyState: ProjectStageState
    var primaryVerifyState: ProjectStageState
    var backupCopyState: ProjectStageState
    var backupVerifyState: ProjectStageState
    var primaryReportID: UUID?
    var backupReportID: UUID?
    var skipVerificationConfirmations: Int
    var autoStartEnabled: Bool
    var autoStartDeadline: Date?
    var errorMessage: String?
    var resumeExistingFiles: Bool
    var backupOnlyRetry: Bool
    var primaryCompletionReference: PrimaryCompletionReference?
    var sourceVolumeIdentifier: String?
    var targetVolumeIdentifier: String?
    var backupVolumeIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case taskFolderName
        case createdAt
        case updatedAt
        case sourceName
        case sourceVolumePath
        case sourceRootPath
        case targetRootPath
        case backupRootPath
        case selectedItems
        case totalBytes
        case verificationMode
        case status
        case orderIndex
        case primaryCopyState
        case primaryVerifyState
        case backupCopyState
        case backupVerifyState
        case primaryReportID
        case backupReportID
        case skipVerificationConfirmations
        case autoStartEnabled
        case autoStartDeadline
        case errorMessage
        case resumeExistingFiles
        case backupOnlyRetry
        case primaryCompletionReference
        case sourceVolumeIdentifier
        case targetVolumeIdentifier
        case backupVolumeIdentifier
    }

    init(
        id: UUID = UUID(),
        name: String,
        taskFolderName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceName: String,
        sourceVolumePath: String,
        sourceRootPath: String,
        targetRootPath: String,
        backupRootPath: String?,
        selectedItems: [ProjectMediaItem],
        totalBytes: Int64,
        verificationMode: VerificationMode,
        status: CopyProjectStatus = .queued,
        orderIndex: Int,
        autoStartEnabled: Bool = false,
        autoStartDeadline: Date? = nil,
        resumeExistingFiles: Bool = false,
        sourceVolumeIdentifier: String? = nil,
        targetVolumeIdentifier: String? = nil,
        backupVolumeIdentifier: String? = nil,
        backupOnlyRetry: Bool = false
    ) {
        self.id = id
        self.name = name
        self.taskFolderName = taskFolderName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sourceName = sourceName
        self.sourceVolumePath = sourceVolumePath
        self.sourceRootPath = sourceRootPath
        self.targetRootPath = targetRootPath
        self.backupRootPath = backupRootPath
        self.selectedItems = selectedItems
        self.totalBytes = totalBytes
        self.verificationMode = verificationMode
        self.status = status
        self.orderIndex = orderIndex
        primaryCopyState = ProjectStageState(title: ProjectStageKind.primaryCopy.title)
        primaryVerifyState = ProjectStageState(title: ProjectStageKind.primaryVerify.title)
        backupCopyState = ProjectStageState(title: ProjectStageKind.backupCopy.title, detail: backupRootPath == nil ? "未配置备份盘" : "等待主盘完成")
        backupVerifyState = ProjectStageState(title: ProjectStageKind.backupVerify.title, detail: backupRootPath == nil ? "未配置备份盘" : "等待备份完成")
        primaryReportID = nil
        backupReportID = nil
        skipVerificationConfirmations = 0
        self.autoStartEnabled = autoStartEnabled
        self.autoStartDeadline = autoStartDeadline
        errorMessage = nil
        self.resumeExistingFiles = resumeExistingFiles
        self.backupOnlyRetry = backupOnlyRetry
        primaryCompletionReference = nil
        self.sourceVolumeIdentifier = sourceVolumeIdentifier
            ?? (try? URL(fileURLWithPath: sourceRootPath).resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
        self.targetVolumeIdentifier = targetVolumeIdentifier
            ?? (try? URL(fileURLWithPath: targetRootPath).resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
        self.backupVolumeIdentifier = backupVolumeIdentifier
            ?? backupRootPath.flatMap { (try? URL(fileURLWithPath: $0).resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let now = Date()
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "未命名项目"
        taskFolderName = try container.decodeIfPresent(String.self, forKey: .taskFolderName)
            ?? FileNameSanitizer.safeComponent(name)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? now
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? "未知源设备"
        sourceVolumePath = try container.decodeIfPresent(String.self, forKey: .sourceVolumePath) ?? ""
        sourceRootPath = try container.decodeIfPresent(String.self, forKey: .sourceRootPath) ?? sourceVolumePath
        targetRootPath = try container.decodeIfPresent(String.self, forKey: .targetRootPath) ?? ""
        backupRootPath = try container.decodeIfPresent(String.self, forKey: .backupRootPath)
        selectedItems = try container.decodeIfPresent([ProjectMediaItem].self, forKey: .selectedItems) ?? []
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes)
            ?? selectedItems.reduce(Int64(0)) { $0 + $1.size }

        if let rawVerificationMode = try container.decodeIfPresent(String.self, forKey: .verificationMode),
           let decodedVerificationMode = VerificationMode(rawValue: rawVerificationMode) {
            verificationMode = decodedVerificationMode
        } else {
            verificationMode = .sha256
        }

        if let rawStatus = try container.decodeIfPresent(String.self, forKey: .status),
           let decodedStatus = CopyProjectStatus(rawValue: rawStatus) {
            status = decodedStatus
        } else {
            status = .queued
        }

        orderIndex = try container.decodeIfPresent(Int.self, forKey: .orderIndex) ?? 0
        primaryCopyState = try container.decodeIfPresent(ProjectStageState.self, forKey: .primaryCopyState)
            ?? ProjectStageState(title: ProjectStageKind.primaryCopy.title, totalBytes: totalBytes, totalFiles: selectedItems.count)
        primaryVerifyState = try container.decodeIfPresent(ProjectStageState.self, forKey: .primaryVerifyState)
            ?? ProjectStageState(title: ProjectStageKind.primaryVerify.title, totalBytes: totalBytes, totalFiles: selectedItems.count)
        backupCopyState = try container.decodeIfPresent(ProjectStageState.self, forKey: .backupCopyState)
            ?? ProjectStageState(
                title: ProjectStageKind.backupCopy.title,
                detail: backupRootPath == nil ? "未配置备份盘" : "等待主盘完成",
                totalBytes: backupRootPath == nil ? 0 : totalBytes,
                totalFiles: backupRootPath == nil ? 0 : selectedItems.count
            )
        backupVerifyState = try container.decodeIfPresent(ProjectStageState.self, forKey: .backupVerifyState)
            ?? ProjectStageState(
                title: ProjectStageKind.backupVerify.title,
                detail: backupRootPath == nil ? "未配置备份盘" : "等待备份完成",
                totalBytes: backupRootPath == nil ? 0 : totalBytes,
                totalFiles: backupRootPath == nil ? 0 : selectedItems.count
            )
        primaryReportID = try container.decodeIfPresent(UUID.self, forKey: .primaryReportID)
        backupReportID = try container.decodeIfPresent(UUID.self, forKey: .backupReportID)
        skipVerificationConfirmations = try container.decodeIfPresent(Int.self, forKey: .skipVerificationConfirmations) ?? 0
        autoStartEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoStartEnabled) ?? false
        autoStartDeadline = try container.decodeIfPresent(Date.self, forKey: .autoStartDeadline)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        resumeExistingFiles = try container.decodeIfPresent(Bool.self, forKey: .resumeExistingFiles) ?? false
        backupOnlyRetry = try container.decodeIfPresent(Bool.self, forKey: .backupOnlyRetry) ?? false
        primaryCompletionReference = try container.decodeIfPresent(PrimaryCompletionReference.self, forKey: .primaryCompletionReference)
        sourceVolumeIdentifier = try container.decodeIfPresent(String.self, forKey: .sourceVolumeIdentifier)
        targetVolumeIdentifier = try container.decodeIfPresent(String.self, forKey: .targetVolumeIdentifier)
        backupVolumeIdentifier = try container.decodeIfPresent(String.self, forKey: .backupVolumeIdentifier)
    }

    var sourceRootURL: URL {
        URL(fileURLWithPath: sourceRootPath, isDirectory: true)
    }

    var targetRootURL: URL {
        URL(fileURLWithPath: targetRootPath, isDirectory: true)
    }

    var backupRootURL: URL? {
        backupRootPath.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    var primaryImportURL: URL {
        targetRootURL.appendingPathComponent(taskFolderName, isDirectory: true)
    }

    var backupImportURL: URL? {
        backupRootURL?.appendingPathComponent(taskFolderName, isDirectory: true)
    }

    var hasBackup: Bool {
        backupRootPath != nil
    }

    mutating func prepareForRetry() {
        status = .queued
        errorMessage = nil
        skipVerificationConfirmations = 0
        resumeExistingFiles = true
        backupOnlyRetry = false
        primaryCompletionReference = nil
        primaryCopyState = ProjectStageState(title: ProjectStageKind.primaryCopy.title, totalBytes: totalBytes, totalFiles: selectedItems.count)
        primaryVerifyState = ProjectStageState(title: ProjectStageKind.primaryVerify.title, totalBytes: totalBytes, totalFiles: selectedItems.count)
        backupCopyState = ProjectStageState(
            title: ProjectStageKind.backupCopy.title,
            detail: hasBackup ? "等待主盘完成" : "未配置备份盘",
            totalBytes: hasBackup ? totalBytes : 0,
            totalFiles: hasBackup ? selectedItems.count : 0
        )
        backupVerifyState = ProjectStageState(
            title: ProjectStageKind.backupVerify.title,
            detail: hasBackup ? "等待备份完成" : "未配置备份盘",
            totalBytes: hasBackup ? totalBytes : 0,
            totalFiles: hasBackup ? selectedItems.count : 0
        )
        primaryReportID = nil
        backupReportID = nil
        autoStartEnabled = false
        autoStartDeadline = nil
    }

    var canPrepareBackupRetry: Bool {
        hasBackup && status != .running && status != .cancelling
            && primaryCopyState.isComplete && primaryVerifyState.isComplete && primaryReportID != nil
    }

    @discardableResult
    mutating func prepareForBackupRetry() -> Bool {
        guard canPrepareBackupRetry else { return false }
        status = .queued
        errorMessage = nil
        skipVerificationConfirmations = 0
        resumeExistingFiles = true
        backupOnlyRetry = true
        backupCopyState = ProjectStageState(
            title: ProjectStageKind.backupCopy.title, detail: "等待独立备份重试",
            totalBytes: totalBytes, totalFiles: selectedItems.count
        )
        backupVerifyState = ProjectStageState(
            title: ProjectStageKind.backupVerify.title, detail: "等待备份完成",
            totalBytes: totalBytes, totalFiles: selectedItems.count
        )
        autoStartEnabled = false
        autoStartDeadline = nil
        return true
    }

    func isAutoStartReady(at now: Date) -> Bool {
        guard status == .queued,
              autoStartEnabled,
              let autoStartDeadline else {
            return false
        }
        return now >= autoStartDeadline
    }
}

enum FileNameSanitizer {
    static func safeComponent(_ rawValue: String, fallback: String = "Airwang_DIT_Project", maximumLength: Int = 80) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? fallback : trimmed
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_()[]"))
        let scalars = base.unicodeScalars.map { scalar -> Character in
            if allowed.contains(scalar) {
                return Character(scalar)
            }
            return "_"
        }
        let collapsed = String(scalars)
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "._- "))
        let safe = collapsed.isEmpty ? fallback : collapsed
        if safe.count <= maximumLength {
            return safe
        }
        return String(safe.prefix(maximumLength)).trimmingCharacters(in: CharacterSet(charactersIn: "._- "))
    }
}

final class ImportInterruptionToken: @unchecked Sendable {
    private let lock = NSLock()
    private var storedReason: String?
    private var storedVerificationModeOverride: VerificationMode?

    var reason: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedReason
    }

    var verificationModeOverride: VerificationMode? {
        lock.lock()
        defer { lock.unlock() }
        return storedVerificationModeOverride
    }

    func reset() {
        lock.lock()
        storedReason = nil
        storedVerificationModeOverride = nil
        lock.unlock()
    }

    func stop(reason: String) {
        lock.lock()
        if storedReason == nil {
            storedReason = reason
        }
        lock.unlock()
    }

    func overrideVerificationMode(_ mode: VerificationMode) {
        lock.lock()
        storedVerificationModeOverride = mode
        lock.unlock()
    }
}

struct TransferState {
    var totalBytes: Int64 = 0
    var processedBytes: Int64 = 0
    var verificationTotalBytes: Int64 = 0
    var verificationProcessedBytes: Int64 = 0
    var copiedFiles: Int = 0
    var verifiedFiles: Int = 0
    var verificationCheckedFiles: Int = 0
    var totalFiles: Int = 0
    var startedAt = Date()
    var verificationStartedAt: Date?
    var currentFile = ""
    var verificationStatus = "等待校验"
    var failedFiles: [String] = []
    var copyFailedFiles: [String] = []
    var verificationFailedFiles: [String] = []
    var skippedFiles: [String] = []
    var phaseTitle = "等待任务"
    var reportSummary = ""
    var isCancelled = false
    var currentSpeedBytesPerSecond: Double = 0
    var currentVerificationSpeedBytesPerSecond: Double = 0
    var interruptionReason: String?
    var spacePreflightResults: [DestinationSpacePreflight] = []

    var copyFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(processedBytes) / Double(totalBytes), 0), 1)
    }

    var verificationFraction: Double {
        if verificationTotalBytes > 0 {
            return min(max(Double(verificationProcessedBytes) / Double(verificationTotalBytes), 0), 1)
        }
        guard totalFiles > 0 else { return 0 }
        return min(max(Double(verificationCheckedFiles) / Double(totalFiles), 0), 1)
    }

    var copySpeedBytesPerSecond: Double {
        if currentSpeedBytesPerSecond > 0 {
            return currentSpeedBytesPerSecond
        }

        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 0 else { return 0 }
        return Double(processedBytes) / elapsed
    }

    var verificationSpeedBytesPerSecond: Double {
        if currentVerificationSpeedBytesPerSecond > 0 {
            return currentVerificationSpeedBytesPerSecond
        }

        guard let verificationStartedAt else { return 0 }
        let elapsed = Date().timeIntervalSince(verificationStartedAt)
        guard elapsed > 0 else { return 0 }
        return Double(verificationProcessedBytes) / elapsed
    }

    var speedBytesPerSecond: Double {
        isVerifying ? verificationSpeedBytesPerSecond : copySpeedBytesPerSecond
    }

    var copyETA: TimeInterval? {
        let speed = copySpeedBytesPerSecond
        guard speed > 0 else { return nil }
        return Double(max(totalBytes - processedBytes, 0)) / speed
    }

    var verificationETA: TimeInterval? {
        let speed = verificationSpeedBytesPerSecond
        guard verificationTotalBytes > 0, speed > 0 else { return nil }
        return Double(max(verificationTotalBytes - verificationProcessedBytes, 0)) / speed
    }

    var eta: TimeInterval? {
        isVerifying ? verificationETA : copyETA
    }

    var isVerifying: Bool {
        verificationStartedAt != nil && verificationCheckedFiles < totalFiles
    }
}

struct FileVerificationRecord: Codable, Identifiable {
    var id: String { relativePath }
    let relativePath: String
    let size: Int64
    let sourceChecksum: String?
    let targetChecksum: String?
    let backupChecksum: String?
    let status: String
    let message: String
}

/// A completed primary retains its full file evidence across app restarts.
/// Ordinary report logs continue using their existing compact encoding.
struct PrimaryCompletionReference: Codable {
    let report: TransferReport

    init(report: TransferReport) { self.report = report }
    init(from decoder: any Decoder) throws { report = try TransferReport(from: decoder) }
    func encode(to encoder: any Encoder) throws { try report.encodeComplete(to: encoder) }
}

struct TransferReport: Identifiable, Codable {
    let id: UUID
    let startedAt: Date
    let finishedAt: Date
    let sourceName: String
    let sourcePath: String
    let sourceRootPath: String?
    let targetPath: String
    let backupPath: String?
    let selectedFileCount: Int
    let totalBytes: Int64
    let verificationMode: String
    let namingRule: String
    let success: Bool
    let cancelled: Bool
    let failedFiles: [String]
    let copyFailedFiles: [String]
    let verificationFailedFiles: [String]
    let skippedFiles: [String]
    let verificationSummary: String
    let interruptionReason: String?
    let duration: TimeInterval
    let reportDocumentPath: String?
    let localReportDocumentPath: String?
    let reportDocumentWriteFailed: Bool
    let importedItems: [String]
    let fileRecords: [FileVerificationRecord]
    let resumedFiles: [String]

    var title: String {
        if cancelled {
            return "导入已取消"
        }
        if interruptionReason != nil {
            return "任务已中断"
        }
        if reportDocumentWriteFailed {
            return "报告写入异常"
        }
        return success ? "导入完成" : "导入存在异常"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case finishedAt
        case sourceName
        case sourcePath
        case sourceRootPath
        case targetPath
        case backupPath
        case selectedFileCount
        case totalBytes
        case verificationMode
        case namingRule
        case success
        case cancelled
        case failedFiles
        case copyFailedFiles
        case verificationFailedFiles
        case skippedFiles
        case verificationSummary
        case interruptionReason
        case duration
        case reportDocumentPath
        case localReportDocumentPath
        case reportDocumentWriteFailed
        case importedItems
        case fileRecords
        case resumedFiles
    }

    init(
        id: UUID,
        startedAt: Date,
        finishedAt: Date,
        sourceName: String,
        sourcePath: String,
        sourceRootPath: String?,
        targetPath: String,
        backupPath: String?,
        selectedFileCount: Int,
        totalBytes: Int64,
        verificationMode: String,
        namingRule: String,
        success: Bool,
        cancelled: Bool,
        failedFiles: [String],
        copyFailedFiles: [String],
        verificationFailedFiles: [String],
        skippedFiles: [String],
        verificationSummary: String,
        interruptionReason: String?,
        duration: TimeInterval,
        reportDocumentPath: String?,
        localReportDocumentPath: String?,
        reportDocumentWriteFailed: Bool = false,
        importedItems: [String],
        fileRecords: [FileVerificationRecord],
        resumedFiles: [String] = []
    ) {
        self.id = id
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.sourceName = sourceName
        self.sourcePath = sourcePath
        self.sourceRootPath = sourceRootPath
        self.targetPath = targetPath
        self.backupPath = backupPath
        self.selectedFileCount = selectedFileCount
        self.totalBytes = totalBytes
        self.verificationMode = verificationMode
        self.namingRule = namingRule
        self.success = success
        self.cancelled = cancelled
        self.failedFiles = failedFiles
        self.copyFailedFiles = copyFailedFiles
        self.verificationFailedFiles = verificationFailedFiles
        self.skippedFiles = skippedFiles
        self.verificationSummary = verificationSummary
        self.interruptionReason = interruptionReason
        self.duration = duration
        self.reportDocumentPath = reportDocumentPath
        self.localReportDocumentPath = localReportDocumentPath
        self.reportDocumentWriteFailed = reportDocumentWriteFailed
        self.importedItems = importedItems
        self.fileRecords = fileRecords
        self.resumedFiles = resumedFiles
    }

    func encode(to encoder: any Encoder) throws {
        try encode(to: encoder, preservingSuccessfulRecords: false)
    }

    func encodeComplete(to encoder: any Encoder) throws {
        try encode(to: encoder, preservingSuccessfulRecords: true)
    }

    private func encode(to encoder: any Encoder, preservingSuccessfulRecords: Bool) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(finishedAt, forKey: .finishedAt)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(sourcePath, forKey: .sourcePath)
        try container.encodeIfPresent(sourceRootPath, forKey: .sourceRootPath)
        try container.encode(targetPath, forKey: .targetPath)
        try container.encodeIfPresent(backupPath, forKey: .backupPath)
        try container.encode(selectedFileCount, forKey: .selectedFileCount)
        try container.encode(totalBytes, forKey: .totalBytes)
        try container.encode(verificationMode, forKey: .verificationMode)
        try container.encode(namingRule, forKey: .namingRule)
        try container.encode(success, forKey: .success)
        try container.encode(cancelled, forKey: .cancelled)
        try container.encode(failedFiles, forKey: .failedFiles)
        try container.encode(copyFailedFiles, forKey: .copyFailedFiles)
        try container.encode(verificationFailedFiles, forKey: .verificationFailedFiles)
        try container.encode(skippedFiles, forKey: .skippedFiles)
        try container.encode(verificationSummary, forKey: .verificationSummary)
        try container.encodeIfPresent(interruptionReason, forKey: .interruptionReason)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(reportDocumentPath, forKey: .reportDocumentPath)
        try container.encodeIfPresent(localReportDocumentPath, forKey: .localReportDocumentPath)
        try container.encode(reportDocumentWriteFailed, forKey: .reportDocumentWriteFailed)
        try container.encode(preservingSuccessfulRecords ? importedItems : [], forKey: .importedItems)
        try container.encode(preservingSuccessfulRecords ? fileRecords : fileRecords.filter { $0.status != "通过" }, forKey: .fileRecords)
        try container.encode(resumedFiles, forKey: .resumedFiles)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? .distantPast
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt) ?? startedAt
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? "未知源设备"
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath) ?? ""
        sourceRootPath = try container.decodeIfPresent(String.self, forKey: .sourceRootPath)
        targetPath = try container.decodeIfPresent(String.self, forKey: .targetPath) ?? ""
        backupPath = try container.decodeIfPresent(String.self, forKey: .backupPath)
        selectedFileCount = try container.decodeIfPresent(Int.self, forKey: .selectedFileCount) ?? 0
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        verificationMode = try container.decodeIfPresent(String.self, forKey: .verificationMode) ?? VerificationMode.sha256.title
        namingRule = try container.decodeIfPresent(String.self, forKey: .namingRule) ?? "时间戳+源盘"
        success = try container.decodeIfPresent(Bool.self, forKey: .success) ?? false
        cancelled = try container.decodeIfPresent(Bool.self, forKey: .cancelled) ?? false
        failedFiles = try container.decodeIfPresent([String].self, forKey: .failedFiles) ?? []
        copyFailedFiles = try container.decodeIfPresent([String].self, forKey: .copyFailedFiles) ?? []
        verificationFailedFiles = try container.decodeIfPresent([String].self, forKey: .verificationFailedFiles) ?? []
        skippedFiles = try container.decodeIfPresent([String].self, forKey: .skippedFiles) ?? []
        verificationSummary = try container.decodeIfPresent(String.self, forKey: .verificationSummary) ?? ""
        interruptionReason = try container.decodeIfPresent(String.self, forKey: .interruptionReason)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
            ?? max(finishedAt.timeIntervalSince(startedAt), 0)
        reportDocumentPath = try container.decodeIfPresent(String.self, forKey: .reportDocumentPath)
        localReportDocumentPath = try container.decodeIfPresent(String.self, forKey: .localReportDocumentPath)
            ?? Self.inferredLocalReportPath(reportDocumentPath: reportDocumentPath, targetPath: targetPath)
        reportDocumentWriteFailed = try container.decodeIfPresent(Bool.self, forKey: .reportDocumentWriteFailed) ?? false
        importedItems = try container.decodeIfPresent([String].self, forKey: .importedItems) ?? []
        fileRecords = try container.decodeIfPresent([FileVerificationRecord].self, forKey: .fileRecords) ?? []
        resumedFiles = try container.decodeIfPresent([String].self, forKey: .resumedFiles) ?? []
    }

    private static func inferredLocalReportPath(reportDocumentPath: String?, targetPath: String) -> String? {
        let taskFolder = URL(fileURLWithPath: targetPath, isDirectory: true).lastPathComponent
        guard !taskFolder.isEmpty else { return nil }

        let reportKind: String
        if let reportDocumentPath,
           URL(fileURLWithPath: reportDocumentPath).lastPathComponent.localizedCaseInsensitiveContains("backup") {
            reportKind = "Backup"
        } else {
            reportKind = "Copy"
        }
        let localURL = AppStorageScope.localReportDocumentURL(taskFolder: taskFolder, reportKind: reportKind)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL.path
        }

        guard let reportDocumentPath else { return nil }
        let reportName = URL(fileURLWithPath: reportDocumentPath).lastPathComponent
        guard reportName == localURL.lastPathComponent else { return nil }
        return localURL.path
    }
}

struct CopyActivityDay: Identifiable, Equatable, Codable {
    let date: Date
    let bytes: Int64
    let files: Int
    let reportCount: Int
    let successCount: Int

    var id: Date { date }

    var hasActivity: Bool {
        bytes > 0 || reportCount > 0
    }
}

struct CopyStatisticsCountItem: Identifiable, Equatable, Codable {
    let title: String
    let count: Int

    var id: String { title }
}

struct CopyStatisticsSummary: Equatable {
    let days: [CopyActivityDay]
    let totalBytes: Int64
    let recent7Bytes: Int64
    let totalFiles: Int
    let totalReports: Int
    let successfulReports: Int
    let activeBytes: Int64
    let activeProjectCount: Int
    let peakDayBytes: Int64
    let peakDay: CopyActivityDay?
    let longestReportDuration: TimeInterval
    let currentStreakDays: Int
    let longestStreakDays: Int
    let activeDayCount: Int
    let backupReportCount: Int
    let verificationModeCounts: [CopyStatisticsCountItem]
    let sourceCounts: [CopyStatisticsCountItem]

    var hasReportActivity: Bool {
        totalReports > 0 || totalBytes > 0
    }

    static func make(
        reports: [TransferReport],
        projects: [CopyProject],
        calendar: Calendar = .current,
        now: Date = Date(),
        dayCount: Int = 365
    ) -> CopyStatisticsSummary {
        let normalizedDayCount = max(dayCount, 7)
        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -(normalizedDayCount - 1), to: today) ?? today
        let endDay = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        var visibleBuckets: [Date: StatisticsDayAccumulator] = [:]
        var allTimeBuckets: [Date: StatisticsDayAccumulator] = [:]
        let reportsUpToToday = reports.filter { $0.finishedAt < endDay }

        for report in reportsUpToToday {
            let day = calendar.startOfDay(for: report.finishedAt)
            accumulate(report, on: day, into: &allTimeBuckets)

            if day >= firstDay && day < endDay {
                accumulate(report, on: day, into: &visibleBuckets)
            }
        }

        let days = (0..<normalizedDayCount).compactMap { offset -> CopyActivityDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return nil
            }
            let bucket = visibleBuckets[date] ?? StatisticsDayAccumulator()
            return CopyActivityDay(
                date: date,
                bytes: bucket.bytes,
                files: bucket.files,
                reportCount: bucket.reportCount,
                successCount: bucket.successCount
            )
        }

        let allTimeDays = allTimeBuckets.map { date, bucket in
            CopyActivityDay(
                date: date,
                bytes: bucket.bytes,
                files: bucket.files,
                reportCount: bucket.reportCount,
                successCount: bucket.successCount
            )
        }
        let recent7Start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let peakDay = allTimeDays.max { lhs, rhs in
            if lhs.bytes == rhs.bytes {
                return lhs.date < rhs.date
            }
            return lhs.bytes < rhs.bytes
        }
        let activeProjects = projects.filter { $0.status == .running || $0.status == .cancelling }
        let activeDates = Set(allTimeDays.filter(\.hasActivity).map(\.date))

        return CopyStatisticsSummary(
            days: days,
            totalBytes: allTimeDays.reduce(0) { $0 + $1.bytes },
            recent7Bytes: days.filter { $0.date >= recent7Start }.reduce(0) { $0 + $1.bytes },
            totalFiles: allTimeDays.reduce(0) { $0 + $1.files },
            totalReports: allTimeDays.reduce(0) { $0 + $1.reportCount },
            successfulReports: allTimeDays.reduce(0) { $0 + $1.successCount },
            activeBytes: activeProjects.reduce(0) { $0 + activeProcessedBytes(for: $1) },
            activeProjectCount: activeProjects.count,
            peakDayBytes: peakDay?.bytes ?? 0,
            peakDay: peakDay?.hasActivity == true ? peakDay : nil,
            longestReportDuration: reportsUpToToday.map(\.duration).max() ?? 0,
            currentStreakDays: currentStreakDays(activeDates: activeDates, today: today, calendar: calendar),
            longestStreakDays: longestStreakDays(activeDates: activeDates, calendar: calendar),
            activeDayCount: activeDates.count,
            backupReportCount: reportsUpToToday.filter { $0.backupPath != nil }.count,
            verificationModeCounts: topCounts(reportsUpToToday.map(\.verificationMode)),
            sourceCounts: topCounts(reportsUpToToday.map(\.sourceName))
        )
    }

    private static func accumulate(_ report: TransferReport, on day: Date, into buckets: inout [Date: StatisticsDayAccumulator]) {
        var bucket = buckets[day] ?? StatisticsDayAccumulator()
        bucket.bytes += max(report.totalBytes, 0)
        bucket.files += max(report.selectedFileCount, 0)
        bucket.reportCount += 1
        if report.success {
            bucket.successCount += 1
        }
        buckets[day] = bucket
    }

    private static func activeProcessedBytes(for project: CopyProject) -> Int64 {
        [
            project.primaryCopyState,
            project.primaryVerifyState,
            project.backupCopyState,
            project.backupVerifyState
        ]
        .filter(\.isActive)
        .reduce(0) { partial, state in
            partial + max(state.processedBytes, 0)
        }
    }

    private static func currentStreakDays(activeDates: Set<Date>, today: Date, calendar: Calendar) -> Int {
        var streak = 0
        var cursor = today
        while activeDates.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }
        return streak
    }

    private static func longestStreakDays(activeDates: Set<Date>, calendar: Calendar) -> Int {
        let sortedDates = activeDates.sorted()
        var longest = 0
        var current = 0
        var previousDate: Date?

        for date in sortedDates {
            if let previousDate,
               let expectedDate = calendar.date(byAdding: .day, value: 1, to: previousDate),
               expectedDate == date {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previousDate = date
        }

        return longest
    }

    private static func topCounts(_ values: [String], limit: Int = 5) -> [CopyStatisticsCountItem] {
        Dictionary(grouping: values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, by: { $0 })
            .map { key, values in
                CopyStatisticsCountItem(title: key, count: values.count)
            }
            .sorted {
                if $0.count == $1.count {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.count > $1.count
            }
            .prefix(limit)
            .map { $0 }
    }
}

struct CopyStatisticsIndex: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var calendarIdentifier: String
    var timeZoneIdentifier: String
    var indexedReportIDs: Set<UUID>
    var dayBuckets: [CopyStatisticsIndexDay]
    var totalBytes: Int64
    var totalFiles: Int
    var totalReports: Int
    var successfulReports: Int
    var peakDay: CopyActivityDay?
    var longestReportDuration: TimeInterval
    var backupReportCount: Int
    var verificationModeCounts: [CopyStatisticsCountItem]
    var sourceCounts: [CopyStatisticsCountItem]

    init(
        schemaVersion: Int = Self.currentSchemaVersion,
        indexedReportIDs: Set<UUID> = [],
        dayBuckets: [CopyStatisticsIndexDay] = [],
        totalBytes: Int64 = 0,
        totalFiles: Int = 0,
        totalReports: Int = 0,
        successfulReports: Int = 0,
        peakDay: CopyActivityDay? = nil,
        longestReportDuration: TimeInterval = 0,
        backupReportCount: Int = 0,
        verificationModeCounts: [CopyStatisticsCountItem] = [],
        sourceCounts: [CopyStatisticsCountItem] = [],
        calendar: Calendar = .current
    ) {
        self.schemaVersion = schemaVersion
        calendarIdentifier = Self.identifier(for: calendar)
        timeZoneIdentifier = calendar.timeZone.identifier
        self.indexedReportIDs = indexedReportIDs
        self.dayBuckets = dayBuckets
        self.totalBytes = totalBytes
        self.totalFiles = totalFiles
        self.totalReports = totalReports
        self.successfulReports = successfulReports
        self.peakDay = peakDay
        self.longestReportDuration = longestReportDuration
        self.backupReportCount = backupReportCount
        self.verificationModeCounts = verificationModeCounts
        self.sourceCounts = sourceCounts
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case calendarIdentifier
        case timeZoneIdentifier
        case indexedReportIDs
        case dayBuckets
        case totalBytes
        case totalFiles
        case totalReports
        case successfulReports
        case peakDay
        case longestReportDuration
        case backupReportCount
        case verificationModeCounts
        case sourceCounts
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        try PersistentSchema.validate(schemaVersion, supported: Self.currentSchemaVersion, decoder: decoder)
        calendarIdentifier = try container.decodeIfPresent(String.self, forKey: .calendarIdentifier) ?? ""
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZoneIdentifier) ?? ""
        indexedReportIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .indexedReportIDs) ?? []
        dayBuckets = try container.decodeIfPresent([CopyStatisticsIndexDay].self, forKey: .dayBuckets) ?? []
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes) ?? 0
        totalFiles = try container.decodeIfPresent(Int.self, forKey: .totalFiles) ?? 0
        totalReports = try container.decodeIfPresent(Int.self, forKey: .totalReports) ?? 0
        successfulReports = try container.decodeIfPresent(Int.self, forKey: .successfulReports) ?? 0
        peakDay = try container.decodeIfPresent(CopyActivityDay.self, forKey: .peakDay)
        longestReportDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .longestReportDuration) ?? 0
        backupReportCount = try container.decodeIfPresent(Int.self, forKey: .backupReportCount) ?? 0
        verificationModeCounts = try container.decodeIfPresent(
            [CopyStatisticsCountItem].self,
            forKey: .verificationModeCounts
        ) ?? []
        sourceCounts = try container.decodeIfPresent([CopyStatisticsCountItem].self, forKey: .sourceCounts) ?? []
    }

    static func make(
        reports: [TransferReport],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> CopyStatisticsIndex {
        var index = CopyStatisticsIndex(calendar: calendar)
        var buckets: [Date: CopyStatisticsIndexDay] = [:]
        var modes: [String: Int] = [:]
        var sources: [String: Int] = [:]
        let today = calendar.startOfDay(for: now)
        let endDay = calendar.date(byAdding: .day, value: 1, to: today) ?? today

        // 批量重建仅聚合一次，最后排序。逐条 add 会反复搜索日期并排序设备榜。
        for report in reports where report.finishedAt < endDay {
            guard index.indexedReportIDs.insert(report.id).inserted else { continue }
            let day = calendar.startOfDay(for: report.finishedAt)
            var bucket = buckets[day] ?? CopyStatisticsIndexDay(date: day)
            bucket.bytes += max(report.totalBytes, 0)
            bucket.files += max(report.selectedFileCount, 0)
            bucket.reportCount += 1
            bucket.successCount += report.success ? 1 : 0
            buckets[day] = bucket
            index.totalBytes += max(report.totalBytes, 0)
            index.totalFiles += max(report.selectedFileCount, 0)
            index.totalReports += 1
            index.successfulReports += report.success ? 1 : 0
            index.backupReportCount += report.backupPath == nil ? 0 : 1
            index.longestReportDuration = max(index.longestReportDuration, report.duration)
            let mode = report.verificationMode.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = report.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !mode.isEmpty { modes[mode, default: 0] += 1 }
            if !source.isEmpty { sources[source, default: 0] += 1 }
        }
        index.dayBuckets = Array(buckets.values)
        index.verificationModeCounts = modes.map { CopyStatisticsCountItem(title: $0.key, count: $0.value) }
        index.sourceCounts = sources.map { CopyStatisticsCountItem(title: $0.key, count: $0.value) }
        index.normalize()
        return index
    }

    func matches(
        reports: [TransferReport],
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Bool {
        schemaVersion == Self.currentSchemaVersion
            && calendarIdentifier == Self.identifier(for: calendar)
            && timeZoneIdentifier == calendar.timeZone.identifier
            && Set(dayBuckets.map(\.date)).count == dayBuckets.count
            && indexedReportIDs == Set(Self.eligibleReports(reports, calendar: calendar, now: now).map(\.id))
    }

    mutating func add(
        _ report: TransferReport,
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        guard Self.isEligible(report, calendar: calendar, now: now) else { return }
        guard !indexedReportIDs.contains(report.id) else { return }

        let day = calendar.startOfDay(for: report.finishedAt)
        if let index = dayBuckets.firstIndex(where: { $0.date == day }) {
            dayBuckets[index].bytes += max(report.totalBytes, 0)
            dayBuckets[index].files += max(report.selectedFileCount, 0)
            dayBuckets[index].reportCount += 1
            if report.success {
                dayBuckets[index].successCount += 1
            }
        } else {
            dayBuckets.append(CopyStatisticsIndexDay(
                date: day,
                bytes: max(report.totalBytes, 0),
                files: max(report.selectedFileCount, 0),
                reportCount: 1,
                successCount: report.success ? 1 : 0
            ))
        }

        indexedReportIDs.insert(report.id)
        totalBytes += max(report.totalBytes, 0)
        totalFiles += max(report.selectedFileCount, 0)
        totalReports += 1
        if report.success {
            successfulReports += 1
        }
        if report.backupPath != nil {
            backupReportCount += 1
        }
        longestReportDuration = max(longestReportDuration, report.duration)
        verificationModeCounts = Self.incrementedCounts(report.verificationMode, counts: verificationModeCounts)
        sourceCounts = Self.incrementedCounts(report.sourceName, counts: sourceCounts)
        updatePeakDay(for: day)
    }

    mutating func normalize() {
        dayBuckets = Self.mergedDayBuckets(dayBuckets)
            .values
            .sorted { $0.date < $1.date }
        verificationModeCounts = Self.sortedCounts(verificationModeCounts)
        sourceCounts = Self.sortedCounts(sourceCounts)
        if let bucket = dayBuckets.max(by: { lhs, rhs in
            if lhs.bytes == rhs.bytes {
                return lhs.date < rhs.date
            }
            return lhs.bytes < rhs.bytes
        }) {
            let day = bucket.activityDay
            peakDay = day.hasActivity ? day : nil
        } else {
            peakDay = nil
        }
    }

    func summary(
        projects: [CopyProject],
        calendar: Calendar = .current,
        now: Date = Date(),
        dayCount: Int = 365
    ) -> CopyStatisticsSummary {
        let normalizedDayCount = max(dayCount, 7)
        let today = calendar.startOfDay(for: now)
        let firstDay = calendar.date(byAdding: .day, value: -(normalizedDayCount - 1), to: today) ?? today
        let recent7Start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let bucketsByDate = Self.mergedDayBuckets(dayBuckets)
        let days = (0..<normalizedDayCount).compactMap { offset -> CopyActivityDay? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: firstDay) else {
                return nil
            }
            return (bucketsByDate[date] ?? CopyStatisticsIndexDay(date: date)).activityDay
        }
        let activeDates = Set(dayBuckets.filter(\.hasActivity).map(\.date))
        let activeProjects = projects.filter { $0.status == .running || $0.status == .cancelling }

        return CopyStatisticsSummary(
            days: days,
            totalBytes: totalBytes,
            recent7Bytes: days.filter { $0.date >= recent7Start }.reduce(0) { $0 + $1.bytes },
            totalFiles: totalFiles,
            totalReports: totalReports,
            successfulReports: successfulReports,
            activeBytes: activeProjects.reduce(0) { $0 + Self.activeProcessedBytes(for: $1) },
            activeProjectCount: activeProjects.count,
            peakDayBytes: peakDay?.bytes ?? 0,
            peakDay: peakDay,
            longestReportDuration: longestReportDuration,
            currentStreakDays: Self.currentStreakDays(activeDates: activeDates, today: today, calendar: calendar),
            longestStreakDays: Self.longestStreakDays(activeDates: activeDates, calendar: calendar),
            activeDayCount: activeDates.count,
            backupReportCount: backupReportCount,
            verificationModeCounts: verificationModeCounts.prefix(5).map { $0 },
            sourceCounts: sourceCounts.prefix(5).map { $0 }
        )
    }

    private static func incrementedCounts(_ value: String, counts: [CopyStatisticsCountItem]) -> [CopyStatisticsCountItem] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return counts }
        var updated = counts
        if let index = updated.firstIndex(where: { $0.title == trimmed }) {
            updated[index] = CopyStatisticsCountItem(title: trimmed, count: updated[index].count + 1)
        } else {
            updated.append(CopyStatisticsCountItem(title: trimmed, count: 1))
        }
        return Self.sortedCounts(updated)
    }

    private mutating func updatePeakDay(for date: Date) {
        guard let bucket = dayBuckets.first(where: { $0.date == date }) else { return }
        let day = bucket.activityDay
        guard day.hasActivity else { return }
        guard let current = peakDay else {
            peakDay = day
            return
        }
        if day.date == current.date || day.bytes > current.bytes || (day.bytes == current.bytes && day.date > current.date) {
            peakDay = day
        }
    }

    private static func sortedCounts(_ counts: [CopyStatisticsCountItem]) -> [CopyStatisticsCountItem] {
        counts.sorted {
            if $0.count == $1.count {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.count > $1.count
        }
    }

    private static func eligibleReports(
        _ reports: [TransferReport],
        calendar: Calendar,
        now: Date
    ) -> [TransferReport] {
        let today = calendar.startOfDay(for: now)
        let endDay = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return reports.filter { $0.finishedAt < endDay }
    }

    private static func isEligible(
        _ report: TransferReport,
        calendar: Calendar,
        now: Date
    ) -> Bool {
        let today = calendar.startOfDay(for: now)
        let endDay = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return report.finishedAt < endDay
    }

    private static func mergedDayBuckets(
        _ buckets: [CopyStatisticsIndexDay]
    ) -> [Date: CopyStatisticsIndexDay] {
        buckets.reduce(into: [:]) { result, bucket in
            guard var existing = result[bucket.date] else {
                result[bucket.date] = bucket
                return
            }
            existing.bytes += bucket.bytes
            existing.files += bucket.files
            existing.reportCount += bucket.reportCount
            existing.successCount += bucket.successCount
            result[bucket.date] = existing
        }
    }

    private static func identifier(for calendar: Calendar) -> String {
        String(describing: calendar.identifier)
    }

    private static func activeProcessedBytes(for project: CopyProject) -> Int64 {
        [
            project.primaryCopyState,
            project.primaryVerifyState,
            project.backupCopyState,
            project.backupVerifyState
        ]
        .filter(\.isActive)
        .reduce(0) { partial, state in
            partial + max(state.processedBytes, 0)
        }
    }

    private static func currentStreakDays(activeDates: Set<Date>, today: Date, calendar: Calendar) -> Int {
        var streak = 0
        var cursor = today
        while activeDates.contains(cursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                break
            }
            cursor = previousDay
        }
        return streak
    }

    private static func longestStreakDays(activeDates: Set<Date>, calendar: Calendar) -> Int {
        let sortedDates = activeDates.sorted()
        var longest = 0
        var current = 0
        var previousDate: Date?

        for date in sortedDates {
            if let previousDate,
               let expectedDate = calendar.date(byAdding: .day, value: 1, to: previousDate),
               expectedDate == date {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previousDate = date
        }

        return longest
    }
}

struct CopyStatisticsIndexDay: Codable, Equatable {
    let date: Date
    var bytes: Int64 = 0
    var files: Int = 0
    var reportCount: Int = 0
    var successCount: Int = 0

    var hasActivity: Bool {
        bytes > 0 || reportCount > 0
    }

    var activityDay: CopyActivityDay {
        CopyActivityDay(
            date: date,
            bytes: bytes,
            files: files,
            reportCount: reportCount,
            successCount: successCount
        )
    }
}

struct CopyStatisticsHeatmap: Equatable {
    let days: [CopyActivityDay]
    let weeks: [[CopyActivityDay?]]
    let peakDay: CopyActivityDay?
    let maxBytes: Int64

    static func make(days: [CopyActivityDay], calendar: Calendar = .current) -> CopyStatisticsHeatmap {
        let peakDay = days.max { lhs, rhs in
            if lhs.bytes == rhs.bytes {
                return lhs.date < rhs.date
            }
            return lhs.bytes < rhs.bytes
        }
        let activePeakDay = peakDay?.hasActivity == true ? peakDay : nil

        return CopyStatisticsHeatmap(
            days: days,
            weeks: calendarWeeks(from: days, calendar: calendar),
            peakDay: activePeakDay,
            maxBytes: max(days.map(\.bytes).max() ?? 0, 1)
        )
    }

    private static func calendarWeeks(from days: [CopyActivityDay], calendar: Calendar) -> [[CopyActivityDay?]] {
        guard let firstDate = days.first?.date else { return [] }

        let leadingEmptySlots = max(calendar.component(.weekday, from: firstDate) - 1, 0)
        var slots = Array<CopyActivityDay?>(repeating: nil, count: leadingEmptySlots)
        slots.append(contentsOf: days.map { Optional($0) })

        while !slots.isEmpty && slots.count % 7 != 0 {
            slots.append(nil)
        }

        return stride(from: 0, to: slots.count, by: 7).map { startIndex in
            Array(slots[startIndex..<min(startIndex + 7, slots.count)])
        }
    }
}

struct CopyStatisticsHeatmaps: Equatable {
    let daily: CopyStatisticsHeatmap
    let weekly: CopyStatisticsHeatmap
    let cumulative: CopyStatisticsHeatmap

    static func make(days: [CopyActivityDay], calendar: Calendar = .current) -> CopyStatisticsHeatmaps {
        CopyStatisticsHeatmaps(
            daily: CopyStatisticsHeatmap.make(days: days, calendar: calendar),
            weekly: CopyStatisticsHeatmap.make(days: weeklyDays(from: days, calendar: calendar), calendar: calendar),
            cumulative: CopyStatisticsHeatmap.make(days: cumulativeDays(from: days), calendar: calendar)
        )
    }

    func heatmap(for mode: StatisticsActivityMode) -> CopyStatisticsHeatmap {
        switch mode {
        case .daily:
            return daily
        case .weekly:
            return weekly
        case .cumulative:
            return cumulative
        }
    }

    private static func weeklyDays(from days: [CopyActivityDay], calendar: Calendar) -> [CopyActivityDay] {
        CopyStatisticsHeatmap.make(days: days, calendar: calendar).weeks.flatMap { week in
            let realDays = week.compactMap { $0 }
            let bytes = realDays.reduce(0) { $0 + $1.bytes }
            let files = realDays.reduce(0) { $0 + $1.files }
            let reportCount = realDays.reduce(0) { $0 + $1.reportCount }
            let successCount = realDays.reduce(0) { $0 + $1.successCount }
            return realDays.map { day in
                CopyActivityDay(
                    date: day.date,
                    bytes: bytes,
                    files: files,
                    reportCount: reportCount,
                    successCount: successCount
                )
            }
        }
    }

    private static func cumulativeDays(from days: [CopyActivityDay]) -> [CopyActivityDay] {
        var runningBytes: Int64 = 0
        var runningFiles = 0
        var runningReports = 0
        var runningSuccess = 0

        return days.map { day in
            runningBytes += day.bytes
            runningFiles += day.files
            runningReports += day.reportCount
            runningSuccess += day.successCount
            return CopyActivityDay(
                date: day.date,
                bytes: runningBytes,
                files: runningFiles,
                reportCount: runningReports,
                successCount: runningSuccess
            )
        }
    }
}

private struct StatisticsDayAccumulator {
    var bytes: Int64 = 0
    var files: Int = 0
    var reportCount: Int = 0
    var successCount: Int = 0
}

/// 按内容可用宽度分栏，避免 680–730 pt 区间五列的最小宽度撑出窗口。
enum StatisticsLayoutPolicy {
    static func metricColumnCount(availableWidth: CGFloat) -> Int {
        if availableWidth >= 800 { return 5 }
        if availableWidth >= 560 { return 3 }
        return 2
    }
}
