import Foundation

public enum EventType: String, Codable, Sendable {
    case modeChanged = "MODE_CHANGED"
    case temperatureLost = "TEMPERATURE_LOST"
    case temperatureRecovered = "TEMPERATURE_RECOVERED"
    case deviceConnecting = "DEVICE_CONNECTING"
    case deviceConnected = "DEVICE_CONNECTED"
    case deviceDisconnected = "DEVICE_DISCONNECTED"
    case commandError = "COMMAND_ERROR"
    case failsafeHandoff = "FAILSAFE_HANDOFF"
    case recovery = "RECOVERY"
    case powerFault = "POWER_FAULT"
    case sleep = "SLEEP"
    case wake = "WAKE"
    case configurationError = "CONFIGURATION_ERROR"
    case stopped = "STOPPED"
}

public struct EventLogEntry: Codable, Equatable, Sendable {
    public let timestamp: TimeInterval
    public let type: EventType
    public let detail: String

    public init(timestamp: TimeInterval, type: EventType, detail: String = "") {
        self.timestamp = timestamp
        self.type = type
        self.detail = detail
    }
}

public actor EventLog {
    public let capacity: Int
    private var entries: [EventLogEntry] = []

    public init(capacity: Int = 128) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public func append(timestamp: TimeInterval, type: EventType, detail: String = "") {
        entries.append(EventLogEntry(timestamp: timestamp, type: type, detail: detail))
        if entries.count > capacity { entries.removeFirst(entries.count - capacity) }
    }

    public func snapshot() -> [EventLogEntry] { entries }
    public var count: Int { entries.count }
    public func clear() { entries.removeAll(keepingCapacity: true) }
}
