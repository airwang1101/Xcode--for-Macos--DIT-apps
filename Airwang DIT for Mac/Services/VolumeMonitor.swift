import AppKit
import Combine
import Foundation

@MainActor
final class VolumeMonitor: ObservableObject {
    @Published private(set) var volumes: [StorageVolume] = []
    var onNewExternalVolume: ((StorageVolume) -> Void)?
    var onVolumeUnmounted: ((URL) -> Void)?

    private let workspace = NSWorkspace.shared
    private var cancellables: Set<AnyCancellable> = []

    init() {
        refreshVolumes()

        workspace.notificationCenter.publisher(for: NSWorkspace.didMountNotification)
            .sink { [weak self] notification in
                self?.handleMount(notification)
            }
            .store(in: &cancellables)

        workspace.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)
            .sink { [weak self] notification in
                self?.handleUnmount(notification)
            }
            .store(in: &cancellables)
    }

    func refreshVolumes() {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [
            .volumeNameKey,
            .volumeLocalizedNameKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
            .volumeIsBrowsableKey
        ], options: [.skipHiddenVolumes]) ?? []

        volumes = urls.compactMap(makeVolume(from:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func handleMount(_ notification: Notification) {
        refreshVolumes()

        guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL,
              let volume = makeVolume(from: url),
              shouldSurface(volume) else {
            return
        }

        onNewExternalVolume?(volume)
    }

    private func handleUnmount(_ notification: Notification) {
        let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
        refreshVolumes()

        if let url {
            onVolumeUnmounted?(url)
        }
    }

    private func makeVolume(from url: URL) -> StorageVolume? {
        guard let values = try? url.resourceValues(forKeys: [
            .volumeNameKey,
            .volumeLocalizedNameKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeTotalCapacityKey,
            .volumeIsBrowsableKey
        ]),
        values.volumeIsBrowsable != false else {
            return nil
        }

        let name = values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent
        let capacity = DiskCapacityResolver.capacity(for: url)
        return StorageVolume(
            id: url.path,
            name: name,
            url: url,
            isRemovable: values.volumeIsRemovable ?? false,
            isInternal: values.volumeIsInternal ?? false,
            totalCapacity: capacity.totalCapacity,
            availableCapacity: capacity.availableCapacity
        )
    }

    private func shouldSurface(_ volume: StorageVolume) -> Bool {
        volume.url.path != "/" && (volume.isRemovable || !volume.isInternal || volume.url.path.hasPrefix("/Volumes/"))
    }
}
