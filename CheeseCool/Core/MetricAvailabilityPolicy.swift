import Foundation

public enum MetricAvailabilityPolicy {
    public static func unsupportedMetrics(in snapshot: MetricsSnapshot?) -> Set<MetricIdentifier> {
        guard let snapshot else { return [] }
        return Set([
            snapshot.socTemperature.sourceStatus == .unsupported ? .socTemperature : nil,
            snapshot.cpuLoad.sourceStatus == .unsupported ? .cpuLoad : nil,
            snapshot.socPower.sourceStatus == .unsupported ? .socPower : nil,
            snapshot.gpuLoad.sourceStatus == .unsupported ? .gpuLoad : nil
        ].compactMap { $0 })
    }
}
