import Foundation

public enum HostDeviceError: Error, Equatable, LocalizedError, Sendable {
    case unavailable(String)
    case commandFailed(String)
    case readFailed(String)
    case timeout(String)
    case invalidDuty(Int)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message), .commandFailed(let message),
             .readFailed(let message), .timeout(let message):
            return message
        case .invalidDuty(let duty):
            return "Duty must be an integer from 0 through 100 (received \(duty))"
        }
    }
}

public protocol HostDevice: Sendable {
    func connect() async throws
    func disconnect() async
    var isConnected: Bool { get async }
    func getStatus() async throws -> DeviceStatus
    func setHostControlled() async throws
    func setMax() async throws
    func setDuty(_ percent: Int) async throws
    func close() async
}

public struct DeviceCommandRecord: Codable, Equatable, Sendable {
    public let timestamp: TimeInterval
    public let command: String
    public let value: Int?
}
