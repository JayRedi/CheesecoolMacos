import Foundation

public struct DryRunSample: Codable, Equatable, Sendable {
    public let elapsedSeconds: Double
    public let temperatureCelsius: Double?
    public let temperatureState: TemperatureState
    public let temperatureValid: Bool
    public let rawAutoDuty: Double?
    public let requestedDuty: Int?
    public let fakeDeviceDuty: Int?
    public let fakeRPM: Int?
    public let cpuLoadPercent: Double?
    public let socPowerWatts: Double?
    public let gpuLoadPercent: Double?
    public let temperatureLatencyMilliseconds: Double
    public let cpuLatencyMilliseconds: Double
    public let error: String?

    public init(
        elapsedSeconds: Double,
        temperatureCelsius: Double?,
        temperatureState: TemperatureState,
        temperatureValid: Bool,
        rawAutoDuty: Double?,
        requestedDuty: Int?,
        fakeDeviceDuty: Int?,
        fakeRPM: Int?,
        cpuLoadPercent: Double?,
        socPowerWatts: Double?,
        gpuLoadPercent: Double?,
        temperatureLatencyMilliseconds: Double,
        cpuLatencyMilliseconds: Double,
        error: String?
    ) {
        self.elapsedSeconds = elapsedSeconds
        self.temperatureCelsius = temperatureCelsius
        self.temperatureState = temperatureState
        self.temperatureValid = temperatureValid
        self.rawAutoDuty = rawAutoDuty
        self.requestedDuty = requestedDuty
        self.fakeDeviceDuty = fakeDeviceDuty
        self.fakeRPM = fakeRPM
        self.cpuLoadPercent = cpuLoadPercent
        self.socPowerWatts = socPowerWatts
        self.gpuLoadPercent = gpuLoadPercent
        self.temperatureLatencyMilliseconds = temperatureLatencyMilliseconds
        self.cpuLatencyMilliseconds = cpuLatencyMilliseconds
        self.error = error
    }
}

public struct DryRunReport: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let requestedDurationSeconds: Double
    public let actualDurationSeconds: Double
    public let samplingIntervalSeconds: Double
    public let samples: [DryRunSample]
    public let commandCount: Int

    public init(
        startedAt: Date,
        requestedDurationSeconds: Double,
        actualDurationSeconds: Double,
        samplingIntervalSeconds: Double,
        samples: [DryRunSample],
        commandCount: Int
    ) {
        self.startedAt = startedAt
        self.requestedDurationSeconds = requestedDurationSeconds
        self.actualDurationSeconds = actualDurationSeconds
        self.samplingIntervalSeconds = samplingIntervalSeconds
        self.samples = samples
        self.commandCount = commandCount
    }
}
