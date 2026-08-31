import Foundation

public struct HIDDiagnosticsSnapshot: Equatable, Sendable {
    public let matchingDevices: [HIDDeviceIdentity]
    public let selectedDevice: HIDDeviceIdentity?
    public let connected: Bool
    public let lastCommand: ProtocolV1Command?
    public let lastSequence: UInt8?
    public let lastRoundTripMilliseconds: Double?
    public let lastError: String?
    public let disconnectCount: Int
    public let reconnectCount: Int
}

/// Serialized Protocol V1 HostDevice. It deliberately has no keepalive or retry loop:
/// ControlSession remains the sole owner of command cadence, traffic stopping and recovery.
public actor HIDHostDevice: HostDevice {
    public static let transactionTimeout: Duration = .milliseconds(750)

    private let discovery: any HIDDeviceDiscovering
    private let transport: any HIDTransport
    private let sequenceAllocator: ProtocolV1SequenceAllocator
    private var selectedIdentity: HIDDeviceIdentity?
    private var connected = false
    private var lastCommand: ProtocolV1Command?
    private var lastSequence: UInt8?
    private var lastRoundTripMilliseconds: Double?
    private var lastError: String?
    private var disconnectCount = 0
    private var reconnectCount = 0

    public init(
        discovery: any HIDDeviceDiscovering,
        transport: any HIDTransport,
        sequenceAllocator: ProtocolV1SequenceAllocator = ProtocolV1SequenceAllocator()
    ) {
        self.discovery = discovery
        self.transport = transport
        self.sequenceAllocator = sequenceAllocator
        discovery.start()
        discovery.setRemovalHandler { [weak self] identity in
            Task { await self?.handleRemoval(identity) }
        }
    }

    public var isConnected: Bool { connected }

    public func connect() async throws {
        if connected { return }
        guard let identity = discovery.selectedDevice() else {
            lastError = HIDTransportError.deviceNotFound.localizedDescription
            throw HIDTransportError.deviceNotFound
        }
        do {
            try await transport.open(identity)
            selectedIdentity = identity
            _ = try await transact(command: .ping, payload: [])
            connected = true
            reconnectCount += 1
        } catch {
            connected = false
            selectedIdentity = nil
            lastError = error.localizedDescription
            await transport.close()
            throw error
        }
    }

    public func disconnect() async {
        if connected || selectedIdentity != nil { disconnectCount += 1 }
        connected = false
        selectedIdentity = nil
        await transport.close()
    }

    public func close() async {
        await disconnect()
        discovery.stop()
    }

    public func getStatus() async throws -> DeviceStatus {
        let response = try await requireAndTransact(command: .getStatus, payload: [])
        return try ProtocolV1Codec.decodeDeviceStatus(response)
    }

    public func setHostControlled() async throws {
        _ = try await requireAndTransact(command: .setMode, payload: [ProtocolV1Mode.hostControlled.rawValue])
    }

    public func setMax() async throws {
        _ = try await requireAndTransact(command: .setMode, payload: [ProtocolV1Mode.max.rawValue])
    }

    public func setDuty(_ percent: Int) async throws {
        guard (0...100).contains(percent) else { throw HostDeviceError.invalidDuty(percent) }
        _ = try await requireAndTransact(command: .setDuty, payload: [UInt8(percent)])
    }

    public func diagnostics() -> HIDDiagnosticsSnapshot {
        HIDDiagnosticsSnapshot(
            matchingDevices: discovery.matchingDevices(),
            selectedDevice: selectedIdentity,
            connected: connected,
            lastCommand: lastCommand,
            lastSequence: lastSequence,
            lastRoundTripMilliseconds: lastRoundTripMilliseconds,
            lastError: lastError,
            disconnectCount: disconnectCount,
            reconnectCount: reconnectCount
        )
    }

    private func requireAndTransact(command: ProtocolV1Command, payload: [UInt8]) async throws -> ProtocolV1Response {
        guard connected else { throw HIDTransportError.deviceDisconnected }
        return try await transact(command: command, payload: payload)
    }

    private func transact(command: ProtocolV1Command, payload: [UInt8]) async throws -> ProtocolV1Response {
        let sequence = await sequenceAllocator.allocate()
        let request = ProtocolV1Request(command: command, sequence: sequence, payload: payload)
        let frame = try ProtocolV1Codec.encode(request)
        let start = ContinuousClock.now
        do {
            let responseFrame = try await transport.transact(frame, timeout: Self.transactionTimeout)
            let response = try ProtocolV1Codec.decodeResponse(responseFrame, expecting: request)
            let elapsed = start.duration(to: .now)
            lastCommand = command
            lastSequence = sequence
            lastRoundTripMilliseconds = Double(elapsed.components.seconds) * 1_000
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000
            lastError = nil
            return response
        } catch {
            connected = false
            lastCommand = command
            lastSequence = sequence
            lastError = error.localizedDescription
            throw error
        }
    }

    private func handleRemoval(_ identity: HIDDeviceIdentity) async {
        guard selectedIdentity == identity else { return }
        connected = false
        selectedIdentity = nil
        disconnectCount += 1
        if let nativeTransport = transport as? NativeHIDTransport {
            nativeTransport.deviceRemoved(identity)
        } else {
            await transport.close()
        }
    }
}
