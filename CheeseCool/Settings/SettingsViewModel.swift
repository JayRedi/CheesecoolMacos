import CheeseCoolCore
import Combine

@MainActor
public final class SettingsViewModel: ObservableObject {
    @Published public var configuration: Configuration {
        didSet {
            guard !isReplacingConfiguration else { return }
            onConfigurationChanged?(configuration)
        }
    }
    @Published public private(set) var metrics: MetricsSnapshot?
    public var onConfigurationChanged: ((Configuration) -> Void)?
    public var onReset: (() -> Void)?
    public var onClearLogs: (() -> Void)?
    private var isReplacingConfiguration = false

    public init(configuration: Configuration) {
        self.configuration = configuration
    }

    public func reset() { onReset?() }
    public func clearLogs() { onClearLogs?() }

    public func replaceConfiguration(_ configuration: Configuration) {
        isReplacingConfiguration = true
        self.configuration = configuration
        isReplacingConfiguration = false
    }

    public func update(metrics: MetricsSnapshot) {
        self.metrics = metrics
        let unsupported = MetricAvailabilityPolicy.unsupportedMetrics(in: metrics)
        if configuration.menuBar.visibleMetrics.contains(where: unsupported.contains) {
            configuration.menuBar.visibleMetrics.removeAll { unsupported.contains($0) }
        }
    }

    public func sample(for metric: MetricIdentifier) -> MetricSample? {
        switch metric {
        case .socTemperature: return metrics?.socTemperature
        case .cpuLoad: return metrics?.cpuLoad
        case .socPower: return metrics?.socPower
        case .gpuLoad: return metrics?.gpuLoad
        case .fanRPM, .fanDuty: return nil
        }
    }

    public func isPermanentlyUnsupported(_ metric: MetricIdentifier) -> Bool {
        sample(for: metric)?.sourceStatus == .unsupported
    }
}
