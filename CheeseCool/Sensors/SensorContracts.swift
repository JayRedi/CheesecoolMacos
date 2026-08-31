import Foundation

public enum SensorError: Error, Equatable, Sendable {
    case unavailable
    case failed(String)
}

public protocol TemperatureSource: Sendable {
    func readTemperature(now: TimeInterval) async -> TemperatureSample
}

public protocol SoCTemperatureProviding: Sendable {
    func readSoCTemperature() async throws -> Double
}

public protocol CPULoadProviding: Sendable {
    func readCPULoad() async throws -> Double
}

public protocol PowerProviding: Sendable {
    func readSoCPower() async throws -> Double
}

public protocol GPULoadProviding: Sendable {
    func readGPULoad() async throws -> Double
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
        staleAfter: TimeInterval = 5
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
            sensorCount: 1,
            sensorsUsed: ["FAKE PMU tdie0"],
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
