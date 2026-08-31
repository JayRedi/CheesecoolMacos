import Foundation

public enum ProtocolV1Command: UInt8, CaseIterable, Sendable {
    case ping = 0x01
    case enterDFULegacy = 0x08
    case getStatus = 0x09
    case setMode = 0x0A
    case setDuty = 0x0B
    case setCurve = 0x0C
    case enterDFU = 0x0D
}

public enum ProtocolV1Mode: UInt8, Sendable {
    case hostControlled = 0
    case max = 1
}

public enum ProtocolV1Error: Error, Equatable, LocalizedError, Sendable {
    case invalidReportLength(Int)
    case invalidProtocolVersion(UInt8)
    case invalidPayloadLength(Int)
    case checksumMismatch(expected: UInt8, actual: UInt8)
    case commandMismatch(expected: UInt8, actual: UInt8)
    case sequenceMismatch(expected: UInt8, actual: UInt8)
    case deviceStatusError(UInt8)
    case malformedStatusPayload(String)
    case unsupportedMode(UInt8)

    public var errorDescription: String? {
        switch self {
        case .invalidReportLength(let length): return "Protocol V1 报文长度无效：\(length)"
        case .invalidProtocolVersion(let version): return "Protocol V1 版本无效：\(version)"
        case .invalidPayloadLength(let length): return "Protocol V1 载荷长度无效：\(length)"
        case .checksumMismatch: return "Protocol V1 校验和不匹配"
        case .commandMismatch: return "Protocol V1 命令不匹配"
        case .sequenceMismatch: return "Protocol V1 序列号不匹配"
        case .deviceStatusError(let status): return "设备返回 Protocol V1 状态错误：\(status)"
        case .malformedStatusPayload(let reason): return "设备状态载荷无效：\(reason)"
        case .unsupportedMode(let mode): return "设备模式无效：\(mode)"
        }
    }
}

public struct ProtocolV1Request: Equatable, Sendable {
    public let command: ProtocolV1Command
    public let sequence: UInt8
    public let payload: [UInt8]

    public init(command: ProtocolV1Command, sequence: UInt8, payload: [UInt8] = []) {
        self.command = command
        self.sequence = sequence
        self.payload = payload
    }
}

public struct ProtocolV1Response: Equatable, Sendable {
    public let command: ProtocolV1Command
    public let sequence: UInt8
    public let status: UInt8
    public let payload: [UInt8]
}

public struct PingRequest: Equatable, Sendable {
    public init() {}
}

public struct PingResponse: Equatable, Sendable {
    public init() {}
}

public struct GetStatusRequest: Equatable, Sendable {
    public init() {}
}

public struct SetModeRequest: Equatable, Sendable {
    public let mode: ProtocolV1Mode
    public init(mode: ProtocolV1Mode) { self.mode = mode }
}

public struct SetDutyRequest: Equatable, Sendable {
    public let duty: UInt8
    public init(duty: UInt8) { self.duty = duty }
}

public enum ProtocolV1Codec {
    public static let version: UInt8 = 1
    public static let frameLength = 64
    public static let maximumRequestPayloadLength = 59
    public static let maximumResponsePayloadLength = 58
    public static let statusPayloadLength = 17

    public static func encode(_ request: ProtocolV1Request) throws -> [UInt8] {
        guard request.payload.count <= maximumRequestPayloadLength else {
            throw ProtocolV1Error.invalidPayloadLength(request.payload.count)
        }
        var frame = [UInt8](repeating: 0, count: frameLength)
        frame[0] = version
        frame[1] = request.command.rawValue
        frame[2] = request.sequence
        frame[3] = UInt8(request.payload.count)
        frame.replaceSubrange(4..<(4 + request.payload.count), with: request.payload)
        frame[63] = checksum(frame[0...62])
        return frame
    }

    public static func decodeRequest(_ frame: [UInt8]) throws -> ProtocolV1Request {
        try validateCommonFrame(frame, maximumPayloadLength: maximumRequestPayloadLength)
        guard let command = ProtocolV1Command(rawValue: frame[1]) else {
            throw ProtocolV1Error.commandMismatch(expected: 0, actual: frame[1])
        }
        let payloadLength = Int(frame[3])
        return ProtocolV1Request(
            command: command,
            sequence: frame[2],
            payload: Array(frame[4..<(4 + payloadLength)])
        )
    }

    public static func encodeResponse(
        command: ProtocolV1Command,
        sequence: UInt8,
        status: UInt8 = 0,
        payload: [UInt8] = []
    ) throws -> [UInt8] {
        guard payload.count <= maximumResponsePayloadLength else {
            throw ProtocolV1Error.invalidPayloadLength(payload.count)
        }
        var frame = [UInt8](repeating: 0, count: frameLength)
        frame[0] = version
        frame[1] = command.rawValue
        frame[2] = sequence
        frame[3] = UInt8(payload.count)
        frame[4] = status
        frame.replaceSubrange(5..<(5 + payload.count), with: payload)
        frame[63] = checksum(frame[0...62])
        return frame
    }

    public static func decodeResponse(
        _ frame: [UInt8],
        expecting request: ProtocolV1Request
    ) throws -> ProtocolV1Response {
        try validateCommonFrame(frame, maximumPayloadLength: maximumResponsePayloadLength)
        guard frame[1] == request.command.rawValue else {
            throw ProtocolV1Error.commandMismatch(expected: request.command.rawValue, actual: frame[1])
        }
        guard frame[2] == request.sequence else {
            throw ProtocolV1Error.sequenceMismatch(expected: request.sequence, actual: frame[2])
        }
        guard let command = ProtocolV1Command(rawValue: frame[1]) else {
            throw ProtocolV1Error.commandMismatch(expected: request.command.rawValue, actual: frame[1])
        }
        let status = frame[4]
        guard status == 0 else { throw ProtocolV1Error.deviceStatusError(status) }
        let payloadLength = Int(frame[3])
        return ProtocolV1Response(
            command: command,
            sequence: frame[2],
            status: status,
            payload: Array(frame[5..<(5 + payloadLength)])
        )
    }

    public static func decodeDeviceStatus(_ response: ProtocolV1Response) throws -> DeviceStatus {
        guard response.command == .getStatus else {
            throw ProtocolV1Error.commandMismatch(expected: ProtocolV1Command.getStatus.rawValue, actual: response.command.rawValue)
        }
        guard response.payload.count == statusPayloadLength else {
            throw ProtocolV1Error.malformedStatusPayload("预期 17 字节，实际 \(response.payload.count) 字节")
        }
        let bytes = response.payload
        let mode: DeviceMode
        switch bytes[0] {
        case ProtocolV1Mode.hostControlled.rawValue: mode = .hostControlled
        case ProtocolV1Mode.max.rawValue: mode = .max
        default: throw ProtocolV1Error.unsupportedMode(bytes[0])
        }
        let targetDuty = Int(bytes[1])
        let actualDuty = Int(bytes[2])
        guard (0...100).contains(targetDuty), (0...100).contains(actualDuty) else {
            throw ProtocolV1Error.malformedStatusPayload("占空比超出 0...100")
        }
        guard bytes[7] <= 1, bytes[8] <= 1, bytes[9] <= 1 else {
            throw ProtocolV1Error.malformedStatusPayload("布尔标志必须为 0 或 1")
        }
        let rpm = Int(littleEndianUInt32(bytes[3...6]))
        let uptime = TimeInterval(littleEndianUInt32(bytes[10...13]))
        return DeviceStatus(
            mode: mode,
            targetDuty: targetDuty,
            actualDuty: actualDuty,
            rpm: rpm,
            usbConfigured: bytes[7] == 1,
            failsafe: bytes[8] == 1,
            powerFault: bytes[9] == 1,
            uptime: uptime,
            firmwareVersion: FirmwareVersion("\(bytes[14]).\(bytes[15]).\(bytes[16])")
        )
    }

    public static func checksum<S: Sequence>(_ bytes: S) -> UInt8 where S.Element == UInt8 {
        bytes.reduce(0, ^)
    }

    private static func validateCommonFrame(_ frame: [UInt8], maximumPayloadLength: Int) throws {
        guard frame.count == frameLength else { throw ProtocolV1Error.invalidReportLength(frame.count) }
        guard frame[0] == version else { throw ProtocolV1Error.invalidProtocolVersion(frame[0]) }
        let payloadLength = Int(frame[3])
        guard payloadLength <= maximumPayloadLength else { throw ProtocolV1Error.invalidPayloadLength(payloadLength) }
        let actualChecksum = checksum(frame[0...62])
        guard frame[63] == actualChecksum else {
            throw ProtocolV1Error.checksumMismatch(expected: actualChecksum, actual: frame[63])
        }
    }

    private static func littleEndianUInt32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        precondition(bytes.count == 4)
        return bytes.enumerated().reduce(0) { partial, value in
            partial | (UInt32(value.element) << UInt32(value.offset * 8))
        }
    }
}

public actor ProtocolV1SequenceAllocator {
    private var nextSequence: UInt8

    public init(initialSequence: UInt8 = 0) {
        self.nextSequence = initialSequence
    }

    public func allocate() -> UInt8 {
        let allocated = nextSequence
        nextSequence &+= 1
        return allocated
    }
}
