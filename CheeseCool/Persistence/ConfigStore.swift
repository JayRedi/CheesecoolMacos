import Foundation

public actor ConfigStore {
    public let fileURL: URL
    public private(set) var current: Configuration
    public private(set) var lastLoadError: String?

    public init(fileURL: URL, defaults: Configuration = .defaults) {
        self.fileURL = fileURL
        self.current = defaults
    }

    public static func productionURL(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CheeseCool", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    @discardableResult
    public func reload(fileManager: FileManager = .default) -> ConfigurationLoadResult {
        guard fileManager.fileExists(atPath: fileURL.path) else {
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
}
