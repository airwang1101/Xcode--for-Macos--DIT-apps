import Foundation

struct ProjectStoreFile: Codable {
    static let currentSchemaVersion = 2

    var schemaVersion: Int
    var projects: [CopyProject]

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projects
    }

    init(schemaVersion: Int = Self.currentSchemaVersion, projects: [CopyProject]) {
        self.schemaVersion = schemaVersion
        self.projects = projects
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        try PersistentSchema.validate(schemaVersion, supported: Self.currentSchemaVersion, decoder: decoder)
        projects = try container.decode([CopyProject].self, forKey: .projects)
    }
}

struct ReportStoreFile: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var reports: [TransferReport]

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case reports
    }

    init(schemaVersion: Int = Self.currentSchemaVersion, reports: [TransferReport]) {
        self.schemaVersion = schemaVersion
        self.reports = reports
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        try PersistentSchema.validate(schemaVersion, supported: Self.currentSchemaVersion, decoder: decoder)
        reports = try container.decode([TransferReport].self, forKey: .reports)
    }
}

struct PersistentLoadResult<Value> {
    let value: Value
    let warning: String?
}

enum PersistentSchema {
    static func validateDataVersion(_ data: Data, supported: Int = 1) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schemaVersion"] != nil else { return }
        struct Header: Decodable { var schemaVersion: Int }
        let header = try JSONDecoder().decode(Header.self, from: data)
        guard header.schemaVersion > 0, header.schemaVersion <= supported else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Unsupported schema version \(header.schemaVersion)."))
        }
    }

    static func validate(_ version: Int, supported: Int, decoder: any Decoder) throws {
        guard version > 0, version <= supported else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported schema version \(version); this app supports \(supported)."
            ))
        }
    }
}

enum PersistenceWriteError: LocalizedError {
    case protectedFile(URL, String)

    var errorDescription: String? {
        switch self {
        case let .protectedFile(url, reason):
            "为保护现有数据，未覆盖 \(url.lastPathComponent)：\(reason)。请使用能读取此格式的版本或先检查原文件。"
        }
    }
}

enum JSONPersistence {
    static func loadProjects(from url: URL) -> PersistentLoadResult<[CopyProject]> {
        loadArray(
            from: url,
            wrappedType: ProjectStoreFile.self,
            wrappedValue: \.projects,
            emptyValue: [],
            dataName: "项目队列"
        )
    }

    static func loadReports(from url: URL) -> PersistentLoadResult<[TransferReport]> {
        loadArray(
            from: url,
            wrappedType: ReportStoreFile.self,
            wrappedValue: \.reports,
            emptyValue: [],
            dataName: "任务日志"
        )
    }

    static func loadStatisticsIndex(from url: URL) -> PersistentLoadResult<CopyStatisticsIndex> {
        loadValue(
            from: url,
            type: CopyStatisticsIndex.self,
            emptyValue: CopyStatisticsIndex(),
            dataName: "统计索引"
        )
    }

    static func writeProjects(_ projects: [CopyProject], to url: URL) throws {
        try validateExistingFile(at: url, supportedSchemaVersion: ProjectStoreFile.currentSchemaVersion) { data in
            let decoder = JSONDecoder()
            do { _ = try decoder.decode(ProjectStoreFile.self, from: data) }
            catch { _ = try decoder.decode([CopyProject].self, from: data) }
            let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if (fields?["schemaVersion"] as? Int ?? 1) < ProjectStoreFile.currentSchemaVersion {
                let backup = url.deletingLastPathComponent().appendingPathComponent(
                    url.deletingPathExtension().lastPathComponent + ".before-v2-" + UUID().uuidString + ".json"
                )
                // Keep the original v1/legacy bytes independently of the rolling
                // .bak file, which later saves replace. Failure prevents migration.
                try data.write(to: backup, options: .withoutOverwriting)
            }
        }
        try write(ProjectStoreFile(projects: projects), to: url)
    }

    static func writeReports(_ reports: [TransferReport], to url: URL) throws {
        try validateExistingFile(at: url) { data in
            let decoder = JSONDecoder()
            do { _ = try decoder.decode(ReportStoreFile.self, from: data) }
            catch { _ = try decoder.decode([TransferReport].self, from: data) }
        }
        try write(ReportStoreFile(reports: reports), to: url)
    }

    static func writeStatisticsIndex(_ index: CopyStatisticsIndex, to url: URL) throws {
        try validateExistingFile(at: url) { data in
            _ = try JSONDecoder().decode(CopyStatisticsIndex.self, from: data)
        }
        try write(index, to: url)
    }

    static func writeSettings<Value: Codable>(_ value: Value, to url: URL) throws {
        try validateExistingFile(at: url) { data in
            _ = try JSONDecoder().decode(Value.self, from: data)
        }
        // Retain additive settings from newer compatible versions, including
        // keys this executable does not know. Known optional values can still
        // be cleared because keys from the old decoded value are removed first.
        if let data = try? Data(contentsOf: url),
           let previous = try? JSONDecoder().decode(Value.self, from: data),
           var fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           let previousFields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(previous)) as? [String: Any],
           let newFields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any] {
            for key in previousFields.keys { fields.removeValue(forKey: key) }
            fields.merge(newFields) { _, new in new }
            try writeData(JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys]), to: url)
            return
        }
        try write(value, to: url)
    }

    /// Validate the file again at save time. A launch-time warning alone cannot
    /// stop a later save, or protect against another version replacing the store.
    private static func validateExistingFile(at url: URL, supportedSchemaVersion: Int = 1, decode: (Data) throws -> Void) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true {
            throw PersistenceWriteError.protectedFile(url, "存储文件是符号链接")
        }
        let data = try Data(contentsOf: url)
        do {
            try PersistentSchema.validateDataVersion(data, supported: supportedSchemaVersion)
            try decode(data)
        } catch {
            if (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil {
                throw PersistenceWriteError.protectedFile(url, error.localizedDescription)
            }
            guard backupCorruptFile(at: url) != nil else {
                throw PersistenceWriteError.protectedFile(url, "损坏文件备份失败")
            }
        }
    }

    private static func loadArray<Wrapper: Decodable, Element: Decodable>(
        from url: URL,
        wrappedType: Wrapper.Type,
        wrappedValue: (Wrapper) -> [Element],
        emptyValue: [Element],
        dataName: String
    ) -> PersistentLoadResult<[Element]> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PersistentLoadResult(value: emptyValue, warning: nil)
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()

            // Try the current wrapped format first; capture the error for diagnostics.
            var wrappedDecodeError: Swift.Error?
            do {
                let wrapped = try decoder.decode(Wrapper.self, from: data)
                return PersistentLoadResult(value: wrappedValue(wrapped), warning: nil)
            } catch {
                wrappedDecodeError = error
            }

            // Fall back to the legacy bare-array format.
            do {
                let legacy = try decoder.decode([Element].self, from: data)
                return PersistentLoadResult(value: legacy, warning: nil)
            } catch {
                // Both formats failed. Check if the bytes are valid JSON at all:
                // JSONSerialization succeeds → valid JSON but unrecognised schema (e.g. future
                // version) → preserve the file so data is not lost on downgrade.
                // JSONSerialization fails → syntactically corrupt bytes → safe to back up.
                let isSyntacticallyValid = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
                if isSyntacticallyValid {
                    let diagnostic = wrappedDecodeError?.localizedDescription ?? error.localizedDescription
                    return PersistentLoadResult(
                        value: emptyValue,
                        warning: "\(dataName) 格式无法识别（可能来自更新版本）：\(diagnostic)。文件已保留，未自动清除。"
                    )
                }
                let backupURL = backupCorruptFile(at: url)
                let backupMessage = backupURL.map { "已备份到：\($0.path)" } ?? "备份损坏文件失败"
                return PersistentLoadResult(
                    value: emptyValue,
                    warning: "\(dataName) JSON 语法损坏，无法解析：\(error.localizedDescription)。\(backupMessage)。"
                )
            }
        } catch {
            return PersistentLoadResult(
                value: emptyValue,
                warning: "\(dataName) 文件读取失败：\(error.localizedDescription)。"
            )
        }
    }

    private static func loadValue<Value: Decodable>(
        from url: URL,
        type: Value.Type,
        emptyValue: Value,
        dataName: String
    ) -> PersistentLoadResult<Value> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return PersistentLoadResult(value: emptyValue, warning: nil)
        }

        do {
            let data = try Data(contentsOf: url)
            do {
                let value = try JSONDecoder().decode(Value.self, from: data)
                return PersistentLoadResult(value: value, warning: nil)
            } catch {
            let isSyntacticallyValid = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
                if isSyntacticallyValid {
                    return PersistentLoadResult(
                        value: emptyValue,
                        warning: "\(dataName) 格式无法识别（可能来自更新版本）：\(error.localizedDescription)。文件已保留，未自动清除。"
                    )
                }
                let backupURL = backupCorruptFile(at: url)
                let backupMessage = backupURL.map { "已备份到：\($0.path)" } ?? "备份损坏文件失败"
                return PersistentLoadResult(
                    value: emptyValue,
                    warning: "\(dataName) JSON 语法损坏，无法解析：\(error.localizedDescription)。\(backupMessage)。"
                )
            }
        } catch {
            return PersistentLoadResult(
                value: emptyValue,
                warning: "\(dataName) 文件读取失败：\(error.localizedDescription)。"
            )
        }
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try writeData(data, to: url)
    }

    private static func writeData(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try backupExistingFile(at: url)
        try data.write(to: url, options: .atomic)
    }

    private static func backupExistingFile(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".bak")
            .appendingPathExtension(url.pathExtension)
        // Atomic write (temp + rename) so the .bak is never left truncated on crash,
        // and it transparently overwrites an existing .bak or creates a new one.
        let existing = try Data(contentsOf: url)
        try existing.write(to: backupURL, options: .atomic)
    }

    private static func backupCorruptFile(at url: URL) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".corrupt-\(formatter.string(from: Date()))-\(UUID().uuidString)")
            .appendingPathExtension(url.pathExtension)
        do {
            try FileManager.default.copyItem(at: url, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }
}
