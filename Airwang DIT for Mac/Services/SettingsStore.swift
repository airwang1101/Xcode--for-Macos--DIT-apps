import Foundation

final class SettingsStore {
    private let fileManager = FileManager.default
    private(set) var lastLoadWarning: String?

    func load() -> AppPreferences {
        load(AppPreferences.self, from: AppStorageScope.preferencesURL, fallback: .default, dataName: "工作预设")
    }

    func save(_ preferences: AppPreferences) throws {
        try save(preferences, to: AppStorageScope.preferencesURL)
    }

    func loadUISettings() -> AppUISettings {
        load(AppUISettings.self, from: AppStorageScope.uiSettingsURL, fallback: .default, dataName: "界面设置")
    }

    func saveUISettings(_ settings: AppUISettings) throws {
        try save(settings, to: AppStorageScope.uiSettingsURL)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL, fallback: T, dataName: String) -> T {
        guard fileManager.fileExists(atPath: url.path) else {
            return fallback
        }

        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let backupURL = backupCorruptFile(at: url)
            let backupMessage = backupURL.map { "已备份到：\($0.path)" } ?? "备份损坏文件失败"
            lastLoadWarning = "\(dataName) JSON 无法读取：\(error.localizedDescription)。\(backupMessage)。"
            return fallback
        }
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try data.write(to: url, options: .atomic)
    }

    private func backupCorruptFile(at url: URL) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".corrupt-\(formatter.string(from: Date()))")
            .appendingPathExtension(url.pathExtension)
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: url, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }
}
