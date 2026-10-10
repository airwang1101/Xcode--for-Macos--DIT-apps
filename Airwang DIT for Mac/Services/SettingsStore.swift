import Foundation

final class SettingsStore {
    private let fileManager = FileManager.default
    private let preferencesURL: URL
    private let uiSettingsURL: URL
    private(set) var lastLoadWarning: String?

    var hasSavedSettings: Bool {
        fileManager.fileExists(atPath: preferencesURL.path) || fileManager.fileExists(atPath: uiSettingsURL.path)
    }

    init(preferencesURL: URL = AppStorageScope.preferencesURL, uiSettingsURL: URL = AppStorageScope.uiSettingsURL) {
        self.preferencesURL = preferencesURL
        self.uiSettingsURL = uiSettingsURL
    }

    func load() -> AppPreferences {
        load(AppPreferences.self, from: preferencesURL, fallback: .default, dataName: "工作预设")
    }

    func save(_ preferences: AppPreferences) throws {
        try JSONPersistence.writeSettings(preferences, to: preferencesURL)
    }

    func loadUISettings() -> AppUISettings {
        load(AppUISettings.self, from: uiSettingsURL, fallback: .default, dataName: "界面设置")
    }

    func saveUISettings(_ settings: AppUISettings) throws {
        try JSONPersistence.writeSettings(settings, to: uiSettingsURL)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL, fallback: T, dataName: String) -> T {
        guard fileManager.fileExists(atPath: url.path) else {
            return fallback
        }

        do {
            let data = try Data(contentsOf: url)
            try PersistentSchema.validateDataVersion(data)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            if let data = try? Data(contentsOf: url),
               (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
                lastLoadWarning = "\(dataName) 格式无法识别：\(error.localizedDescription)。文件已保留，保存时将检查并保护原文件。"
                return fallback
            }
            let backupURL = backupCorruptFile(at: url)
            let backupMessage = backupURL.map { "已备份到：\($0.path)" } ?? "备份损坏文件失败"
            lastLoadWarning = "\(dataName) JSON 无法读取：\(error.localizedDescription)。\(backupMessage)。"
            return fallback
        }
    }

    private func backupCorruptFile(at url: URL) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".corrupt-\(formatter.string(from: Date()))-\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension)
        do {
            try fileManager.copyItem(at: url, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }
}
