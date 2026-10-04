import SwiftUI

private struct PaperAppearanceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var ditPaperAppearance: Bool {
        get { self[PaperAppearanceKey.self] }
        set { self[PaperAppearanceKey.self] = newValue }
    }
}

struct PaperPalette {
    let theme: AppTheme
    private var dark: Bool { theme == .night }
    var background: Color { dark ? color(0x22211E) : color(0xF8F7F3) }
    var surface: Color { dark ? color(0x2B2925) : color(0xFCFBF8) }
    var ink: Color { dark ? color(0xF2EFE7) : color(0x24231F) }
    var secondary: Color { dark ? color(0xBDB8AD) : color(0x6C6961) }
    var accent: Color { dark ? color(0xE7A083) : color(0xA7472C) }
    var secondaryAccent: Color { dark ? color(0xC5B38B) : color(0x76613A) }
    var divider: Color { dark ? color(0x49463F) : color(0xDEDCD5) }
    var success: Color { dark ? color(0x8BBF9E) : color(0x386A4D) }
    var warning: Color { dark ? color(0xE4C483) : color(0x89600C) }
    var error: Color { dark ? color(0xEE9C91) : color(0xA73832) }

    private func color(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255,
              blue: Double(hex & 255) / 255)
    }
}

enum PaperCopyTab: String, CaseIterable, Identifiable {
    case create, devices, queue, reports
    var id: String { rawValue }
    var title: String {
        switch self {
        case .create: "新建任务"
        case .devices: "设备"
        case .queue: "队列"
        case .reports: "报告"
        }
    }
}

struct PaperPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    let palette: PaperPalette
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 22)
            .frame(minHeight: 42)
            .foregroundStyle(palette.theme == .night ? Color.black : Color.white)
            .background(palette.accent.opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.35),
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}
