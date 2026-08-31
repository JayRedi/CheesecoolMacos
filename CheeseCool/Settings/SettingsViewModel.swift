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
    @Published public private(set) var telemetry: TelemetrySnapshot?
    @Published public private(set) var hidDiagnostics: HIDDiagnosticsSnapshot?
    public let simulationMode: Bool
    public var onConfigurationChanged: ((Configuration) -> Void)?
    public var onReset: (() -> Void)?
    public var onClearLogs: (() -> Void)?
    public var onUninstall: (() -> Void)?
    private var isReplacingConfiguration = false

    public init(configuration: Configuration, simulationMode: Bool = false) {
        self.configuration = configuration
        self.simulationMode = simulationMode
    }

    public func reset() { onReset?() }
    public func clearLogs() { onClearLogs?() }
    public func uninstall() { onUninstall?() }

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

    public func update(telemetry: TelemetrySnapshot) {
        self.telemetry = telemetry
    }

    public func update(hidDiagnostics: HIDDiagnosticsSnapshot) {
        self.hidDiagnostics = hidDiagnostics
    }

    public func setMetric(_ metric: MetricIdentifier, visible: Bool) {
        configuration.menuBar.visibleMetrics.removeAll { $0 == metric }
        if visible { configuration.menuBar.visibleMetrics.append(metric) }
    }

    public func moveMetric(_ metric: MetricIdentifier, by offset: Int) {
        guard let index = configuration.menuBar.metricOrder.firstIndex(of: metric) else { return }
        let target = index + offset
        guard configuration.menuBar.metricOrder.indices.contains(target) else { return }
        configuration.menuBar.metricOrder.swapAt(index, target)
    }

    public func setManualDuty(_ duty: Int) {
        configuration.manualDuty = min(100, max(0, duty))
    }

    public func setAutoCurvePoint(at index: Int, temperature: Double? = nil, duty: Double? = nil) {
        guard configuration.autoCurve.indices.contains(index) else { return }
        let current = configuration.autoCurve[index]
        let lowerBound = index == 0 ? -100 : configuration.autoCurve[index - 1].temperatureCelsius + 1
        let upperBound = index == configuration.autoCurve.count - 1
            ? 200
            : configuration.autoCurve[index + 1].temperatureCelsius - 1
        let proposedTemperature = min(upperBound, max(lowerBound, (temperature ?? current.temperatureCelsius).rounded()))
        let proposedDuty = min(100, max(0, (duty ?? current.duty).rounded()))
        var candidate = configuration
        candidate.autoCurve[index] = AutoCurvePoint(
            temperatureCelsius: proposedTemperature,
            duty: proposedDuty
        )
        guard (try? candidate.validate()) != nil else { return }
        configuration = candidate
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
