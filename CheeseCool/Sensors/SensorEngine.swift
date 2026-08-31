import Foundation

public actor SensorEngine {
    private let temperatureProvider: any SoCTemperatureProviding
    private let cpuProvider: any CPULoadProviding
    private let powerProvider: any PowerProviding
    private let gpuProvider: any GPULoadProviding
    private let clock: any MonotonicClock

    public init(
        temperatureProvider: any SoCTemperatureProviding,
        cpuProvider: any CPULoadProviding,
        powerProvider: any PowerProviding,
        gpuProvider: any GPULoadProviding,
        clock: any MonotonicClock
    ) {
        self.temperatureProvider = temperatureProvider
        self.cpuProvider = cpuProvider
        self.powerProvider = powerProvider
        self.gpuProvider = gpuProvider
        self.clock = clock
    }

    public func poll() async -> MetricsSnapshot {
        async let temperature = optional { try await temperatureProvider.readSoCTemperature() }
        async let cpu = optional { try await cpuProvider.readCPULoad() }
        async let power = optional { try await powerProvider.readSoCPower() }
        async let gpu = optional { try await gpuProvider.readGPULoad() }
        return await MetricsSnapshot(
            timestamp: clock.now,
            socTemperatureCelsius: temperature,
            cpuLoadPercent: cpu,
            socPowerWatts: power,
            gpuLoadPercent: gpu
        )
    }

    private func optional(_ operation: @Sendable () async throws -> Double) async -> Double? {
        try? await operation()
    }
}
