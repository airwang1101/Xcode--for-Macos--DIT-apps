import AppKit
import SwiftUI

struct ImportSheet: View {
    let volume: StorageVolume
    @EnvironmentObject private var viewModel: AppViewModel
    @State private var expandedGroupIDs: Set<String> = []
    @State private var selectedBrowserFolder = ""
    @State private var focusedGalleryItemID: String?

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button {
                    handlePrimaryBackAction()
                } label: {
                    Label(primaryBackTitle, systemImage: primaryBackIcon)
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isScanning || (!viewModel.hasScannedSource && !canGoUp))

                VStack(alignment: .leading, spacing: 5) {
                    Text("新存储设备已接入")
                        .font(.title2.bold())
                    Text(volume.name)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.hasScannedSource {
                    Picker("模式", selection: $viewModel.selectedImportMode) {
                        ForEach(ImportMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }

                Button {
                    viewModel.closeImportSheet()
                } label: {
                    Label("退出", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }

            importStepRail

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    if viewModel.hasScannedSource {
                        Text(viewModel.selectedImportMode.subtitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(secondaryTextColor)
                    } else {
                        Text("先在当前设备里选择一个具体文件夹，再点击扫描。扫描完成后再选择需要拷贝的素材。")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(secondaryTextColor)
                    }

                    if viewModel.isScanning {
                        scanningState
                    } else if viewModel.hasScannedSource {
                        content
                    } else {
                        sourcePickerSection
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 500, alignment: .topLeading)

                ScrollView {
                    summarySection
                }
                .frame(width: 340)
            }
        }
        .padding(28)
        .frame(minWidth: 980, idealWidth: 1180, maxWidth: .infinity, minHeight: 660, idealHeight: 760, maxHeight: .infinity)
        .background(importSheetBackground)
        .background(ResizableSheetWindowConfigurator(minSize: NSSize(width: 980, height: 660), idealSize: NSSize(width: 1180, height: 760)))
        .fontDesign(viewModel.interfaceStyle == .paper ? .default : .serif)
        .preferredColorScheme(viewModel.selectedTheme == .night ? .dark : .light)
    }

    private func handlePrimaryBackAction() {
        if viewModel.hasScannedSource {
            viewModel.returnToSourceFolderSelection()
        } else if canGoUp {
            viewModel.navigateSourceFolderUp()
        }
    }

    private var primaryBackTitle: String {
        if viewModel.isScanning {
            return "正在扫描"
        }
        if viewModel.hasScannedSource {
            return "重新选择文件夹"
        }
        if canGoUp {
            return "上一级"
        }
        return "设备根目录"
    }

    private var primaryBackIcon: String {
        if viewModel.isScanning {
            return "hourglass"
        }
        return "chevron.left"
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            scannedSelectionHeader

            if viewModel.scannedItems.isEmpty {
                importEmptyState(
                    title: "没有找到匹配素材",
                    detail: "可以切换扫描类型，或返回上一级选择更大的源文件夹后重新扫描。"
                )
            } else {
                switch viewModel.selectedImportMode {
                case .time:
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.timeGroups) { group in
                                timeGroupCard(group)
                            }
                        }
                    }
                case .free:
                    assetBrowserContent
                }
            }
        }
    }

    @ViewBuilder
    private var assetBrowserContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            browserModeBar

            switch viewModel.selectedAssetBrowserMode {
            case .icon:
                iconBrowser
            case .list:
                listBrowser
            case .column:
                columnBrowser
            case .gallery:
                galleryBrowser
            }
        }
    }

    private var browserModeBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("自由浏览")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                Text(viewModel.selectedAssetBrowserMode.subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(secondaryTextColor)
            }
            Spacer()
            Picker("浏览方式", selection: $viewModel.selectedAssetBrowserMode) {
                ForEach(AssetBrowserMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 390)
        }
        .padding(14)
        .background(glassPanel(cornerRadius: 18))
    }

    private var iconBrowser: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(viewModel.scannedItems) { item in
                    freeSelectionTile(item)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var listBrowser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("名称")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("类型")
                    .frame(width: 72, alignment: .leading)
                Text("大小")
                    .frame(width: 100, alignment: .trailing)
                Text("创建时间")
                    .frame(width: 128, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(secondaryTextColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().opacity(0.35)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(viewModel.scannedItems) { item in
                        listSelectionRow(item: item)
                    }
                }
                .padding(8)
            }
        }
        .background(glassPanel(cornerRadius: 20))
    }

    private var columnBrowser: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("文件夹")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(browserFolders, id: \.self) { folder in
                            Button {
                                selectedBrowserFolder = folder
                            } label: {
                                HStack {
                                    Image(systemName: folder.isEmpty ? "externaldrive.fill" : "folder.fill")
                                        .foregroundStyle(folder.isEmpty ? accentColor : .orange)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(folder.isEmpty ? "扫描根目录" : folderName(folder))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(primaryTextColor)
                                            .lineLimit(1)
                                        Text(folder.isEmpty ? "根目录文件" : folder)
                                            .font(.caption2)
                                            .foregroundStyle(secondaryTextColor)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text("\(items(in: folder).count)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(secondaryTextColor)
                                }
                                .padding(10)
                                .background(
                                    selectedBrowserFolder == folder ? accentColor.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
            }
            .frame(width: 260)
            .padding(14)
            .background(glassPanel(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selectedBrowserFolder.isEmpty ? "扫描根目录" : folderName(selectedBrowserFolder))
                            .font(.headline)
                            .foregroundStyle(primaryTextColor)
                        Text(selectedBrowserFolder.isEmpty ? "显示根目录下匹配文件" : selectedBrowserFolder)
                            .font(.caption)
                            .foregroundStyle(secondaryTextColor)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text("\(columnItems.count) 个文件")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(columnItems) { item in
                            listSelectionRow(item: item)
                        }
                    }
                }
            }
            .padding(14)
            .background(glassPanel(cornerRadius: 20))
        }
        .onAppear {
            normalizeSelectedBrowserFolder()
        }
        .onChange(of: viewModel.scannedItems) { _, _ in
            normalizeSelectedBrowserFolder()
        }
    }

    private var galleryBrowser: some View {
        VStack(alignment: .leading, spacing: 12) {
            let item = focusedGalleryItem
            HStack(alignment: .top, spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(thumbFill)
                    if let item {
                        ThumbnailView(url: item.fileURL)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(14)
                    } else {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 58, weight: .semibold))
                            .foregroundStyle(secondaryTextColor)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 330)
                .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.24, elevation: .card)
                .onTapGesture {
                    if let item {
                        viewModel.toggle(item: item)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("预览详情")
                        .font(.headline)
                        .foregroundStyle(primaryTextColor)
                    if let item {
                        galleryDetail(label: "文件名", value: item.displayName)
                        galleryDetail(label: "路径", value: item.relativePath)
                    galleryDetail(label: "类型", value: mediaKindTitle(for: item))
                        galleryDetail(label: "大小", value: byteText(item.size))
                        galleryDetail(label: "创建时间", value: item.createdAt.formatted(date: .abbreviated, time: .shortened))

                        Button(viewModel.selectedItemIDs.contains(item.id) ? "从导入中移除" : "加入导入选择") {
                            viewModel.toggle(item: item)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(viewModel.selectedItemIDs.contains(item.id) ? .red : accentColor)
                        .controlSize(.large)
                    } else {
                        Text("没有可预览的素材")
                            .foregroundStyle(secondaryTextColor)
                    }
                    Spacer()
                }
                .frame(width: 240, alignment: .topLeading)
                .padding(16)
                .background(glassPanel(cornerRadius: 20))
            }

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(viewModel.scannedItems) { item in
                        galleryStripTile(item)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .background(glassPanel(cornerRadius: 22))
        .onAppear {
            normalizeFocusedGalleryItem()
        }
        .onChange(of: viewModel.scannedItems) { _, _ in
            normalizeFocusedGalleryItem()
        }
    }

    private var importStepRail: some View {
        // 步骤 3 的 active 条件不再依赖 `selectedItems.isEmpty`(扫描完成后会自动全选,
        // 导致这条件永远 false → 步骤 3 从未被点亮,见 TEST_REPORT.md #74)。
        // 现在的语义是:扫描完成后,用户处于"选择 / 复核素材"阶段,步骤 3 一直
        // 高亮直到 sheet 关闭。步骤 4 与之并列高亮,表示"下一步按钮已就绪"。
        //
        // 步骤 4 标题改为"加入任务队列",与按钮 `创建项目并加入队列` 的实际行为
        // 保持一致(原"开始拷贝+校验"具有误导性,见 #54 / #75)。
        let scanDone = viewModel.hasScannedSource
        return HStack(spacing: 10) {
            stepPill(index: "1", title: "选源文件夹", isActive: !scanDone && !viewModel.isScanning, isDone: viewModel.isScanning || scanDone)
            stepPill(index: "2", title: "扫描素材", isActive: viewModel.isScanning, isDone: scanDone)
            stepPill(index: "3", title: "选择素材", isActive: scanDone, isDone: false)
            stepPill(index: "4", title: "加入任务队列", isActive: scanDone && viewModel.canStartImport, isDone: false)
        }
        .padding(12)
        .background(glassPanel(cornerRadius: 22))
    }

    private func stepPill(index: String, title: String, isActive: Bool, isDone: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(isDone ? accentColor : (isActive ? accentColor.opacity(0.16) : secondaryTextColor.opacity(0.14)))
                    .frame(width: 26, height: 26)
                if isDone {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                } else {
                    Text(index)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isActive ? accentColor : secondaryTextColor)
                }
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive || isDone ? primaryTextColor : secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isActive ? accentColor.opacity(0.10) : Color.clear, in: Capsule())
    }

    private var scanningState: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .scaleEffect(1.15)
            Text("正在扫描素材...")
                .font(.headline)
                .foregroundStyle(primaryTextColor)
            Text("当前只读取你选择的文件夹，不会浪费资源扫描整张卡。")
                .font(.subheadline)
                .foregroundStyle(secondaryTextColor)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 420)
        .background(glassPanel(cornerRadius: 24))
    }

    private var scannedSelectionHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("已扫描 \(viewModel.scannedItems.count) 个文件")
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                Text("当前选择 \(viewModel.selectedItems.count) 个 · \(byteText(viewModel.selectedTotalBytes)) / 扫描总量 \(byteText(viewModel.scannedTotalBytes))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                Text("勾选素材时会自动带上同文件夹、同文件名的 sidecar / 元数据文件。")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(secondaryTextColor)
            }
            Spacer()
            Button("全选") {
                viewModel.selectAllScannedItems()
            }
            .buttonStyle(.bordered)
            .tint(accentColor)

            Button("清空选择") {
                viewModel.clearScannedSelection()
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(16)
        .background(glassPanel(cornerRadius: 20))
    }

    private func timeGroupCard(_ group: TimeGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    viewModel.toggle(group: group)
                } label: {
                    Image(systemName: isGroupSelected(group) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isGroupSelected(group) ? accentColor : secondaryTextColor)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(group.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.headline)
                        .foregroundStyle(primaryTextColor)
                    Text("\(group.items.count) 个文件 · \(byteText(group.totalSize))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(secondaryTextColor)
                }
                Spacer()
                Text(isGroupSelected(group) ? "整组已选" : "点击圆圈选择整组")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isGroupSelected(group) ? accentColor : secondaryTextColor)
            }

            ForEach(expandedGroupIDs.contains(group.id) ? group.items : Array(group.items.prefix(6))) { item in
                selectionRow(item: item)
            }

            if group.items.count > 6 {
                Button(expandedGroupIDs.contains(group.id) ? "收起" : "展开全部 \(group.items.count) 个文件") {
                    if expandedGroupIDs.contains(group.id) {
                        expandedGroupIDs.remove(group.id)
                    } else {
                        expandedGroupIDs.insert(group.id)
                    }
                }
                .buttonStyle(.borderless)
                .tint(accentColor)
            }
        }
        .padding(16)
        .background(glassPanel(cornerRadius: 20))
    }

    private func freeSelectionTile(_ item: MediaItem) -> some View {
        let isSelected = viewModel.selectedItemIDs.contains(item.id)

        return Button {
            viewModel.toggle(item: item)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                ThumbnailView(url: item.fileURL)
                    .frame(height: 104)
                    .frame(maxWidth: .infinity)
                    .background(thumbFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.18, elevation: .tile)

                Text(item.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(2)
                Text(byteText(item.size))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? accentColor : Color.clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(accentColor)
                            .padding(8)
                            .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.45, elevation: .tile)
                }
            }
            .background(glassPanel(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func listSelectionRow(item: MediaItem) -> some View {
        let isSelected = viewModel.selectedItemIDs.contains(item.id)

        return Button {
            viewModel.toggle(item: item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? accentColor : secondaryTextColor)
                    .frame(width: 24)

                Image(systemName: mediaIcon(for: item))
                    .font(.headline)
                    .foregroundStyle(accentColor)
                    .frame(width: 24)
                    .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.18, elevation: .tile)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(primaryTextColor)
                        .lineLimit(1)
                    Text(item.relativePath)
                        .font(.caption2)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(mediaKindTitle(for: item))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 72, alignment: .leading)

                Text(byteText(item.size))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 100, alignment: .trailing)

                Text(item.createdAt.formatted(date: .numeric, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .frame(width: 128, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                isSelected ? accentColor.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func galleryDetail(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(primaryTextColor)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func galleryStripTile(_ item: MediaItem) -> some View {
        let isFocused = focusedGalleryItem?.id == item.id
        let isSelected = viewModel.selectedItemIDs.contains(item.id)

        return Button {
            focusedGalleryItemID = item.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ThumbnailView(url: item.fileURL)
                    .frame(width: 118, height: 72)
                    .background(thumbFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.15, elevation: .tile)

                Text(item.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                    .lineLimit(1)
            }
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isFocused ? accentColor : (isSelected ? secondaryAccentColor : Color.clear), lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(secondaryAccentColor)
                            .padding(5)
                            .airwangSoftShadow(theme: viewModel.selectedTheme, tint: secondaryAccentColor, tintStrength: 0.45, elevation: .tile)
                }
            }
            .background(glassPanel(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var browserFolders: [String] {
        let folders = Set(viewModel.scannedItems.map(folderPath(for:)))
        return folders.sorted { lhs, rhs in
            if lhs.isEmpty { return true }
            if rhs.isEmpty { return false }
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }

    private var columnItems: [MediaItem] {
        items(in: selectedBrowserFolder)
    }

    private var focusedGalleryItem: MediaItem? {
        if let focusedGalleryItemID,
           let item = viewModel.scannedItems.first(where: { $0.id == focusedGalleryItemID }) {
            return item
        }
        return viewModel.scannedItems.first
    }

    private func normalizeSelectedBrowserFolder() {
        guard !browserFolders.isEmpty else {
            selectedBrowserFolder = ""
            return
        }
        if !browserFolders.contains(selectedBrowserFolder) {
            selectedBrowserFolder = browserFolders.first ?? ""
        }
    }

    private func normalizeFocusedGalleryItem() {
        guard !viewModel.scannedItems.isEmpty else {
            focusedGalleryItemID = nil
            return
        }
        if let focusedGalleryItemID,
           viewModel.scannedItems.contains(where: { $0.id == focusedGalleryItemID }) {
            return
        }
        focusedGalleryItemID = viewModel.scannedItems.first?.id
    }

    private func items(in folder: String) -> [MediaItem] {
        viewModel.scannedItems.filter { folderPath(for: $0) == folder }
    }

    private func folderPath(for item: MediaItem) -> String {
        guard let slashIndex = item.relativePath.lastIndex(of: "/") else { return "" }
        return String(item.relativePath[..<slashIndex])
    }

    private func folderName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    private func mediaIcon(for item: MediaItem) -> String {
        item.mediaKind.systemImageName
    }

    private func mediaKindTitle(for item: MediaItem) -> String {
        switch item.mediaKind {
        case .video:
            return "视频"
        case .photo:
            return "照片"
        case .audio:
            return "音频"
        case .all:
            return item.fileURL.pathExtension.isEmpty ? "其他" : item.fileURL.pathExtension.uppercased()
        }
    }

    private func importEmptyState(title: String, detail: String) -> some View {
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(accentColor)
            Text(title)
                .font(.headline)
                .foregroundStyle(primaryTextColor)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(secondaryTextColor)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .padding(24)
        .background(glassPanel(cornerRadius: 24))
    }

    private var sourcePickerSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                sourceGuideCard(number: "1", title: "进入文件夹", detail: "只扫描你确认的目录")
                sourceGuideCard(number: "2", title: "选择类型", detail: "视频 / 照片 / 音频 / 全部")
                sourceGuideCard(number: "3", title: "开始扫描", detail: "扫描后再勾选素材")
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("选择源文件夹")
                        .font(.headline)
                    Text(viewModel.sourceFolderURL?.path ?? volume.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    viewModel.navigateSourceFolderUp()
                } label: {
                    Label("上一级", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
                .disabled(!canGoUp)
            }

            Picker("扫描类型", selection: Binding(
                get: { viewModel.selectedScanFilter },
                set: { viewModel.setScanFilter($0) }
            )) {
                ForEach(ScanFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 320)

            ScrollView {
                LazyVStack(spacing: 10) {
                    currentSourceFolderCard

                    if viewModel.isLoadingSourceFolderChildren {
                        ProgressView("正在读取文件夹...")
                            .frame(maxWidth: .infinity)
                            .padding(24)
                    }

                    ForEach(viewModel.sourceFolderChildren) { item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name)
                                    .font(.headline)
                                    .foregroundStyle(primaryTextColor)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(secondaryTextColor)
                                    .lineLimit(1)
                                Text(item.capacityLine)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(secondaryTextColor)
                                CapacityMeter(
                                    totalCapacity: item.totalCapacity,
                                    availableCapacity: item.availableCapacity,
                                    tint: accentColor,
                                    backgroundColor: secondaryTextColor.opacity(0.15)
                                )
                                .frame(maxWidth: 260)
                            }
                            Spacer()
                            Button("进入并设为当前") {
                                viewModel.navigateSourceFolder(to: item.url)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accentColor)
                        }
                        .padding(14)
                        .background(glassPanel(cornerRadius: 18))
                    }
                }
            }
        }
    }

    private var currentSourceFolderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前准备扫描")
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            Text(viewModel.selectedSourceFolderItem?.name ?? volume.name)
                .font(.title3.weight(.semibold))
                .foregroundStyle(primaryTextColor)
            Text(viewModel.selectedSourceFolderItem?.subtitle ?? volume.url.path)
                .font(.caption)
                .foregroundStyle(secondaryTextColor)
            if let selectedSourceFolderItem = viewModel.selectedSourceFolderItem {
                Text(selectedSourceFolderItem.capacityLine)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                CapacityMeter(
                    totalCapacity: selectedSourceFolderItem.totalCapacity,
                    availableCapacity: selectedSourceFolderItem.availableCapacity,
                    tint: accentColor,
                    backgroundColor: secondaryTextColor.opacity(0.15)
                )
            }
            HStack {
                Text("只扫描这个目录")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                Spacer()
                Button("扫描此文件夹") {
                    viewModel.scanSelectedSourceFolder()
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor)
            }
        }
        .padding(18)
        .background(glassPanel(cornerRadius: 20))
    }

    private func sourceGuideCard(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
        .background(glassPanel(cornerRadius: 16))
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("导入摘要")
                    .font(.headline)
                    .foregroundStyle(primaryTextColor)
                Spacer()
                Text(viewModel.hasScannedSource ? "已扫描" : "待扫描")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((viewModel.hasScannedSource ? accentColor : secondaryTextColor).opacity(0.14), in: Capsule())
                    .foregroundStyle(viewModel.hasScannedSource ? accentColor : secondaryTextColor)
            }

            let selectedItems = viewModel.selectedItems
            let totalBytes = viewModel.selectedTotalBytes

            VStack(alignment: .leading, spacing: 8) {
                Text("\(selectedItems.count) 个文件")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(primaryTextColor)
                Text("待拷贝总量 \(byteText(totalBytes))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Group {
                summaryRow("扫描目录", value: viewModel.sourceFolderURL?.path ?? volume.url.path)
                summaryRow("扫描类型", value: viewModel.selectedScanFilter.title)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("项目名称")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                Picker("项目名称", selection: $viewModel.projectNameMode) {
                    ForEach(ProjectNameMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if viewModel.projectNameMode == .custom {
                    TextField("例如 A_CAM_Day01_Card03", text: $viewModel.draftProjectName)
                        .textFieldStyle(.roundedBorder)
                }
                Text("当前名称：\(viewModel.projectNamePreview)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(primaryTextColor)
            }
            .padding(12)
            .background(glassPanel(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.localized("当前执行方式"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                Text(viewModel.localized(
                    viewModel.autoStartQueuedProjects
                        ? "加入队列，5 分钟后自动执行"
                        : "加入队列，等待手动执行"
                ))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryTextColor)

                if viewModel.autoStartQueuedProjects {
                    Label(
                        viewModel.localized("任务将在 5 分钟后开始写入目标盘，请确认源盘、主盘、备份盘路径无误。"),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .background(glassPanel(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 10) {
                Text("校验方式")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryTextColor)
                Picker("校验方式", selection: $viewModel.selectedVerificationMode) {
                    ForEach(VerificationMode.selectableCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                Text(viewModel.selectedVerificationMode.detail)
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(glassPanel(cornerRadius: 16))

            destinationSummaryCard(
                title: "主目标盘",
                path: viewModel.preferences.targetPath ?? "-",
                capacity: viewModel.targetCapacity,
                spacePreflight: viewModel.targetSpacePreflight,
                tint: accentColor
            )

            if viewModel.preferences.backupEnabled {
                destinationSummaryCard(
                    title: "备份盘",
                    path: viewModel.preferences.backupPath ?? "未设置",
                    capacity: viewModel.backupCapacity,
                    spacePreflight: viewModel.backupSpacePreflight,
                    tint: secondaryAccentColor
                )
            }

            ForEach(viewModel.destinationWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Text(startDisabledReason)
                .font(.caption.weight(.semibold))
                .foregroundStyle(viewModel.canStartImport && viewModel.hasScannedSource ? accentColor : secondaryTextColor)
                .fixedSize(horizontal: false, vertical: true)

            Button("创建项目并加入队列") {
                viewModel.startImport()
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(!viewModel.canStartImport || !viewModel.hasScannedSource)
        }
        .padding(18)
        .background(glassPanel(cornerRadius: 24))
    }

    private func destinationSummaryCard(
        title: String,
        path: String,
        capacity: StorageCapacitySnapshot?,
        spacePreflight: DestinationSpacePreflight?,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            Text(path)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(primaryTextColor)
                .lineLimit(2)
                .textSelection(.enabled)
            Text(capacity?.capacityLine ?? "容量暂不可读")
                .font(.caption.weight(.semibold))
                .foregroundStyle(secondaryTextColor)
            CapacityMeter(
                totalCapacity: capacity?.totalCapacity,
                availableCapacity: capacity?.availableCapacity,
                tint: tint,
                backgroundColor: secondaryTextColor.opacity(0.16)
            )

            if let preflight = spacePreflight {
                Divider()
                    .overlay(secondaryTextColor.opacity(0.16))
                spacePreflightRow(
                    title: viewModel.localized("素材总量"),
                    value: ByteDisplayFormatter.string(fromByteCount: preflight.requirement.payloadBytes)
                )
                spacePreflightRow(
                    title: viewModel.localized("安全冗余"),
                    value: ByteDisplayFormatter.string(fromByteCount: preflight.requirement.safetyMarginBytes)
                )
                spacePreflightRow(
                    title: viewModel.localized("最低需求"),
                    value: ByteDisplayFormatter.string(fromByteCount: preflight.requirement.requiredBytes)
                )
                spacePreflightRow(
                    title: viewModel.localized("可用空间"),
                    value: preflight.availableBytes.map { ByteDisplayFormatter.string(fromByteCount: $0) }
                        ?? viewModel.localized("容量暂不可读")
                )
                spacePreflightRow(
                    title: viewModel.localized("预检状态"),
                    value: spacePreflightStatusText(preflight.status),
                    valueColor: preflight.status == .passed ? tint : .red
                )
            }
        }
        .padding(12)
        .background(
            AirwangGlassSurface(
                cornerRadius: 16,
                theme: viewModel.selectedTheme,
                tint: tint,
                tintStrength: 0.35,
                elevation: .tile,
                reduceEffects: false
            )
        )
    }

    private func spacePreflightRow(
        title: String,
        value: String,
        valueColor: Color? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(secondaryTextColor)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(valueColor ?? primaryTextColor)
                .multilineTextAlignment(.trailing)
        }
        .font(.caption.weight(.semibold))
    }

    private func spacePreflightStatusText(_ status: DestinationSpacePreflight.Status) -> String {
        switch status {
        case .passed:
            return viewModel.localized("可执行")
        case .insufficient:
            return viewModel.localized("空间不足")
        case .capacityUnavailable:
            return viewModel.localized("容量不可读，已阻止执行")
        }
    }

    private var startDisabledReason: String {
        if !viewModel.hasScannedSource {
            return "请先扫描源文件夹。"
        }
        if viewModel.selectedItems.isEmpty {
            return "请至少选择一个素材文件。"
        }
        if let warning = viewModel.destinationWarnings.first {
            return warning
        }
        return "准备就绪：开始后会创建项目，先主盘拷贝与校验，再按需从主盘串行备份。"
    }

    private func isGroupSelected(_ group: TimeGroup) -> Bool {
        Set(group.items.map(\.id)).isSubset(of: viewModel.selectedItemIDs)
    }

    private func selectionRow(item: MediaItem) -> some View {
        let isSelected = viewModel.selectedItemIDs.contains(item.id)

        return HStack {
            Button {
                viewModel.toggle(item: item)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? accentColor : secondaryTextColor)
            }
            .buttonStyle(.plain)
            ThumbnailView(url: item.fileURL)
                .frame(width: 54, height: 40)
                .airwangSoftShadow(theme: viewModel.selectedTheme, tint: accentColor, tintStrength: 0.16, elevation: .tile)
            VStack(alignment: .leading) {
                Text(item.displayName)
                    .foregroundStyle(primaryTextColor)
                Text(item.relativePath)
                    .font(.caption)
                    .foregroundStyle(secondaryTextColor)
                    .lineLimit(1)
            }
            Spacer()
            Text(byteText(item.size))
                .foregroundStyle(secondaryTextColor)
        }
        .padding(8)
        .background(isSelected ? accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .frame(width: 100, alignment: .leading)
                .foregroundStyle(secondaryTextColor)
            Text(value)
                .foregroundStyle(primaryTextColor)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    private func byteText(_ value: Int64) -> String {
        ByteDisplayFormatter.string(fromByteCount: value)
    }

    private var importSheetBackground: some View {
        Group {
            if viewModel.interfaceStyle == .paper {
                PaperPalette(theme: viewModel.selectedTheme).background
            } else if viewModel.selectedTheme == .night {
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
    }

    private func glassPanel(cornerRadius: CGFloat) -> some View {
        AirwangGlassSurface(
            cornerRadius: cornerRadius,
            theme: viewModel.selectedTheme,
            tint: accentColor,
            tintStrength: 0.22,
            elevation: .card,
            reduceEffects: false
        )
    }

    // 颜色委托给 `AppTheme` 扩展,与主面板保持一致(原本 ImportSheet 在白天模式
    // 走 `Color.primary` / `Color.secondary`,与暖色背景不协调,见 #45)。
    private var primaryTextColor: Color { viewModel.interfaceStyle == .paper ? PaperPalette(theme: viewModel.selectedTheme).ink : viewModel.selectedTheme.primaryTextColor }
    private var secondaryTextColor: Color { viewModel.interfaceStyle == .paper ? PaperPalette(theme: viewModel.selectedTheme).secondary : viewModel.selectedTheme.secondaryTextColor }
    private var accentColor: Color { viewModel.interfaceStyle == .paper ? PaperPalette(theme: viewModel.selectedTheme).accent : viewModel.selectedTheme.accentColor }
    private var secondaryAccentColor: Color { viewModel.interfaceStyle == .paper ? PaperPalette(theme: viewModel.selectedTheme).secondaryAccent : viewModel.selectedTheme.secondaryAccentColor }

    private var thumbFill: Color {
        viewModel.selectedTheme == .night ? Color.white.opacity(0.06) : Color.black.opacity(0.08)
    }

    private var canGoUp: Bool {
        guard let sourceFolderURL = viewModel.sourceFolderURL else { return false }
        return sourceFolderURL.path != volume.url.path && sourceFolderURL.path != sourceFolderURL.deletingLastPathComponent().path
    }
}
