import Foundation

@MainActor
public final class TelemetryStore: ObservableObject {
    @Published public private(set) var latest: TelemetrySnapshot?
    @Published public private(set) var metrics: MetricsSnapshot?

    public init() {}

    public func publish(_ snapshot: TelemetrySnapshot) {
        latest = snapshot
    }

    public func publish(metrics: MetricsSnapshot) {
        self.metrics = metrics
    }
}
