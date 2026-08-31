import Foundation

public enum OperatingMode: String, Codable, CaseIterable, Sendable {
    case auto = "AUTO"
    case manual = "MANUAL"
    case max = "MAX"
}

public enum DeviceMode: String, Codable, Sendable {
    case hostControlled = "HOST_CONTROLLED"
    case max = "MAX"
}

public enum ConnectionState: String, Codable, Sendable {
    case disconnected = "DISCONNECTED"
    case connecting = "CONNECTING"
    case connected = "CONNECTED"
    case unavailable = "UNAVAILABLE"
}

public enum ControlState: String, Codable, Sendable {
    case idle = "IDLE"
    case autoActive = "AUTO_ACTIVE"
    case manualActive = "MANUAL_ACTIVE"
    case maxActive = "MAX_ACTIVE"
    case temperatureGrace = "TEMPERATURE_GRACE"
    case temperatureUnavailable = "TEMPERATURE_UNAVAILABLE"
    case deviceUnavailable = "DEVICE_UNAVAILABLE"
    case failsafeHandoff = "FAILSAFE_HANDOFF"
    case recovering = "RECOVERING"
    case powerFault = "POWER_FAULT"
    case sleeping = "SLEEPING"
    case stopped = "STOPPED"
}

public enum TemperatureState: String, Codable, Sendable {
    case unknown = "UNKNOWN"
    case cool = "COOL"
    case normal = "NORMAL"
    case warm = "WARM"
    case hot = "HOT"
    case critical = "CRITICAL"
}

public enum SensorSourceStatus: String, Codable, Sendable {
    case ok = "OK"
    case unavailable = "UNAVAILABLE"
    case empty = "EMPTY"
    case error = "ERROR"
    case timeout = "TIMEOUT"
    case stale = "STALE"
}

public struct TemperatureSample: Codable, Equatable, Sendable {
    public let timestamp: TimeInterval
    public let controlTemperatureCelsius: Double?
    public let state: TemperatureState
    public let valid: Bool
    public let sourceStatus: SensorSourceStatus
    public let sensorCount: Int
    public let sensorsUsed: [String]
    public let sampleAgeMilliseconds: Int

    public init(
        timestamp: TimeInterval,
        controlTemperatureCelsius: Double?,
        state: TemperatureState,
        valid: Bool,
        sourceStatus: SensorSourceStatus,
        sensorCount: Int = 0,
        sensorsUsed: [String] = [],
        sampleAgeMilliseconds: Int = 0
    ) {
        self.timestamp = timestamp
        self.controlTemperatureCelsius = controlTemperatureCelsius
        self.state = state
        self.valid = valid
        self.sourceStatus = sourceStatus
        self.sensorCount = sensorCount
        self.sensorsUsed = sensorsUsed
        self.sampleAgeMilliseconds = sampleAgeMilliseconds
    }
}

public struct FirmwareVersion: Codable, Equatable, Sendable, CustomStringConvertible {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public var description: String { value }
}

public struct DeviceStatus: Codable, Equatable, Sendable {
    public let mode: DeviceMode
    public let targetDuty: Int
    public let actualDuty: Int
    public let rpm: Int
    public let usbConfigured: Bool
    public let failsafe: Bool
    public let powerFault: Bool
    public let uptime: TimeInterval
    public let firmwareVersion: FirmwareVersion

    public init(
        mode: DeviceMode,
        targetDuty: Int,
        actualDuty: Int,
        rpm: Int,
        usbConfigured: Bool,
        failsafe: Bool,
        powerFault: Bool,
        uptime: TimeInterval,
        firmwareVersion: FirmwareVersion
    ) {
        self.mode = mode
        self.targetDuty = targetDuty
        self.actualDuty = actualDuty
        self.rpm = rpm
        self.usbConfigured = usbConfigured
        self.failsafe = failsafe
        self.powerFault = powerFault
        self.uptime = uptime
        self.firmwareVersion = firmwareVersion
    }
}

public struct ControlCommand: Codable, Equatable, Sendable {
    public let requestedMode: OperatingMode
    public let requestedDuty: Int?
    public let reason: String
    public let timestamp: TimeInterval
}

public struct ControlDecision: Codable, Equatable, Sendable {
    public let requestedMode: OperatingMode
    public let requestedDuty: Int?
    public let reason: String
    public let timestamp: TimeInterval
    public let rawAutoDuty: Double?

    public init(
        requestedMode: OperatingMode,
        requestedDuty: Int?,
        reason: String,
        timestamp: TimeInterval,
        rawAutoDuty: Double? = nil
    ) {
        self.requestedMode = requestedMode
        self.requestedDuty = requestedDuty
        self.reason = reason
        self.timestamp = timestamp
        self.rawAutoDuty = rawAutoDuty
    }
}

public enum MetricIdentifier: String, Codable, CaseIterable, Sendable {
    case fanRPM
    case fanDuty
    case socTemperature
    case cpuLoad
    case socPower
    case gpuLoad
}

public struct MetricsSnapshot: Codable, Equatable, Sendable {
    public let timestamp: TimeInterval
    public let socTemperatureCelsius: Double?
    public let cpuLoadPercent: Double?
    public let socPowerWatts: Double?
    public let gpuLoadPercent: Double?

    public init(
        timestamp: TimeInterval,
        socTemperatureCelsius: Double? = nil,
        cpuLoadPercent: Double? = nil,
        socPowerWatts: Double? = nil,
        gpuLoadPercent: Double? = nil
    ) {
        self.timestamp = timestamp
        self.socTemperatureCelsius = socTemperatureCelsius
        self.cpuLoadPercent = cpuLoadPercent
        self.socPowerWatts = socPowerWatts
        self.gpuLoadPercent = gpuLoadPercent
    }
}

public struct TelemetrySnapshot: Codable, Equatable, Sendable {
    public let timestamp: TimeInterval
    public let socTemperatureCelsius: Double?
    public let temperatureState: TemperatureState
    public let temperatureValid: Bool
    public let operatingMode: OperatingMode
    public let controlState: ControlState
    public let rawAutoDuty: Double?
    public let requestedDuty: Int?
    public let lastSentDuty: Int?
    public let deviceTargetDuty: Int?
    public let deviceActualDuty: Int?
    public let rpm: Int?
    public let failsafe: Bool?
    public let powerFault: Bool?
    public let connectionState: ConnectionState
    public let lastCommand: String?
    public let lastCommandAge: TimeInterval?
    public let lastError: String?
    public let reason: String
    public let physicalFanOffSupported: Bool
}
