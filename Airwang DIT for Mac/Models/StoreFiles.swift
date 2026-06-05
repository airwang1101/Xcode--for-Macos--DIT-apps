import Foundation

struct ProjectStoreFile: Codable {
    static let currentSchemaVersion = 1

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
        projects = try container.decodeIfPresent([CopyProject].self, forKey: .projects) ?? []
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
        reports = try container.decodeIfPresent([TransferReport].self, forKey: .reports) ?? []
    }
}

struct PersistentLoadResult<Value> {
    let value: Value
    let warning: String?
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

    static func writeProjects(_ projects: [CopyProject], to url: URL) throws {
        try write(ProjectStoreFile(projects: projects), to: url)
    }

    static func writeReports(_ reports: [TransferReport], to url: URL) throws {
        try write(ReportStoreFile(reports: reports), to: url)
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
            if let wrapped = try? decoder.decode(Wrapper.self, from: data) {
                return PersistentLoadResult(value: wrappedValue(wrapped), warning: nil)
            }
            let legacy = try decoder.decode([Element].self, from: data)
            return PersistentLoadResult(value: legacy, warning: nil)
        } catch {
            let backupURL = backupCorruptFile(at: url)
            let backupMessage = backupURL.map { "已备份到：\($0.path)" } ?? "备份损坏文件失败"
            return PersistentLoadResult(
                value: emptyValue,
                warning: "\(dataName) JSON 无法读取：\(error.localizedDescription)。\(backupMessage)。"
            )
        }
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
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
        if FileManager.default.fileExists(atPath: backupURL.path) {
            try FileManager.default.removeItem(at: backupURL)
        }
        try FileManager.default.copyItem(at: url, to: backupURL)
    }

    private static func backupCorruptFile(at url: URL) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".corrupt-\(formatter.string(from: Date()))")
            .appendingPathExtension(url.pathExtension)
        do {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try FileManager.default.removeItem(at: backupURL)
            }
            try FileManager.default.copyItem(at: url, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }
}
