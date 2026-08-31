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
        let timestamp = clock.now
        async let temperature = temperatureProvider.readSoCTemperature(now: timestamp)
        async let cpu = cpuProvider.readCPULoad(now: timestamp)
        async let power = powerProvider.readSoCPower(now: timestamp)
        async let gpu = gpuProvider.readGPULoad(now: timestamp)
        return await MetricsSnapshot(
            timestamp: timestamp,
            socTemperature: temperature,
            cpuLoad: cpu,
            socPower: power,
            gpuLoad: gpu,
            temperatureSensorCount: temperature.sensorCount,
            temperatureSensorsUsed: temperature.sensorsUsed
        )
    }
}
