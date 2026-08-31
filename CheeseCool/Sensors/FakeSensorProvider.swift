import Foundation

public actor FakeSensorProvider: TemperatureSource,
    SoCTemperatureProviding, CPULoadProviding, PowerProviding, GPULoadProviding {
    private var temperature: Double?
    private var cpuLoad: Double
    private var socPower: Double
    private var gpuLoad: Double
    private var status: SensorSourceStatus = .ok
    private var timestampOverride: TimeInterval?

    public init(
        temperature: Double = 50,
        cpuLoad: Double = 20,
        socPower: Double = 12,
        gpuLoad: Double = 10
    ) {
        self.temperature = temperature
        self.cpuLoad = cpuLoad
        self.socPower = socPower
        self.gpuLoad = gpuLoad
    }

    public func setTemperature(_ temperature: Double) {
        self.temperature = temperature
        status = .ok
        timestampOverride = nil
    }

    public func setUnavailable(_ status: SensorSourceStatus = .unavailable) {
        precondition(status != .ok)
        temperature = nil
        self.status = status
        timestampOverride = nil
    }

    public func setStale(timestamp: TimeInterval) {
        timestampOverride = timestamp
    }

    public func setMetrics(cpuLoad: Double, socPower: Double, gpuLoad: Double) {
        self.cpuLoad = cpuLoad
        self.socPower = socPower
        self.gpuLoad = gpuLoad
    }

    public func readTemperature(now: TimeInterval) -> TemperatureSample {
        TemperatureClassifier.sample(
            temperature: temperature,
            timestamp: timestampOverride ?? now,
            now: now,
            sourceStatus: status
        )
    }

    public func readSoCTemperature() throws -> Double {
        guard status == .ok, let temperature else { throw SensorError.unavailable }
        return temperature
    }

    public func readCPULoad() throws -> Double { cpuLoad }
    public func readSoCPower() throws -> Double { socPower }
    public func readGPULoad() throws -> Double { gpuLoad }
}
