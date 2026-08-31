import Foundation

public struct UnsupportedSoCPowerProvider: PowerProviding {
    public init() {}

    public func readSoCPower(now: TimeInterval) -> MetricSample {
        .unavailable(
            timestamp: now,
            source: "No supported source",
            status: .unsupported,
            reason: "系统没有稳定、免提权的公开 SoC 功耗接口"
        )
    }
}

public struct UnsupportedGPULoadProvider: GPULoadProviding {
    public init() {}

    public func readGPULoad(now: TimeInterval) -> MetricSample {
        .unavailable(
            timestamp: now,
            source: "No supported source",
            status: .unsupported,
            reason: "系统没有稳定、免提权的公开 GPU 利用率接口"
        )
    }
}
