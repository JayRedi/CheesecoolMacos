import AppKit
import CheeseCoolCore

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var configuration: Configuration
    public let configurationURL: URL
    public var onSave: ((Configuration) -> Void)?
    public var onReload: (() -> Void)?
    public var onReset: (() -> Void)?
    public var onClearLogs: (() -> Void)?

    public init(configuration: Configuration, configurationURL: URL) {
        self.configuration = configuration
        self.configurationURL = configurationURL
    }

    public func save() { onSave?(configuration) }
    public func reload() { onReload?() }
    public func reset() { onReset?() }
    public func clearLogs() { onClearLogs?() }

    public func openConfigurationFolder() {
        NSWorkspace.shared.open(configurationURL.deletingLastPathComponent())
    }
}
