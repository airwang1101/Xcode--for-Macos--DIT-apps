import SwiftUI

/// 全工程统一的主题色板。
///
/// 历史背景:`ContentView` / `ImportSheet` / `FolderPickerSheet` 各自维护了一份
/// `primaryTextColor` / `secondaryTextColor` / `accentColor` 的 computed property。
/// 其中 `ContentView` 走暖色定制(`#290D14` 系列),另两份直接用 `Color.primary`
/// / `Color.secondary` 系统色,在白天模式下视觉发冷,与暖色背景不一致(见
/// `TEST_REPORT.md` #45/#46/#47)。
///
/// 这里把四种色集中到 `AppTheme` 的扩展上,白天模式统一走暖色版本。
/// 任何视图都通过 `viewModel.selectedTheme.primaryTextColor` 取色,避免再次出现
/// 三处独立定义。
extension AppTheme {

    // MARK: - 文本

    /// 主文本色:夜间纯白,白天偏暖的深棕,落在暖色背景上比 `Color.primary`
    /// 协调,且不会显得发灰。
    var primaryTextColor: Color {
        switch self {
        case .night: return .white
        case .day:   return Color(red: 0.16, green: 0.08, blue: 0.11)
        }
    }

    /// 次要文本色:夜间白色 72% 透明,白天黑色 58%。比 `Color.secondary`
    /// 更黑一些,保证在暖色 / 玻璃质感背景上的可读性。
    var secondaryTextColor: Color {
        switch self {
        case .night: return Color.white.opacity(0.72)
        case .day:   return Color.black.opacity(0.58)
        }
    }

    // MARK: - 强调

    /// 主强调色(玫瑰红 / 酒红):全工程仅此一个。
    var accentColor: Color {
        switch self {
        case .night: return Color(red: 1.00, green: 0.34, blue: 0.54)
        case .day:   return Color(red: 0.73, green: 0.14, blue: 0.27)
        }
    }

    /// 次要强调色(橙黄):多用于备份盘 / 第二条进度。
    var secondaryAccentColor: Color {
        switch self {
        case .night: return Color(red: 1.00, green: 0.65, blue: 0.40)
        case .day:   return Color(red: 0.98, green: 0.58, blue: 0.39)
        }
    }
}
