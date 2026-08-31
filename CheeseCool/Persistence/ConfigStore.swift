import Foundation

public actor ConfigStore {
    public let fileURL: URL
    public let legacyFileURL: URL?
    public private(set) var current: Configuration
    public private(set) var lastLoadError: String?

    public init(
        fileURL: URL,
        legacyFileURL: URL? = nil,
        defaults: Configuration = .defaults
    ) {
        self.fileURL = fileURL
        self.legacyFileURL = legacyFileURL
        self.current = defaults
    }

    public static func productionURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CheeseCool", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    public static func legacyProductionURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CheeseCool", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    @discardableResult
    public func load(fileManager: FileManager = .default) -> ConfigurationLoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            if let legacyFileURL,
               fileManager.fileExists(atPath: legacyFileURL.path) {
                return migrateLegacy(from: legacyFileURL, fileManager: fileManager)
            }
            current = .defaults
            lastLoadError = nil
            return ConfigurationLoadResult(configuration: current, usedDefaults: true, error: nil)
        }
        do {
            let data = try Data(contentsOf: fileURL)
            current = try Configuration.decodeStrict(from: data)
            lastLoadError = nil
            return ConfigurationLoadResult(configuration: current, usedDefaults: false, error: nil)
        } catch {
            current = .defaults
            lastLoadError = error.localizedDescription
            return ConfigurationLoadResult(
                configuration: current,
                usedDefaults: true,
                error: lastLoadError
            )
        }
    }

    public func save(_ configuration: Configuration, fileManager: FileManager = .default) throws {
        try configuration.validate()
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try configuration.encoded().write(to: fileURL, options: [.atomic])
        current = configuration
        lastLoadError = nil
    }

    public func resetToDefaults(fileManager: FileManager = .default) throws {
        try save(.defaults, fileManager: fileManager)
    }

    private func migrateLegacy(
        from legacyURL: URL,
        fileManager: FileManager
    ) -> ConfigurationLoadResult {
        do {
            let data = try Data(contentsOf: legacyURL)
            let configuration = try Configuration.decodeStrict(from: data)
            try save(configuration, fileManager: fileManager)
            return ConfigurationLoadResult(configuration: configuration, usedDefaults: false, error: nil)
        } catch {
            let migrationError = "旧设置迁移失败：\(error.localizedDescription)"
            do {
                try save(.defaults, fileManager: fileManager)
            } catch {
                current = .defaults
                lastLoadError = "\(migrationError)；默认设置保存失败：\(error.localizedDescription)"
                return ConfigurationLoadResult(
                    configuration: current,
                    usedDefaults: true,
                    error: lastLoadError
                )
            }
            lastLoadError = migrationError
            return ConfigurationLoadResult(
                configuration: current,
                usedDefaults: true,
                error: lastLoadError
            )
        }
    }
}
