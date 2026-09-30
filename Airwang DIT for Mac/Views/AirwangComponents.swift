import AppKit
import QuickLookThumbnailing
import SwiftUI

/// 复用 DateFormatter 实例。DateFormatter 创建开销高，而这些日期文本只在主线程的
/// 视图渲染里产出（热力图月标、报告行等会随 hover/滚动反复重算），按 locale+格式
/// 缓存可避免每次渲染都重建格式器。仅限主线程访问，故用 @MainActor 隔离。
@MainActor
enum CachedDateFormatters {
    private static var cache: [String: DateFormatter] = [:]

    static func formatter(localeIdentifier: String, template: String? = nil, fixedFormat: String? = nil) -> DateFormatter {
        let key = "\(localeIdentifier)|t:\(template ?? "")|f:\(fixedFormat ?? "")"
        if let cached = cache[key] { return cached }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        if let template { formatter.setLocalizedDateFormatFromTemplate(template) }
        if let fixedFormat { formatter.dateFormat = fixedFormat }
        cache[key] = formatter
        return formatter
    }

    /// 剩余时间（ETA）格式器：传输进度行高频重算，复用两种单位配置即可。
    static let etaHoursMinutes: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static let etaMinutesSeconds: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}

struct WorkspaceHeaderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 全工程统一的投影标尺:每个海拔等级只有两层阴影 ——
/// ambient(环境光,大半径低不透明度,决定"浮多高")+ contact(接触影,
/// 小半径,把元素"压"在表面上)。此前每个表面叠 4 层(白色顶光 + 染色光晕 +
/// 两层黑),且大量调用点没有先做 compositingGroup,阴影按内部每个图元分别
/// 绘制,视觉上糊成一片、GPU 上是数倍浪费。顶光效果由玻璃面板的描边承担,
/// 染色光晕由选中态的描边承担,阴影只负责深度,层级一目了然。
enum AirwangGlassElevation {
    case panel
    case card
    case tile
    case floating
    case selected

    var ambientRadius: CGFloat {
        switch self {
        case .panel: 26
        case .card: 18
        case .tile: 11
        case .floating: 34
        case .selected: 22
        }
    }

    var ambientY: CGFloat {
        switch self {
        case .panel: 13
        case .card: 9
        case .tile: 5
        case .floating: 17
        case .selected: 11
        }
    }

    var contactRadius: CGFloat {
        switch self {
        case .panel: 9
        case .card: 7
        case .tile: 4
        case .floating: 12
        case .selected: 8
        }
    }

    var contactY: CGFloat {
        switch self {
        case .panel: 4
        case .card: 3
        case .tile: 2
        case .floating: 6
        case .selected: 4
        }
    }

    /// 环境影不透明度(日 / 夜)。
    var ambientOpacity: (day: Double, night: Double) {
        switch self {
        case .panel: (0.09, 0.46)
        case .card: (0.08, 0.42)
        case .tile: (0.06, 0.34)
        case .floating: (0.13, 0.55)
        case .selected: (0.11, 0.50)
        }
    }

    /// 接触影不透明度(日 / 夜)。
    var contactOpacity: (day: Double, night: Double) {
        switch self {
        case .panel: (0.06, 0.24)
        case .card: (0.05, 0.22)
        case .tile: (0.04, 0.18)
        case .floating: (0.08, 0.28)
        case .selected: (0.07, 0.25)
        }
    }
}

struct AirwangGlassSurface: View {
    let cornerRadius: CGFloat
    let theme: AppTheme
    let tint: Color
    let tintStrength: Double
    let elevation: AirwangGlassElevation
    var reduceEffects = false

    // 材质(实时背景采样模糊)只保留在悬浮 chrome(.floating):滚动内容里的
    // 面板和瓦片下面是静态渐变 + 光晕背景,本就平滑,模糊输出与半透明填充
    // 在视觉上无法区分;但滚动时每个可见材质面板都要每帧重新采样背景做
    // 高斯模糊,这是滚动掉帧的最大单项开销。悬浮 chrome 浮在滚动内容之上,
    // 背景真实变化,材质才有意义。
    private var materialActive: Bool {
        !reduceEffects && elevation == .floating
    }

    var body: some View {
        // 此前 reduceEffects 在两棵不同的 ZStack 之间整体切换,窗口缩放的
        // 起点和落点各触发一次全部表面的销毁重建,恰好把卡顿尖峰放在用户
        // 抓住窗口边缘的那一帧。现在只有一棵树,降级仅调整图层参数。
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let isNight = theme == .night
        let baseOpacity = materialActive
            ? (isNight ? 0.70 : 0.18)
            : (isNight ? 0.82 : 0.64)

        ZStack {
            shape
                .fill(Color(red: 0.095, green: 0.075, blue: 0.086).opacity(isNight ? baseOpacity : 0))
            shape
                .fill(Color.white.opacity(isNight ? 0 : baseOpacity))

            shape
                .fill(.ultraThinMaterial.opacity(materialActive ? (isNight ? 0.26 : 0.78) : 0))

            shape
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isNight ? 0.08 : 0.34),
                            tint.opacity(isNight ? 0.032 * tintStrength : 0.07 * tintStrength),
                            Color.black.opacity(isNight ? 0.14 : 0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(isNight ? .plusLighter : .screen)

            shape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isNight ? 0.22 : 0.86),
                            Color.white.opacity(isNight ? 0.07 : 0.22),
                            tint.opacity(isNight ? 0.10 * tintStrength : 0.12 * tintStrength)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isNight ? 1.15 : 0.9
                )

            shape
                .strokeBorder(Color.black.opacity(isNight ? 0.34 : 0.055), lineWidth: 0.7)
                .blendMode(.multiply)

            shape
                .inset(by: 1.2)
                .strokeBorder(Color.white.opacity(isNight ? 0.05 : 0.42), lineWidth: 0.6)
        }
        // 注意:这里不再叠加 macOS 26 的 glassEffect —— 上面的 material + 渐变
        // 已经是完整的玻璃质感,双重玻璃 = 每帧两次背景采样,只贵不亮。
        .compositingGroup()
        .modifier(AirwangLayeredShadow(
            theme: theme,
            tint: tint,
            tintStrength: tintStrength,
            elevation: elevation,
            enabled: !reduceEffects
        ))
    }
}

private struct AirwangLayeredShadow: ViewModifier {
    let theme: AppTheme
    let tint: Color
    let tintStrength: Double
    let elevation: AirwangGlassElevation
    var enabled = true

    func body(content: Content) -> some View {
        let isNight = theme == .night
        let ambient = elevation.ambientOpacity
        let contact = elevation.contactOpacity
        // tint / tintStrength 参数保留以兼容既有调用点;
        // 染色光晕已从阴影系统移除(由选中态描边承担)。
        // enabled 走透明度归零而非增删修饰符:修饰符链保持恒定,
        // 窗口缩放降级不再引起视图身份变化。
        let gate = enabled ? 1.0 : 0.0
        return content
            .shadow(
                color: Color.black.opacity((isNight ? ambient.night : ambient.day) * gate),
                radius: elevation.ambientRadius,
                x: 0,
                y: elevation.ambientY
            )
            .shadow(
                color: Color.black.opacity((isNight ? contact.night : contact.day) * gate),
                radius: elevation.contactRadius,
                x: 0,
                y: elevation.contactY
            )
    }
}

extension View {
    @ViewBuilder
    func airwangSoftShadow(
        theme: AppTheme,
        tint: Color,
        tintStrength: Double = 0,
        elevation: AirwangGlassElevation = .tile,
        enabled: Bool = true
    ) -> some View {
        // compositingGroup 把内容先合成为单层再投影:没有它,.shadow 会给
        // 视图内部每个图元各画一份阴影(文字、图标、描边各一份),又糊又慢。
        // enabled=false 时保持同一条修饰符链、只把阴影透明度归零,避免
        // 窗口缩放降级在两棵视图树之间整体切换。
        compositingGroup()
            .modifier(AirwangLayeredShadow(theme: theme, tint: tint, tintStrength: tintStrength, elevation: elevation, enabled: enabled))
    }
}

struct CapacityMeter: View {
    let totalCapacity: Int64?
    let availableCapacity: Int64?
    let tint: Color
    let backgroundColor: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(backgroundColor)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.95), tint.opacity(0.55)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: proxy.size.width * usedFraction)
            }
        }
        .frame(height: 6)
        .opacity(totalCapacity == nil || availableCapacity == nil ? 0.42 : 1)
    }

    private var usedFraction: CGFloat {
        guard let totalCapacity, totalCapacity > 0, let availableCapacity else { return 0 }
        let used = 1 - (Double(availableCapacity) / Double(totalCapacity))
        return CGFloat(min(max(used, 0), 1))
    }
}

struct ResizableSheetWindowConfigurator: NSViewRepresentable {
    let minSize: NSSize
    let idealSize: NSSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.postsFrameChangedNotifications = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window, coordinator: context.coordinator)
        }
    }

    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }

        window.styleMask.insert(.resizable)
        window.minSize = minSize
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        guard !coordinator.didSetInitialSize else { return }
        coordinator.didSetInitialSize = true

        let currentSize = window.contentLayoutRect.size
        let targetSize = NSSize(
            width: max(currentSize.width, idealSize.width),
            height: max(currentSize.height, idealSize.height)
        )
        window.setContentSize(targetSize)
    }

    final class Coordinator {
        var didSetInitialSize = false
    }
}

struct ThumbnailView: View {
    let url: URL
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .padding(10)
            }
        }
        .task(id: "\(url.path)-\(viewModel.isImporting)") {
            guard !viewModel.isImporting else {
                image = nil
                return
            }
            image = await ThumbnailCache.shared.image(for: url)
        }
    }
}

@MainActor
private final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private var activeRequests = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let maxConcurrentRequests = 4

    func image(for url: URL) async -> NSImage? {
        let key = url.path as NSString
        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }
        if let task = inFlight[url.path] {
            return await task.value
        }

        let task = Task { @MainActor in
            await acquireSlot()
            defer { releaseSlot() }
            return await Self.generateThumbnail(for: url)
        }
        inFlight[url.path] = task

        let generatedImage = await task.value
        if let generatedImage {
            cache.setObject(generatedImage, forKey: key)
        }
        inFlight[url.path] = nil
        return generatedImage
    }

    private func acquireSlot() async {
        if activeRequests < maxConcurrentRequests {
            activeRequests += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        activeRequests += 1
    }

    private func releaseSlot() {
        activeRequests = max(activeRequests - 1, 0)
        guard !waiters.isEmpty else { return }
        let continuation = waiters.removeFirst()
        continuation.resume()
    }

    private static func generateThumbnail(for url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 320, height: 180),
            scale: 2,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, error in
                if let thumbnail {
                    continuation.resume(returning: thumbnail.nsImage)
                } else if error != nil {
                    continuation.resume(returning: NSWorkspace.shared.icon(forFile: url.path))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

extension Text {
    func sectionTitle() -> some View {
        self.font(.title3.weight(.semibold))
    }
}
