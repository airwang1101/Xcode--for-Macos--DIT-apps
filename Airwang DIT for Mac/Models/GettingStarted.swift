import Foundation

enum GettingStartedStep: Int, CaseIterable, Identifiable {
    case welcome, destinations, source, verification, queue, recovery, history, ready
    var id: Int { rawValue }

    var symbol: String {
        switch self {
        case .welcome: "sparkles"
        case .destinations: "externaldrive"
        case .source: "sdcard"
        case .verification: "checkmark.shield"
        case .queue: "list.bullet.rectangle"
        case .recovery: "arrow.clockwise"
        case .history: "doc.text"
        case .ready: "flag.checkered"
        }
    }

    func title(language: AppLanguage) -> String {
        let titles: (String, String) = switch self {
        case .welcome: ("认识工作台", "Meet your workspace")
        case .destinations: ("主目标与备份", "Primary and backup")
        case .source: ("选择素材", "Select media")
        case .verification: ("选择校验方式", "Choose verification")
        case .queue: ("执行与进度", "Run your queue")
        case .recovery: ("中断后恢复", "Recover a transfer")
        case .history: ("报告与历史", "Reports and history")
        case .ready: ("开始第一项任务", "Your first project")
        }
        return language == .english ? titles.1 : titles.0
    }
}

struct GettingStartedProgress: Codable, Equatable {
    static let currentVersion = 1
    var completedVersion = 0
    var lastVisitedStep = 0

    var step: GettingStartedStep {
        GettingStartedStep(rawValue: min(max(lastVisitedStep, 0), GettingStartedStep.allCases.count - 1)) ?? .welcome
    }

    // Future completion markers are also respected on downgrade.
    var shouldPresentAutomatically: Bool { completedVersion == 0 }

    enum CodingKeys: String, CodingKey { case completedVersion, lastVisitedStep }

    init(completedVersion: Int = 0, lastVisitedStep: Int = 0) {
        self.completedVersion = completedVersion
        self.lastVisitedStep = lastVisitedStep
    }

    init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        completedVersion = max(0, try fields.decodeIfPresent(Int.self, forKey: .completedVersion) ?? 0)
        lastVisitedStep = try fields.decodeIfPresent(Int.self, forKey: .lastVisitedStep) ?? 0
    }

    static func initial(saved: Self?, hasExistingData: Bool) -> Self {
        saved ?? Self(completedVersion: hasExistingData ? currentVersion : 0)
    }
}
