import Foundation

public enum MockHIDBehavior: Sendable {
    case normal
    case timeout
    case disconnected
    case badChecksum
    case wrongSequence
    case malformedStatus
}

public actor MockHIDTransport: HIDTransport {
    public let supportedIdentity: HIDDeviceIdentity
    private var opened = false
    private var behavior: MockHIDBehavior = .normal
    private var device = MockProtocolV1Device()
    public private(set) var requestFrames: [[UInt8]] = []

    public init(identity: HIDDeviceIdentity = HIDDeviceIdentity(registryID: 1)) {
        self.supportedIdentity = identity
    }

    public var isOpen: Bool { opened }

    public func open(_ identity: HIDDeviceIdentity) throws {
        guard identity == supportedIdentity else { throw HIDTransportError.deviceNotFound }
        opened = true
    }

    public func close() { opened = false }

    public func transact(_ frame: [UInt8], timeout: Duration) async throws -> [UInt8] {
        guard opened else { throw HIDTransportError.transportClosed }
        requestFrames.append(frame)
        switch behavior {
        case .timeout: throw HIDTransportError.timeout
        case .disconnected:
            opened = false
            throw HIDTransportError.deviceDisconnected
        case .normal, .badChecksum, .wrongSequence, .malformedStatus:
            let request = try ProtocolV1Codec.decodeRequest(frame)
            var response = try device.respond(to: request)
            switch behavior {
            case .badChecksum: response[63] ^= 0xFF
            case .wrongSequence: response[2] &+= 1; response[63] = ProtocolV1Codec.checksum(response[0...62])
            case .malformedStatus where request.command == .getStatus:
                response[3] = 1
                response[5] = 0
                response[63] = ProtocolV1Codec.checksum(response[0...62])
            default: break
            }
            return response
        }
    }

    public func setBehavior(_ behavior: MockHIDBehavior) { self.behavior = behavior }
    public func setPowerFault(_ active: Bool) { device.powerFault = active }
    public func setFailsafe(_ active: Bool) { device.failsafe = active }
}

private struct MockProtocolV1Device: Sendable {
    var mode: ProtocolV1Mode = .hostControlled
    var targetDuty: UInt8 = 0
    var actualDuty: UInt8 = 0
    var failsafe = false
    var powerFault = false

    mutating func respond(to request: ProtocolV1Request) throws -> [UInt8] {
        switch request.command {
        case .ping:
            return try ProtocolV1Codec.encodeResponse(command: .ping, sequence: request.sequence)
        case .getStatus:
            let rpm: UInt32 = actualDuty == 0 ? 345 : UInt32((345 + (2_500 - 345) * Int(actualDuty) / 100))
            let payload: [UInt8] = [
                mode.rawValue, targetDuty, actualDuty,
                UInt8(truncatingIfNeeded: rpm), UInt8(truncatingIfNeeded: rpm >> 8), UInt8(truncatingIfNeeded: rpm >> 16), UInt8(truncatingIfNeeded: rpm >> 24),
                1, failsafe ? 1 : 0, powerFault ? 1 : 0,
                0, 0, 0, 0,
                1, 0, 0
            ]
            return try ProtocolV1Codec.encodeResponse(command: .getStatus, sequence: request.sequence, payload: payload)
        case .setMode:
            guard request.payload.count == 1, let requestedMode = ProtocolV1Mode(rawValue: request.payload[0]) else {
                return try ProtocolV1Codec.encodeResponse(command: .setMode, sequence: request.sequence, status: 1)
            }
            mode = requestedMode
            failsafe = false
            if mode == .max { targetDuty = 100; actualDuty = 100 }
            return try ProtocolV1Codec.encodeResponse(command: .setMode, sequence: request.sequence)
        case .setDuty:
            guard request.payload.count == 1, request.payload[0] <= 100, mode == .hostControlled else {
                return try ProtocolV1Codec.encodeResponse(command: .setDuty, sequence: request.sequence, status: 1)
            }
            targetDuty = request.payload[0]
            actualDuty = request.payload[0]
            failsafe = false
            return try ProtocolV1Codec.encodeResponse(command: .setDuty, sequence: request.sequence)
        case .enterDFULegacy, .setCurve, .enterDFU:
            return try ProtocolV1Codec.encodeResponse(command: request.command, sequence: request.sequence, status: 1)
        }
    }
}
