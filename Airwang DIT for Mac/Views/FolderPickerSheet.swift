import AppKit
import SwiftUI

struct FolderPickerSheet: View {
    let purpose: FolderPickerPurpose
    @EnvironmentObject private var viewModel: AppViewModel

    private enum FolderBrowserDisplayMode: String {
        case grid
        case list
    }

    @State private var displayMode: FolderBrowserDisplayMode = .grid

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    viewModel.closeFolderPicker()
                } label: {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                VStack(alignment: .leading, spacing: 4) {
                    Text(purpose.title)
                        .font(.title2.weight(.semibold))
                    Text("在软件内浏览目录，并直接查看目标位置的可用容量。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider()

            HStack(spacing: 0) {
                rootSidebar
                Divider()
                folderBrowser
                Divider()
                selectionInspector
            }
        }
        .frame(minWidth: 980, idealWidth: 1160, maxWidth: .infinity, minHeight: 640, idealHeight: 740, maxHeight: .infinity)
        .background(
            Group {
                if viewModel.selectedTheme == .night {
                    LinearGradient(
                        colors: [
                            Color(red: 0.025, green: 0.028, blue: 0.042),
                            Color(red: 0.070, green: 0.036, blue: 0.070),
                            Color(red: 0.110, green: 0.052, blue: 0.080),
                            Color(red: 0.035, green: 0.045, blue: 0.068)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                } else {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            Color(red: 0.995, green: 0.925, blue: 0.930),
                            Color(red: 0.970, green: 0.860, blue: 0.895),
                            Color(red: 0.940, green: 0.835, blue: 0.920)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        )
        .background(ResizableSheetWindowConfigurator(minSize: NSSize(width: 980, height: 640), idealSize: NSSize(width: 1160, height: 740)))
        .fontDesign(.serif)
        .preferredColorScheme(viewModel.selectedTheme == .night ? .dark : .light)
    }

    private var rootSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("位置")
                .font(.headline)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.folderRoots) { item in
                        Button {
                            viewModel.navigate(to: item.url)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: sidebarIcon(for: item.url))
                                    .foregroundStyle(themeAccentColor)
                                    .frame(width: 20)
                                    .airwangSoftShadow(theme: viewModel.selectedTheme, tint: themeAccentColor, tintStrength: 0.20, elevation: .tile)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .font(.headline)
                                        .foregroundStyle(themePrimaryTextColor)
                                    Text(item.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(themeSecondaryTextColor)
                                        .lineLimit(1)
                                    Text(item.capacityLine)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(themeSecondaryTextColor)
                                    CapacityMeter(
                                        totalCapacity: item.totalCapacity,
                                        availableCapacity: item.availableCapacity,
                                        tint: themeAccentColor,
                                        backgroundColor: themeSecondaryTextColor.opacity(0.16)
                                    )
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(themeGlassPanel(cornerRadius: 14, tint: isCurrent(item.url) ? themeAccentColor : nil))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 260, alignment: .topLeading)
    }

    private var folderBrowser: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    viewModel.navigateUp()
                } label: {
                    Label("上一级", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .tint(themeAccentColor)
                .disabled(!canGoUp)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.currentFolderURL?.lastPathComponent.isEmpty == false ? (viewModel.currentFolderURL?.lastPathComponent ?? "目录") : "目录")
                        .font(.headline)
                        .foregroundStyle(themePrimaryTextColor)
                    Text(viewModel.currentFolderURL?.path ?? "")
                        .font(.caption)
                        .foregroundStyle(themeSecondaryTextColor)
                }
                Spacer()
                displayModeToggle
            }

            ScrollView {
                if viewModel.isLoadingFolderChildren {
                    ProgressView("正在读取文件夹...")
                        .frame(maxWidth: .infinity)
                        .padding(24)
                } else if viewModel.folderChildren.isEmpty {
                    Text("此目录下没有子文件夹，可直接在右侧确认选择当前目录。")
                        .font(.callout)
                        .foregroundStyle(themeSecondaryTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                }

                switch displayMode {
                case .list:
                    folderList
                case .grid:
                    folderGrid
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var displayModeToggle: some View {
        HStack(spacing: 4) {
            displayModeButton(.grid, systemImage: "square.grid.2x2", help: "网格视图")
            displayModeButton(.list, systemImage: "list.bullet", help: "列表视图")
        }
        .padding(4)
        .background(themeGlassPanel(cornerRadius: 12))
    }

    private func displayModeButton(_ mode: FolderBrowserDisplayMode, systemImage: String, help: String) -> some View {
        Button {
            displayMode = mode
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(displayMode == mode ? Color.white : themeSecondaryTextColor)
                .frame(width: 32, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(displayMode == mode ? themeAccentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
    }

    private var folderList: some View {
        LazyVStack(spacing: 8) {
            ForEach(viewModel.folderChildren) { item in
                folderListRow(item: item)
            }
        }
    }

    private func folderListRow(item: FolderBrowserItem) -> some View {
        HStack(spacing: 12) {
            Button {
                viewModel.selectFolder(item.url)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.orange)
                        .airwangSoftShadow(theme: viewModel.selectedTheme, tint: .orange, tintStrength: 0.20, elevation: .tile)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.headline)
                            .foregroundStyle(themePrimaryTextColor)
                        Text(item.subtitle)
                            .font(.caption2)
                            .foregroundStyle(themeSecondaryTextColor)
                            .lineLimit(1)
                        Text(item.capacityLine)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(themeSecondaryTextColor)
                        CapacityMeter(
                            totalCapacity: item.totalCapacity,
                            availableCapacity: item.availableCapacity,
                            tint: themeAccentColor,
                            backgroundColor: themeSecondaryTextColor.opacity(0.16)
                        )
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            Button("进入") {
                viewModel.navigate(to: item.url)
            }
            .buttonStyle(.bordered)
            .tint(themeAccentColor)
        }
        .padding(12)
        .background(themeGlassPanel(cornerRadius: 16, tint: isSelected(item.url) ? themeAccentColor : nil))
    }

    private var folderGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132, maximum: 168), spacing: 14)],
            alignment: .leading,
            spacing: 16
        ) {
            ForEach(viewModel.folderChildren) { item in
                folderGridCell(item: item)
            }
        }
        .padding(.vertical, 4)
    }

    private func folderGridCell(item: FolderBrowserItem) -> some View {
        // 单击选中（右侧检查器实时联动），双击进入下一级，贴近 Finder / Bridge 的习惯。
        Button {
            viewModel.selectFolder(item.url)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(.orange)
                    .airwangSoftShadow(theme: viewModel.selectedTheme, tint: .orange, tintStrength: 0.22, elevation: .tile)
                    .frame(height: 54)

                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(themePrimaryTextColor)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let available = item.availableCapacity {
                    Text("剩余 \(byteText(available))")
                        .font(.caption2)
                        .foregroundStyle(themeSecondaryTextColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 132)
            .padding(.vertical, 14)
            .padding(.horizontal, 10)
            .background(themeGlassPanel(cornerRadius: 18, tint: isSelected(item.url) ? themeAccentColor : nil))
            .overlay(alignment: .topTrailing) {
                if isSelected(item.url) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(themeAccentColor)
                        .padding(8)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            viewModel.navigate(to: item.url)
        })
        .help(item.subtitle)
    }

    private var selectionInspector: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    Text("已选目录")
                        .font(.headline)
                        .foregroundStyle(themePrimaryTextColor)

                    if let selection = viewModel.folderSelection {
                        inspectorCard(title: "目标路径", value: selection.subtitle)
                        inspectorCard(title: "目录名称", value: selection.name)
                        inspectorCard(title: "剩余容量", value: selection.availableCapacity.map(byteText) ?? "-")
                        inspectorCard(title: "总容量", value: selection.totalCapacity.map(byteText) ?? "-")
                        CapacityMeter(
                            totalCapacity: selection.totalCapacity,
                            availableCapacity: selection.availableCapacity,
                            tint: themeAccentColor,
                            backgroundColor: themeSecondaryTextColor.opacity(0.16)
                        )
                        Text("容量读取使用系统文件系统属性，并在不可读时自动回退，避免外置盘剩余空间显示错误。")
                            .font(.caption)
                            .foregroundStyle(themeSecondaryTextColor)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("请选择一个目录")
                            .foregroundStyle(themeSecondaryTextColor)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Button(purpose.confirmTitle) {
                viewModel.confirmFolderSelection()
            }
            .buttonStyle(.borderedProminent)
            .tint(themeAccentColor)
            .disabled(viewModel.selectedFolderURL == nil)
        }
        .padding(20)
        .frame(width: 280, alignment: .topLeading)
    }

    private func inspectorCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(themeSecondaryTextColor)
            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(themePrimaryTextColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(themeGlassPanel(cornerRadius: 16))
    }

    private func sidebarIcon(for url: URL) -> String {
        Self.sidebarSpecialPaths[url.standardizedFileURL.path] ?? "externaldrive.fill"
    }

    private static let sidebarSpecialPaths: [String: String] = {
        let fileManager = FileManager.default
        let homePath = fileManager.homeDirectoryForCurrentUser.standardizedFileURL.path
        var paths: [String: String] = [homePath: "house.fill"]

        if let desktopPath = userDirectoryPath(.desktopDirectory) {
            paths[desktopPath] = "desktopcomputer"
        }
        if let moviesPath = userDirectoryPath(.moviesDirectory) {
            paths[moviesPath] = "film.fill"
        }
        if let documentsPath = userDirectoryPath(.documentDirectory) {
            paths[documentsPath] = "doc.text.fill"
        }

        return paths
    }()

    private static func userDirectoryPath(_ directory: FileManager.SearchPathDirectory) -> String? {
        FileManager.default.urls(for: directory, in: .userDomainMask).first?.standardizedFileURL.path
    }

    private func byteText(_ value: Int64) -> String {
        ByteDisplayFormatter.string(fromByteCount: value)
    }

    private func isCurrent(_ url: URL) -> Bool {
        viewModel.currentFolderURL?.path == url.path
    }

    private func isSelected(_ url: URL) -> Bool {
        viewModel.selectedFolderURL?.path == url.path
    }

    private var canGoUp: Bool {
        guard let current = viewModel.currentFolderURL else { return false }
        return current.path != current.deletingLastPathComponent().path
    }

    private func themeGlassPanel(cornerRadius: CGFloat, tint: Color? = nil) -> some View {
        AirwangGlassSurface(
            cornerRadius: cornerRadius,
            theme: viewModel.selectedTheme,
            tint: tint ?? themeAccentColor,
            tintStrength: tint == nil ? 0.0 : 0.32,
            elevation: .tile,
            reduceEffects: false
        )
    }

    // 颜色委托给 `AppTheme` 扩展,与主面板和 ImportSheet 保持一致(见 #46)。
    private var themePrimaryTextColor: Color { viewModel.selectedTheme.primaryTextColor }
    private var themeSecondaryTextColor: Color { viewModel.selectedTheme.secondaryTextColor }
    private var themeAccentColor: Color { viewModel.selectedTheme.accentColor }

}
