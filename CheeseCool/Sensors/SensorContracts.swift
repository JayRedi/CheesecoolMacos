import Foundation

public enum SensorError: Error, Equatable, Sendable {
    case unavailable
    case failed(String)
}

public protocol TemperatureSource: Sendable {
    func readTemperature(now: TimeInterval) async -> TemperatureSample
}

public protocol SoCTemperatureProviding: Sendable {
    func readSoCTemperature(now: TimeInterval) async -> MetricSample
}

public protocol CPULoadProviding: Sendable {
    func readCPULoad(now: TimeInterval) async -> MetricSample
}

public protocol PowerProviding: Sendable {
    func readSoCPower(now: TimeInterval) async -> MetricSample
}

public protocol GPULoadProviding: Sendable {
    func readGPULoad(now: TimeInterval) async -> MetricSample
}

public protocol TemperatureSensorReadingSource: Sendable {
    func readSensors() async throws -> [RawTemperatureSensor]
}

public struct RawTemperatureSensor: Equatable, Sendable {
    public let name: String
    public let celsius: Double

    public init(name: String, celsius: Double) {
        self.name = name
        self.celsius = celsius
    }
}

public enum TemperatureClassifier {
    public static func classify(_ temperature: Double) -> TemperatureState {
        if temperature < 35 { return .cool }
        if temperature < 55 { return .normal }
        if temperature < 70 { return .warm }
        if temperature < 85 { return .hot }
        return .critical
    }

    public static func sample(
        temperature: Double?,
        timestamp: TimeInterval,
        now: TimeInterval,
        sourceStatus: SensorSourceStatus = .ok,
        staleAfter: TimeInterval = 5,
        sensorCount: Int = 1,
        sensorsUsed: [String] = []
    ) -> TemperatureSample {
        let age = max(0, now - timestamp)
        guard sourceStatus == .ok else {
            return unknown(timestamp: timestamp, now: now, status: sourceStatus)
        }
        guard age <= staleAfter else {
            return unknown(timestamp: timestamp, now: now, status: .stale)
        }
        guard let temperature,
              temperature.isFinite,
              (0...125).contains(temperature) else {
            return unknown(timestamp: timestamp, now: now, status: .empty)
        }
        return TemperatureSample(
            timestamp: timestamp,
            controlTemperatureCelsius: temperature,
            state: classify(temperature),
            valid: true,
            sourceStatus: .ok,
            sensorCount: sensorCount,
            sensorsUsed: sensorsUsed,
            sampleAgeMilliseconds: Int((age * 1_000).rounded())
        )
    }

    private static func unknown(
        timestamp: TimeInterval,
        now: TimeInterval,
        status: SensorSourceStatus
    ) -> TemperatureSample {
        TemperatureSample(
            timestamp: timestamp,
            controlTemperatureCelsius: nil,
            state: .unknown,
            valid: false,
            sourceStatus: status,
            sampleAgeMilliseconds: Int((max(0, now - timestamp) * 1_000).rounded())
        )
    }
}
